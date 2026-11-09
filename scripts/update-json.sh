#!/bin/bash
# update.json для обновлений в Magisk / update.json for in-app updates. Использование / usage: scripts/update-json.sh
set -e
cd "$(dirname "$0")/.."
V=$(sed -n 's/^version=//p' module/module.prop); C=$(sed -n 's/^versionCode=//p' module/module.prop)
cat > update.json <<J
{
  "version": "$V",
  "versionCode": $C,
  "zipUrl": "https://github.com/Rolarn/davinci-control/releases/download/$V/davinci-control-$V.zip",
  "changelog": "https://raw.githubusercontent.com/Rolarn/davinci-control/main/CHANGELOG.md"
}
J
cat update.json
