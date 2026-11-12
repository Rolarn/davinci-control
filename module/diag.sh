#!/system/bin/sh
# Davinci Control — диагностика в один файл (только чтение), около минуты.
# Ход: $D/diag.status «N/12 время_начала» / «done:путь» / «error:…».
# Личные данные (почта, IP, MAC, длинные номера) в файле маскируются.
# Каждый шаг идёт в отдельном процессе под присмотром: если чтение из ядра не отвечает (его нельзя прервать
# даже сигналом), шаг бросаем и идём дальше — отчёт всё равно будет готов.
# Diagnostics into one file (read-only), about a minute. Personal data (e-mail, IP, MAC, long numbers) is masked.
# Every step runs in its own supervised process: if a kernel read never answers (it cannot be interrupted even
# by a signal), the step is abandoned and the report still completes.
MODDIR=${MODDIR:-${0%/*}}
. "$MODDIR/common.sh"
load_conf
mkdir -p "$D" "$OUT"
F=$(outname diag)
TMP=$D/diag.tmp
STEPS=12; n=0
echo $$ > "$D/diag.pid"
# Не дать телефону уснуть на время сбора; тайм-аут 6 мин — блокировка снимется сама, даже если процесс убьют.
# Keep the phone awake while collecting; the 6 min timeout releases the lock even if the process is killed.
WL=davinci_control_diag
{ echo "$WL 360000000000" > $R/sys/power/wake_lock; } 2>/dev/null
{ echo $$ > $R/sys/fs/cgroup/cgroup.procs; } 2>/dev/null
cleanup() { { echo $WL > $R/sys/power/wake_unlock; } 2>/dev/null; rm -f "$TMP" "$TMP".[0-9]* "$D/diag.pid"; }
trap cleanup EXIT
trap 'put "$D/diag.status" "error:stopped"; exit 1' TERM INT HUP
T0=$(date +%s)
SLP=${SLEEP_CMD:-sleep}
LIM=${DIAG_LIM:-10}   # DIAG_LIM, DIAG_STEP и SLEEP_CMD — только для тестового стенда / test bench hooks only
# Внешняя команда — не дольше 10 с. / an external command — at most 10 s.
lim() { timeout "$LIM" "$@" 2>/dev/null; }
h() { printf '\n===== %s =====\n' "$*"; }
# имя печатаем до чтения: если узел не ответит, в файле видно, какой / the name is printed before the read
kv() { for f in "$@"; do [ -r "$f" ] && { printf '%s = ' "${f#"$R"}"; timeout 3 head -c 500 "$f" 2>/dev/null | tr '\n' ' '; echo; }; done; }
dump_dir() { for f in "$1"/*; do [ -f "$f" ] && [ -r "$f" ] && printf '%s = %s\n' "${f##*/}" "$(head -c 400 "$f" 2>/dev/null | tr '\n' ' ')"; done; }
# Маскировка личных данных / masking personal data
mask() {
  sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email>/g
          s/([0-9]{1,3}\.){3}[0-9]{1,3}/<ip>/g
          s/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/<mac>/g
          s/([0-9a-fA-F]{1,4}:){3,7}[0-9a-fA-F]{1,4}/<ip6>/g
          s/\+?[0-9]{11,20}/<num>/g'
}
# run N "Название" секунд — шаг под присмотром. / a supervised step: number, title, time limit in seconds.
run() {
  n=$1; put "$D/diag.status" "$n/$STEPS $T0"
  printf '\n\n########## %s. %s ##########\n' "$n" "$2"
  _f=$TMP.$n; rm -f "$_f" "$_f.ok"; _t=$(date +%s)
  ( "s$n" > "$_f" 2>&1; : > "$_f.ok" ) &
  _p=$!; _w=0
  _l=${DIAG_STEP:-$3}
  while [ ! -e "$_f.ok" ] && [ $_w -lt $((_l * 4)) ]; do sleep 0.25; _w=$((_w + 1)); done
  cat "$_f" 2>/dev/null
  if [ -e "$_f.ok" ]; then wait $_p 2>/dev/null; printf '\n(step %s took %s s)\n' "$n" "$(( $(date +%s) - _t ))"
  else
    # не ждём: зависшее чтение из ядра не убить, оно останется сиротой до перезагрузки
    # no wait: a stuck kernel read cannot be killed and stays orphaned until a reboot
    pkill -9 -P $_p 2>/dev/null; kill -9 $_p 2>/dev/null; hung="$hung $n"
    printf '\n!! step %s abandoned after %s s: no answer; the last line above shows where it stopped\n' "$n" "$_l"
  fi
  rm -f "$_f" "$_f.ok"
}

s1() {
  lim getprop ro.build.fingerprint
  uname -a; cat $R/proc/uptime; cat $R/proc/loadavg
  h "Modules"
  for m in $R/data/adb/modules/*; do
    [ -f "$m/module.prop" ] && printf '%s%s  %s\n' "$( [ -f "$m/disable" ] && echo '[off] ')" "${m##*/}" "$(grep -m1 '^version=' "$m/module.prop" | cut -d= -f2-)"
  done
}
s2() { sh "$MODDIR/tune.sh" logs 2>&1; }
s3() {
  # заголовок перед каждым чтением: если шаг бросили, видно, на чём / a header before every read shows where a step stopped
  h "battery/uevent"; lim cat $B/uevent
  h "usb/uevent"; lim cat $U/uevent
  h "bms/uevent"; lim cat $BMS/uevent
  h "SMB1390 charge pump"; if [ "$(rd $CP/cp_enable)" = 1 ]; then lim cat $CP/uevent; else echo "off (cp_enable=$(rd $CP/cp_enable))"; fi
  # cp_isns и cp_die_temp при выключенной микросхеме дёргают АЦП впустую — пропускаем
  # cp_isns and cp_die_temp poke the ADC for nothing while the chip is off — skipped
  for f in $CP/*; do case "${f##*/}" in cp_isns*|cp_die_temp|uevent) continue ;; esac; [ -f "$f" ] && [ -r "$f" ] && printf '%s = %s\n' "${f##*/}" "$(lim head -c 80 "$f" | tr '\n' ' ')"; done
  h "Chip temperatures (°C×10)"; echo "battery=$(rd $B/temp) pm6150=$(t_pmic) smb1390=$(t_cp) connector=$(t_conn)"
  h "Writable power_supply nodes"
  for f in $B/* $U/* $R/sys/class/power_supply/main/*; do [ -f "$f" ] && case "$(stat -c %A "$f" 2>/dev/null)" in -rw*) printf '%s = ' "${f#*/power_supply/}"; lim head -c 80 "$f" | tr '\n' ' '; echo ;; esac; done
  h "Current limiters"
  kv "$CCL" "$CCLMAX" $B/charge_control_limit $B/charger_temp $B/charger_temp_max $B/die_health $B/sw_jeita_enabled $B/step_charging_enabled $B/voltage_max $U/therm_icl_limit $U/input_current_settled
  h "Kernel switches (disable_thermal / skip_thermal)"
  kv $DISABLE_THERMAL $SKIP_THERMAL
  [ -f $DISABLE_THERMAL ] || echo "disable_thermal: -"; [ -f $SKIP_THERMAL ] || echo "skip_thermal: - (not VantomKernel)"
  case "$(rd $SKIP_THERMAL)" in 1|Y|y) echo "WARNING: skip_thermal is on — current levels are accepted but ignored" ;; esac
  case "$(rd $DISABLE_THERMAL)" in 1|Y|y) echo "WARNING: disable_thermal is on — current levels are rejected" ;; esac
  h "Does the kernel accept a level via $CCLN (write 1, read back; level 1 does not affect charging)"
  o=$(rd "$CCL")
  if [ "$o" = 0 ]; then
    e=$( { echo 1 > "$CCL"; } 2>&1 ); r=$(rd "$CCL"); echo 0 > "$CCL" 2>/dev/null
    if [ "$r" = 1 ]; then echo "$CCLN: ACCEPTS"; else echo "$CCLN: REJECTS (read «$r», error: ${e:-none})"; fi
  else echo "$CCLN = $o, test skipped"; fi
  echo "battery/charge_control_limit (sysfs, read-only by design) = $(rd $B/charge_control_limit)"
  h "Device tree current tables (µA per level)"
  dt_cache; cat "$D/dt.tables" 2>/dev/null
  h "Thermal configs"; echo "state: $(rd "$D/thermal.state")"
  while read -r hh f; do
    c=$(sha256sum "$R/vendor/etc/$f" 2>/dev/null | cut -d' ' -f1)
    if [ "$c" = "$hh" ]; then w=stock-tested; elif [ "$c" = "$(sha256sum "$MODDIR/thermal/$f" 2>/dev/null | cut -d' ' -f1)" ]; then w=module-copy; else w=other; fi
    printf '%s %s\n' "$f" "$w"
  done < "$MODDIR/thermal/orig.sha256"
  h "Charging sessions"; cat "$SESS" 2>/dev/null
  h "pmic-votable"
  for v in $R/sys/kernel/debug/pmic-votable/*; do [ -r "$v/status" ] && { echo "--- ${v##*/}"; lim head -n 20 "$v/status"; }; done 2>/dev/null
}
s4() {
  for p in $CPU0 $CPU6; do
    h "${p##*/}"
    kv $p/related_cpus $p/scaling_governor $p/scaling_min_freq $p/scaling_max_freq $p/scaling_cur_freq $p/cpuinfo_max_freq $p/scaling_available_frequencies
    g=$(rd $p/scaling_governor); [ -d "$p/$g" ] && dump_dir "$p/$g"
    cat $p/stats/time_in_state 2>/dev/null
  done
}
s5() {
  kv $K/gpu_model $K/gpuclk $K/max_gpuclk $K/gpu_busy_percentage $K/max_pwrlevel $K/min_pwrlevel $K/thermal_pwrlevel $K/devfreq/governor $K/devfreq/min_freq $K/devfreq/max_freq
  cat $K/devfreq/trans_stat 2>/dev/null
}
s6() {
  for z in $R/sys/class/thermal/thermal_zone*; do [ -r "$z/temp" ] && printf '%-28s %8s\n' "$(rd "$z/type")" "$(rd "$z/temp")"; done
  h "Cooling devices"
  for c in $R/sys/class/thermal/cooling_device*; do [ -r "$c/type" ] && printf '%-28s cur=%s max=%s\n' "$(rd "$c/type")" "$(rd "$c/cur_state")" "$(rd "$c/max_state")"; done
  h "dumpsys thermalservice"; lim dumpsys -t 8 thermalservice | head -n 80
}
s7() {
  cat $R/proc/meminfo
  kv $R/sys/block/zram0/disksize $R/sys/block/zram0/comp_algorithm $R/sys/block/zram0/mm_stat
}
s8() {
  for d in $R/sys/class/net/*; do [ -r "$d/statistics/rx_bytes" ] && printf '%-16s rx %8s MB  tx %8s MB\n' "${d##*/}" $(( $(cat "$d/statistics/rx_bytes") / 1048576 )) $(( $(cat "$d/statistics/tx_bytes") / 1048576 )); done
  echo "active SIMs: $(sims)"
}
s9() {
  # /sys/power/wakeup_count не читаем: чтение ждёт, пока в системе нет активных блокировок сна, то есть может висеть минутами
  # /sys/power/wakeup_count is not read: the read blocks while any wakeup source is active, i.e. for minutes
  kv $R/sys/kernel/wakeup_reasons/last_resume_reason
  h "suspend_control_internal"; lim dumpsys -t 8 suspend_control_internal | head -n 150
  h "deviceidle"; lim dumpsys -t 8 deviceidle | head -n 40
  echo "brightness: $(sget system screen_brightness) mode: $(sget system screen_brightness_mode) saver: $(sget global low_power)"
  echo "busybox: ${BB:-none} · uevent: $("$BB" --list 2>/dev/null | grep -qx uevent && echo yes || echo no)"
}
s10() { timeout $((LIM * 2)) dumpsys -t 18 batterystats --charged 2>/dev/null | head -n 2500; }
s11() {
  lim top -b -n 1 | head -n 32
  h "Android errors (last 150)"; lim logcat -d -b main,system -t 150 '*:E'
  h "Kernel log (last 120)"; lim dmesg | grep -v 'ibat_ua =' | tail -n 120
}
s12() {  # не больше 30 с: чтение температур микросхем само занимает до 2 с / at most 30 s: chip reads take up to 2 s each
  m0=$(date +%s); j=0
  while [ $j -lt 15 ] && [ $(( $(date +%s) - m0 )) -lt 30 ]; do
    echo "t=$(( $(date +%s) - m0 ))s little=$(rd $CPU0/scaling_cur_freq) big=$(rd $CPU6/scaling_cur_freq) gpu=$(rd $K/devfreq/cur_freq) cpuT=$(zt cpu-1-0-usr) body=$(zt quiet_therm) bat=$(rd $B/temp) pmic=$(t_pmic) cp=$(t_cp) I=$(rd $B/current_now) st=$(rd $B/status)"
    $SLP 2; j=$((j + 1))
  done
}

hung=""
{
header diag
run 1 "General" 15
run 2 "Module report and log" 20
run 3 "Battery and charging" 30
run 4 "CPU" 15
run 5 "GPU" 15
run 6 "Thermal" 25
run 7 "Memory" 15
run 8 "Network traffic since boot" 15
run 9 "Sleep and wakeups" 40
run 10 "Battery stats since last charge" 30
run 11 "Load" 40
run 12 "30 s monitor" 45
echo; echo "== end $(date '+%H:%M:%S') · total $(( $(date +%s) - T0 )) s · abandoned steps:${hung:- none}"
} > "$TMP" 2>&1

if [ -s "$TMP" ] && mask < "$TMP" > "$F"; then put "$D/diag.status" "done:${F#"$R"}"; ev diag_saved "${F#"$R"}"
else put "$D/diag.status" "error:write"; fi
