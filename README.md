# WireproxyBar 🛡️

**WireproxyBar** — это ультралегковесное нативное меню-бар приложение для macOS (Apple Silicon), позволяющее в один клик управлять [wireproxy](https://github.com/windtf/wireproxy) (userspace WireGuard-клиент с SOCKS5/HTTP прокси).

---

## Возможности

- 🚀 **Полная автономность:** `wireproxy` встроен прямо внутрь приложения. Никаких установок через терминал или Homebrew не требуется.
- ⚡️ **Мгновенный статус:** Адаптивная иконка в строке меню: пустой щит при выключении, полный щит при подключении.
- 📋 **Копирование параметров в один клик:** Нажмите на адрес SOCKS5 или HTTP в меню, чтобы мгновенно скопировать хост и порт в буфер обмена.
- 🌐 **Двуязычный интерфейс:** Автоматически подстраивается под системный язык macOS (русский для русскоязычной системы, английский для всех остальных).
- 📜 **Интеграция с Консолью macOS:** Кнопка «Показать логи...» открывает `Console.app` с живым потоком логов туннеля в реальном времени (`Cmd + L`).
- 🛠 **Автошаблон конфига:** При первом запуске или отсутствии конфигурации приложение само создаст шаблон `~/.config/wireproxy/wireproxy.conf` с правами `0600` и откроет его.

---

## Установка

### Вариант 1: Загрузка готового релиза
Скачайте актуальный `.dmg` из раздела [Releases](https://github.com/eychu/WireproxyBar/releases) и перетащите `WireproxyBar` в папку `Applications`.

### Вариант 2: Сборка из исходников
```bash
git clone https://github.com/eychu/WireproxyBar.git
cd WireproxyBar
./scripts/build.sh
cp -R build/WireproxyBar.app ~/Applications/
```

---

## Настройка подключения

Файл конфигурации хранится по пути:  
`~/.config/wireproxy/wireproxy.conf`

Пример конфигурации:
```ini
[Interface]
PrivateKey = YOUR_PRIVATE_KEY
Address = 10.5.5.3/32
DNS = 1.1.1.1

[Peer]
PublicKey = SERVER_PUBLIC_KEY
AllowedIPs = 0.0.0.0/0
Endpoint = your.server.ip:51820
PersistentKeepalive = 25

# SOCKS5-прокси
[Socks5]
BindAddress = 127.0.0.1:1080

# HTTP-прокси
[Http]
BindAddress = 127.0.0.1:8080
```

---

## Использование с приложениями

### В терминале:
```bash
export all_proxy="socks5h://127.0.0.1:1080"
curl https://ifconfig.me/ip
```

### В Telegram:
*Настройки → Данные и память → Прокси → Добавить SOCKS5* (`127.0.0.1:1080`).

### В браузере:
Используйте расширение (например, *ZeroOmega* / *Proxy SwitchyOmega*) с SOCKS5 прокси на `127.0.0.1:1080`.

---

## CI/CD и Notarization

В репозитории настроен GitHub Actions workflow (`.github/workflows/release.yml`), который при создании тега `v*`:
1. Автоматически скачивает свежий релиз `wireproxy`.
2. Компилирует приложение на раннере macOS Apple Silicon.
3. Подписывает бинарники сертификатом Apple Developer ID.
4. Отправляет DMG на нотаризацию в Apple (`notarytool`).
5. Прикрепляет нотариальный билет (`stapler`) и публикует релиз на GitHub.

### Секреты для GitHub Actions (Repository Secrets):
* `MACOS_CERTIFICATE_BASE64` — экспорт сертификата Developer ID Application (`.p12` в base64).
* `MACOS_CERTIFICATE_PWD` — пароль от `.p12`.
* `MACOS_SIGNING_IDENTITY` — имя сертификата (например, `Developer ID Application: Your Name (TEAM_ID)`).
* `APPLE_ID` — ваш Apple ID.
* `APPLE_TEAM_ID` — Team ID из Apple Developer портала.
* `APPLE_APP_SPECIFIC_PASSWORD` — пароль для приложения, созданный на appleid.apple.com.

---

## Лицензия

MIT License © 2026 eychu
