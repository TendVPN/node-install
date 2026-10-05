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

## После установки

Откройте новое SSH-соединение и подтвердите доступ:

```sh
ssh -p 22223 root@YOUR_VPS_IP
tend confirm-ssh
```

Для SSH предусмотрен откат через 60 минут, для защиты node-accelerator — через 20 минут. Подтверждение снимает оба таймера. Скрипт не перезагружает сервер; после перезагрузки проверьте доступ и сервисы.

Подключение ноды, inbound и маршруты Xray настройте в панели Remnawave. Psiphon предоставляет локальный SOCKS-прокси для использования в маршрутах.

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

Повторная установка сохраняет существующую ноду. Смена домена требует отдельной настройки.

Программа хранится в `/opt/tend`, конфигурация — в `/etc/tend/config.json`, журналы — в `/var/log/tend`, данные ноды — в `/opt/remnanode`. Конфигурация содержит секрет: не публикуйте её вместе с журналами.

## Исходники

```text
install.sh          загрузка проекта и запуск установки
src/
  tend.sh           команды и обработка параметров
  ui.sh             мастер и сообщения
  server.sh         установка и обслуживание сервера
  config.py         чтение и проверка конфигурации
vendor/             интеграция Remnawave reverse proxy
upstream-lock.json  версии сторонних компонентов
tests/              автоматические проверки
docs/               устройство проекта и проверки
```

Компоненты: [node-accelerator](https://github.com/jestivald/node-accelerator), [TrafficGuard](https://github.com/dotX12/traffic-guard), [Remnawave reverse proxy](https://github.com/eGamesAPI/remnawave-reverse-proxy), [Psiphon](https://github.com/Chara-Freedom/vps-psiphon), [multitest](https://github.com/saveksme/multitest). Коммиты закреплены в `upstream-lock.json`; версии скачиваемых ими контейнеров и бинарных файлов определяются самими компонентами.

[Устройство проекта](docs/ARCHITECTURE.md) · [Проверки](docs/TESTING.md) · [Лицензия MIT](LICENSE)
