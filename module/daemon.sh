#!/system/bin/sh
# Davinci Control — фоновая служба: лимит заряда, пауза при нагреве, ток по температуре, удержание ниже 45°,
# частоты, яркость, сеансы зарядки, ночной расход, история. Во сне телефона не будит.
# Davinci Control background service. Never wakes the phone: sleep does not hold a wakelock.
MODDIR=${MODDIR:-${0%/*}}
. "$MODDIR/common.sh"
mkdir -p "$D"
echo $$ > "$D/pid"

BAD=$(rd "$D/bad_switches")
choose() {  # первый доступный и не отбракованный способ остановить зарядку / first usable charge switch
  SW=""
  for s in $SWITCHES; do
    n=${s%%:*}
    case " $BAD " in *" $n "*) continue ;; esac
    [ -f "$B/$n" ] || continue
    r=${s#*:}; SW=$n; ON=${r%%:*}; OFF=${r#*:}; return 0
  done
  return 1
}
set_chg() {  # пишем и перечитываем: не принял — способ отбракован / write, read back, drop switch if rejected
  if [ -n "$SW" ]; then
    if [ "$1" = on ]; then v=$ON; else v=$OFF; fi
    echo "$v" > "$B/$SW" 2>/dev/null
    if [ "$(rd "$B/$SW")" != "$v" ]; then
      ev sw_bad "$SW" "$v" "$(rd "$B/$SW")"
      BAD="$BAD $SW"; echo "$BAD" > "$D/bad_switches"; choose && ev sw_now "$SW"
      [ -n "$SW" ] && [ "$1" = off ] && echo "$OFF" > "$B/$SW" 2>/dev/null
    fi
  fi
  chg=$1; [ "$1" = off ] && { off_t=$(date +%s); off_c=$cap; }
}
deg() { echo "$(($1 / 10)).$(($1 % 10))"; }

choose
if [ -n "$SW" ]; then ev start "$(version)" "$SW"; else ev start_nosw "$(version)"; fi
load_conf
dt_cache

# Ступень тока: перечитывается каждый круг; ядро не приняло — функция выключается до перезагрузки.
# Current level: re-checked every loop; if the kernel rejects it, the feature is off until reboot.
cc_cur=""; CC_OK=1; [ -f "$CCL" ] || CC_OK=0; cc_ovr=0; cc_q=0
[ "$(rd $DISABLE_THERMAL)" = 1 ] || [ "$(rd $DISABLE_THERMAL)" = Y ] && { CC_OK=0; ev disable_thermal; }
case "$(rd $SKIP_THERMAL)" in 1|Y|y) CC_OK=2; ev skip_thermal ;; esac
cc_set() {  # $1 = ступень / level (0 = без ограничения / none)
  [ $CC_OK = 1 ] || return
  v=$1; [ "$v" -gt $CC_TOP ] && v=$CC_TOP
  cur=$(rd "$CCL")
  # заводская термозащита включена — её ступень не ослабляем / stock thermal on: never weaken its level
  [ "$THERMAL_CHG" = 1 ] && [ "${cur:-0}" -gt "$v" ] && [ "$cur" != "$cc_cur" ] && return
  if [ "$cur" != "$v" ]; then
    [ "$v" = "$cc_cur" ] && [ $cc_ovr = 0 ] && { ev cc_other "$v" "$cur"; cc_ovr=1; }
    echo "$v" > "$CCL" 2>/dev/null
    if [ "$(rd "$CCL")" != "$v" ]; then ev cc_reject "$CCLN" "$v" "$(rd "$CCL")"; CC_OK=0; return; fi
  fi
  [ "$v" = "$cc_cur" ] && return
  [ "$cc_q" = 1 ] && { cc_cur=$v; return; }
  if [ "$v" -gt 0 ]; then ev cc_limit "$v" "$(rd "$CCLMAX")" "$(deg "$t")"
  elif [ -n "$cc_cur" ]; then ev cc_free "$(deg "$t")"; fi
  cc_cur=$v
}

# Кабель: BusyBox uevent будит службу сразу (uev.sh). Нет — проверка по таймеру.
# Cable: BusyBox uevent wakes the service at once (uev.sh); otherwise a timer.
UEV=""; uev_n=0
uev_start() {
  [ -n "$BB" ] && "$BB" --list 2>/dev/null | grep -qx uevent || return 1
  op=$(rd "$D/uev.pid")
  [ -n "$op" ] && grep -q uevent "/proc/$op/cmdline" 2>/dev/null && kill "$op" 2>/dev/null
  rd $U/online > "$D/uev.online"
  "$BB" uevent sh "$MODDIR/uev.sh" </dev/null >/dev/null 2>&1 &
  UEV=$!; echo $UEV > "$D/uev.pid"; uev_n=$((uev_n + 1))
}
uev_stop() { [ -n "$UEV" ] && kill "$UEV" 2>/dev/null; rm -f "$D/uev.pid"; }
stop_all() { set_chg on; cc_set 0; uev_stop; rm -f "$D/pid"; }
trap 'stop_all; exit 0' TERM INT HUP
if uev_start; then ev uev_on; else ev uev_off; fi

# Состояние файлов нагрева / thermal config state: module | stock | mismatch | nomount
th_state() {
  if [ "$THERMAL_CHG" = 1 ]; then echo stock
  elif [ -f "$D/thermal.mismatch" ]; then echo mismatch
  elif [ "$(sha256sum "$R/vendor/etc/thermal-normal.conf" 2>/dev/null | cut -d' ' -f1)" = "$(sha256sum "$MODDIR/thermal/thermal-normal.conf" 2>/dev/null | cut -d' ' -f1)" ]; then echo module
  else echo nomount; fi
}
TH=$(th_state); echo "$TH" > "$D/thermal.state"
case $TH in module) ev thermal_off ;; mismatch) ev thermal_mismatch ;; nomount) ev thermal_nomount ;; esac

# Сеанс зарядки / charging session
s_t0=""
sess_start() { s_t0=$now; s_c0=$cap; s_tmax=$t; s_sum=0; s_n=0; s_pmax=0; s_typ=""; s_on=0; s_all=0; s_jl=0; jl_t0=""; }
sess_charger() {
  u_REAL_TYPE=""; u_VOLTAGE_NOW=0; u_INPUT_CURRENT_NOW=0
  eval "$(sed -n 's/^POWER_SUPPLY_\(REAL_TYPE\|VOLTAGE_NOW\|INPUT_CURRENT_NOW\)=\([A-Za-z0-9_]*\)$/u_\1="\2"/p' $U/uevent 2>/dev/null)"
  case "$u_REAL_TYPE" in ""|Unknown) ;; *) s_typ=$u_REAL_TYPE ;; esac
  p=$(( ${u_VOLTAGE_NOW:-0} / 1000 * (${u_INPUT_CURRENT_NOW:-0} / 1000) / 1000000 ))
  [ $p -gt $s_pmax ] && s_pmax=$p
}
sess_end() {
  [ -n "$s_t0" ] || return; dur=$((now - s_t0)); gain=$((cap - s_c0))
  if [ $dur -ge 300 ] && [ $gain -ge 1 ]; then
    a=0; [ $s_n -gt 0 ] && a=$((s_sum / s_n)); so=0; [ $s_all -gt 0 ] && so=$((s_on * 100 / s_all))
    # начало,конец,с%,до%,ср.мА,макс.темп×10,блок,макс.Вт,режим,экран вкл %,запаздывание JEITA с
    echo "$s_t0,$now,$s_c0,$cap,$a,$s_tmax,${s_typ:-?},$s_pmax,$([ "$CC_SMART" = 1 ] && echo care || echo fast),$so,$s_jl" >> "$SESS"
    ev sess "$s_c0" "$cap" "$((dur / 60))"
  fi
  s_t0=""
}
# Ночной расход: тренд по неделям и предупреждение / overnight drain: weekly trend and alert
drain_check() {
  r=$(awk -F, -v now="$now" '$4 > 0 { age = now - $1; m = $4 * 3600 / $2
      if (age < 7 * 86400) { a += m; na++ } else if (age < 28 * 86400) { b += m; nb++ } }
      END { if (na >= 2 && nb >= 2) { x = a / na; y = b / nb; if (x > y * 1.3 && x - y >= 10) printf "%d %d", x, y } }' "$DRAIN" 2>/dev/null)
  if [ -n "$r" ]; then [ -f "$D/drain.alert" ] || ev drain_alert ${r% *} ${r#* }; echo "$r" > "$D/drain.alert"
  else rm -f "$D/drain.alert"; fi
}

[ -f "$D/pkgs" ] || awk '{ print $1, $2 }' $PKGL 2>/dev/null | sort > "$D/pkgs"
pk_m=$(stat -c %Y $PKGL 2>/dev/null)
cap=$(rd $B/capacity); t=$(rd $B/temp); t=${t:-250}; set_chg on
[ -f $HBM ] && [ "$(rd $HBM | tr -dc 0-9 | cut -c1)" = 1 ] && set_hbm 0
PH=$(ph_edits); last_desc=""
why=""; scr=""; soff_t=""; i=0; last_h=0; last_pl=""; reg=0
while :; do
  if [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]; then stop_all; ev disabled; exit 0; fi
  load_conf
  cap=$(rd $B/capacity); t=$(rd $B/temp); st=$(rd $B/status); cap=${cap:-50}; t=${t:-250}
  now=$(date +%s)

  # Пределы частот: опускаем, если кто-то поднял выше заданного / cap CPU clusters if raised above the limit
  if [ "$LITTLE_MAX" -gt 0 ]; then cur=$(rd $CPU0/scaling_max_freq); [ "${cur:-0}" -gt "$LITTLE_MAX" ] && echo "$LITTLE_MAX" > $CPU0/scaling_max_freq; fi
  if [ "${BIG_MAX:-0}" -gt 0 ]; then cur=$(rd $CPU6/scaling_max_freq); [ "${cur:-0}" -gt "$BIG_MAX" ] && echo "$BIG_MAX" > $CPU6/scaling_max_freq; fi
  [ -f $FFC ] && [ "$(rd $FFC)" != "$USB_FAST" ] && echo "$USB_FAST" > $FFC

  # Зарядка / charging
  if plugged; then
    pl=1
    if [ "$chg" = off ] && [ -n "$SW" ] && [ $((now - off_t)) -ge 20 ]; then
      if [ "$st" = Charging ] || [ "$cap" -ge $((off_c + 2)) ]; then
        ev sw_nostop "$SW" "$st" "$off_c" "$cap"
        echo "$ON" > "$B/$SW"; BAD="$BAD $SW"; echo "$BAD" > "$D/bad_switches"; chg=on
        if choose; then ev sw_now "$SW"; else ev sw_none; fi
      fi
    fi
    if [ -f "$D/full" ]; then want=on; why=""
    elif [ "$chg" = on ]; then
      want=on
      if [ "$CHARGE_LIMIT" -lt 100 ] && [ "$cap" -ge "$CHARGE_LIMIT" ]; then want=off; why=limit
      elif [ "$HOT_PAUSE" -gt 0 ] && [ "$t" -ge $((HOT_PAUSE * 10)) ]; then want=off; why=hot; fi
    else
      want=off
      if [ "$why" = hot ]; then
        # пауза не меньше 2 минут; датчик у разъёма остывает быстро / at least 2 min; the sensor cools fast
        [ $((now - off_t)) -ge 120 ] && { [ "$HOT_PAUSE" -eq 0 ] || [ "$t" -le $((HOT_RESUME * 10)) ]; } && { [ "$CHARGE_LIMIT" -ge 100 ] || [ "$cap" -lt "$CHARGE_LIMIT" ]; } && want=on
      else
        { [ "$CHARGE_LIMIT" -ge 100 ] || [ "$cap" -le "$CHARGE_RESUME" ]; } && want=on
      fi
    fi
    [ -z "$SW" ] && want=on
  else
    pl=0; want=on; why=""; rm -f "$D/full"
  fi
  if [ "$want" != "$chg" ]; then
    set_chg $want
    if [ $want = off ]; then
      if [ "$why" = hot ]; then ev pause_hot "$(deg "$t")" "$HOT_PAUSE" "$cap"; else ev pause_limit "$CHARGE_LIMIT" "$cap"; fi
    elif [ $pl = 1 ]; then ev resume "$cap" "$(deg "$t")"; fi
  fi
  [ "$chg" = on ] && why=""

  reg=0
  if [ $pl = 1 ] && [ "$CC_SMART" = 1 ]; then
    # «Бережно»: ступени по температуре, ослабляем только после остывания ещё на 1°
    # care: levels by temperature; relax only after cooling one more degree
    want_cc=$(cc_for_temp "$t")
    [ -n "$cc_cur" ] && [ "$want_cc" -lt "$cc_cur" ] && want_cc=$(cc_for_temp $((t + 10)))
    cc_set "$want_cc"
  elif [ $pl = 1 ] && [ "$chg" = on ]; then
    # «Быстро»: держим датчик чуть ниже 45°, где ядро режет ток до 1,95 А (JEITA). Ступени 8…12 = 2,7…2,0 А.
    # fast: keep the sensor just below 45 °C where the kernel cuts to 1.95 A (JEITA). Levels 8…12 = 2.7…2.0 A.
    c=${cc_cur:-0}
    if [ "$t" -ge $REG_HI ]; then
      if [ "$t" -ge 450 ]; then want_cc=$CC_TOP; elif [ "$c" -lt $REG_MIN ]; then want_cc=$REG_MIN; else want_cc=$((c + 1)); fi
    elif [ "$t" -lt $REG_LO ]; then
      if [ "$c" -gt $REG_MIN ]; then want_cc=$((c - 1)); else want_cc=0; fi
    else want_cc=$c; fi
    cc_q=1; cc_set "$want_cc"; cc_q=0
    [ "${cc_cur:-0}" -gt 0 ] && reg=1
    if [ "$c" = 0 ] && [ $reg = 1 ]; then ev hold_on "$cc_cur" "$(deg "$t")"
    elif [ "$c" -gt 0 ] && [ $reg = 0 ]; then ev hold_off "$(deg "$t")"; fi
  else
    cc_set 0
  fi

  bl=$(backlight); if [ "${bl:-1}" -gt 0 ]; then s=on; else s=off; fi
  if [ $pl = 1 ]; then
    [ -n "$s_t0" ] || sess_start
    [ "$t" -gt "$s_tmax" ] && s_tmax=$t
    sess_charger
    if [ "$st" = Charging ]; then
      I=$(rd $B/current_now); I=${I#-}; I=$((${I:-0} / 1000)); s_sum=$((s_sum + I)); s_n=$((s_n + 1))
      s_all=$((s_all + 1)); [ $s = on ] && s_on=$((s_on + 1))
      # Проверка JEITA: выше 45° ядро должно снизить ток до 1,95 А / JEITA check above 45 °C
      if [ "$t" -ge 451 ] && [ $I -gt 2100 ]; then [ -n "$jl_t0" ] || jl_t0=$now
      elif [ -n "$jl_t0" ]; then l=$((now - jl_t0)); jl_t0=""; [ $l -ge 60 ] && { ev jeita_lag "$l"; [ $l -gt $s_jl ] && s_jl=$l; }; fi
    fi
  else
    sess_end
  fi
  [ -n "$UEV" ] && ! kill -0 "$UEV" 2>/dev/null && { if [ $uev_n -lt 5 ]; then uev_start && ev uev_restart; else ev uev_fail; UEV=""; fi; }

  # Журнал приложений / app install log
  m=$(stat -c %Y $PKGL 2>/dev/null)
  if [ -n "$m" ] && [ "$m" != "$pk_m" ]; then
    pk_m=$m; awk '{ print $1, $2 }' $PKGL 2>/dev/null | sort > "$D/pkgs.new"
    if [ -s "$D/pkgs.new" ]; then
      awk 'NR == FNR { o[$1] = $2; next } { n[$1] = $2 }
           END { for (p in o) if (!(p in n)) print "app_rem", p; for (p in n) if (!(p in o)) print "app_inst", p; else if (o[p] != n[p]) print "app_re", p }' \
        "$D/pkgs" "$D/pkgs.new" | while read -r act p; do ev "$act" "$p"; done
      mv "$D/pkgs.new" "$D/pkgs"
    fi
  fi
  echo "cc=${cc_cur:-0} ccok=$CC_OK reg=$reg chg=$chg why=$why sw=$SW pl=$pl bad=$(echo $BAD | tr ' ' ',') th=$TH" > "$D/state"

  # Статус в списке модулей / status line in the module list
  pr=""
  [ "$PH" != 3 ] && [ "$PH" != "-" ] && pr="$pr, $(t desc_ph "$PH")"
  [ -z "$SW" ] && pr="$pr, $(t desc_nosw)"
  [ $CC_OK = 2 ] && pr="$pr, $(t desc_skip)"
  if [ -z "$pr" ]; then dsc=$(t desc_ok); else dsc=$(t desc_bad "${pr#, }"); fi
  [ "$dsc" != "$last_desc" ] && { sed -i "s|^description=.*|description=$dsc|" "$MODDIR/module.prop"; last_desc=$dsc; }

  # Яркость и экономия при смене «кабель есть/нет» / brightness and saver on plug change
  if [ "$pl" != "$last_pl" ]; then
    if [ $pl = 1 ]; then
      [ "$BRIGHT_CHARGE" = 1 ] && { if bright_max; then ev bright_max; else ev bright_fail; fi; }; last_bm=$now
    elif [ -n "$last_pl" ]; then
      [ "$AUTO_BATT" = 1 ] && { if bright_auto; then ev bright_auto; else ev bright_fail; fi; }
      [ "$SAVER_BATT" = 1 ] && { saver_on; if [ "$(saver_get)" = 1 ]; then ev saver_on; else ev saver_fail; fi; }
    fi
    last_pl=$pl
  elif [ $pl = 1 ] && [ "$BRIGHT_CHARGE" = 1 ] && [ $s = on ]; then
    bm=$(backlight_max)
    [ -n "$bm" ] && [ "${bl:-0}" -lt "$bm" ] && [ $((now - ${last_bm:-0})) -ge 120 ] && { bright_max || ev bright_fail; last_bm=$now; }
  fi

  # Ночной расход: экран выключен дольше 30 мин без кабеля / overnight drain: screen off > 30 min, unplugged
  [ $pl = 1 ] && pd=1
  if [ "$s" != "$scr" ]; then
    if [ $s = off ]; then
      soff_t=$now; soff_c=$cap; soff_m=$(mono_s); soff_mob=$(net_rx 'rmnet_data*'); soff_wl=$(net_rx 'wlan*'); soff_cc=$(rd $B/charge_counter); pd=$pl
    elif [ -n "$soff_t" ] && [ "$scr" = off ]; then
      dt=$((now - soff_t)); dm=$(( $(mono_s) - soff_m ))
      if [ $dt -ge 1800 ] && [ "$pd" = 0 ] && [ "$cap" -le "$soff_c" ]; then
        cc1=$(rd $B/charge_counter); mah=0; [ -n "$soff_cc" ] && [ -n "$cc1" ] && mah=$(( (soff_cc - cc1) / 1000 )); [ $mah -lt 0 ] && mah=0
        deep=$((100 - dm * 100 / dt)); [ $deep -lt 0 ] && deep=0
        mob=$(( $(net_rx 'rmnet_data*') - soff_mob )); wl=$(( $(net_rx 'wlan*') - soff_wl ))
        share=-1; [ $((mob + wl)) -gt 1048576 ] && share=$((mob * 100 / (mob + wl)))
        # конец,длит.с,−%,мАч,глуб.сон %,моб. МБ,доля моб. %,SIM
        echo "$now,$dt,$((soff_c - cap)),$mah,$deep,$((mob / 1048576)),$share,$(sims)" >> "$DRAIN"
        drain_check
      fi
    fi
    [ $s = on ] && [ "$pl" = 0 ] && [ "$SAVER_BATT" = 1 ] && [ "$(saver_get)" != 1 ] && { saver_on; ev saver_again; }
    scr=$s; last_h=0
  fi

  # История раз в 5 минут / history every 5 minutes: время,заряд,темп×10,статус,ток мА,зарядка,экран,кабель
  if [ $((now - last_h)) -ge 300 ]; then
    I=$(rd $B/current_now); echo "$now,$cap,$t,$st,$(( ${I:-0} / 1000 )),$chg,$s,$pl" >> "$HIST"; last_h=$now
  fi

  i=$((i + 1)); [ $((i % 60)) = 0 ] && { trim "$LOG" 400; trim "$DRAIN" 120; trim "$HIST" 900; trim "$SESS" 60; }
  # SLEEP_CMD — только для тестового стенда / test bench hook only
  if [ $reg = 1 ]; then ${SLEEP_CMD:-sleep} 15; elif [ $pl = 1 ]; then ${SLEEP_CMD:-sleep} 30; else ${SLEEP_CMD:-sleep} 60; fi
done
