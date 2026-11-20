#!/system/bin/sh
# Davinci Control: удаление — вернуть ток зарядки и частоты, стереть свои данные. Логи в «Загрузках» остаются.
# Removal: restore charging and CPU limits, delete module data. Saved logs in Download stay.
B=/sys/class/power_supply/battery
for n in charging_enabled battery_charging_enabled; do [ -f $B/$n ] && echo 1 > $B/$n; done
[ -f $B/input_suspend ] && echo 0 > $B/input_suspend
for c in /sys/class/thermal/cooling_device*; do [ "$(cat $c/type 2>/dev/null)" = battery ] && echo 0 > $c/cur_state 2>/dev/null; done
for p in /sys/devices/system/cpu/cpufreq/policy0 /sys/devices/system/cpu/cpufreq/policy6; do
  [ -f $p/cpuinfo_max_freq ] && cat $p/cpuinfo_max_freq > $p/scaling_max_freq 2>/dev/null
done
# Экономия: снять «залипание» (и выключить, если её включал модуль) — когда система загрузится.
# Battery Saver: clear the sticky flag (and turn it off if the module turned it on) once the system is up.
sv=0; grep -q '^SAVER_BATT=1' /data/adb/davinci-control/config 2>/dev/null && sv=1
(
  i=0; while [ "$(getprop sys.boot_completed)" != 1 ] && [ $i -lt 120 ]; do sleep 5; i=$((i + 1)); done
  [ $sv = 1 ] && cmd power set-mode 0 >/dev/null 2>&1
  settings put global low_power_sticky 0 >/dev/null 2>&1
) </dev/null >/dev/null 2>&1 &
rm -rf /data/adb/davinci-control
