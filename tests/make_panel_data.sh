#!/bin/bash
# Данные для проверки панели: короткий прогон службы на стенде → tests/out/json.json и strings.json
# Panel test data: a short service run on the bench → tests/out/json.json and strings.json
. "$(dirname "$0")/lib.sh"
mkdir -p "$ROOT/tests/out"
SC=$(mktemp -d "${TMPDIR:-/tmp}/dcsc.XXXXXX"); CLEAN="$CLEAN $SC"
cat > $SC/s <<'S'
#!/bin/bash
R=@R@; B=$R/sys/class/power_supply/battery
n=$(cat $R/step 2>/dev/null || echo 0); n=$((n+1)); echo $n > $R/step
echo $(( $(cat $R/now) + 300 )) > $R/now
echo $((50 + n)) > $B/capacity
T=(300 330 360 400 425 441 443 438 430)
[ $n -le 9 ] && echo ${T[$((n-1))]} > $B/temp
[ $n = 12 ] && touch $R/data/adb/modules/davinci-control/disable
exit 0
S
mkroot $SC/s
D=$R/data/adb/davinci-control; echo "CC_SMART=0" > $D/config; echo "HOT_PAUSE=48" >> $D/config
n0=1700000000
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do echo "$((n0 - i * 86400)),27000,$((3 + i % 3)),$((140 + i * 4)),9$((i % 9)),$((i * 3)),$((20 + i * 3)),2" ; done | sort -n > $D/drain.csv
for i in 3 2 1; do echo "$((n0 - i * 86400 - 7200)),$((n0 - i * 86400)),$((30 + i)),80,2350,44$i,USB_HVDCP_3,17,fast,$((i * 20)),0" >> $D/sessions.csv; done
for i in $(seq 288 -1 1); do s=$((n0 - i * 300)); c=$(( 80 - (288 - i) / 6 )); [ $c -lt 30 ] && c=30; echo "$s,$c,$((290 + i % 40)),Discharging,-300,on,$([ $((i % 3)) = 0 ] && echo on || echo off),0" >> $D/history.csv; done
run_daemon
echo 0 > $R/step; rm -f $M/disable
sed -i "s/^cc=0 /cc=10 /; s/ reg=0 / reg=1 /; s/ pl=0 / pl=1 /" $D/state 2>/dev/null
echo 10 > $R/sys/class/power_supply/battery/system_temp_level; echo 441 > $R/sys/class/power_supply/battery/temp
echo module > $D/thermal.state
tune json > "$ROOT/tests/out/json.json"; tune strings > "$ROOT/tests/out/strings.json"
python3 -m json.tool "$ROOT/tests/out/json.json" >/dev/null && echo "panel data: OK"
