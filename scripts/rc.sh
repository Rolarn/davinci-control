#!/bin/bash
# Следующая тестовая сборка: ставит тег vX.Y.Z-rc.N на текущий коммит, отправляет его и собирает zip.
# Next test build: tags the current commit vX.Y.Z-rc.N, pushes the tag and builds the zip.
set -e
cd "$(dirname "$0")/.."
[ -z "$(git status --porcelain)" ] || { echo "есть незакоммиченные изменения / uncommitted changes"; exit 1; }
V=$(sed -n 's/^version=//p' module/module.prop)
git fetch -q origin --tags
N=$(git tag -l "$V-rc.*" | sed "s/^$V-rc\.//" | sort -n | tail -n 1)
T=$V-rc.$(( ${N:-0} + 1 ))
git tag -a "$T" -m "Тестовая сборка / test build $T"
git push -q origin "$T"
scripts/build.sh
