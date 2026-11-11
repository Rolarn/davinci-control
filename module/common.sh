#!/system/bin/sh
# Davinci Control: общие пути и функции. R — префикс путей только для тестов (на телефоне пустой).
# Davinci Control: shared paths and helpers. R is a path prefix for tests only (empty on the phone).
ID=davinci-control
MODDIR=${MODDIR:-$R/data/adb/modules/$ID}
D=$R/data/adb/$ID                         # настройки и данные модуля / module settings and data
CONF=$D/config
LOG=$D/events.log                         # epoch<TAB>код<TAB>аргументы…
DRAIN=$D/drain.csv
HIST=$D/history.csv
SESS=$D/sessions.csv
OUT=$R/sdcard/Download/$ID                # логи и диагностика для пользователя / user-visible logs
STR=$MODDIR/strings.tsv
K=$R/sys/class/kgsl/kgsl-3d0
P=$R/vendor/etc/powerhint.json
B=$R/sys/class/power_supply/battery
U=$R/sys/class/power_supply/usb
CP=$R/sys/class/power_supply/charge_pump_master
BMS=$R/sys/class/power_supply/bms
CPU0=$R/sys/devices/system/cpu/cpufreq/policy0
CPU6=$R/sys/devices/system/cpu/cpufreq/policy6
FFC=$R/sys/kernel/fast_charge/force_fast_charge
DISABLE_THERMAL=$R/sys/module/qpnp_smb5/parameters/disable_thermal
SKIP_THERMAL=$R/sys/module/smb5_lib/parameters/skip_thermal
# Способы остановить зарядку: имя:можно:нельзя. Первые два — только зарядку, input_suspend — вход целиком.
SWITCHES="charging_enabled:1:0 battery_charging_enabled:1:0 input_suspend:0:1"

defaults() {
  CHARGE_LIMIT=80; CHARGE_RESUME=75; HOT_PAUSE=42; HOT_RESUME=38; USB_FAST=1; LITTLE_MAX=1612800; BIG_MAX=0
  BRIGHT_CHARGE=0; AUTO_BATT=1; SAVER_BATT=1; THERMAL_CHG=0; CC_SMART=1; UI_LANG=auto; SKIN=blue; DRAIN_ALERT=1; ACK=""
  APP_LOG=0; NOTIFY=0; FULL_BY=""
}
# Число в границах, иначе значение по умолчанию: испорченная настройка не должна ронять службу.
# A number within bounds, otherwise the default: a broken setting must not crash the service.
_num() {  # ИМЯ мин макс по_умолчанию / NAME min max default
  eval "_v=\$$1"
  case "$_v" in ''|*[!0-9]*) eval "$1=$4"; return 0 ;; esac
  { [ "$_v" -lt "$2" ] || [ "$_v" -gt "$3" ]; } && eval "$1=$4"
  return 0
}
load_conf() {
  defaults; [ -f "$CONF" ] && . "$CONF"
  _num CHARGE_LIMIT 50 100 80; _num CHARGE_RESUME 40 100 $((CHARGE_LIMIT - 5)); _num HOT_PAUSE 0 50 42; _num HOT_RESUME 30 50 38
  _num LITTLE_MAX 0 4000000 1612800; _num BIG_MAX 0 4000000 0
  for _k in USB_FAST AUTO_BATT SAVER_BATT CC_SMART DRAIN_ALERT; do _num $_k 0 1 1; done
  for _k in BRIGHT_CHARGE THERMAL_CHG APP_LOG NOTIFY; do _num $_k 0 1 0; done
  case "$UI_LANG" in auto|ru|en) ;; *) UI_LANG=auto ;; esac
  case "$SKIN" in blue|red|black) ;; *) SKIN=blue ;; esac
  case "$FULL_BY" in [0-1][0-9]:[0-5][0-9]|2[0-3]:[0-5][0-9]) ;; *) FULL_BY="" ;; esac
  case "$ACK" in *[!a-z\ ]*) ACK="" ;; esac
}
write_default_conf() {
  [ -f "$CONF" ] && return
  mkdir -p "$D"
  cat > "$CONF" <<'EOF'
# Davinci Control. Меняется из панели / changed from the panel.
CHARGE_LIMIT=80
CHARGE_RESUME=75
HOT_PAUSE=42
HOT_RESUME=38
USB_FAST=1
LITTLE_MAX=1612800
BIG_MAX=0
BRIGHT_CHARGE=0
AUTO_BATT=1
SAVER_BATT=1
CC_SMART=1
THERMAL_CHG=0
UI_LANG=auto
SKIN=blue
DRAIN_ALERT=1
APP_LOG=0
NOTIFY=0
FULL_BY=
EOF
}

# Первая строка файла без запуска cat (у службы и панели сотни чтений) / first line of a file, no cat spawned
rd() { _rd=""; { IFS= read -r _rd < "$1"; } 2>/dev/null; [ -n "$_rd" ] && printf '%s\n' "$_rd"; }
# То же в переменную, без подоболочки / same into a variable, no subshell: rdv ИМЯ ФАЙЛ
rdv() { eval "$1=''"; { IFS= read -r "$1" < "$2"; } 2>/dev/null; return 0; }
# Запись целиком или никак: панель не прочитает половину файла / all-or-nothing write
put() { printf '%s\n' "$2" > "$1.tmp" && mv -f "$1.tmp" "$1"; }
version() { sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null; }
# версия без кода коммита — для имён файлов / version without the commit — for file names
vname() { version | cut -d' ' -f1; }
vcode() { sed -n 's/^versionCode=//p' "$MODDIR/module.prop" 2>/dev/null; }
trim() { [ -f "$1" ] && [ "$(wc -l < "$1")" -gt "$2" ] && tail -n "$2" "$1" > "$1.t" && mv "$1.t" "$1"; }

# Имя файла для «Загрузок»; если такое уже есть (две записи за минуту) — суффикс _2, _3…
# File name for Download; if it exists (two saves within a minute) — a _2, _3… suffix
outname() {
  f=$OUT/davinci-control_$(vname)_$1_$(date +%Y-%m-%d_%H%M); n=1; x=$f.txt
  while [ -e "$x" ]; do n=$((n + 1)); x=${f}_$n.txt; done; echo "$x"
}
# ---------- язык / language ----------
ui_lang() {
  case "$UI_LANG" in ru|en) echo "$UI_LANG"; return ;; esac
  l=$(getprop persist.sys.locale 2>/dev/null); [ -n "$l" ] || l=$(getprop ro.product.locale 2>/dev/null)
  case "$l" in ru*) echo ru ;; *) echo en ;; esac
}
# t КОД [аргументы] — строка на языке интерфейса; {1}, {2}… подставляются. / message in UI language.
t() {
  c=$1; shift
  awk -F'\t' -v c="$c" -v l="$(ui_lang)" -v a="$(for x in "$@"; do printf '%s\037' "$x"; done)" '
    BEGIN { n = split(a, A, "\037") }
    $1 == c { s = (l == "en" ? $3 : $2); for (i = 1; i <= n; i++) { v = A[i]; gsub(/&/, "\\\\&", v); gsub("\\{" i "\\}", v, s) } print s; f = 1; exit }
    END { if (!f) print c }' "$STR"
}
# ev КОД [аргументы] — событие в журнал (без текста: панель и отчёт переводят сами). / log an event as a code.
ev() {
  mkdir -p "$D"
  { printf '%s\t%s' "$(date +%s)" "$1"; shift; for x in "$@"; do printf '\t%s' "$x"; done; printf '\n'; } >> "$LOG"
}
# render_log ФАЙЛ [N] — журнал текстом на языке интерфейса. / log as text in the UI language.
render_log() {
  [ -f "$1" ] || return 0
  # Время считаем сами: у awk в Android нет strftime. / the time is computed by hand: Android's awk has no strftime.
  _z=$(date +%z); _zs=$(( (1${_z#[+-]} - 10000) / 100 * 3600 + (1${_z#[+-]} - 10000) % 100 * 60 )); case "$_z" in -*) _zs=$((-_zs)) ;; esac
  tail -n "${2:-100000}" "$1" | awk -F'\t' -v l="$(ui_lang)" -v str="$STR" -v off="$_zs" '
    function fmt(e,   d, s, z, era, doe, yoe, doy, mp) {
      e += off; d = int(e / 86400); s = e - d * 86400; z = d + 719468; era = int(z / 146097); doe = z - era * 146097
      yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365); doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100)); mp = int((5 * doy + 2) / 153)
      return sprintf("%02d.%02d %02d:%02d:%02d", doy - int((153 * mp + 2) / 5) + 1, (mp < 10 ? mp + 3 : mp - 9), int(s / 3600), int(s % 3600 / 60), s % 60)
    }
    BEGIN { while ((getline line < str) > 0) { split(line, p, "\t"); m[p[1]] = (l == "en" ? p[3] : p[2]) } }
    { s = ($2 in m) ? m[$2] : $2; for (i = 3; i <= NF; i++) { v = $i; gsub(/&/, "\\\\&", v); gsub("\\{" (i - 2) "\\}", v, s) }
      printf "%s %s\n", fmt($1), s }'
}

# ---------- root-менеджер / root manager ----------
root_mgr() {
  if [ -n "$APATCH" ] || [ -x $R/data/adb/apd ]; then echo "APatch $($R/data/adb/apd -V 2>/dev/null | head -n 1)"
  elif [ -n "$KSU" ] || [ -x $R/data/adb/ksud ]; then echo "KernelSU $($R/data/adb/ksud -V 2>/dev/null | head -n 1)"
  elif command -v magisk >/dev/null 2>&1; then echo "Magisk $(magisk -v 2>/dev/null) ($(magisk -V 2>/dev/null))"
  else echo "?"; fi
}
find_bb() {
  for b in $R/data/adb/magisk/busybox $R/data/adb/ksu/bin/busybox $R/data/adb/ap/bin/busybox; do [ -x "$b" ] && { echo "$b"; return; }; done
  command -v busybox 2>/dev/null
}
BB=${BB:-$(find_bb)}

# ---------- устройство / device ----------
is_davinci() { case "$(getprop ro.product.device)$(getprop ro.product.vendor.device)" in *davinci*) return 0 ;; esac; return 1; }
header() {  # шапка файлов логов и диагностики / header for saved logs and diagnostics
  echo "Davinci Control $(version) · $1 · $(date '+%Y-%m-%d %H:%M:%S')"
  echo "device: $(getprop ro.product.model 2>/dev/null) ($(getprop ro.product.device 2>/dev/null))"
  echo "build: $(getprop ro.build.display.id 2>/dev/null) · Android $(getprop ro.build.version.release 2>/dev/null) · patch $(getprop ro.build.version.security_patch 2>/dev/null)"
  echo "kernel: $(uname -r 2>/dev/null)"
  echo "root: $(root_mgr)"
  echo "panel: ${PANEL_HOST:-?} · busybox: ${BB:-—}"
}

# ---------- датчики / sensors ----------
ph_edits() {  # сколько из 3 правок powerhint видит система / powerhint edits in effect (of 3)
  [ -f "$P" ] || { echo "-"; return; }
  a=$(grep -c '"1017600"' "$P" 2>/dev/null)
  b=$(grep -A3 '"PowerHint": "EXPENSIVE_RENDERING"' "$P" 2>/dev/null | grep -A2 '"GPUMinFreq"' | grep -c '"Value": "7"')
  echo $(( ${a:-0} + ${b:-0} ))
}
zt() { for z in $R/sys/class/thermal/thermal_zone*; do [ "$(rd "$z/type")" = "$1" ] && { echo $(( $(rd "$z/temp") / 1000 )); return; }; done; echo "?"; }
zt10() { for n in "$@"; do for z in $R/sys/class/thermal/thermal_zone*; do [ "$(rd "$z/type")" = "$n" ] && { v=$(rd "$z/temp"); [ -n "$v" ] && { echo $(( v / 100 )); return; }; }; done; done; }
plugged() { [ "$(rd $U/present)" = 1 ] || [ "$(rd $U/online)" = 1 ]; }
mono_s() { awk '/now at/ { print int($3 / 1000000000); exit }' $R/proc/timer_list 2>/dev/null; }
boot_s() { awk '{ print int($1) }' $R/proc/uptime; }
backlight() { for f in $R/sys/class/backlight/*/brightness; do rd "$f"; return; done; }
backlight_max() { for f in $R/sys/class/backlight/*/max_brightness; do rd "$f"; return; done; }
# Температуры, °C×10: контроллер зарядки PM6150, микросхема быстрой зарядки SMB1390 (charge pump), разъём.
# АЦП иногда отвечает ошибкой — одна повторная попытка / the ADC sometimes errors — one retry
t_pmic() { v=$(rd $B/charger_temp); [ -n "$v" ] || v=$(rd $B/charger_temp); [ -n "$v" ] && echo "$v"; }
# SMB1390 (микросхема быстрой зарядки) отдаёт температуру, только пока включена / only while enabled
t_cp() { [ "$(rd $CP/cp_enable)" = 1 ] || return 0; v=$(rd $CP/cp_die_temp); [ -n "$v" ] && echo "$v"; }
t_conn() { v=$(rd $U/connector_temp); [ -n "$v" ] && { echo "$v"; return; }; zt10 conn_therm usb_conn_therm usb-therm; }
sims() { getprop gsm.sim.state 2>/dev/null | tr ',' '\n' | grep -cE 'LOADED|READY'; }

# Настройки Android: stdin всегда /dev/null, иначе «Failed transaction». / Android settings helpers.
sget() { settings get "$1" "$2" </dev/null 2>/dev/null; }
sput() {
  settings put "$1" "$2" "$3" </dev/null >/dev/null 2>&1; [ "$(sget "$1" "$2")" = "$3" ] && return 0
  su 2000 -c "settings put $1 $2 $3" </dev/null >/dev/null 2>&1; [ "$(sget "$1" "$2")" = "$3" ] && return 0
  content insert --uri "content://settings/$1" --bind "name:s:$2" --bind "value:s:$3" </dev/null >/dev/null 2>&1; [ "$(sget "$1" "$2")" = "$3" ]
}
bright_max() { sput system screen_brightness_mode 0 && sput system screen_brightness 255; r=$?; cmd display set-brightness 1.0 </dev/null >/dev/null 2>&1; return $r; }
bright_auto() { sput system screen_brightness_mode 1; }
saver_get() { sget global low_power; }
saver_on() { cmd power set-mode 1 </dev/null >/dev/null 2>&1; [ "$(saver_get)" = 1 ] || sput global low_power 1; }
net_rx() {  # $1 = шаблон интерфейса / interface glob
  s=0; for f in $R/sys/class/net/$1/statistics/rx_bytes; do [ -r "$f" ] && s=$((s + $(cat "$f"))); done; echo $s
}

# Ступень ограничения тока (рычаг заводской термозащиты). / charge current level (the stock thermal lever).
# charge_control_limit в sysfs только для чтения (ядро не даёт права записи даже root). Рабочий путь —
# охлаждающее устройство «battery»: его cur_state ядро передаёт в тот же CHARGE_CONTROL_LIMIT.
# charge_control_limit is read-only in sysfs (no write bit, even for root). The working path is the
# "battery" cooling device: the kernel passes its cur_state to the same CHARGE_CONTROL_LIMIT.
CCL=""; CCLMAX=""; CCLN=""
for c in $R/sys/class/thermal/cooling_device*; do
  [ "$(cat "$c/type" 2>/dev/null)" = battery ] && { CCL=$c/cur_state; CCLMAX=$c/max_state; CCLN="${c##*/}(battery)"; break; }
done
[ -n "$CCL" ] || { CCL=$B/system_temp_level; CCLMAX=$B/num_system_temp_levels; CCLN=system_temp_level; }
REG_HI=440; REG_LO=425           # удержание «Быстро»: окно датчика, °C×10 / fast-mode hold window
CC_CAP=13                        # выше не ставим: последние ступени почти останавливают зарядку / never above
# Какая таблица тока действует сейчас (как в ядре, smblib_therm_charging). / the table in effect now.
cc_table() {
  rdv _ty $U/real_type; rdv _cp $U/smb_en_reason
  case "$_ty" in
    USB_HVDCP_3) if [ "$_cp" = 1 ]; then echo qc3cp; else echo qc3; fi ;;
    USB_HVDCP_3P5) echo qc3cp ;; USB_HVDCP) echo qc2 ;; USB_DCP) echo dcp ;; USB_PD) echo pd ;; *) echo fcc ;;
  esac
}
# Ступени по доле от полного тока таблицы: L1 ≈ 89% (3,1 из 3,5 А), L2 ≈ 77% (2,7 А), L3 ≈ 57% (2,0 А).
# Таблицы у разных блоков разные, поэтому считаем по амперам, а не по номерам ступеней.
# Levels by share of the table's full current: L1 ≈ 89%, L2 ≈ 77%, L3 ≈ 57%. Tables differ per charger,
# so levels are picked by amps, not by level numbers.
cc_plan() {  # $1 = ключ таблицы / table key → L1 L2 L3
  L1=4; L2=8; L3=12; _t=""
  [ -f "$D/dt.tables" ] || return 0
  while IFS='=' read -r _k _vals; do [ "$_k" = "$1" ] && _t=$_vals; done < "$D/dt.tables"
  [ -n "$_t" ] || return 0
  set -- $_t; _max=$1; [ "${_max:-0}" -gt 0 ] || return 0
  _i=0; _a=""; _b=""; _c=""
  for _x in "$@"; do
    [ -z "$_a" ] && [ $((_x * 100)) -le $((_max * 89)) ] && _a=$_i
    [ -z "$_b" ] && [ $((_x * 100)) -le $((_max * 78)) ] && _b=$_i
    [ -z "$_c" ] && [ $((_x * 100)) -le $((_max * 58)) ] && _c=$_i
    _i=$((_i + 1))
  done
  [ -n "$_a" ] && [ -n "$_b" ] && [ -n "$_c" ] || return 0
  [ "$_c" -gt $CC_CAP ] && _c=$CC_CAP; [ "$_b" -gt "$_c" ] && _b=$_c; [ "$_a" -gt "$_b" ] && _a=$_b
  L1=$_a; L2=$_b; L3=$_c
}
# Вернуть зарядку и снять ограничение тока (страховка и удаление). / restore charging and lift the limit.
failsafe() {
  for _n in charging_enabled battery_charging_enabled; do [ -f "$B/$_n" ] && echo 1 > "$B/$_n"; done 2>/dev/null
  [ -f "$B/input_suspend" ] && echo 0 > "$B/input_suspend" 2>/dev/null
  [ -f "$CCL" ] && echo 0 > "$CCL" 2>/dev/null
  return 0
}
# Уведомление в шторке от имени системной оболочки (Android 10+). / a notification via the system shell.
notify() {  # тег заголовок текст / tag title text
  [ "$NOTIFY" = 1 ] || return 0
  # одинарные кавычки убираем: текст идёт внутрь кавычек команды / single quotes are stripped: the text goes inside quotes
  _nt=$(printf %s "$2" | tr -d "'\\\`\$"); _nx=$(printf %s "$3" | tr -d "'\\\`\$")
  su 2000 -c "cmd notification post -S bigtext -t '$_nt' 'dc_$1' '$_nx'" </dev/null >/dev/null 2>&1 || true
}
PKGL=$R/data/system/packages.list
daemon_pid() { p=$(rd $D/pid); [ -n "$p" ] && kill -0 "$p" 2>/dev/null && echo "$p"; }
# Процессы модуля: кто жив, в каком состоянии и где в ядре ждёт. Нужен, чтобы понять причину зависания.
# Module processes: which are alive, their state and where in the kernel they wait — to find why something hung.
proc_dump() {
  echo "time: $(date '+%Y-%m-%d %H:%M:%S') · diag.status: $(rd "$D/diag.status")"
  _own=""; for _f in sup.pid pid uev.pid diag.pid; do rdv _p "$D/$_f"; [ -n "$_p" ] && _own="$_own $_p"; done
  for _p in $_own $(grep -l davinci-control $R/proc/[0-9]*/cmdline 2>/dev/null | sed 's|.*/proc/||; s|/cmdline||'); do
    [ "$_p" = "$$" ] && continue; [ -d "$R/proc/$_p" ] || continue
    case " $_seen " in *" $_p "*) continue ;; esac; _seen="$_seen $_p"
    printf 'pid %s · %s· %s · wchan=%s\n' "$_p" "$(tr '\0' ' ' < "$R/proc/$_p/cmdline" 2>/dev/null | cut -c1-120)" "$(grep -m1 '^State' "$R/proc/$_p/status" 2>/dev/null | tr -s '\t ' ' ')" "$(cat "$R/proc/$_p/wchan" 2>/dev/null)"
    head -n 8 "$R/proc/$_p/stack" 2>/dev/null | sed 's/^/    /'
  done
}
wake_daemon() { p=$(daemon_pid); [ -n "$p" ] && pkill -P "$p" sleep 2>/dev/null; true; }

# Файлы нагрева прошивки: подменяем, только если все совпадают с проверенными байт в байт.
# Stock thermal configs: replaced only when all of them match the known originals byte for byte.
thermal_match() {
  [ -f "$MODDIR/thermal/orig.sha256" ] || return 1
  while read -r h f; do
    c=$(sha256sum "$R/vendor/etc/$f" 2>/dev/null | cut -d' ' -f1)
    # совпадение с оригиналом или с уже подключённой копией модуля / original or our own mounted copy
    [ "$c" = "$h" ] || [ "$c" = "$(sha256sum "$MODDIR/thermal/$f" 2>/dev/null | cut -d' ' -f1)" ] || return 1
  done < "$MODDIR/thermal/orig.sha256"
}
# Таблицы тока по ступеням из device tree (мкА). / per-level current tables from the device tree (µA).
dt_table() {  # $1 = имя свойства / property name
  f=$(find $R/proc/device-tree/ -name "$1" 2>/dev/null | head -n 1)
  [ -n "$f" ] && od -An -v -tu1 "$f" 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) { v = v * 256 + $i; if (++n % 4 == 0) { printf "%s%d", (n > 4 ? " " : ""), v; v = 0 } } } END { print "" }'
}
# Кэш таблиц device tree (один раз за загрузку). / device tree tables cache (once per boot).
dt_cache() {
  [ -f $D/dt.tables ] && return
  # по типу блока ядро берёт свою таблицу (smblib_therm_charging) / the kernel picks a table by charger type
  for x in fcc:qcom,thermal-mitigation qc3:qcom,thermal-fcc-qc3-normal qc3cp:qcom,thermal-fcc-qc3-cp qc2:qcom,thermal-mitigation-qc2 \
           dcp:qcom,thermal-mitigation-dcp pd:qcom,thermal-mitigation-pd-base; do
    echo "${x%%:*}=$(dt_table "${x#*:}")"
  done > $D/dt.tables
}
