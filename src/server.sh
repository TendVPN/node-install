#!/usr/bin/env bash
require_server() {
 [[ $EUID == 0 ]] || fail 'Запустите через sudo/root'
 source /etc/os-release
 [[ $ID == ubuntu && $VERSION_ID == 24.04 ]] || fail 'Поддерживается Ubuntu 24.04'
}
fetch_upstream() {
 local name=$1 repo=$2 sha dest=/var/lib/tend/upstream/$1
 sha=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$ROOT/upstream-lock.json" "$name")
 if [[ ! -f $dest/.tend-commit || $(cat "$dest/.tend-commit") != "$sha" ]]; then
  local staging; staging=$(mktemp -d /var/lib/tend/upstream/.download.XXXXXXXX)
  curl --proto '=https' --tlsv1.2 -fSL --retry 3 --connect-timeout 20 "https://codeload.github.com/$repo/tar.gz/$sha" -o "$staging/source.tgz"
  mkdir "$staging/source"; tar -xzf "$staging/source.tgz" -C "$staging/source" --strip-components=1
  printf '%s\n' "$sha" > "$staging/source/.tend-commit"
  rm -rf "$dest"; mv "$staging/source" "$dest"; rm -rf "$staging"
 fi
}
install_cli() {
 mkdir -p /opt/tend /etc/tend /var/lib/tend/upstream /var/log/tend
 if [[ $ROOT != /opt/tend ]]; then
  cp -a "$ROOT/src" "$ROOT/vendor" "$ROOT/upstream-lock.json" /opt/tend/
 fi
 # Remove obsolete installer modules from earlier Tend versions, not service data.
 local family module
 for family in nginx caddy; do
  for module in install_panel install_panel_node install_sub; do
   rm -f "/opt/tend/vendor/remnawave-reverse-proxy/src/$family/$module.sh"
  done
 done
 rm -f /opt/tend/vendor/remnawave-reverse-proxy/src/modules/manage_panel.sh
 if [[ -f /opt/tend/lib/ssh-client.sh ]]; then rm -- /opt/tend/lib/ssh-client.sh; fi
 chmod -R go-rwx /etc/tend /var/lib/tend /var/log/tend
 cat >/usr/local/bin/tend <<'EOF'
#!/usr/bin/env bash
exec bash /opt/tend/src/tend.sh "$@"
EOF
 cat >/usr/local/bin/tend-menu <<'EOF'
#!/usr/bin/env bash
exec bash /opt/tend/src/tend.sh menu "$@"
EOF
 chmod 755 /usr/local/bin/tend /usr/local/bin/tend-menu
}
setup_ssh() {
 ui_action info "Настройка SSH и таймера отката"
 local port=${C[ssh_port]}
 # Socket activation may leave this runtime directory absent before ssh.service starts.
 install -d -o root -g root -m 0755 /run/sshd
 mkdir -p /var/lib/tend/ssh-backup
 cp -a /etc/ssh/sshd_config /etc/ssh/sshd_config.d /var/lib/tend/ssh-backup/
 # Remove explicit Port directives, preserving originals in the backup.
 sed -i -E '/^[[:space:]]*Port[[:space:]]+/d' /etc/ssh/sshd_config
 find /etc/ssh/sshd_config.d -type f -name '*.conf' -exec sed -i -E '/^[[:space:]]*Port[[:space:]]+/d' {} +
 printf 'Port %s\n' "$port" >/etc/ssh/sshd_config.d/00-tend-port.conf
 if [[ ${C[disable_password_auth]:-no} == yes ]]; then
  # Remove overrides, including Match blocks; originals are in the SSH backup.
  local auth_pattern='/^[[:space:]]*(PasswordAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication)[[:space:]]+/Id'
  sed -i -E "$auth_pattern" /etc/ssh/sshd_config
  find /etc/ssh/sshd_config.d -type f -name '*.conf' -exec sed -i -E "$auth_pattern" {} +
  sed -i '1i PasswordAuthentication no\nKbdInteractiveAuthentication no\nChallengeResponseAuthentication no' /etc/ssh/sshd_config
 fi
 if ! /usr/sbin/sshd -t; then
  cp -a /var/lib/tend/ssh-backup/sshd_config /etc/ssh/
  rm -f /etc/ssh/sshd_config.d/00-tend-port.conf
  cp -a /var/lib/tend/ssh-backup/sshd_config.d/. /etc/ssh/sshd_config.d/
  fail 'Ошибка sshd_config; исходная конфигурация SSH восстановлена'
 fi
 # Rollback is armed before any listener change. It persists across reboot.
 cat >/var/lib/tend/ssh-rollback.sh <<'EOF'
#!/bin/bash
cp -a /var/lib/tend/ssh-backup/sshd_config /etc/ssh/sshd_config
rm -rf /etc/ssh/sshd_config.d
cp -a /var/lib/tend/ssh-backup/sshd_config.d /etc/ssh/
systemctl unmask ssh.service
systemctl enable ssh.service
systemctl restart ssh.service
EOF
 chmod 700 /var/lib/tend/ssh-rollback.sh
 cat >/etc/systemd/system/tend-ssh-rollback.service <<'EOF'
[Unit]
Description=Tend SSH rollback
[Service]
Type=oneshot
ExecStart=/var/lib/tend/ssh-rollback.sh
EOF
 cat >/etc/systemd/system/tend-ssh-rollback.timer <<'EOF'
[Unit]
Description=Rollback unconfirmed SSH change
[Timer]
OnActiveSec=60min
OnBootSec=60min
Unit=tend-ssh-rollback.service
[Install]
WantedBy=timers.target
EOF
 systemctl daemon-reload
 systemctl enable --now tend-ssh-rollback.timer
 if command -v ufw >/dev/null; then ufw allow "$port/tcp"; fi
 systemctl disable --now ssh.socket
 systemctl mask ssh.socket
 systemctl unmask ssh.service
 systemctl enable ssh.service
 systemctl restart ssh.service
 /usr/sbin/sshd -T | grep -x "port $port" >/dev/null || fail 'SSH не применил порт'
 ss -H -ltn "sport = :$port" | grep . >/dev/null || fail 'SSH не слушает новый порт'
}
confirm_ssh() {
 require_server
 [[ -n ${SSH_CONNECTION:-} ]] || fail 'Нет SSH_CONNECTION. В SSH-сессии root выполните: tend confirm-ssh; для sudo: sudo --preserve-env=SSH_CONNECTION tend confirm-ssh'
 local client cport server sport
 read -r client cport server sport <<<"$SSH_CONNECTION"
 [[ $sport == "${C[ssh_port]}" ]] || fail "Соединение должно быть на порту ${C[ssh_port]}"
 systemctl disable --now tend-ssh-rollback.timer
 ui_action success 'SSH подтверждён; таймер отката SSH снят.'
 if [[ ${C[protect]} == yes ]]; then
  if ! nft list table inet na_filter >/dev/null 2>&1; then
   fail 'SSH подтверждён, но защита accelerator отсутствует. Возможен откат по таймеру 20 минут. Запустите tend-menu → 8 (Защита), затем откройте НОВОЕ SSH-соединение и выполните tend confirm-ssh в течение 20 минут. Журнал отката: journalctl -u na-fw-safety.service --no-pager'
  fi
  systemctl stop na-fw-safety.timer 2>/dev/null || true
 fi
 if [[ ${C[protect]} == yes ]]; then
  ui_action success 'Защита accelerator активна; её таймер отката снят.'
 fi
}
service_tcp_ports() {
 local ports=80
 [[ ${C[tcp_ports]} == none ]] || ports+=",${C[tcp_ports]}"
 printf '%s' "$ports"
}
accelerator() {
 ui_action info "Запуск node-accelerator: $1"
 fetch_upstream node-accelerator jestivald/node-accelerator
 local dir=/var/lib/tend/upstream/node-accelerator
 if [[ $1 == optimize ]]; then
  local enable_kernel=0
  [[ ${C[xanmod]} != yes ]] || enable_kernel=1
  if [[ -f /etc/systemd/system/ds-guard.service && $enable_kernel == 1 ]]; then
   echo 'DoubleServers ds-guard обнаружен: штатное ядро сохраняется для совместимости его модулей. Остальная optimize выполняется.'
   enable_kernel=0
  fi
  ENABLE_XANMOD=$enable_kernel bash "$dir/scripts/optimize.sh" </dev/null
 else
  REMNAWAVE_NONINTERACTIVE=1 SSH_PORT="${C[ssh_port]}" TCP_PORTS="$(service_tcp_ports)" UDP_PORTS="${C[udp_ports]}" \
   NODE_PORT=2222 NODE_PORT_WHITELIST_ONLY=1 WHITELIST="${C[whitelist]:-none}" FW_MODE=strict \
   SAFETY_DELAY=1200 ENABLE_PORTSCAN_BAN=0 ENABLE_CROWDSEC=0 bash "$dir/scripts/protect.sh" </dev/null
 fi
}
guard_refresh() {
 ui_action info "Обновление списков TrafficGuard"
 local staging; staging=$(mktemp -d /var/lib/tend/.guard.XXXXXXXX)
 local urls=() url n=0
 IFS=',' read -ra urls <<<"${C[guard_urls]}"
 for url in "${urls[@]}"; do
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL --retry 3 --connect-timeout 20 --max-time 120 "$url" -o "$staging/list-$n"
  n=$((n+1))
 done
 cat "$staging"/list-* > "$staging/all"
 python3 "$ROOT/src/config.py" subtract "$staging/all" "${C[whitelist]}" > "$staging/filtered"
 [[ -s $staging/filtered ]] || fail 'Пустой список блокировки; прежние правила сохранены'
 traffic-guard full -u "file://$staging/filtered" </dev/null
 mv "$staging/filtered" /var/lib/tend/guard-filtered.list
 rm -rf "$staging"
}
install_guard() {
 ui_action info "Установка TrafficGuard"
 fetch_upstream traffic-guard dotX12/traffic-guard
 bash /var/lib/tend/upstream/traffic-guard/install.sh </dev/null
 guard_refresh
 cat >/etc/systemd/system/tend-guard-refresh.service <<'EOF'
[Unit]
Description=Refresh TrafficGuard with Tend whitelist
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/opt/tend/src/tend.sh whitelist refresh
EOF
 # The internal refresh action is added below by whitelist_change.
 cat >/etc/systemd/system/tend-guard-refresh.timer <<'EOF'
[Unit]
Description=Daily scanner-list refresh
[Timer]
OnCalendar=daily
RandomizedDelaySec=30min
Persistent=true
[Install]
WantedBy=timers.target
EOF
 systemctl daemon-reload; systemctl enable --now tend-guard-refresh.timer
}
whitelist_change() {
 require_server
 local action=$1 ips=${2:-}
 exec 8>/var/lib/tend/install.lock; flock -n 8 || fail 'Уже идёт установка/изменение настроек'
 if [[ $action != refresh ]]; then
  C[whitelist]=$(python3 - "${C[whitelist]}" "$ips" "$action" <<'PY'
import sys,ipaddress
old=[x for x in sys.argv[1].split(',') if x]; new=sys.argv[2].split(',')
for x in new: ipaddress.ip_network(x,strict=False)
if sys.argv[3]=='add': old=list(dict.fromkeys(old+new))
elif sys.argv[3]=='remove': old=[x for x in old if x not in new]
else: raise SystemExit('Используйте add/remove')
print(','.join(old))
PY
)
  save /etc/tend/config.json
 fi
 [[ ${C[traffic_guard]} != yes ]] || guard_refresh
 if [[ ${C[protect]} == yes && $action != refresh ]]; then ui_step "Обновление защиты" accelerator protect; fi
 ui_action success 'Белый список обновлён.'
}
repair_node_certificate_mount() {
 local compose=/opt/remnanode/docker-compose.yml
 [[ -f $compose ]] || fail "Не найден $compose"
 local changed
 changed=$(python3 "$ROOT/src/compose.py" "$compose")
 if [[ $changed == changed ]]; then
  ui_action info 'Добавлен доступ ноды к сертификатам; пересоздание remnanode'
 fi
 docker compose -f "$compose" config -q
 docker compose -f "$compose" up -d --no-deps remnanode
}
install_remnawave() {
 ui_action info "Установка Remnawave: ${C[role]}"
 if [[ -f /var/lib/tend/remnawave-role ]]; then
  [[ $(cat /var/lib/tend/remnawave-role) == "${C[role]}" ]] || fail "Смена установленной роли требует отдельного VPS или ручной миграции"
  repair_node_certificate_mount
  echo "Remnawave уже установлен; существующая установка сохранена."; return 0
 fi
 export TEND_NODE_SECRET=${C[node_secret]:-}
 (
  # Upstream was written without nounset/errexit; use its explicit error checks.
  set +u
  set +o pipefail
  source "$ROOT/vendor/remnawave-reverse-proxy/library.sh"
  mkdir -p "$DIR_REMNAWAVE"
  set_language ru
  clear() { :; }
  spinner() { echo "Ожидание операции…"; wait "$1"; }
  check_domain() {
   local resolved server_ip
   resolved=$(dig +time=3 +tries=2 +short A "$1" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
   server_ip=$(curl -4 -fsS --connect-timeout 10 --max-time 20 https://api.ipify.org)
   [[ -n $server_ip ]] && printf '%s\n' "$resolved" | grep -x "$server_ip" >/dev/null || { echo "DNS $1 должен указывать напрямую на IPv4 этого VPS" >&2; exit 1; }
  }
  reading() {
   local key=$2 val
   case $key in
   SELFSTEAL_DOMAIN) val=${C[node_domain]};;
   PANEL_IP) val=${C[panel_ip]};; auth_choice|sub_auth_choice) val=1;;
   cert_method) val=4;; letsencrypt_email) val=${C[email]};;
   *) echo "Неожиданный запрос upstream: $key" >&2; exit 1;; esac
   printf -v "$key" '%s' "$val"
  }
  reading_yn() { echo 'Upstream запросил незапланированное подтверждение' >&2; exit 1; }
  load_selfsteal_templates_module() { :; }
  randomhtml() { mkdir -p /var/www/html; printf '<!doctype html><html lang="ru"><meta charset="utf-8"><title>Добро пожаловать</title><h1>Добро пожаловать</h1></html>\n' >/var/www/html/index.html; chmod 755 /var/www/html; chmod 644 /var/www/html/index.html; }
  CERT_METHOD=4 LETSENCRYPT_EMAIL=${C[email]}
  load_api_module
  load_install_node_module
  installation_node
 ) </dev/null
 printf '%s\n' "${C[role]}" >/var/lib/tend/remnawave-role
}
configure_firewall_ports() {
 local tcp; tcp=$(service_tcp_ports)
 for port in ${tcp//,/ }; do ufw allow "$port/tcp"; done
 if [[ ${C[udp_ports]} != none ]]; then
  for port in ${C[udp_ports]//,/ }; do ufw allow "$port/udp"; done
 fi
 ufw allow 80/tcp
 [[ -z ${C[panel_ip]:-} ]] || ufw allow from "${C[panel_ip]}" to any port 2222 proto tcp
}
install_psiphon() {
 fetch_upstream vps-psiphon Chara-Freedom/vps-psiphon
 bash /var/lib/tend/upstream/vps-psiphon/psiphon_install.sh --region "${C[regions]}" --bind-loopback --no-http </dev/null
}
install_multitest() {
 fetch_upstream multitest saveksme/multitest
 ln -sf /var/lib/tend/upstream/multitest/multitest.sh /usr/local/bin/multitest
 chmod +x /var/lib/tend/upstream/multitest/multitest.sh
}
install_server() {
 require_server
 mkdir -p /var/lib/tend /var/log/tend
 chmod 700 /var/log/tend
 local logfile=/var/log/tend/install-$(date -u +%Y%m%dT%H%M%SZ).log
 touch "$logfile"; chmod 600 "$logfile"
 local TEND_LOGFILE=$logfile
 ui_action info "Журнал установки: $logfile"
 exec 8>/var/lib/tend/install.lock; flock -n 8 || fail 'Уже идёт установка'
 export DEBIAN_FRONTEND=noninteractive
 ui_step "Обновление списка пакетов" apt-get update
 ui_step "Установка зависимостей" apt-get install -y curl ca-certificates python3 openssh-server ufw iptables ipset nftables certbot jq openssl cron docker.io docker-compose-v2 dnsutils rsync
 ui_step "Запуск Docker и cron" systemctl enable --now docker cron
 ui_step "Установка tend-menu" install_cli
 # Preserve secret configuration only on this machine, never in the project.
 local connection=${SSH_CONNECTION:-}
 local admin=${connection%% *}
 if [[ -n $admin && ,${C[whitelist]}, != *,$admin,* ]]; then C[whitelist]=${C[whitelist]:+${C[whitelist]},}$admin; fi
 if [[ -n ${C[panel_ip]:-} && ,${C[whitelist]}, != *,${C[panel_ip]},* ]]; then C[whitelist]=${C[whitelist]:+${C[whitelist]},}${C[panel_ip]}; fi
 save /etc/tend/config.json
 ui_step "Настройка SSH" setup_ssh
 ui_step "Настройка портов firewall" configure_firewall_ports
 if [[ ${C[protect]} == yes ]] && nft list table inet na_filter >/dev/null 2>&1; then ui_step "Обновление защиты" accelerator protect; fi
 ui_step "Установка ноды Remnawave" install_remnawave
 [[ ${C[optimize]} != yes ]] || ui_step "Оптимизация сети и ядра" accelerator optimize
 [[ ${C[psiphon]} != yes ]] || ui_step "Установка Psiphon" install_psiphon
 [[ ${C[multitest]} != yes ]] || ui_step "Установка multitest" install_multitest
 [[ ${C[traffic_guard]} != yes ]] || ui_step "Установка TrafficGuard" install_guard
 [[ ${C[protect]} != yes ]] || ui_step "Установка защиты" accelerator protect
 ui_action success "Установка завершена. Подключитесь НОВОЙ сессией на ${C[ssh_port]} и выполните от root: tend confirm-ssh"
 echo 'Проверка после перезагрузки обязательна. Автоматическая перезагрузка не выполняется.'
}
status() {
 ui_action info "Проверка состояния сервисов"
 for unit in ssh docker cron tend-guard-refresh.timer na-firewall.service vps-psiphon.service; do systemctl --no-pager --full status "$unit" || true; done
 command -v docker >/dev/null && docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
}
server_menu() {
 require_server
 while true; do
  ui_heading 'TEND · Управление VPS'
  ui_note 'Выберите действие; установка и настройки относятся к этому серверу.'
  echo '1) Статус  2) Доустановка / параметры  3) Добавить IP в whitelist'
  echo '4) Удалить IP из whitelist  5) Multitest  6) Psiphon status'
  echo '7) Optimize  8) Защита  9) Подтвердить SSH  0) Выход'
  local answer ips
  read -rp "${UI_BLUE}Выбор [0]: ${UI_RESET}" answer </dev/tty || return
  case ${answer:-0} in
  0) return;; 1) status;;
  2) bash "$ROOT/src/tend.sh" install || ui_action error 'Установка прервана; подробности выше.';;
  3|4) read -rp 'IP/CIDR через запятую: ' ips </dev/tty; bash "$ROOT/src/tend.sh" whitelist "$([[ $answer == 3 ]] && echo add || echo remove)" "$ips";;
  5) [[ -f /var/lib/tend/upstream/multitest/multitest.sh ]] || fetch_upstream multitest saveksme/multitest; bash /var/lib/tend/upstream/multitest/multitest.sh </dev/tty;;
  6) vps-psiphon status;; 7) ui_step "Оптимизация сети и ядра" accelerator optimize;; 8) ui_step "Установка защиты" accelerator protect;; 9) confirm_ssh;; *) ui_action warning 'Выберите 0–9';;
  esac
 done
}
