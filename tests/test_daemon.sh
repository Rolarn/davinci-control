#!/bin/bash
# Сценарии службы на тестовом стенде / service scenarios on the test bench
. "$(dirname "$0")/lib.sh"
SC=$(mktemp -d "${TMPDIR:-/tmp}/dcsc.XXXXXX"); CLEAN="$CLEAN $SC"
D_=data/adb/davinci-control

# Общая «часть сна»: шаг, время вперёд, затем сценарий / common sleep: step, advance clock, scenario
head_sleep='#!/bin/bash
R=@R@; B=$R/sys/class/power_supply/battery; U=$R/sys/class/power_supply/usb; BL=$R/sys/class/backlight/panel0-backlight/brightness
n=$(cat $R/step 2>/dev/null || echo 0); n=$((n+1)); echo $n > $R/step
echo $(( $(cat $R/now) + ${1:-60} )) > $R/now
echo "step $n t=$(cat $B/temp) lvl=$(cat $R/sys/class/thermal/cooling_device5/cur_state) en=$(cat $B/battery_charging_enabled) $(cat $R/data/adb/davinci-control/state 2>/dev/null)" >> $R/trace
unplug() { echo 0 > $U/present; echo 0 > $U/online; echo Discharging > $B/status; }
plug() { echo 1 > $U/present; echo 1 > $U/online; echo Charging > $B/status; }
# как ядро: переключатель выключен — батарея не заряжается / like the kernel: switch off → not charging
sync_st() { if [ "$(cat $U/online)" = 1 ]; then if [ "$(cat $B/battery_charging_enabled)" = 0 ] || [ "$(cat $B/input_suspend)" = 1 ]; then echo "Not charging" > $B/status; else echo Charging > $B/status; fi; fi; }
trap sync_st EXIT'

echo "1. «Бережно»: ступени тока и пауза при нагреве / Care: levels and heat pause"
cat > $SC/care <<EOF
$head_sleep
T=(300 415 435 455 425 395 375 375 375 375)
[ \$n -le 10 ] && echo \${T[\$((n-1))]} > \$B/temp
[ \$n = 11 ] && touch \$R/data/adb/modules/davinci-control/disable
exit 0
EOF
mkroot $SC/care; run_daemon
check "ступень 4 при 41,5° / level 4 at 41.5°" "grep -q 't=415 lvl=4' $R/trace"
check "ступень 8 при 43,5° / level 8 at 43.5°" "grep -q 't=435 lvl=8 en=0' $R/trace"
check "пауза при 45,5° (порог 42) / pause at 45.5° (threshold 42)" "grep -q 'pause_hot' $R/$D_/events.log"
check "пауза держится минимум 2 мин / pause lasts ≥ 2 min" "[ \$(grep -c 'chg=off why=hot' $R/trace) -ge 4 ]"
check "продолжение при 37,5° / resume at 37.5°" "grep -q 'resume' $R/$D_/events.log"
check "при выключении ток без ограничения / level 0 on disable" "[ \$(cat $R/sys/class/thermal/cooling_device5/cur_state) = 0 ] && [ \$(cat $B/battery_charging_enabled) = 1 ]"
check "событие «выключен» / disabled event" "grep -q 'disabled' $R/$D_/events.log"
check "статус в module.prop / status in module.prop" "grep -q '^description=✅' $M/module.prop"

echo "2. «Быстро»: удержание ниже 45° / Fast: hold below 45°"
cat > $SC/fast <<EOF
$head_sleep
T=(300 441 441 443 451 438 430 420 420 300)
[ \$n -le 10 ] && echo \${T[\$((n-1))]} > \$B/temp
[ \$n = 11 ] && touch \$R/data/adb/modules/davinci-control/disable
exit 0
EOF
mkroot $SC/fast; printf 'CC_SMART=0\nHOT_PAUSE=48\nHOT_RESUME=44\n' > $R/$D_/config
run_daemon
check "44,1° → ступень 8 / 44.1° → level 8" "grep -q 't=441 lvl=8' $R/trace"
check "держит и повышает / holds and raises" "grep -q 't=443 lvl=10' $R/trace"
check "45,1° → ступень 12 / 45.1° → level 12" "grep -q 't=451 lvl=12' $R/trace && grep -q 't=438 lvl=12' $R/trace"
check "остыло → ступень вниз / cooled → level down" "grep -q 't=420 lvl=11' $R/trace"
check "события удержания / hold events" "grep -q 'hold_on' $R/$D_/events.log"
check "без паузы при 45° в «Быстро» / no pause at 45° in Fast" "! grep -q pause_hot $R/$D_/events.log"

echo "3. Лимит 80%, отключение кабеля, сеанс, яркость / limit, unplug, session, brightness"
cat > $SC/limit <<EOF
$head_sleep
C=(60 70 79 80 81 79 76 75 74 74)
[ \$n -le 10 ] && echo \${C[\$((n-1))]} > \$B/capacity
[ \$n = 7 ] && echo 0 > \$BL
[ \$n = 8 ] && echo 1000 > \$BL
[ \$n = 10 ] && unplug
[ \$n = 12 ] && touch \$R/data/adb/modules/davinci-control/disable
exit 0
EOF
mkroot $SC/limit; mkdir -p $R/$D_; echo BRIGHT_CHARGE=1 > $R/$D_/config; run_daemon
check "пауза на 80% / pause at 80%" "grep -q 'pause_limit	80' $R/$D_/events.log"
check "переключатель реально выключен / switch really off" "grep -q 'en=0 .*why=limit sw=battery_charging_enabled' $R/trace && ! grep -q sw_nostop $R/$D_/events.log"
check "продолжение с 75% / resume at 75%" "grep -q 'resume	75' $R/$D_/events.log"
check "сеанс записан с экраном и блоком / session with screen share and charger" "grep -qE '^[0-9]+,[0-9]+,40,74,[0-9]+,300,USB_HVDCP_3,17,care,[0-9]+,0$' $R/$D_/sessions.csv"
check "яркость 100% на зарядке / 100% brightness on charge" "grep -q 'bright_max' $R/$D_/events.log"
check "автояркость и экономия без кабеля / auto brightness and saver" "grep -q bright_auto $R/$D_/events.log && grep -q saver_on $R/$D_/events.log && [ \$(cat $R/lowpower) = 1 ]"

echo "4. Ночной расход в мА, причины и предупреждение / overnight drain mA, causes, alert"
cat > $SC/drain <<EOF
$head_sleep
case \$n in
  1) unplug ;;
  2) echo 0 > \$BL ;;
  3) echo 80 > \$B/capacity; echo 1700000 > \$B/charge_counter; echo 7689 > \$R/sys/class/power_supply/bms/capacity_raw; echo 5000000 > \$R/sys/class/net/rmnet_data0/statistics/rx_bytes; echo 3000000 > \$R/sys/class/net/wlan0/statistics/rx_bytes; echo \$(( \$(cat \$R/now) + 28800 )) > \$R/now; echo "now at 3007200000000 nsecs" > \$R/proc/timer_list ;;
  4) echo 1000 > \$BL ;;
  6) touch \$R/data/adb/modules/davinci-control/disable ;;
esac
exit 0
EOF
mkroot $SC/drain; echo 85 > $R/sys/class/power_supply/battery/capacity; mkdir -p $R/$D_; echo 8500 > $R/sys/class/power_supply/bms/capacity_raw
now0=1700000000
for d in 20 18 15; do echo "$((now0 - d * 86400)),28800,4,120,90,0,0,1" >> $R/$D_/drain.csv; done
for d in 5 3; do echo "$((now0 - d * 86400)),28800,8,600,60,30,80,2" >> $R/$D_/drain.csv; done
run_daemon
L=$(tail -n 1 $R/$D_/drain.csv)
check "запись: −5%, 300 мАч по точному счётчику, 2 SIM / record: −5%, 300 mAh from the precise gauge, 2 SIMs ($L)" "echo '$L' | grep -qE '^[0-9]+,28[0-9]{3},5,300,[0-9]+,4,[0-9]+,2$'"
check "доля мобильной сети посчитана / mobile share computed" "echo '$L' | awk -F, '{exit !(\$7 >= 50 && \$7 <= 70)}'"
check "предупреждение о росте расхода / drain alert" "grep -q drain_alert $R/$D_/events.log && [ -s $R/$D_/drain.alert ]"

echo "5. Задержка JEITA выше 45° / JEITA lag above 45°"
cat > $SC/jeita <<EOF
$head_sleep
echo \$((40 + n)) > \$B/capacity
case \$n in 1) echo 452 > \$B/temp ;; 7) echo -1900000 > \$B/current_now ;; 30) unplug ;; 32) touch \$R/data/adb/modules/davinci-control/disable ;; esac
exit 0
EOF
mkroot $SC/jeita; mkdir -p $R/$D_; printf 'CC_SMART=0\nHOT_PAUSE=48\nCHARGE_LIMIT=100\n' > $R/$D_/config; run_daemon
check "событие задержки JEITA / JEITA lag event" "grep -q jeita_lag $R/$D_/events.log"
check "задержка в сеансе / lag stored in session" "awk -F, '{exit !(\$11 >= 60)}' $R/$D_/sessions.csv"

echo "6. skip_thermal, отброшенный переключатель / skip_thermal, rejected switch"
cat > $SC/skip <<EOF
$head_sleep
[ \$n = 3 ] && echo 85 > \$B/capacity
[ \$n = 4 ] && echo 1 > \$B/battery_charging_enabled
[ \$n = 6 ] && touch \$R/data/adb/modules/davinci-control/disable
exit 0
EOF
mkroot $SC/skip; echo Y > $R/sys/module/smb5_lib/parameters/skip_thermal; echo 445 > $R/sys/class/power_supply/battery/temp
run_daemon
check "событие skip_thermal / skip_thermal event" "grep -q skip_thermal $R/$D_/events.log"
check "ступень не пишется / level not written" "! grep -qE 'lvl=[1-9]' $R/trace"
check "предупреждение в module.prop / warning in module.prop" "grep -q 'skip_thermal' $M/module.prop"
check "переключатель не держит — следующий / switch fails — next one" "grep -q sw_nostop $R/$D_/events.log && grep -q 'sw_now	input_suspend' $R/$D_/events.log"

echo "7. Микросхема быстрой зарядки включена: ступени по её таблице / charge pump on: levels from its table"
cat > $SC/cp <<EOF
$head_sleep
T=(300 415 435 300)
[ \$n -le 4 ] && echo \${T[\$((n-1))]} > \$B/temp
[ \$n = 5 ] && echo USB_DCP > \$U/real_type
[ \$n = 6 ] && echo 435 > \$B/temp
[ \$n = 8 ] && touch \$R/data/adb/modules/davinci-control/disable
exit 0
EOF
mkroot $SC/cp; echo 1 > $R/sys/class/power_supply/usb/smb_en_reason; echo HOT_PAUSE=0 > $R/$D_/config; run_daemon
check "3,1 А — ступень 7 (без неё была бы 4) / 3.1 A is level 7 here" "grep -q 't=415 lvl=7' $R/trace"
check "2,6 А — ступень 10 / 2.6 A is level 10" "grep -q 't=435 lvl=10' $R/trace"
check "таблица в состоянии / table in state" "grep -q 'tbl=qc3cp' $R/trace && grep -q 'tbl=dcp' $R/trace"
check "сменился блок — ступени пересчитаны (1,4 А — 11) / charger changed, levels recomputed" "grep -q 't=435 lvl=11' $R/trace"

echo "8. Сеанс переживает перезагрузку / a session survives a reboot"
cat > $SC/reboot <<EOF
$head_sleep
[ \$n = 2 ] && echo 62 > \$B/capacity
[ \$n = 3 ] && unplug
[ \$n = 5 ] && touch \$R/data/adb/modules/davinci-control/disable
exit 0
EOF
mkroot $SC/reboot
echo "s_t0=$((1700000000 - 3600)); s_c0=22; s_tmax=410; s_sum=250000; s_n=100; s_pmax=17; s_typ=USB_HVDCP_3; s_on=10; s_all=100; s_jl=0; s_last=$((1700000000 - 60)); s_cap=60" > $R/$D_/session
run_daemon
check "сеанс продолжен с 22% / session continued from 22%" "grep -qE '^1699996400,[0-9]+,22,62,[0-9]+,410,USB_HVDCP_3,17,care' $R/$D_/sessions.csv"
check "файл сеанса убран / session file removed" "[ ! -f $R/$D_/session ]"
mkroot $SC/reboot; echo 0 > $R/sys/class/power_supply/usb/present; echo 0 > $R/sys/class/power_supply/usb/online; echo Discharging > $R/sys/class/power_supply/battery/status
echo "s_t0=$((1700000000 - 3600)); s_c0=22; s_tmax=410; s_sum=250000; s_n=100; s_pmax=17; s_typ=USB_HVDCP_3; s_on=10; s_all=100; s_jl=0; s_last=$((1700000000 - 600)); s_cap=58" > $R/$D_/session
run_daemon
check "кабель вынули, пока телефон был выключен: сеанс закрыт по последней записи / closed at the last record" "grep -qE '^1699996400,1699999400,22,58,' $R/$D_/sessions.csv"

echo "9. Зарядить к времени и уведомления / charge by time and notifications"
cat > $SC/fullby <<EOF
$head_sleep
case \$n in
  1) echo 80 > \$B/capacity ;;
  3) echo \$(( \$(cat \$R/now) + 600 )) > \$R/now ;;
  5) echo 100 > \$B/capacity ;;
  7) touch \$R/data/adb/modules/davinci-control/disable ;;
esac
exit 0
EOF
# стенд: 22:13 UTC, блок 17 Вт → на 20% нужно 40 мин / bench: 22:13 UTC, a 17 W charger → 40 min for 20%
mkroot $SC/fullby; echo 79 > $R/sys/class/power_supply/battery/capacity; printf 'FULL_BY=23:00\nNOTIFY=1\n' > $R/$D_/config; run_daemon
check "сначала пауза на лимите / first a pause at the limit" "grep -q 'pause_limit	80' $R/$D_/events.log"
check "за 40 мин до срока — дозарядка / top-up starts 40 min before" "grep -q 'fullby_go	23:00	80' $R/$D_/events.log && grep -q 'fb=1' $R/trace"
check "после дозарядки пауз нет / no pause after the top-up starts" "[ \$(grep -c pause_limit $R/$D_/events.log) = 1 ]"
check "уведомления: пауза и «заряжено» / notifications: pause and charged" "[ \$(grep -c 'cmd notification post' $R/calls.log) = 2 ] && grep -q 'dc_chg' $R/calls.log"
mkroot $SC/fullby; echo 79 > $R/sys/class/power_supply/battery/capacity; printf 'FULL_BY=23:00\n' > $R/$D_/config; run_daemon
check "и без уведомлений дозарядка идёт / the top-up works without notifications too" "grep -q fullby_go $R/$D_/events.log"
mkroot $SC/fullby; printf 'FULL_BY=23:00\n' > $R/$D_/config; run_daemon
check "мало времени — заряжает сразу, без паузы / little time left: charges straight away" "grep -q 'fullby_go	23:00	40' $R/$D_/events.log && ! grep -q pause_limit $R/$D_/events.log"
check "уведомления выключены по умолчанию / notifications are off by default" "! grep -q 'cmd notification' $R/calls.log 2>/dev/null"

echo "10. Журнал приложений — только по желанию / app log is opt-in"
cat > $SC/apps <<EOF
$head_sleep
[ \$n = 2 ] && { echo "com.b 10101 0 /data" >> \$R/data/system/packages.list; touch -d "2030-01-01 00:00:00" \$R/data/system/packages.list; }
[ \$n = 4 ] && touch \$R/data/adb/modules/davinci-control/disable
exit 0
EOF
mkroot $SC/apps; run_daemon
check "по умолчанию приложения не записываются / off by default" "! grep -q app_inst $R/$D_/events.log"
mkroot $SC/apps; echo APP_LOG=1 > $R/$D_/config; run_daemon
check "включено — установка записана / on: install logged" "grep -q 'app_inst	com.b' $R/$D_/events.log"

echo "11. Испорченные настройки и страховка / broken settings and the failsafe"
mkroot $SC/care; printf 'CHARGE_LIMIT=abc\nHOT_PAUSE=999\nFULL_BY=29:99\nSKIN=x\nCC_SMART=7\nLITTLE_MAX=\n' > $R/$D_/config; run_daemon
check "служба работает со значениями по умолчанию / service runs on defaults" "grep -q 't=415 lvl=4' $R/trace && grep -q 'pause_hot' $R/$D_/events.log && ! grep -qi 'arithmetic\|syntax' $R/daemon.out"
J=$(tune json)
check "панель видит значения по умолчанию / panel sees defaults" "echo '$J' | python3 -c 'import json,sys; c=json.load(sys.stdin)[\"conf\"]; assert (c[\"limit\"],c[\"hot\"],c[\"fullBy\"],c[\"littleMax\"])==(80,42,\"\",1612800), c'"
echo 9 > $R/sys/class/thermal/cooling_device5/cur_state; echo 0 > $R/sys/class/power_supply/battery/battery_charging_enabled; echo 1 > $R/sys/class/power_supply/battery/input_suspend
(PATH=$R/bin R=$R MODDIR=$M $BBX ash -c ". $M/common.sh; failsafe")
check "страховка: зарядка включена, ток без ограничения / failsafe: charging on, no current limit" "[ \$(cat $R/sys/class/thermal/cooling_device5/cur_state) = 0 ] && [ \$(cat $R/sys/class/power_supply/battery/battery_charging_enabled) = 1 ] && [ \$(cat $R/sys/class/power_supply/battery/input_suspend) = 0 ]"
check "служба сдаётся только после страховки / the supervisor runs the failsafe before giving up" "grep -q 'failsafe; ev daemon_giveup' $M/service.sh"

echo "12. Журнал текстом на двух языках / log rendered in two languages"
T1=$(logtxt | head -n 3)
check "русский / Russian" "echo \"\$T1\" | grep -q 'Служба запущена'"
echo en-US > $R/locale; T2=$(logtxt | head -n 3)
check "английский / English" "echo \"\$T2\" | grep -q 'Service started'"

echo
[ $FAILS = 0 ] && echo "daemon: OK" || { echo "daemon: $FAILS FAILED"; exit 1; }
