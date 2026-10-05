#!/bin/sh
# Run on the VPS: curl .../install.sh | sh -s -- [installation flags]
set -eu
repo=${TEND_REPO:-TendVPN/node-install}; ref=${TEND_REF:-main}
while [ "$#" -gt 0 ]; do
 case "$1" in
 --repo) repo=${2:?Укажите репозиторий}; shift 2;;
 --ref) ref=${2:?Укажите ветку или commit}; shift 2;;
 --) shift; break;; *) break;; esac
done
case "${1:-}" in --help|-h) :;; *)
 [ "$(id -u)" = 0 ] || { echo 'Запускайте установщик на VPS от root или через sudo.' >&2; exit 1; };; esac
printf '%s' "$repo" | LC_ALL=C grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || exit 2
printf '%s' "$ref" | LC_ALL=C grep -Eq '^[A-Za-z0-9_.-]+$' || exit 2
command -v bash >/dev/null || { echo 'Нужен Bash 4.3+' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'Установите Python 3: apt install python3' >&2; exit 1; }
command -v curl >/dev/null || exit 1
staging=$(mktemp -d); trap 'rm -rf "$staging"' EXIT HUP INT TERM
curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL --retry 3 "https://codeload.github.com/$repo/tar.gz/$ref?tend=$(date +%s)" -o "$staging/source.tgz"
tar -xzf "$staging/source.tgz" -C "$staging" --strip-components=1
bash "$staging/src/tend.sh" install "$@"
