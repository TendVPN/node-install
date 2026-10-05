#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "Upstream test failed at line $LINENO" >&2' ERR
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
set +u
set +o pipefail
source "$root/vendor/remnawave-reverse-proxy/library.sh"
set_language ru
check_domain() { return 0; }
load_selfsteal_templates_module() { :; }
declare -A unique_domains
source "$root/vendor/remnawave-reverse-proxy/src/nginx/install_node.sh"
eval "$(declare -f install_node_nginx | sed "s|/opt/remnanode|$tmp/node|g")"
TEND_NODE_SECRET=TEST_SECRET
reading() { case "$2" in SELFSTEAL_DOMAIN) printf -v "$2" '%s' node.example.org;; PANEL_IP) printf -v "$2" '%s' 203.0.113.1;; *) exit 1;; esac; }
install_node_nginx >/dev/null
[[ $CERTIFICATE == TEST_SECRET ]]
grep -q 'remnawave-nginx:' "$tmp/node/docker-compose.yml"
echo 'eGames node renderer/secret: OK'

# Render the complete installation without touching services or real certificates.
eval "$(declare -f installation_node | sed "s|/opt/remnanode|$tmp/node|g; s|/dev/shm/nginx.sock|$tmp/nginx.sock|g")"
check_node_not_running() { :; }
check_port_443_free() { :; }
load_certificates_module() { :; }
handle_certificates() { :; }
resolve_certificate_domain() { echo node.example.org; }
ufw() { :; }
sleep() { :; }
docker() { if [[ $1 == inspect ]]; then echo true; fi; }
spinner() { wait "$1"; }
randomhtml() { :; }
CERT_METHOD=4 LETSENCRYPT_EMAIL=admin@example.org
python3 - "$tmp/nginx.sock" <<'PYTEST'
import socket, sys
sock = socket.socket(socket.AF_UNIX)
sock.bind(sys.argv[1])
sock.close()
PYTEST
installation_node >/dev/null
python3 - "$tmp/node/docker-compose.yml" <<'PYTEST'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
node = text.split('  remnanode:', 1)[1]
assert '      - /etc/letsencrypt:/etc/letsencrypt:ro' in node
assert 'SECRET_KEY=TEST_SECRET' in node
PYTEST
echo 'Node certificate mount: OK'
