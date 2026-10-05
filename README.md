# Node Install

Установка ноды Remnawave на Ubuntu 24.04 с меню для обслуживания VPS. Скрипт настраивает ноду, сертификат, SSH и сетевые порты. Дополнительно доступны node-accelerator, TrafficGuard, Psiphon и multitest.

## Установка

Нужны доступ root, работающая панель Remnawave, домен с A-записью на IP ноды, IPv4 панели, SECRET_KEY ноды и email для сертификата. Откройте 80/tcp и выбранный SSH-порт в firewall провайдера. Для запуска нужны curl, Bash 4.3+ и Python 3.

```sh
curl -fsSL https://raw.githubusercontent.com/TendVPN/node-install/main/install.sh | sh
```

Мастер запросит параметры сервера. Enter принимает предложенное значение; `y` включает компонент, `n` отключает. Флаги позволяют заранее задать ответы.

Для установки без вопросов сохраните SECRET_KEY в `/root/node.secret` с правами `600`:

```sh
curl -fsSL https://raw.githubusercontent.com/TendVPN/node-install/main/install.sh | sh -s -- \
  --node-domain node.example.org \
  --panel-ip 203.0.113.10 \
  --node-secret-file /root/node.secret \
  --email admin@example.org \
  --udp-ports none --xanmod no --non-interactive
```

Добавьте `--dry-run` для проверки параметров перед установкой. Секрет не выводится в плане.

## Настройки

| Флаг | По умолчанию | Назначение |
| --- | --- | --- |
| `--disable-password-auth` | `no` | Закрыть вход по SSH с паролем |
| `--ssh-port` | `22223` | Порт SSH |
| `--tcp-ports` | `443,8443` | Дополнительные TCP-порты |
| `--udp-ports` | `443,8443` | Дополнительные UDP-порты |
| `--whitelist` | пусто | Доверенные IP и CIDR через запятую |
| `--regions` | `DE,NL,FR` | Регионы Psiphon |
| `--optimize` | `yes` | Оптимизации node-accelerator |
| `--protect` | `yes` | Защита node-accelerator |
| `--traffic-guard` | `yes` | Блокировка адресов сканеров |
| `--psiphon` | `yes` | Локальный SOCKS-прокси |
| `--multitest` | `yes` | Утилита проверки сети |
| `--xanmod` | `yes` | Разрешить установку ядра XanMod |

Переключатели принимают `yes` или `no`. `--accelerator no` отключает оптимизации и защиту вместе. `none` для списка портов пропускает дополнительные порты этого протокола. `--guard-urls` задаёт HTTPS-адреса списков TrafficGuard через запятую.

Настройки хранятся в `/etc/tend/config.json`; флаги имеют приоритет. Другой файл выбирается через `--config FILE`. Отключение компонента пропускает его установку, но не удаляет уже установленный компонент. При наличии ds-guard установка XanMod пропускается.

Для отключения пароля используйте `--disable-password-auth yes` или ответьте «да» на вопрос «Закрыть вход по паролю?» в мастере. Отключаются пароль и keyboard-interactive для всех SSH-пользователей. Сначала проверьте вход по ключу в новом соединении. Значение `no` сохраняет текущие настройки аутентификации. Изменение входит в общий откат SSH.

TrafficGuard получает список после вычитания доверенных сетей через временный HTTP-сервер на `127.0.0.1`; сервер закрывается после обновления. Для node-accelerator установщик адаптирует правила `ct count` к динамическим наборам без таймаута. Установка пакетов ждёт освобождения блокировки dpkg до 10 минут.

## После установки

Откройте новое SSH-соединение и подтвердите доступ:

```sh
ssh -p 22223 root@YOUR_VPS_IP
tend confirm-ssh
```

Для SSH предусмотрен откат через 60 минут, для защиты node-accelerator — через 20 минут. Подтверждение снимает оба таймера. Скрипт не перезагружает сервер; после перезагрузки проверьте доступ и сервисы.

Подключение ноды, inbound и маршруты Xray настройте в панели Remnawave. Psiphon предоставляет локальный SOCKS-прокси для использования в маршрутах.

## Пример профиля Remnawave

Пример с VLESS TCP REALITY на 443/tcp и Hysteria 2 на 443/udp. Создайте профиль в панели, замените значения в квадратных скобках и назначьте его ноде. Для Hysteria оставьте UDP-порт 443 открытым (`--udp-ports 443`); вариант установки с `--udp-ports none` выше его не открывает.

Укажите имя ноды, домен, приватный ключ REALITY, short ID и fingerprint клиента. Каталог `/etc/letsencrypt` монтируется в контейнер ноды в режиме чтения. Укажите пути `/etc/letsencrypt/live/[ДОМЕН СЕРТИФИКАТА]/privkey.pem` и `/etc/letsencrypt/live/[ДОМЕН СЕРТИФИКАТА]/fullchain.pem` (имя каталога может отличаться от домена ноды). Salamander используется по желанию: если он не нужен, удалите массив `finalmask.udp`; при использовании задайте одинаковый пароль на сервере и клиенте.

Адрес `172.17.0.1:1080` в примере — адрес SOCKS-прокси Psiphon. Проверьте его доступность из контейнера: установщик запускает Psiphon с `--bind-loopback`, поэтому для доступа через Docker bridge потребуется отдельная настройка адреса прослушивания и firewall. Если Psiphon не используется, удалите `psiphon-out` и правило для доменов Google AI.

```json
{
  "log": {
    "loglevel": "none"
  },
  "inbounds": [
    {
      "tag": "[НАЗВАНИЕ НОДЫ]_VLESS_TCP_REALITY",
      "port": 443,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "xver": 1,
          "target": "/dev/shm/nginx.sock",
          "shortIds": ["[SHORT_ID]"],
          "privateKey": "[ПРИВАТНЫЙ КЛЮЧ]",
          "fingerprint": "[FINGERPRINT]",
          "serverNames": ["[ДОМЕН НОДЫ]"]
        }
      }
    },
    {
      "tag": "[НАЗВАНИЕ НОДЫ]_HYSTERIA",
      "port": 443,
      "listen": "0.0.0.0",
      "protocol": "hysteria",
      "settings": {
        "clients": [],
        "version": 2
      },
      "streamSettings": {
        "network": "hysteria",
        "security": "tls",
        "finalmask": {
          "udp": [
            {
              "type": "salamander",
              "settings": {
                "password": "[ПАРОЛЬ SALAMANDER]"
              }
            }
          ],
          "quicParams": {
            "debug": false,
            "congestion": "bbr"
          }
        },
        "tlsSettings": {
          "alpn": ["h3"],
          "serverName": "[ДОМЕН НОДЫ]",
          "certificates": [
            {
              "keyFile": "[ПУТЬ К privkey.pem]",
              "certificateFile": "[ПУТЬ К fullchain.pem]"
            }
          ]
        },
        "hysteriaSettings": {
          "version": 2
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "psiphon-out",
      "protocol": "socks",
      "settings": {
        "port": 1080,
        "address": "172.17.0.1"
      },
      "streamSettings": {
        "sockopt": {
          "domainStrategy": "UseIPv4"
        }
      }
    },
    {
      "tag": "DIRECT",
      "protocol": "freedom"
    },
    {
      "tag": "BLOCK",
      "protocol": "blackhole"
    }
  ],
  "routing": {
    "rules": [
      {
        "port": "25,465,587",
        "type": "field",
        "outboundTag": "BLOCK"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "BLOCK"
      },
      {
        "type": "field",
        "domain": ["geosite:category-ads-all", "geosite:win-spy"],
        "outboundTag": "BLOCK"
      },
      {
        "ip": ["geoip:private"],
        "type": "field",
        "outboundTag": "BLOCK"
      },
      {
        "type": "field",
        "domain": [
          "domain:gemini.google.com",
          "domain:generativelanguage.googleapis.com",
          "domain:ai.google.dev",
          "domain:aistudio.google.com"
        ],
        "outboundTag": "psiphon-out"
      },
      {
        "type": "field",
        "inboundTag": [
          "[НАЗВАНИЕ НОДЫ]_VLESS_TCP_REALITY",
          "[НАЗВАНИЕ НОДЫ]_HYSTERIA"
        ],
        "outboundTag": "DIRECT"
      }
    ],
    "domainStrategy": "AsIs"
  }
}
```

## Управление VPS

```sh
tend-menu                            # меню обслуживания
tend status                          # состояние сервисов
tend configure                       # сохранить настройки
tend plan --non-interactive           # показать план
tend install --non-interactive        # повторная установка
tend whitelist add 203.0.113.5        # добавить доверенный IP
tend whitelist remove 203.0.113.5     # удалить доверенный IP
tend whitelist refresh               # обновить списки защиты
tend --help                          # справка
```

Повторная установка сохраняет существующую ноду. Для ранее установленной ноды она добавляет монтирование сертификатов в Compose и применяет его к `remnanode`; исходный Compose сохраняется в `docker-compose.yml.before-certificates`. Смена домена требует отдельной настройки.

Программа хранится в `/opt/tend`, конфигурация — в `/etc/tend/config.json`, журналы — в `/var/log/tend`, данные ноды — в `/opt/remnanode`. Конфигурация содержит секрет: не публикуйте её вместе с журналами.

## Исходники

```text
install.sh          загрузка проекта и запуск установки
src/
  tend.sh           команды и обработка параметров
  ui.sh             мастер и сообщения
  server.sh         установка и обслуживание сервера
  config.py         чтение и проверка конфигурации
  compose.py        исправление монтирования сертификатов
  guard.py          передача списка TrafficGuard через loopback
  accelerator.py    совместимость правил connlimit nftables
vendor/             интеграция Remnawave reverse proxy
upstream-lock.json  версии сторонних компонентов
tests/              автоматические проверки
docs/               устройство проекта и проверки
```

Компоненты: [node-accelerator](https://github.com/jestivald/node-accelerator), [TrafficGuard](https://github.com/dotX12/traffic-guard), [Remnawave reverse proxy](https://github.com/eGamesAPI/remnawave-reverse-proxy), [Psiphon](https://github.com/Chara-Freedom/vps-psiphon), [multitest](https://github.com/saveksme/multitest). Коммиты закреплены в `upstream-lock.json`; версии скачиваемых ими контейнеров и бинарных файлов определяются самими компонентами.

[Устройство проекта](docs/ARCHITECTURE.md) · [Проверки](docs/TESTING.md) · [Лицензия MIT](LICENSE)
