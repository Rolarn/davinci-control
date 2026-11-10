#!/bin/bash
# Следующая тестовая сборка: номер в файле RC +1, коммит, отправка ветки, zip.
# Тег vX.Y.Z-rc.N на этот коммит ставит автосборка (ci.yml).
# Next test build: RC number +1, commit, push the branch, build the zip. CI tags the commit vX.Y.Z-rc.N.
set -e
cd "$(dirname "$0")/.."
[ -z "$(git status --porcelain)" ] || { echo "есть незакоммиченные изменения / uncommitted changes"; exit 1; }
[ "$(git rev-parse --abbrev-ref HEAD)" != main ] || { echo "не в main / not on main"; exit 1; }
V=$(sed -n 's/^version=//p' module/module.prop)
N=$(( $(cat RC 2>/dev/null || echo 0) + 1 )); echo $N > RC
git add RC; git commit -q -m "Тестовая сборка / test build $V-rc.$N"
git push -q
scripts/build.sh
