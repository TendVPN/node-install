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
declare -A unique_domains
source "$root/vendor/remnawave-reverse-proxy/src/nginx/install_node.sh"
eval "$(declare -f install_node_nginx | sed "s|/opt/remnanode|$tmp/node|g")"
TEND_NODE_SECRET=TEST_SECRET
reading() { case "$2" in SELFSTEAL_DOMAIN) printf -v "$2" '%s' node.example.org;; PANEL_IP) printf -v "$2" '%s' 203.0.113.1;; *) exit 1;; esac; }
install_node_nginx >/dev/null
[[ $CERTIFICATE == TEST_SECRET ]]
grep -q 'remnawave-nginx:' "$tmp/node/docker-compose.yml"
echo 'eGames node renderer/secret: OK'
