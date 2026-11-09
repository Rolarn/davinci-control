#!/bin/bash
# Сборка zip модуля из module/ → dist/davinci-control-vX.Y.Z.zip и печать SHA-256.
# Builds the module zip from module/ → dist/davinci-control-vX.Y.Z.zip and prints SHA-256.
set -e
cd "$(dirname "$0")/.."
V=$(sed -n 's/^version=//p' module/module.prop)
mkdir -p dist; Z=dist/davinci-control-$V.zip; rm -f "$Z"
# одинаковое время файлов — одинаковый zip / fixed timestamps for a reproducible zip
TMP=$(mktemp -d); cp -a module/. "$TMP/"; find "$TMP" -exec touch -d '2026-01-01 00:00:00' {} +
(cd "$TMP" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | zip -X -q -9 "$OLDPWD/$Z" -@)
rm -rf "$TMP"
echo "$Z"
sha256sum "$Z" | cut -d' ' -f1 > "$Z.sha256"; cat "$Z.sha256"
