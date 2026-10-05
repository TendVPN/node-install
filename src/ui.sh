#!/usr/bin/env bash
UI_RESET='' UI_BOLD='' UI_BLUE='' UI_GREEN='' UI_DIM='' UI_YELLOW='' UI_RED=''
if [[ -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]] && [[ -t 1 ]]; then
 UI_RESET=$'\e[0m'; UI_BOLD=$'\e[1m'; UI_BLUE=$'\e[36m'; UI_GREEN=$'\e[32m'; UI_DIM=$'\e[90m'; UI_YELLOW=$'\e[33m'; UI_RED=$'\e[31m'
fi
ui_action() {
 local level=$1; shift
 local color=$UI_BLUE
 case $level in success) color=$UI_GREEN;; warning) color=$UI_YELLOW;; error) color=$UI_RED;; esac
 printf '%s%s[Tend-Menu]: %s%s\n' "$UI_BOLD" "$color" "$*" "$UI_RESET"
}
ui_heading() { printf '\n%s%s  %s%s\n' "$UI_BOLD" "$UI_BLUE" "$1" "$UI_RESET" >/dev/tty; }
ui_note() { printf '  %s%s%s\n' "$UI_DIM" "$1" "$UI_RESET" >/dev/tty; }
ui_field() {
 local key=$1 title description example
 case $key in
 email) title='Email для сертификатов'; description='Let’s Encrypt использует его для регистрации сертификатов ваших доменов.'; example='admin@example.org';;
 ssh_port) title='Порт SSH этого VPS'; description='Порт для подключения после установки. Это не порт управления нодой (2222).'; example='22223';;
 tcp_ports) title='Разрешённые TCP-порты'; description='Порты через запятую или n — без дополнительных TCP-портов. SSH, HTTP для сертификатов и порт управления нодой для панели сохраняется.'; example='443,8443 или n';;
 udp_ports) title='Разрешённые UDP-порты'; description='Порты через запятую. Введите n, чтобы не открывать сервисные UDP-порты.'; example='443,8443 или n';;
 optimize) title='Оптимизация VPS'; description='node-accelerator: настройки сети, лимитов, памяти и ротации логов.'; example='y';;
 protect) title='Сетевая защита'; description='node-accelerator: firewall и ограничения сетевого флуда.'; example='y';;
 traffic_guard) title='Блокировка сканеров'; description='TrafficGuard блокирует IP из списков сканеров с учётом вашего белого списка.'; example='y';;
 psiphon) title='Установить Psiphon'; description='Создаёт локальный SOCKS-прокси. Использование в Xray настраивается в панели.'; example='y';;
 multitest) title='Диагностика сервера'; description='Устанавливает multitest для проверки сети и производительности из меню VPS.'; example='y';;
 xanmod) title='Разрешить установку ядра XanMod'; description='Оптимизатор может установить другое ядро для BBRv3. Потребуется reboot; на ds-guard пропускается.'; example='n';;
 regions) title='Страны выхода Psiphon'; description='Двухбуквенные коды через запятую. При ротации страны меняются по этому списку.'; example='DE,NL,FR';;
 whitelist) title='Доверенные IP и сети'; description='Список сохранён на этом VPS. Ранее введённые IP, адрес SSH-клиента и IP панели; Enter сохраняет список.'; example='203.0.113.10,198.51.100.0/24';;
 node_domain) title='Домен ноды'; description='Его DNS A-запись должна указывать на устанавливаемый VPS.'; example='node.example.org';;
 panel_ip) title='IPv4 вашей панели'; description='Панель будет обращаться к ноде на порт 2222. IP добавится в белый список.'; example='203.0.113.10';;
 node_secret) title='Secret ноды из Remnawave'; description='Вставьте SECRET_KEY из панели. Ввод скрыт. Через CLI удобнее --node-secret-file.'; example='скопированный SECRET_KEY';;
 *) title=$2; description='Значение можно переопределить флагом при установке.'; example='';;
 esac
 printf '\n  %s%s%s\n' "$UI_BOLD" "$title" "$UI_RESET" >/dev/tty
 ui_note "$description"
 [[ -z $example ]] || ui_note "Пример ответа: $example"
}
wizard_field() {
 [[ -v EXPLICIT[$1] ]] || ask "$1" "$1" "${C[$1]:-}"
}
setup_wizard() {
 ui_heading 'TEND · Установка на VPS'
 ui_note 'Enter — оставить предложенное значение. Переключатели: y — включить, n — выключить; большая буква — ответ по умолчанию.'
 ui_note 'Параметры, указанные флагами, повторно не спрашиваются.'
 collect
 ui_heading 'SSH и сервисные порты'
 for k in ssh_port tcp_ports udp_ports; do wizard_field "$k"; done
 ui_heading 'Компоненты'
 for k in optimize protect traffic_guard psiphon multitest xanmod; do wizard_field "$k"; done
 ui_heading 'Регионы и доверенные адреса'
 for k in regions whitelist; do wizard_field "$k"; done
}

# Detailed output stays in the private log; progress alone reaches the terminal.
ui_step() {
 local label=$1; shift
 local logfile=${TEND_LOGFILE:-} pid rc=0 frame=0 worker var
 if [[ -z $logfile ]]; then
  mkdir -p /var/log/tend
  chmod 700 /var/log/tend
  logfile=$(mktemp /var/log/tend/action-XXXXXXXX.log)
  chmod 600 "$logfile"
 fi
 printf '\n[%s] %s\n' "$(date -u +%FT%TZ)" "$label" >>"$logfile"
 # A fresh shell preserves errexit even when ui_step is called in an OR-list.
 # Private script file keeps node credentials out of process arguments.
 worker=$(mktemp)
 chmod 600 "$worker"
 declare -f >"$worker"
 for var in ROOT CONFIG C UI_RESET UI_BOLD UI_BLUE UI_GREEN UI_DIM UI_YELLOW UI_RED TEND_LOGFILE; do
  declare -p "$var" >>"$worker" 2>/dev/null || true
 done
 printf '\nset -Eeuo pipefail\n"$@"\n' >>"$worker"
 bash "$worker" "$@" >>"$logfile" 2>&1 </dev/null &
 pid=$!
 if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  while kill -0 "$pid" 2>/dev/null; do
   printf '\r%s%s[Tend-Menu]: %s %s%s' "$UI_BOLD" "$UI_BLUE" "$label" "${frames[frame % 10]}" "$UI_RESET"
   frame=$((frame + 1)); sleep 0.12
  done
  printf '\r\033[2K'
 else
  ui_action info "$label …"
 fi
 wait "$pid" || rc=$?
 rm -f "$worker"
 if ((rc)); then
  ui_action error "$label — ошибка ($rc). Журнал: $logfile" >&2
  return "$rc"
 fi
 ui_action success "$label — готово"
}
