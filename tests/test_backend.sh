#!/bin/bash
# Бэкенд панели, установщик, файлы нагрева, удаление / panel backend, installer, thermal configs, removal
. "$(dirname "$0")/lib.sh"
D_=data/adb/davinci-control

echo "1. JSON панели / panel JSON"
mkroot; run_daemon >/dev/null 2>&1 || true
J=$(tune json); L=$(tune live); S=$(tune strings)
check "json валиден / json is valid" "echo '$J' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"version\"]==\"v1.0.0\"'"
check "live валиден / live is valid" "echo '$L' | python3 -m json.tool >/dev/null"
check "строки: оба языка / strings: both languages" "echo '$S' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert all(len(v)==2 and v[0] and v[1] for v in d.values()) and len(d)>70'"
check "температуры микросхем / chip temperatures" "echo '$J' | python3 -c 'import json,sys; c=json.load(sys.stdin)[\"chips\"]; assert c==dict(pmic=420,cp=380,conn=350), c'"
check "таблица тока из device tree / DT current table" "echo '$J' | python3 -c 'import json,sys; t=json.load(sys.stdin)[\"dt\"]; assert t[\"qc3\"][8]==2700000 and t[\"qc3\"][12]==2000000 and t[\"fcc\"][8]==2600000, t'"
check "SIM: 2 / SIMs: 2" "echo '$J' | python3 -c 'import json,sys; assert json.load(sys.stdin)[\"sims\"]==2'"

check "рычаг тока — охлаждающее устройство / level lever is the cooling device" "echo '$J' | python3 -c 'import json,sys; assert json.load(sys.stdin)[\"cc\"][\"node\"]==\"cooling_device5(battery)\"'"
echo "2. Команды настроек / setting commands"
tune limit 85 >/dev/null; tune chgmode fast >/dev/null; tune lang en >/dev/null; tune skin red >/dev/null; tune profile eco >/dev/null
C=$R/$D_/config
check "лимит 85 / limit 85" "grep -q '^CHARGE_LIMIT=85' $C && grep -q '^CHARGE_RESUME=80' $C"
check "режим «Быстро» / fast mode" "grep -q '^CC_SMART=0' $C && grep -q '^HOT_PAUSE=48' $C"
check "язык и цвет / language and skin" "grep -q '^UI_LANG=en' $C && grep -q '^SKIN=red' $C"
check "профиль «Экономия» / economy profile" "grep -q '^LITTLE_MAX=1324800' $C && [ \$(cat $R/sys/devices/system/cpu/cpufreq/policy6/scaling_max_freq) = 1708800 ]"
check "ошибка на неверном значении / error on bad value" "! tune limit 20 >/dev/null && ! tune lang de >/dev/null"
check "текст ошибки на английском / error text in English" "tune limit 20 | grep -q 'A number from 50 to 100'"
tune ack noprot >/dev/null; tune ack drain >/dev/null; tune ack -noprot >/dev/null
check "«Понятно» сохраняется и снимается / ack is stored and cleared" "grep -q '^ACK=\"drain\"' $C"
check "события настроек / setting events" "grep -q 'set_mode_fast' $R/$D_/events.log && grep -q 'set_profile_eco' $R/$D_/events.log"

echo "3. Сохранение журнала / saving the log"
P=$(tune savelogs "WebUI X")
check "имя файла по шаблону / file name pattern ($P)" "echo '$P' | grep -qE '^/sdcard/Download/davinci-control/davinci-control_v1.0.0_log_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}.txt$'"
check "шапка: версия, устройство, ядро, root, панель / header" "head -n 6 $R$P | grep -q '^Davinci Control v1.0.0' && grep -q '^root: Magisk 31.1 (31100)' $R$P && grep -q '^panel: WebUI X' $R$P"
check "журнал на английском / log in English" "grep -q 'Service started' $R$P"

echo "4. Диагностика и маскировка / diagnostics and masking"
echo 'sync wakelock *sync*/com.google/user.name@gmail.com 192.168.1.20 aa:bb:cc:dd:ee:ff +79991234567' > $R/sys/class/backlight/panel0-backlight/leak
cat > $R/bin/dumpsys <<EOF
#!/bin/sh
cat $R/sys/class/backlight/panel0-backlight/leak
EOF
chmod +x $R/bin/dumpsys
(cd "$R" && PATH=$R/bin R=$R MODDIR=$M BB=$BBX SLEEP_CMD=true timeout 60 $BBX ash -c "sed -i 's/sleep 2; j/j/' $M/diag.sh; $BBX ash $M/diag.sh") >/dev/null 2>&1 || true
F=$(ls $R/sdcard/Download/davinci-control/*_diag_*.txt 2>/dev/null | head -n 1)
check "файл диагностики создан / diagnostics file created" "[ -s '$F' ] && grep -q '^done:' $R/$D_/diag.status"
check "почта, IP, MAC, номер скрыты / e-mail, IP, MAC, number masked" "! grep -qE 'gmail|192\\.168|aa:bb:cc|79991234567' '$F' && grep -q '<email>' '$F'"
check "SMB1390 и таблицы в диагностике / SMB1390 and tables" "grep -q 'charge_pump_master' '$F' && grep -q '^fcc=3500000' '$F'"

echo "5. Установщик / installer"
newI() { I=$(mktemp -d "${TMPDIR:-/tmp}/dc.XXXXXX"); CLEAN="$CLEAN $I"; mkdir -p "$I/m"; cp -a "$ROOT/module/." "$I/m/"; }
inst() {  # $1 устройство, $2 доп. переменные / device, extra env
  (cd "$I" && PATH=$R/bin R=$R MODPATH=$I/m PH_SRC=${PH:-$ROOT/tests/fixtures/powerhint.json} env $2 $BBX ash -c "
    ui_print() { echo \"\$1\"; }; abort() { echo ABORT; exit 1; }; set_perm() { :; }; set_perm_recursive() { :; }
    echo $1 > $R/device; . $I/m/customize.sh" 2>&1) || true
}
newI; O=$(inst davinci "MAGISK_VER_CODE=31100"); check "davinci + Magisk 31: ставится / installs" "! echo '$O' | grep -q ABORT && [ -s $I/m/system/vendor/etc/powerhint.json ]"
check "awk-скрипт удалён из модуля / awk script removed" "[ ! -f $I/m/edit_powerhint.awk ]"
newI; O=$(inst cepheus "MAGISK_VER_CODE=31100"); check "другое устройство: отказ / other device: refused" "echo '$O' | grep -q ABORT"
newI; O=$(inst davinci "MAGISK_VER_CODE=23000"); check "Magisk 23: отказ / refused" "echo '$O' | grep -q ABORT"
newI; O=$(inst davinci "KSU=true"); check "KernelSU: предупреждение про метамодуль / metamodule note" "echo '$O' | grep -q 'метамодуль' && ! echo '$O' | grep -q ABORT"
newI; O=$(PH=/nonexistent inst davinci "MAGISK_VER_CODE=31100"); check "MIUI без powerhint: пропуск, не отказ / skipped, not refused" "echo '$O' | grep -q 'MIUI' && ! echo '$O' | grep -q ABORT"
echo davinci > $R/device

echo "6. Файлы нагрева / thermal configs"
pfd() { (cd "$R" && PATH=$R/bin R=$R MODDIR=$M $BBX ash "$M/post-fs-data.sh") || true; }
pfd; check "чужие файлы: не подменяются / unknown files: not replaced" "[ -f $R/$D_/thermal.mismatch ] && [ ! -f $M/system/vendor/etc/thermal-normal.conf ]"
O_=$(dirname "$0")/fixtures/thermal
if [ -d "$O_" ]; then
  cp "$O_"/thermal-*.conf $R/vendor/etc/; pfd
  check "проверенные файлы: подменяются / tested files: replaced" "[ ! -f $R/$D_/thermal.mismatch ] && cmp -s $M/thermal/thermal-normal.conf $M/system/vendor/etc/thermal-normal.conf"
  echo THERMAL_CHG=1 >> $R/$D_/config; pfd
  check "заводское снижение включено: не подменяются / stock on: not replaced" "[ ! -f $M/system/vendor/etc/thermal-normal.conf ]"
else bad "нет tests/fixtures/thermal"; fi

echo "7. Удаление / removal"
echo 7 > $R/sys/class/thermal/cooling_device5/cur_state
(PATH=$R/bin $BBX ash -c "sed 's|/sys/|$R/sys/|g; s|/data/adb/|$R/data/adb/|g' $M/uninstall.sh | $BBX ash")
check "ступень тока 0 / level 0" "[ \$(cat $R/sys/class/thermal/cooling_device5/cur_state) = 0 ]"
check "данные модуля удалены / module data deleted" "[ ! -d $R/$D_ ]"
check "сохранённые логи остались / saved logs stay" "ls $R/sdcard/Download/davinci-control/*.txt >/dev/null"

echo
[ $FAILS = 0 ] && echo "backend: OK" || { echo "backend: $FAILS FAILED"; exit 1; }
