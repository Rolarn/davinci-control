#!/bin/bash
# Тестовый стенд: поддельный корень R с /sys, /proc, /vendor и поддельными командами Android.
# Test bench: a fake root R with /sys, /proc, /vendor and fake Android commands. Needs busybox.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FAILS=0
BBX=$(command -v busybox)
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad() { printf '  \033[31m✗ %s\033[0m\n' "$1"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

mkroot() {  # $1 = файл сценария (необязательно) / optional scenario file
  R=$(mktemp -d "${TMPDIR:-/tmp}/dc.XXXXXX")
  M=$R/data/adb/modules/davinci-control; CLEAN="$CLEAN $R"
  mkdir -p "$M" "$R/bin" "$R/data/adb/davinci-control" "$R/data/system" "$R/sdcard/Download" "$R/proc" "$R/vendor/etc"
  cp -a "$ROOT/module/." "$M/"
  B=$R/sys/class/power_supply/battery; U=$R/sys/class/power_supply/usb; C=$R/sys/class/power_supply/charge_pump_master
  mkdir -p $B $U $C $R/sys/class/backlight/panel0-backlight $R/sys/kernel/fast_charge $R/sys/class/net/rmnet_data0/statistics $R/sys/class/net/wlan0/statistics \
    $R/sys/devices/system/cpu/cpufreq/policy0/stats $R/sys/devices/system/cpu/cpufreq/policy6/stats $R/sys/class/kgsl/kgsl-3d0/devfreq \
    $R/sys/class/thermal/thermal_zone0 $R/sys/class/thermal/thermal_zone1 $R/sys/class/thermal/thermal_zone2 $R/sys/class/thermal/cooling_device0 $R/sys/class/thermal/cooling_device5 $R/sys/module/qpnp_smb5/parameters $R/sys/module/smb5_lib/parameters \
    "$R/proc/device-tree/soc/qcom,qpnp-smb5"
  w() { echo "$2" > "$1"; }
  w $B/capacity 40; w $B/status Charging; w $B/temp 300; w $B/current_now -2600000; w $B/voltage_now 4100000; w $B/charge_counter 2000000
  # как на davinci: charge_control_limit только для чтения, рабочий рычаг — охлаждающее устройство «battery»
  # like davinci: charge_control_limit is read-only, the working lever is the "battery" cooling device
  w $B/charge_control_limit 0; w $B/charge_control_limit_max 16
  w $R/sys/class/thermal/cooling_device0/type thermal-cpufreq-0; w $R/sys/class/thermal/cooling_device0/cur_state 0
  w $R/sys/class/thermal/cooling_device5/type battery; w $R/sys/class/thermal/cooling_device5/cur_state 0; w $R/sys/class/thermal/cooling_device5/max_state 16
  w $B/input_suspend 0; w $B/battery_charging_enabled 1
  w $B/charge_full 3700000; w $B/charge_full_design 4000000; w $B/cycle_count 310; w $B/charger_temp 420; w $B/charger_temp_max 450
  printf 'POWER_SUPPLY_STATUS=Charging\nPOWER_SUPPLY_HEALTH=Good\nPOWER_SUPPLY_CHARGE_TYPE=Fast\nPOWER_SUPPLY_DIE_HEALTH=Cool\nPOWER_SUPPLY_INPUT_CURRENT_LIMITED=0\n' > $B/uevent
  w $C/cp_enable 1; w $C/cp_die_temp 380; printf 'POWER_SUPPLY_NAME=charge_pump_master\nPOWER_SUPPLY_TEMP=380\n' > $C/uevent
  w $U/present 1; w $U/online 1; w $U/connector_temp 350
  # блок QC3 без микросхемы быстрой зарядки (smb_en_reason=0) / a QC3 charger, charge pump not engaged
  w $U/real_type USB_HVDCP_3; w $U/voltage_now 8800000; w $U/input_current_now 2000000; w $U/smb_en_reason 0
  mkdir -p $R/sys/class/power_supply/bms $R/sys/power; w $R/sys/class/power_supply/bms/capacity_raw 4000
  printf 'POWER_SUPPLY_NAME=bms\nPOWER_SUPPLY_CAPACITY_RAW=4000\n' > $R/sys/class/power_supply/bms/uevent
  # как на телефоне: чтение wakeup_count висит, пока есть активные блокировки сна / reading it blocks, like on the phone
  mkfifo $R/sys/power/wakeup_count
  printf 'POWER_SUPPLY_REAL_TYPE=USB_HVDCP_3\nPOWER_SUPPLY_ONLINE=1\nPOWER_SUPPLY_VOLTAGE_NOW=8800000\nPOWER_SUPPLY_INPUT_CURRENT_NOW=2000000\nPOWER_SUPPLY_QUICK_CHARGE_TYPE=1\n' > $U/uevent
  w $R/sys/class/backlight/panel0-backlight/brightness 1000; w $R/sys/class/backlight/panel0-backlight/max_brightness 2047
  w $R/sys/kernel/fast_charge/force_fast_charge 1; w $R/sys/class/net/rmnet_data0/statistics/rx_bytes 1000; w $R/sys/class/net/rmnet_data0/statistics/tx_bytes 1000
  w $R/sys/class/net/wlan0/statistics/rx_bytes 1000; w $R/sys/class/net/wlan0/statistics/tx_bytes 1000
  w $R/sys/module/qpnp_smb5/parameters/disable_thermal N; w $R/sys/module/smb5_lib/parameters/skip_thermal N
  for p in 0 6; do P=$R/sys/devices/system/cpu/cpufreq/policy$p; w $P/scaling_max_freq 1804800; w $P/scaling_cur_freq 1209600; w $P/cpuinfo_max_freq 1804800
    w $P/scaling_available_frequencies "300000 1017600 1324800 1612800 1708800 1804800"; printf '300000 100\n1804800 50\n' > $P/stats/time_in_state; done
  K=$R/sys/class/kgsl/kgsl-3d0; w $K/gpuclk 180000000; w $K/gpu_busy_percentage "5 %"; w $K/min_pwrlevel 7; w $K/thermal_pwrlevel 0; printf '* 180000000: 0 0 time(ms) 1000\n' > $K/devfreq/trans_stat
  w $R/sys/class/thermal/thermal_zone0/type quiet_therm; w $R/sys/class/thermal/thermal_zone0/temp 38000
  w $R/sys/class/thermal/thermal_zone1/type cpu-1-0-usr; w $R/sys/class/thermal/thermal_zone1/temp 55000
  w $R/sys/class/thermal/thermal_zone2/type conn_therm; w $R/sys/class/thermal/thermal_zone2/temp 36000
  w $R/proc/uptime "5000.00 1000.00"; echo "now at 3000000000000 nsecs" > $R/proc/timer_list; echo "0.1 0.2 0.3 1/100 1" > $R/proc/loadavg
  # таблица тока QC3 из device tree: 17 значений, big-endian / QC3 current table, big-endian u32
  dtw() { python3 -c "import struct,sys; v=[int(x) for x in sys.argv[1:]]; sys.stdout.buffer.write(struct.pack('>%dI'%len(v),*v))" $2 > "$R/proc/device-tree/soc/qcom,qpnp-smb5/$1"; }
  dtw qcom,thermal-mitigation "3500000 3400000 3300000 3200000 3100000 3000000 2900000 2800000 2600000 2400000 2200000 2000000 1800000 1500000 1000000 500000"
  dtw qcom,thermal-fcc-qc3-normal "3500000 3400000 3300000 3200000 3100000 3000000 2900000 2800000 2700000 2600000 2400000 2200000 2000000 2000000 750000 700000"
  dtw qcom,thermal-fcc-qc3-cp "3500000 3500000 3500000 3500000 3400000 3300000 3200000 3100000 3000000 2800000 2600000 2400000 2200000 2000000 1000000 700000"
  dtw qcom,thermal-mitigation-dcp "1800000 1800000 1800000 1800000 1800000 1800000 1800000 1800000 1800000 1700000 1600000 1400000 1200000 1100000 1100000 1000000"
  printf 'com.a 10100 0 /data\n' > $R/data/system/packages.list
  printf '"1017600"\n"1017600"\n"PowerHint": "EXPENSIVE_RENDERING",\n"Node": "GPUMinFreq",\n"Duration": 0,\n"Value": "7"\n' > $R/vendor/etc/powerhint.json
  w $R/now 1700000000; w $R/lowpower 0; w $R/brmode 1
  # поддельные команды / fake commands
  for a in $(busybox --list); do case $a in date|sleep|getprop|settings|cmd|su|logcat|dumpsys|pm|am|magisk|top|dmesg) ;; *) ln -sf "$(command -v busybox)" "$R/bin/$a" ;; esac; done
  cat > $R/bin/date <<EOF
#!/bin/bash
if [ "\$1" = +%s ]; then cat $R/now; else TZ=UTC /bin/date -d @\$(cat $R/now) "\$@"; fi
EOF
  cat > $R/bin/settings <<EOF
#!/bin/bash
echo "settings \$*" >> $R/calls.log
case "\$1 \$2 \$3" in "get global low_power") cat $R/lowpower ;; "put global low_power") echo \$4 > $R/lowpower ;;
  "get system screen_brightness_mode") cat $R/brmode ;; "put system screen_brightness_mode") echo \$4 > $R/brmode ;; "get system screen_brightness") echo 255 ;; esac; true
EOF
  cat > $R/bin/cmd <<EOF
#!/bin/bash
echo "cmd \$*" >> $R/calls.log; [ "\$1 \$2" = "power set-mode" ] && echo \$3 > $R/lowpower; true
EOF
  cat > $R/bin/getprop <<EOF
#!/bin/bash
case "\$1" in ro.product.device) cat $R/device 2>/dev/null || echo davinci ;; persist.sys.locale) cat $R/locale 2>/dev/null || echo ru-RU ;;
  gsm.sim.state) echo LOADED,LOADED ;; sys.boot_completed) echo 1 ;; ro.build.display.id) echo TEST.BUILD ;; *) echo ;; esac
EOF
  printf '#!/bin/sh\ntrue\n' > $R/bin/logcat; cp $R/bin/logcat $R/bin/dumpsys; cp $R/bin/logcat $R/bin/top; cp $R/bin/logcat $R/bin/dmesg; cp $R/bin/logcat $R/bin/am
  printf '#!/bin/sh\necho package:com.example\n' > $R/bin/pm
  printf '#!/bin/sh\ncase "$1" in -v) echo 31.1;; -V) echo 31100;; esac\n' > $R/bin/magisk
  printf '#!/bin/bash\n[ "$1" = 2000 ] && /bin/bash -c "$3"\n' > $R/bin/su
  if [ -n "$1" ]; then sed "s|@R@|$R|g" "$1" > $R/bin/sleep; else printf '#!/bin/sh\ntrue\n' > $R/bin/sleep; fi
  find $R/bin -type f -exec chmod +x {} +
  export R
}
# Запуск службы в стенде / run the daemon on the bench
run_daemon() { (cd "$R" && PATH=$R/bin R=$R MODDIR=$M BB=$BBX SLEEP_CMD=$R/bin/sleep timeout 60 $BBX ash "$M/daemon.sh" >"$R/daemon.out" 2>&1) || true; }
tune() { (cd "$R" && PATH=$R/bin R=$R MODDIR=$M BB=$BBX $BBX ash "$M/tune.sh" "$@"); }
logtxt() { (PATH=$R/bin R=$R MODDIR=$M $BBX ash -c ". $M/common.sh; load_conf; render_log $R/data/adb/davinci-control/events.log"); }
# Уборка временных корней / cleanup of temporary roots
CLEAN=""
trap '[ -z "$KEEP" ] && for x in $CLEAN; do case $x in */dc.*|*/dcsc.*) rm -rf "$x" ;; esac; done' EXIT
