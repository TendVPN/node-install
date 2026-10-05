#!/usr/bin/env python3
"""Add the certificate bind mount to an installer-generated node Compose file."""
from pathlib import Path
import os
import re
import shutil
import sys
import tempfile


def add_certificate_mount(path):
    path = Path(path)
    original = path.read_text()
    lines = original.splitlines(keepends=True)
    start = next((i for i, line in enumerate(lines) if line.rstrip() == '  remnanode:'), None)
    if start is None:
        raise ValueError('Не найден сервис remnanode в Compose')
    end = next((i for i in range(start + 1, len(lines))
                if lines[i].strip() and not lines[i].lstrip().startswith('#')
                and len(lines[i]) - len(lines[i].lstrip()) <= 2), len(lines))
    volumes = next((i for i in range(start + 1, end) if lines[i].rstrip() == '    volumes:'), None)
    if volumes is None:
        raise ValueError('Не найден список volumes ноды в Compose; требуется ручная настройка')
    volume_end = next((i for i in range(volumes + 1, end)
                       if lines[i].strip() and not lines[i].lstrip().startswith('#')
                       and len(lines[i]) - len(lines[i].lstrip()) <= 4), end)
    mount = '/etc/letsencrypt:/etc/letsencrypt:ro'
    for line in lines[volumes + 1:volume_end]:
        value = line.strip().removeprefix('-').strip().split(' #', 1)[0].strip().strip('\'"')
        if value == mount:
            return False
        if re.search(r':/etc/letsencrypt(?:[:/]|$)', value):
            raise ValueError('Найден другой mount /etc/letsencrypt; требуется ручная настройка')
    lines.insert(volumes + 1, '      - ' + mount + '\n')
    # Keep the original alongside Compose, including its permissions.
    backup = path.with_name(path.name + '.before-certificates')
    if backup.exists():
        raise ValueError('Резервная копия уже существует: ' + str(backup))
    shutil.copy2(path, backup)
    fd, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as out:
            out.write(''.join(lines))
        os.chmod(temporary, path.stat().st_mode & 0o777)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return True


if __name__ == '__main__':
    try:
        print('changed' if add_certificate_mount(sys.argv[1]) else 'unchanged')
    except (OSError, ValueError) as error:
        print('Ошибка Compose: ' + str(error), file=sys.stderr)
        sys.exit(1)
