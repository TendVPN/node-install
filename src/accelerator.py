#!/usr/bin/env python3
"""Adapt the pinned accelerator connlimit rules to explicit dynamic sets."""
from pathlib import Path
import re
import sys


def patch_protect(path):
    path = Path(path)
    text = path.read_text()
    if '# Tend connlimit compatibility' in text:
        return
    pattern = r'meter (cc[46]_\$\{p\}|occ[46]) (\{ ip6? saddr ct count over \$\{CONN_LIMIT\} \})'
    text, count = re.subn(pattern, r'add @\1 \2', text)
    if count != 4:
        raise ValueError('Неожиданная версия protect.sh; правила не изменены')
    marker = '    rate_set "syn4_${p}"'
    if marker not in text or '$RATE_SETS' not in text:
        raise ValueError('Не найден генератор наборов protect.sh')
    text = text.replace(marker, '''    # Tend connlimit compatibility: ct count uses add, without timeout.
    RATE_SETS+="
    set cc4_${p} { type ipv4_addr; size ${NA_RATE_SET_SIZE}; flags dynamic; }
    set cc6_${p} { type ipv6_addr; size ${NA_RATE_SET_SIZE}; flags dynamic; }"
'''+marker, 1)
    text = text.replace('$RATE_SETS', '''$RATE_SETS
    set occ4 { type ipv4_addr; size ${NA_RATE_SET_SIZE}; flags dynamic; }
    set occ6 { type ipv6_addr; size ${NA_RATE_SET_SIZE}; flags dynamic; }''', 1)
    path.write_text(text)


if __name__ == '__main__':
    try:
        patch_protect(sys.argv[1])
    except (OSError, ValueError) as error:
        print('Ошибка адаптера node-accelerator: ' + str(error), file=sys.stderr)
        sys.exit(1)
