# mac/ — LegacyRay для OS X: устройство кода

Описание программы, установка и сборка — в [README](../README.md) в корне.

## Из чего собирается

`make -C mac` (или `make mac` в корне) собирает `build/LegacyRay.app`:

| Часть | Откуда |
|---|---|
| Интерфейс | `mac/Sources` — AppKit, ручное управление памятью (MRC), как у версии для iPhone |
| Ядро программы | `app/Sources/Core` — те же файлы, что в версии для iPhone (клиент демона, туннель, каталог, профили, SSH, QR, локализация); то, что там завязано на UIKit (`LRCompat`, `LRImporter`, `LRQRCode`, `LRReminders`, `LRNetInfo`), здесь написано заново с теми же заголовками |
| Демон и помощники | `daemon/Makefile.mac` (с `-DLR_MACOS`), кладутся в `Contents/Helpers` вместе с `cacert.pem` |
| `legacyray-install` | `mac/helper` — запускает `Resources/install-helper.sh` от root после окна авторизации |

Пути, о которых договариваются программа и демон, — в
`common/senko_paths.h` (ветка `LR_MACOS`).

## Исходники

```
Sources/
  LRAppDelegate     меню программы, окна, установка службы, обновления, ссылки legacyray://
  LRStatusMenu      значок и меню в строке меню
  LRImporter        всё, что добавляет серверы (буфер, файлы, QR с экрана, ссылки)
  LRHelperInstaller установка и удаление службы (AuthorizationExecuteWithPrivileges)
  LRCompat          версия системы, vibrancy, растровые картинки 1x/2x, форматы
  Skin/             LRSkin — две палитры; LRDraw — деним, строчка, карточка, флаги, глифы
  Views/            шапка и заголовок окна (LRTitlebarOverlay на 10.8–10.9), кнопка питания,
                    карточка сервера, список серверов, HUD, алерты
  Windows/          главное окно, настройки, сервер/подписка, «Поделиться», проверка,
                    диагностика, AmneziaWG, свои серверы, «О программе»
  Panes/            LRForm — раскладка вкладок настроек в духе 10.8
Resources/          Info.plist, иконка, plist launchd, install-helper.sh, uninstall-helper.sh
```

Классическая тема на 10.8–10.9 накрывает системный заголовок окна своим
видом (`LRTitlebarOverlay` под кнопками окна), на 10.10+ содержимое окна
заходит под прозрачный заголовок (`NSFullSizeContentViewWindowMask`). Всё
новее 10.8 вызывается через `NSClassFromString`/`respondsToSelector:`.

## Строки

Строки Mac — в `scripts/l10n/mac_strings.py` (английский ключ, русский,
китайский). После правки:

```bash
python3 scripts/l10n/build_mac_inc.py   # → mac/Sources/LRMacStrings.inc и список непереведённого
```

## Режим разработчика

```bash
defaults write com.legacyray.mac LRDeveloperNoHelper -bool YES
LegacyRay.app/Contents/Helpers/legacyrayd --managed --ctl /var/tmp/legacyrayd.sock &
```

Программа перестаёт требовать установленную службу и работает с демоном,
запущенным от пользователя (без pf, только SOCKS). В этом режиме доступны
ссылки `legacyray://dev/…`: `prefs/<general|connection|routing|sites|subs|network|advanced>`,
`window/<main|check|diag|awg|ssh|about|server|share>`, `theme/<auto|classic|flat>`,
`lang/<ru|en|zh>`, `connect/<часть имени>`, `ping`, `reload`, `close`,
`click/<power|card>` (настоящий щелчок через оконный сервер) — через них
сняты скриншоты в `docs/`.

## Как демон заворачивает трафик Mac

`daemon/c_backend.c`, сверху вниз; каждый шаг проверяется живым соединением
(демон сам идёт на example.com:80 и ждёт его на своём прозрачном порту):

1. pf, `route-to lo0` + `rdr` на lo0 — с адресом Mac в источнике (как sshuttle);
2. pf, то же с `nat` в 127.0.0.1 — вариант iPhone;
3. ipfw (есть только в 10.8–10.9);
4. системный прокси: `networksetup -setsocksfirewallproxy` для каждой
   включённой службы сети (`daemon/mac_sysproxy.c`); прежние настройки
   лежат в `/Library/Application Support/LegacyRay/sysproxy.state` и
   возвращаются при отключении, при старте демона после сбоя и при удалении.

Перед pf демон проверяет, что основной набор правил проходит якоря
`com.apple/*` (`pfctl -s nat`, `pfctl -s rules`), и при необходимости
загружает `/etc/pf.conf`; свой `pf.conf` без этих якорей не трогается.
