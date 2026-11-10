#!/bin/bash
# Сборка zip модуля из module/ и печать SHA-256. Версия берётся из тега на текущем коммите:
#   тег vX.Y.Z        → релиз:            version=vX.Y.Z,                 dist/davinci-control-vX.Y.Z.zip
#   тег vX.Y.Z-rc.N   → тестовая сборка:  version=vX.Y.Z-rc.N (коммит),   dist/davinci-control-vX.Y.Z-rc.N.zip
#   без тега          → рабочая сборка:   version=vX.Y.Z-dev (коммит),    dist/davinci-control-vX.Y.Z-dev.zip
# Builds the module zip and prints SHA-256. The version comes from the tag on the current commit:
#   vX.Y.Z → release; vX.Y.Z-rc.N → test build (+ commit); no tag → work build vX.Y.Z-dev (+ commit).
set -e
cd "$(dirname "$0")/.."
V=$(sed -n 's/^version=//p' module/module.prop)
SHA=$(git rev-parse --short=7 HEAD 2>/dev/null || echo unknown)
if [ "${GITHUB_REF_TYPE:-}" = tag ]; then TAG=$GITHUB_REF_NAME
else TAG=$(git tag --points-at HEAD 2>/dev/null | grep -E "^$V(-rc\.[0-9]+)?$" | sort -V | tail -n 1); fi
case "$TAG" in
  "$V") NAME=$V; FULL=$V ;;
  "$V"-rc.*) NAME=$TAG; FULL="$TAG ($SHA)" ;;
  *) NAME=$V-dev; FULL="$V-dev ($SHA)" ;;
esac
mkdir -p dist; Z=dist/davinci-control-$NAME.zip; rm -f "$Z"
# одинаковое время файлов — одинаковый zip / fixed timestamps for a reproducible zip
TMP=$(mktemp -d); cp -a module/. "$TMP/"
sed -i "s|^version=.*|version=$FULL|" "$TMP/module.prop"
find "$TMP" -exec touch -d '2026-01-01 00:00:00' {} +
(cd "$TMP" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | zip -X -q -9 "$OLDPWD/$Z" -@)
rm -rf "$TMP"
echo "$Z ($FULL)"
sha256sum "$Z" | cut -d' ' -f1 > "$Z.sha256"; cat "$Z.sha256"
