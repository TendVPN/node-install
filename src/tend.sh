#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3))) || { echo "Нужен Bash 4.3+" >&2; exit 1; }
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG=${TEND_CONFIG:-/etc/tend/config.json}
declare -A C=([role]=node [ssh_port]=22223 [disable_password_auth]=no [tcp_ports]=443,8443 [udp_ports]=443,8443 [regions]=DE,NL,FR [optimize]=yes [protect]=yes [traffic_guard]=yes [psiphon]=yes [multitest]=yes [xanmod]=yes [whitelist]='' [email]='' [guard_urls]=https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/main/public/antiscanner.list)
source "$ROOT/src/ui.sh"
fail() { ui_action error "Ошибка: $*" >&2; exit 1; }
help() {
cat <<'EOF'
Tend — установка Remnawave и обслуживание VPS (Ubuntu 24.04).
  tend configure                     Изменить конфигурацию этого VPS
  tend install [флаги]               Установить на текущий VPS (root)
  tend plan [флаги]                   Проверить настройки без изменений
  tend menu                          Меню VPS (также tend-menu)
  tend whitelist add IP[,CIDR]        Добавить доверенные сети
  tend whitelist remove IP[,CIDR]     Удалить доверенные сети
  tend confirm-ssh                    Подтвердить новое SSH-соединение
  tend status                        Статус сервисов
Флаги (значения через пробел либо =):
  --role node                       Необязательный флаг совместимости
  --email EMAIL --node-domain DOMAIN
  --panel-ip IPV4 --node-secret-file FILE
  --disable-password-auth yes|no     Закрыть вход по SSH с паролем (по умолчанию no)
  --ssh-port 22223 --tcp-ports 443,8443 --udp-ports 443,8443
  --tcp-ports none                    Не открывать дополнительные TCP-порты (также n)
  --udp-ports none                    Не открывать сервисные UDP-порты (также n)
  --whitelist IP,CIDR --regions DE,NL,FR --guard-urls HTTPS_URL[,HTTPS_URL]
  --accelerator yes|no (optimize + protect)
  --optimize yes|no --protect yes|no --traffic-guard yes|no
  --psiphon yes|no --multitest yes|no --xanmod yes|no
  --config FILE --non-interactive --dry-run
Секреты предпочтительно передавать через файл конфигурации с chmod 600.
Установщик настраивает ноду Remnawave. Секреты не печатаются в plan.
EOF
}
load() {
 [[ -f $1 ]] || return 0
 python3 "$ROOT/src/config.py" validate "$1" || fail 'Конфигурация не прошла проверку'
 while IFS= read -r -d '' k && IFS= read -r -d '' v; do C[$k]=$v; done < <(python3 "$ROOT/src/config.py" read "$1")
}
save() { for k in "${!C[@]}"; do printf '%s\0%s\0' "$k" "${C[$k]}"; done | python3 "$ROOT/src/config.py" write "$1"; }
ask() {
 local key=$1 label=$2 default=${3:-} answer
 [[ $NONINTERACTIVE == no ]] || fail "Не указан --${key//_/-}. $label"
 [[ -r /dev/tty ]] || fail "Не указан --${key//_/-}; нет терминала. $label"
 ui_field "$key" "$label"
 local displayed=$default
 case $key in
 disable_password_auth|optimize|protect|traffic_guard|psiphon|multitest|xanmod) if [[ $default == yes ]]; then displayed='Y/n'; else displayed='y/N'; fi;;
 tcp_ports|udp_ports) [[ $default != none ]] || displayed=n;;
 esac
 printf '  %sОтвет [%s]: %s' "$UI_BLUE" "${displayed:-пусто}" "$UI_RESET" >/dev/tty
 if [[ $key == *secret* || $key == *token* || $key == *cookie* ]]; then
  IFS= read -rs answer </dev/tty || fail 'Ввод прерван'; echo >/dev/tty
 else IFS= read -r answer </dev/tty || fail 'Ввод прерван'; fi
 C[$key]=${answer:-$default}
 case $key in disable_password_auth|optimize|protect|traffic_guard|psiphon|multitest|xanmod)
  case ${C[$key],,} in да|д|y|yes) C[$key]=yes;; нет|н|n|no) C[$key]=no;; esac;; esac
 if [[ $key == tcp_ports || $key == udp_ports ]]; then
  case ${C[$key],,} in n|no|none|нет) C[$key]=none;; esac
 fi

}
need() { [[ -n ${C[$1]:-} ]] || ask "$1" "$2" "${3:-}"; [[ -n ${C[$1]:-} ]] || fail "Обязательное поле --${1//_/-}"; }
collect() {
 [[ ${C[role]} == node ]] || fail 'Для установки ноды используйте --role node'
 need node_domain 'Домен ноды'
 need panel_ip 'IPv4 панели'
 need node_secret 'Secret из панели (или --node-secret-file)'
 need email 'Email для сертификатов'
}

plan() {
 ui_action info 'Параметры установки:'
 for k in role email node_domain panel_ip ssh_port disable_password_auth tcp_ports udp_ports regions whitelist optimize protect traffic_guard psiphon multitest xanmod; do
  [[ ! -v C[$k] ]] || printf '  %-15s %s\n' "$k" "${C[$k]}"
 done
 echo 'Psiphon создаёт локальный SOCKS-прокси; маршруты Xray задаются в панели.'
}
CMD=${1:-install}
case $CMD in
 --help|-h) CMD=help; shift;;
 --*) CMD=install;;
 *) [[ $# == 0 ]] || shift;;
esac
[[ $CMD != help ]] || { help; exit; }
case $CMD in install|configure|plan|menu|whitelist|confirm-ssh|status) :;; *) fail "Неизвестная команда $CMD";; esac
ACTION=''; IPS=''; NONINTERACTIVE=no; DRY=no
declare -A EXPLICIT=()
if [[ $CMD == whitelist ]]; then ACTION=${1:?add/remove/refresh}; shift; if [[ $ACTION != refresh ]]; then IPS=${1:?IP/CIDR}; shift; fi; fi
ARGS=("$@"); for ((i=0;i<${#ARGS[@]};i++)); do
 case ${ARGS[$i]} in --config) CONFIG=${ARGS[$((i+1))]:?}; i=$((i+1));; --config=*) CONFIG=${ARGS[$i]#*=};; esac
 done
load "$CONFIG"
while (($#)); do
 flag=$1; shift
 case $flag in
 --non-interactive) NONINTERACTIVE=yes; continue;; --dry-run) DRY=yes; continue;;
 --help|-h) help; exit;; --*=*) value=${flag#*=}; flag=${flag%%=*};;
 --*) (($#)) || fail "Нужно значение $flag"; value=$1; shift;; *) fail "Неизвестный аргумент $flag";; esac
 key=${flag#--}; key=${key//-/_}
 EXPLICIT[$key]=yes
 case $key in
 accelerator) [[ $value == yes || $value == no ]] || fail "--accelerator: yes/no"; C[optimize]=$value; C[protect]=$value; EXPLICIT[optimize]=yes; EXPLICIT[protect]=yes;; config) :;; node_secret_file) [[ -r $value ]] || fail "Не найден файл secret"; C[node_secret]=$(cat "$value");;
 role|email|node_domain|panel_ip|ssh_port|disable_password_auth|tcp_ports|udp_ports|whitelist|regions|guard_urls|disable_password_auth|optimize|protect|traffic_guard|psiphon|multitest|xanmod) C[$key]=$value;;
 *) fail "Неизвестный флаг $flag";; esac
done
for key in tcp_ports udp_ports; do
 case ${C[$key],,} in n|no|none|нет) C[$key]=none;; esac
done
source "$ROOT/src/server.sh"
case $CMD in
 configure) require_server; setup_wizard; collect; save "$CONFIG"; ui_action success "Сохранено: $CONFIG";;
 plan) collect; tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT; save "$tmp"; plan;;
 install)
  [[ $DRY == yes ]] || require_server
  [[ $NONINTERACTIVE == yes ]] || setup_wizard
  collect; tmp=$(mktemp); save "$tmp"; rm -f "$tmp"
  if [[ $DRY == yes ]]; then plan; else ui_action info "Параметры проверены. Начинаю установку"; fi
  [[ $DRY == no ]] || exit 0
  install_server;;
 menu) server_menu;; whitelist) whitelist_change "$ACTION" "$IPS";;
 confirm-ssh) confirm_ssh;; status) status;; *) fail "Неизвестная команда $CMD";;
esac
