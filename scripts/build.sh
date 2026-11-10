#!/bin/bash
# Сборка zip модуля из module/ и печать SHA-256.
#   RELEASE=1      → релиз:            version=vX.Y.Z,                dist/davinci-control-vX.Y.Z.zip
#   есть файл RC   → тестовая сборка:  version=vX.Y.Z-rc.N (коммит),  dist/davinci-control-vX.Y.Z-rc.N.zip
#   иначе          → рабочая сборка:   version=vX.Y.Z-dev (коммит),   dist/davinci-control-vX.Y.Z-dev.zip
# Builds the module zip and prints SHA-256. RELEASE=1 → release; RC file → test build vX.Y.Z-rc.N (+ commit);
# otherwise a work build vX.Y.Z-dev (+ commit).
set -e
cd "$(dirname "$0")/.."
V=$(sed -n 's/^version=//p' module/module.prop)
SHA=$(git rev-parse --short=7 HEAD 2>/dev/null || echo unknown)
if [ -n "${RELEASE:-}" ]; then NAME=$V; FULL=$V
elif [ -f RC ]; then NAME=$V-rc.$(cat RC); FULL="$NAME ($SHA)"
else NAME=$V-dev; FULL="$V-dev ($SHA)"; fi
mkdir -p dist; Z=dist/davinci-control-$NAME.zip; rm -f "$Z"
# одинаковое время файлов — одинаковый zip / fixed timestamps for a reproducible zip
TMP=$(mktemp -d); cp -a module/. "$TMP/"
sed -i "s|^version=.*|version=$FULL|" "$TMP/module.prop"
find "$TMP" -exec touch -d '2026-01-01 00:00:00' {} +
(cd "$TMP" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | zip -X -q -9 "$OLDPWD/$Z" -@)
rm -rf "$TMP"
echo "$Z ($FULL)"
sha256sum "$Z" | cut -d' ' -f1 > "$Z.sha256"; cat "$Z.sha256"
