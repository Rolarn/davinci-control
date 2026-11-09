#!/bin/bash
# Текст релиза: сначала русский, потом английский. / Release notes: Russian first, then English.
# Использование / usage: scripts/release-notes.sh SHA256 [banner.svg]
set -e
cd "$(dirname "$0")/.."
V=$(sed -n 's/^version=v//p' module/module.prop); SHA=$1
B=${2:-assets/mascot/export/release-$V.svg}
NEW=$(awk -v v="## $V" '$0 == v { f = 1; next } /^## / { f = 0 } f' CHANGELOG.md)
cat <<N
<p align="center"><img src="https://raw.githubusercontent.com/Rolarn/davinci-control/v$V/$B" width="760" alt="Davinci Control $V"></p>

### Русский
$(echo "$NEW" | awk '/^### Русский/ { f = 1; next } /^### / { f = 0 } f')

- **Установка:** скачай zip ниже → Magisk → Модули → Установить из хранилища → перезагрузка. Следующие обновления появятся в Magisk сами.
- **Требования:** root (Magisk 24+), прошивка на основе AOSP для Xiaomi Mi 9T / Redmi K20 (davinci). Подробно — в разделе [«Совместимость»](https://github.com/Rolarn/davinci-control#совместимость).
- **Проверено на:** Mi 9T (davinci), PixelOS 15, VantomKernel 4.14.356, Magisk Alpha 31100.

### English
$(echo "$NEW" | awk '/^### English/ { f = 1; next } /^### / { f = 0 } f')

- **Install:** download the zip below → Magisk → Modules → Install from storage → reboot. Next updates will show up in Magisk by themselves.
- **Requirements:** root (Magisk 24+), an AOSP-based ROM for Xiaomi Mi 9T / Redmi K20 (davinci). See [Compatibility](https://github.com/Rolarn/davinci-control/blob/main/README.en.md#compatibility).
- **Tested on:** Mi 9T (davinci), PixelOS 15, VantomKernel 4.14.356, Magisk Alpha 31100.

SHA-256 \`davinci-control-v$V.zip\`: \`$SHA\`
N
