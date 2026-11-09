# Davinci Control: установка. / installer.
# Работает только на Mi 9T / Redmi K20 (davinci). Правит КОПИЮ powerhint.json с самого телефона.
# Runs only on Mi 9T / Redmi K20 (davinci). Edits a COPY of the phone's own powerhint.json.
L=en; case "$(getprop persist.sys.locale)$(getprop ro.product.locale)" in ru*) L=ru ;; esac
say() { if [ $L = ru ]; then ui_print "$1"; else ui_print "$2"; fi; }

case "$(getprop ro.product.device)$(getprop ro.product.vendor.device)" in
  *davinci*) ;;
  *) say "! Это не Mi 9T / Redmi K20 (davinci) — установка отменена" "! Not a Mi 9T / Redmi K20 (davinci) — installation cancelled"; abort ;;
esac
if [ -n "$KSU" ]; then
  say "- KernelSU: поддержка не проверена. Для подмены файлов нужен метамодуль (например, meta-overlayfs)" \
      "- KernelSU: support is untested. Replacing files needs a metamodule (e.g. meta-overlayfs)"
elif [ -n "$APATCH" ]; then
  say "- APatch: поддержка не проверена" "- APatch: support is untested"
elif [ "${MAGISK_VER_CODE:-0}" -lt 24000 ]; then
  say "! Нужен Magisk 24 или новее" "! Magisk 24 or newer is required"; abort
fi

SRC=${PH_SRC:-/vendor/etc/powerhint.json}
DST=$MODPATH/system/vendor/etc/powerhint.json
mkdir -p "$MODPATH/system/vendor/etc"
if [ -f "$SRC" ]; then
  n=$(awk -f "$MODPATH/edit_powerhint.awk" "$SRC" 2>&1 >"$DST")
  if [ "$n" = 3 ]; then
    set_perm "$DST" 0 0 0644 u:object_r:vendor_configs_file:s0
  else
    rm -f "$DST"
    say "- powerhint.json другого формата ($n из 3) — эта часть пропущена" "- powerhint.json has another format ($n of 3) — this part is skipped"
  fi
else
  say "- Нет powerhint.json (MIUI?) — эта часть пропущена" "- No powerhint.json (MIUI?) — this part is skipped"
fi
rm -f "$MODPATH/edit_powerhint.awk"

MODDIR=$MODPATH
. "$MODPATH/common.sh"
if thermal_match; then
  say "- Файлы нагрева прошивки совпали с проверенными" "- Stock thermal configs match the tested ones"
else
  say "- Файлы нагрева прошивки отличаются от проверенных — их модуль не тронет" "- Stock thermal configs differ from the tested ones — the module will leave them alone"
fi
set_perm_recursive "$MODPATH" 0 0 0755 0644
say "- Davinci Control $(version). Перезагрузись, затем кнопка «Действие» — панель" \
    "- Davinci Control $(version). Reboot, then tap Action to open the panel"
