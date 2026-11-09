#!/bin/bash
# Все проверки перед сборкой / all checks before a build
set -e
cd "$(dirname "$0")/.."
echo "== shellcheck"; shellcheck -s busybox -S warning -e SC2034,SC2154,SC1090,SC1091,SC2086,SC2155 module/*.sh && echo "shellcheck: OK"
echo "== синтаксис / syntax"; for f in module/*.sh; do busybox ash -n "$f"; done; echo "syntax: OK"
echo "== служба / service"; bash tests/test_daemon.sh | tail -n 1
echo "== бэкенд / backend"; bash tests/test_backend.sh | tail -n 1
echo "== переводы / translations"; node tests/check_i18n.js
echo "== панель / panel"; bash tests/make_panel_data.sh; node tests/panel.js | tail -n 1
echo "== чистота / hygiene"
if grep -rIniE 'kenzo|kaizen' --exclude-dir=.git --exclude=run_all.sh . ; then echo "найдено старое имя / old name found"; exit 1; fi
# адреса почты (кроме служебных) и номера телефонов / e-mail addresses (except service ones) and phone numbers
if grep -rInoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}|\+[0-9]{11,13}' --exclude-dir=.git --exclude-dir=out --exclude-dir=node_modules --exclude=test_backend.sh . | grep -vE 'noreply|users\.noreply\.github\.com|example' ; then echo "личные данные / personal data"; exit 1; fi
v=$(sed -n 's/^version=v//p' module/module.prop); c=$(sed -n 's/^versionCode=//p' module/module.prop)
IFS=. read -r a b p <<< "$v"; [ "$c" = $((a * 10000 + b * 100 + p)) ] || { echo "versionCode $c ≠ $v"; exit 1; }
echo "hygiene: OK"
echo "ВСЁ ПРОШЛО / ALL PASSED"
