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
CPU0=$R/sys/devices/system/cpu/cpufreq/policy0
CPU6=$R/sys/devices/system/cpu/cpufreq/policy6
FFC=$R/sys/kernel/fast_charge/force_fast_charge
DISABLE_THERMAL=$R/sys/module/qpnp_smb5/parameters/disable_thermal
SKIP_THERMAL=$R/sys/module/smb5_lib/parameters/skip_thermal
# Способы остановить зарядку: имя:можно:нельзя. Первые два — только зарядку, input_suspend — вход целиком.
SWITCHES="charging_enabled:1:0 battery_charging_enabled:1:0 input_suspend:0:1"

defaults() {
  CHARGE_LIMIT=80; CHARGE_RESUME=75; HOT_PAUSE=42; HOT_RESUME=38; USB_FAST=1; LITTLE_MAX=1612800; BIG_MAX=0
  BRIGHT_CHARGE=0; AUTO_BATT=1; SAVER_BATT=1; THERMAL_CHG=0; CC_SMART=1; UI_LANG=auto; SKIN=blue; DRAIN_ALERT=1
}
load_conf() { defaults; [ -f "$CONF" ] && . "$CONF"; }
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
EOF
}

rd() { cat "$1" 2>/dev/null; }
version() { sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null; }
vcode() { sed -n 's/^versionCode=//p' "$MODDIR/module.prop" 2>/dev/null; }
trim() { [ -f "$1" ] && [ "$(wc -l < "$1")" -gt "$2" ] && tail -n "$2" "$1" > "$1.t" && mv "$1.t" "$1"; }

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
  tail -n "${2:-100000}" "$1" | awk -F'\t' -v l="$(ui_lang)" -v str="$STR" '
    BEGIN { while ((getline line < str) > 0) { split(line, p, "\t"); m[p[1]] = (l == "en" ? p[3] : p[2]) } }
    { s = ($2 in m) ? m[$2] : $2; for (i = 3; i <= NF; i++) { v = $i; gsub(/&/, "\\\\&", v); gsub("\\{" (i - 2) "\\}", v, s) }
      printf "%s %s\n", strftime("%d.%m %H:%M:%S", $1), s }'
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
HBM=$R/sys/devices/platform/soc/soc:qcom,dsi-display/hbm
set_hbm() { [ -f $HBM ] || return 1; echo "$1" > $HBM 2>/dev/null; }
# Температуры микросхем, °C×10: зарядка PM6150, зарядный насос SMB1390, разъём. / chip temperatures, °C×10.
t_pmic() { v=$(rd $B/charger_temp); [ -n "$v" ] && echo "$v"; }
t_cp() { v=$(rd $CP/temp); [ -z "$v" ] && v=$(sed -n 's/^POWER_SUPPLY_TEMP=//p' $CP/uevent 2>/dev/null); [ -n "$v" ] && echo "$v"; }
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
CCL=$B/system_temp_level; [ -f $CCL ] || CCL=$B/charge_control_limit
CCLMAX=$B/num_system_temp_levels; [ -f $CCLMAX ] || CCLMAX=$B/charge_control_limit_max
CC_TOP=12                        # 15+ ядро останавливает зарядку — выше 12 не ставим / never above 12
REG_HI=440; REG_LO=425; REG_MIN=8   # удержание «Быстро» / fast-mode hold
CC_STEPS="410:4 430:8 450:12"    # «Бережно»: °C×10 → ступень / care mode steps
cc_for_temp() { r=0; for s in $CC_STEPS; do [ "$1" -ge "${s%%:*}" ] && r=${s#*:}; done; echo $r; }
PKGL=$R/data/system/packages.list
daemon_pid() { p=$(rd $D/pid); [ -n "$p" ] && kill -0 "$p" 2>/dev/null && echo "$p"; }
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
dt_table() {
  f=$(find $R/proc/device-tree/ -name "qcom,thermal-mitigation$1" 2>/dev/null | head -n 1)
  [ -n "$f" ] && od -An -v -tu1 "$f" 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) { v = v * 256 + $i; if (++n % 4 == 0) { printf "%s%d", (n > 4 ? " " : ""), v; v = 0 } } } END { print "" }'
}
# Кэш таблиц device tree (один раз за загрузку). / device tree tables cache (once per boot).
dt_cache() {
  [ -f $D/dt.tables ] && return
  { echo "fcc=$(dt_table '')"; echo "dcp=$(dt_table -dcp)"; echo "qc2=$(dt_table -qc2)"; echo "icl=$(dt_table -icl)"; } > $D/dt.tables
}
