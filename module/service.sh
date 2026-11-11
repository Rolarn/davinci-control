#!/system/bin/sh
# Davinci Control: после загрузки — настройки по умолчанию и запуск службы под присмотром (упала — через 10 с снова).
# After boot: default settings and a supervised service (restarted 10 s after a crash).
MODDIR=${0%/*}
(
  . "$MODDIR/common.sh"
  mkdir -p "$D"; chmod 700 "$D"
  write_default_conf
  sh -c 'echo $PPID' > "$D/sup.pid"
  # «restart» — перезапуск из панели: без ожидания загрузки / restart from the panel: no boot wait
  if [ "$1" != restart ]; then
    rm -f "$D/dt.tables"
    until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done
    sleep 20
    ev boot "$(version)" "$(ph_edits)"
  fi
  n=0
  while :; do
    sh "$MODDIR/daemon.sh" >/dev/null 2>&1 </dev/null
    { [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]; } && break
    n=$((n + 1)); ev daemon_restart "$n"
    # страховка: служба не поднимается — зарядку включить, ограничение тока снять
    # failsafe: the service will not come back — turn charging on and lift the current limit
    [ $n -ge 20 ] && { failsafe; ev daemon_giveup; break; }
    sleep 10
  done
) &
