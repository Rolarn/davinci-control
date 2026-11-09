#!/system/bin/sh
# Davinci Control — диагностика в один файл (только чтение). Ход: $D/diag.status «N/12» / «done:путь» / «error:…».
# Личные данные (почта, IP, MAC, длинные номера) в файле маскируются.
# Diagnostics into one file (read-only). Personal data (e-mail, IP, MAC, long numbers) is masked.
MODDIR=${MODDIR:-${0%/*}}
. "$MODDIR/common.sh"
load_conf
mkdir -p "$D" "$OUT"
F=$OUT/davinci-control_$(version)_diag_$(date +%Y-%m-%d_%H%M).txt
TMP=$D/diag.tmp
STEPS=12; n=0
step() { n=$((n + 1)); echo "$n/$STEPS" > "$D/diag.status"; printf '\n\n########## %s. %s ##########\n' "$n" "$*"; }
h() { printf '\n===== %s =====\n' "$*"; }
kv() { for f in "$@"; do [ -r "$f" ] && printf '%s = %s\n' "${f#"$R"}" "$(tr '\n' ' ' < "$f" 2>/dev/null | cut -c1-500)"; done; }
dump_dir() { for f in "$1"/*; do [ -f "$f" ] && [ -r "$f" ] && printf '%s = %s\n' "${f##*/}" "$(head -c 400 "$f" 2>/dev/null | tr '\n' ' ')"; done; }
# Маскировка личных данных / masking personal data
mask() {
  sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email>/g
          s/([0-9]{1,3}\.){3}[0-9]{1,3}/<ip>/g
          s/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/<mac>/g
          s/([0-9a-fA-F]{1,4}:){3,7}[0-9a-fA-F]{1,4}/<ip6>/g
          s/\+?[0-9]{11,20}/<num>/g'
}

{
header diag
step "General"
getprop ro.build.fingerprint
uname -a; cat $R/proc/uptime; cat $R/proc/loadavg
h "Modules"
for m in $R/data/adb/modules/*; do
  [ -f "$m/module.prop" ] && printf '%s%s  %s\n' "$( [ -f "$m/disable" ] && echo '[off] ')" "${m##*/}" "$(grep -m1 '^version=' "$m/module.prop" | cut -d= -f2-)"
done

step "Module report and log"
sh "$MODDIR/tune.sh" logs 2>&1

step "Battery and charging"
h "battery/uevent"; cat $B/uevent 2>/dev/null
h "usb/uevent"; cat $U/uevent 2>/dev/null
h "SMB1390 charge pump"; cat $CP/uevent 2>/dev/null || echo "-"
for f in $CP/*; do [ -f "$f" ] && [ -r "$f" ] && printf '%s = %s\n' "${f##*/}" "$(head -c 80 "$f" 2>/dev/null | tr '\n' ' ')"; done
h "Chip temperatures (°C×10)"; echo "battery=$(rd $B/temp) pm6150=$(t_pmic) smb1390=$(t_cp) connector=$(t_conn)"
h "Writable power_supply nodes"
for f in $B/* $U/* $R/sys/class/power_supply/main/*; do [ -f "$f" ] && case "$(stat -c %A "$f" 2>/dev/null)" in -rw*) printf '%s = %s\n' "${f#*/power_supply/}" "$(head -c 80 "$f" 2>/dev/null | tr '\n' ' ')" ;; esac; done
h "Current limiters"
kv "$CCL" "$CCLMAX" $B/charge_control_limit $B/charger_temp $B/charger_temp_max $B/die_health $B/sw_jeita_enabled $B/step_charging_enabled $B/voltage_max $U/therm_icl_limit $U/input_current_settled
h "Kernel switches (disable_thermal / skip_thermal)"
kv $DISABLE_THERMAL $SKIP_THERMAL
[ -f $DISABLE_THERMAL ] || echo "disable_thermal: -"; [ -f $SKIP_THERMAL ] || echo "skip_thermal: - (not VantomKernel)"
case "$(rd $SKIP_THERMAL)" in 1|Y|y) echo "WARNING: skip_thermal is on — current levels are accepted but ignored" ;; esac
case "$(rd $DISABLE_THERMAL)" in 1|Y|y) echo "WARNING: disable_thermal is on — current levels are rejected" ;; esac
h "Does the kernel accept a level (write 1, read back; level 1 does not affect charging)"
o=$(rd "$CCL")
if [ "$o" = 0 ]; then
  e=$( { echo 1 > "$CCL"; } 2>&1 ); r=$(rd "$CCL"); echo 0 > "$CCL" 2>/dev/null
  if [ "$r" = 1 ]; then echo "${CCL##*/}: ACCEPTS"; else echo "${CCL##*/}: REJECTS (read «$r», error: ${e:-none})"; fi
else echo "${CCL##*/} = $o, test skipped"; fi
h "Device tree current tables (µA per level)"
dt_cache; cat "$D/dt.tables" 2>/dev/null
h "Thermal configs"; echo "state: $(rd "$D/thermal.state")"
while read -r hh f; do printf '%s %s\n' "$f" "$( [ "$(sha256sum "$R/vendor/etc/$f" 2>/dev/null | cut -d' ' -f1)" = "$hh" ] && echo stock-tested || echo other)"; done < "$MODDIR/thermal/orig.sha256"
h "pmic-votable"
for v in $R/sys/kernel/debug/pmic-votable/*; do [ -r "$v/status" ] && { echo "--- ${v##*/}"; head -n 20 "$v/status"; }; done 2>/dev/null
h "Charging sessions"; cat "$SESS" 2>/dev/null

step "CPU"
for p in $CPU0 $CPU6; do
  h "${p##*/}"
  kv $p/related_cpus $p/scaling_governor $p/scaling_min_freq $p/scaling_max_freq $p/scaling_cur_freq $p/cpuinfo_max_freq $p/scaling_available_frequencies
  g=$(rd $p/scaling_governor); [ -d "$p/$g" ] && dump_dir "$p/$g"
  cat $p/stats/time_in_state 2>/dev/null
done

step "GPU"
kv $K/gpu_model $K/gpuclk $K/max_gpuclk $K/gpu_busy_percentage $K/max_pwrlevel $K/min_pwrlevel $K/thermal_pwrlevel $K/devfreq/governor $K/devfreq/min_freq $K/devfreq/max_freq
cat $K/devfreq/trans_stat 2>/dev/null

step "Thermal"
for z in $R/sys/class/thermal/thermal_zone*; do [ -r "$z/temp" ] && printf '%-28s %8s\n' "$(rd "$z/type")" "$(rd "$z/temp")"; done
h "Cooling devices"
for c in $R/sys/class/thermal/cooling_device*; do [ -r "$c/type" ] && printf '%-28s cur=%s max=%s\n' "$(rd "$c/type")" "$(rd "$c/cur_state")" "$(rd "$c/max_state")"; done
h "dumpsys thermalservice"; dumpsys thermalservice 2>/dev/null | head -n 80

step "Memory"
cat $R/proc/meminfo
kv $R/sys/block/zram0/disksize $R/sys/block/zram0/comp_algorithm $R/sys/block/zram0/mm_stat

step "Network traffic since boot"
for d in $R/sys/class/net/*; do [ -r "$d/statistics/rx_bytes" ] && printf '%-16s rx %8s MB  tx %8s MB\n' "${d##*/}" $(( $(cat "$d/statistics/rx_bytes") / 1048576 )) $(( $(cat "$d/statistics/tx_bytes") / 1048576 )); done
echo "active SIMs: $(sims)"

step "Sleep and wakeups"
kv $R/sys/power/wakeup_count $R/sys/kernel/wakeup_reasons/last_resume_reason
h "suspend_control_internal"; dumpsys suspend_control_internal 2>/dev/null | head -n 150
h "deviceidle"; dumpsys deviceidle 2>/dev/null | head -n 40
echo "brightness: $(sget system screen_brightness) mode: $(sget system screen_brightness_mode) saver: $(sget global low_power)"
echo "busybox: ${BB:-none} · uevent: $("$BB" --list 2>/dev/null | grep -qx uevent && echo yes || echo no)"

step "Battery stats since last charge"
dumpsys batterystats --charged 2>/dev/null | head -n 2500

step "Load"
top -b -n 1 -m 25 2>/dev/null | head -n 32
h "Android errors (last 150)"; logcat -d -b main,system -t 150 '*:E' 2>/dev/null
h "Kernel log (last 120)"; dmesg 2>/dev/null | tail -n 120

step "30 s monitor"
j=0
while [ $j -lt 15 ]; do
  echo "t=$((j * 2))s little=$(rd $CPU0/scaling_cur_freq) big=$(rd $CPU6/scaling_cur_freq) gpu=$(rd $K/devfreq/cur_freq) cpuT=$(zt cpu-1-0-usr) body=$(zt quiet_therm) bat=$(rd $B/temp) pmic=$(t_pmic) cp=$(t_cp) I=$(rd $B/current_now) st=$(rd $B/status)"
  sleep 2; j=$((j + 1))
done
echo; echo "== end $(date '+%H:%M:%S')"
} > "$TMP" 2>&1

if [ -s "$TMP" ] && mask < "$TMP" > "$F"; then rm -f "$TMP"; echo "done:${F#"$R"}" > "$D/diag.status"; ev diag_saved "${F#"$R"}"
else rm -f "$TMP"; echo "error:write" > "$D/diag.status"; fi
