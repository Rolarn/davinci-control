#!/system/bin/sh
# Кнопка «Действие»: открывает панель в WebUI X, KsuWebUI или MMRL; если их нет — текстовый отчёт.
# Action button: opens the panel in WebUI X, KsuWebUI or MMRL; otherwise prints a text report.
MODDIR=${0%/*}
. "$MODDIR/common.sh"
load_conf
ID=davinci-control
pkgs=$(pm list packages 2>/dev/null | sed -n 's/^package://p')
open_wx() {  # WebUI X (пакет бывает с суффиксом .alpha/.beta)
  WX=$(echo "$pkgs" | grep '^com\.dergoogler\.mmrl\.wx' | head -n 1); [ -n "$WX" ] || return 1
  if dumpsys package "$WX" 2>/dev/null | grep -qE "[/.]ui[.]webui[.]WebUIActivity"; then A=com.dergoogler.mmrl.wx.ui.webui.WebUIActivity
  else A=com.dergoogler.mmrl.wx.ui.activity.webui.WebUIActivity; fi
  am start -n "$WX/$A" -e MODULE_ID "$ID" -e MOD_ID "$ID" >/dev/null 2>&1
}
open_ksuwebui() {
  echo "$pkgs" | grep -qx io.github.a13e300.ksuwebui || return 1
  am start -n "io.github.a13e300.ksuwebui/.WebUIActivity" -e id "$ID" >/dev/null 2>&1
}
open_mmrl() {  # MMRL открывает WebUI модуля по ссылке / MMRL opens module WebUI by intent
  M=$(echo "$pkgs" | grep -E '^com\.dergoogler\.mmrl(\.(debug|alpha|beta))?$' | head -n 1); [ -n "$M" ] || return 1
  am start -n "$M/com.dergoogler.mmrl.ui.activity.webui.WebUIActivity" -e MOD_ID "$ID" >/dev/null 2>&1
}
for o in wx ksuwebui mmrl; do
  if open_$o; then
    echo "$(t act_open)"
    # закрыть промежуточный экран Magisk / close the Magisk intermediate screen
    MG=$(echo "$pkgs" | grep -E '^(com\.topjohnwu\.magisk|io\.github\.vvb2060\.magisk)$' | head -n 1)
    [ -n "$MG" ] && nohup sh -c "sleep 1; am force-stop $MG" >/dev/null 2>&1 </dev/null &
    exit 0
  fi
done
sh "$MODDIR/tune.sh" panel
echo
echo "$(t act_nowebui)"
