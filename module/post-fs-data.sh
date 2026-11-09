#!/system/bin/sh
# Davinci Control: до подключения модуля решаем, подменять ли файлы нагрева прошивки.
# Подмена — только если пользователь выключил заводское снижение тока и все файлы совпадают с проверенными.
# Before the module is mounted: decide whether to replace the stock thermal configs (only on an exact match).
MODDIR=${0%/*}
. "$MODDIR/common.sh"
load_conf
mkdir -p "$D" "$MODDIR/system/vendor/etc"
rm -f "$D/thermal.mismatch"
use=0
if [ "$THERMAL_CHG" = 0 ]; then
  if thermal_match; then use=1; else touch "$D/thermal.mismatch"; fi
fi
for f in "$MODDIR"/thermal/thermal-*.conf; do
  n=${f##*/}
  if [ $use = 1 ]; then
    cp -f "$f" "$MODDIR/system/vendor/etc/$n"; chmod 644 "$MODDIR/system/vendor/etc/$n"
    chcon u:object_r:vendor_configs_file:s0 "$MODDIR/system/vendor/etc/$n" 2>/dev/null || true
  else
    rm -f "$MODDIR/system/vendor/etc/$n"
  fi
done
