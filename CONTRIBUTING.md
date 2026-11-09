# Участие · Contributing

**Русский** · [English](#english)

Спасибо, что хочешь помочь! Пара правил, чтобы всё оставалось аккуратным.

- **Ошибки** — через [шаблон](https://github.com/Rolarn/davinci-control/issues/new?template=bug.yml) с файлом диагностики из панели.
- **Идеи** — через [шаблон идеи](https://github.com/Rolarn/davinci-control/issues/new?template=idea.yml). Метки: `idea` — предложено, `planned` — в планах, `done` — сделано, `won't` — не будет.
- **Код.** Скрипты — POSIX sh для BusyBox ash, панель — HTML, CSS и JavaScript без библиотек.
- **Тексты — на двух языках.** Каждая строка панели есть в русском и английском (`module/webroot/i18n.js`), каждое сообщение журнала — в `module/strings.tsv`. Тест проверяет, что ничего не пропущено.
- **Версии** — SemVer; `versionCode = MAJOR×10000 + MINOR×100 + PATCH`.
- **Проверки:** `bash tests/run_all.sh` (нужны busybox, shellcheck, Node.js и Playwright). Сборка — `scripts/build.sh`.
- **Никаких личных данных** в коммитах: логи, диагностика, номера, списки приложений.
- **Модель** пишем как «Mi 9T / Redmi K20 (davinci)».

## English

Thanks for wanting to help! A few rules to keep things tidy.

- **Bugs** — via the [template](https://github.com/Rolarn/davinci-control/issues/new?template=bug.yml) with the diagnostics file from the panel.
- **Ideas** — via the [idea template](https://github.com/Rolarn/davinci-control/issues/new?template=idea.yml). Labels: `idea` — proposed, `planned` — planned, `done` — done, `won't` — will not happen.
- **Code.** Scripts are POSIX sh for BusyBox ash, the panel is HTML, CSS and JavaScript without libraries.
- **Texts in two languages.** Every panel string exists in Russian and English (`module/webroot/i18n.js`), every log message in `module/strings.tsv`. A test checks nothing is missing.
- **Versions** — SemVer; `versionCode = MAJOR×10000 + MINOR×100 + PATCH`.
- **Checks:** `bash tests/run_all.sh` (needs busybox, shellcheck, Node.js and Playwright). Build — `scripts/build.sh`.
- **No personal data** in commits: logs, diagnostics, numbers, app lists.
- **The model** is written as “Mi 9T / Redmi K20 (davinci)”.
