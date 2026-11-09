#!/system/bin/sh
# Davinci Control: вызывается BusyBox uevent на каждое событие ядра. Нужна только смена «кабель есть/нет» —
# тогда будим службу, чтобы яркость, экономия и сеанс зарядки сработали сразу. Остальное — выход без внешних программ.
# Called by BusyBox uevent for every kernel event; only a cable change wakes the service.
[ "$POWER_SUPPLY_NAME" = usb ] || exit 0
o=${POWER_SUPPLY_ONLINE:-$POWER_SUPPLY_PRESENT}
[ -n "$o" ] || exit 0
d=$R/data/adb/davinci-control
read -r p < $d/uev.online 2>/dev/null
[ "$o" = "$p" ] && exit 0
echo "$o" > $d/uev.online
read -r s < $d/pid 2>/dev/null
[ -n "$s" ] && pkill -P "$s" sleep 2>/dev/null
exit 0
