#!/system/bin/sh
# Davinci Control — фоновая служба: лимит заряда, зарядка к времени, пауза при нагреве, ток по температуре,
# удержание ниже 45°, частоты, яркость, сеансы зарядки, расход во сне, история. Телефон во сне не будит.
# Davinci Control background service: charge limit, charge-by-time, heat pause, current by temperature,
# hold below 45 °C, CPU limits, brightness, sessions, sleep drain, history. Never wakes the phone.
MODDIR=${MODDIR:-${0%/*}}
. "$MODDIR/common.sh"
mkdir -p "$D"
echo $$ > "$D/pid"

# ---------- способ остановить зарядку / charge switch ----------
BAD=$(rd "$D/bad_switches")
choose() {  # первый доступный и не отбракованный / first usable one
  SW=""
  for s in $SWITCHES; do
    n=${s%%:*}
    case " $BAD " in *" $n "*) continue ;; esac
    [ -f "$B/$n" ] || continue
    r=${s#*:}; SW=$n; ON=${r%%:*}; OFF=${r#*:}; return 0
  done
  return 1
}
drop_sw() { BAD="$BAD $SW"; put "$D/bad_switches" "$BAD"; }
set_chg() {  # пишем и перечитываем: не принял — способ отбракован / write, read back, drop if rejected
  if [ -n "$SW" ]; then
    if [ "$1" = on ]; then v=$ON; else v=$OFF; fi
    echo "$v" > "$B/$SW" 2>/dev/null
    rdv got "$B/$SW"
    if [ "$got" != "$v" ]; then
      ev sw_bad "$SW" "$v" "$got"
      drop_sw; choose && ev sw_now "$SW"
      [ -n "$SW" ] && [ "$1" = off ] && echo "$OFF" > "$B/$SW" 2>/dev/null
    fi
  fi
  chg=$1; [ "$1" = off ] && { off_t=$now; off_c=$cap; }
  return 0
}
deg() { echo "$(($1 / 10)).$(($1 % 10))"; }

now=$(date +%s)
choose
if [ -n "$SW" ]; then ev start "$(version)" "$SW"; else ev start_nosw "$(version)"; fi
load_conf
dt_cache

# ---------- ступень тока / current level ----------
# Перечитывается каждый круг; ядро не приняло — функция выключается до перезагрузки.
# Re-checked every loop; if the kernel rejects it, the feature is off until reboot.
cc_cur=""; CC_OK=1; [ -f "$CCL" ] || CC_OK=0; cc_ovr=0; cc_q=0
case "$(rd $DISABLE_THERMAL)" in 1|Y|y) CC_OK=0; ev disable_thermal ;; esac
case "$(rd $SKIP_THERMAL)" in 1|Y|y) CC_OK=2; ev skip_thermal ;; esac
cc_set() {  # $1 = ступень / level (0 = без ограничения / none)
  [ $CC_OK = 1 ] || return 0
  v=$1; [ "$v" -gt $CC_CAP ] && v=$CC_CAP
  rdv cur "$CCL"
  # заводская термозащита включена — её ступень не ослабляем / stock thermal on: never weaken its level
  [ "$THERMAL_CHG" = 1 ] && [ "${cur:-0}" -gt "$v" ] && [ "$cur" != "$cc_cur" ] && return 0
  if [ "$cur" != "$v" ]; then
    [ "$v" = "$cc_cur" ] && [ $cc_ovr = 0 ] && { ev cc_other "$v" "$cur"; cc_ovr=1; }
    echo "$v" > "$CCL" 2>/dev/null
    rdv got "$CCL"
    if [ "$got" != "$v" ]; then ev cc_reject "$CCLN" "$v" "$got"; CC_OK=0; return 0; fi
  fi
  [ "$v" = "$cc_cur" ] && return 0
  [ "$cc_q" = 1 ] && { cc_cur=$v; return 0; }
  if [ "$v" -gt 0 ]; then ev cc_limit "$v" "$(rd "$CCLMAX")" "$(deg "$t")"
  elif [ -n "$cc_cur" ]; then ev cc_free "$(deg "$t")"; fi
  cc_cur=$v
}
care_level() {  # «Бережно»: °C×10 → ступень / care: temperature → level
  if [ "$1" -ge 450 ]; then echo $L3; elif [ "$1" -ge 430 ]; then echo $L2; elif [ "$1" -ge 410 ]; then echo $L1; else echo 0; fi
}

# ---------- кабель / cable ----------
# BusyBox uevent запускает uev.sh на события ядра; тот будит службу при смене «кабель есть/нет».
# Вывод uevent в канал буферизуется, поэтому именно запуск программы, а не чтение потока.
# BusyBox uevent runs uev.sh on kernel events; it wakes the service on a cable change.
UEV=""; uev_n=0
uev_start() {
  [ -n "$BB" ] && "$BB" --list 2>/dev/null | grep -qx uevent || return 1
  rdv op "$D/uev.pid"
  [ -n "$op" ] && grep -q uevent "/proc/$op/cmdline" 2>/dev/null && kill "$op" 2>/dev/null
  rd $U/online > "$D/uev.online"
  "$BB" uevent sh "$MODDIR/uev.sh" </dev/null >/dev/null 2>&1 &
  UEV=$!; echo $UEV > "$D/uev.pid"; uev_n=$((uev_n + 1))
}
uev_stop() { [ -n "$UEV" ] && kill "$UEV" 2>/dev/null; rm -f "$D/uev.pid"; }
stop_all() { sess_save; failsafe; uev_stop; rm -f "$D/pid"; }
trap 'stop_all; exit 0' TERM INT HUP
if uev_start; then ev uev_on; else ev uev_off; fi

# ---------- файлы нагрева / thermal configs: module | stock | mismatch | nomount ----------
th_state() {
  if [ "$THERMAL_CHG" = 1 ]; then echo stock
  elif [ -f "$D/thermal.mismatch" ]; then echo mismatch
  elif [ "$(sha256sum "$R/vendor/etc/thermal-normal.conf" 2>/dev/null | cut -d' ' -f1)" = "$(sha256sum "$MODDIR/thermal/thermal-normal.conf" 2>/dev/null | cut -d' ' -f1)" ]; then echo module
  else echo nomount; fi
}
TH=$(th_state); put "$D/thermal.state" "$TH"
case $TH in module) ev thermal_off ;; mismatch) ev thermal_mismatch ;; nomount) ev thermal_nomount ;; esac

# ---------- сеанс зарядки / charging session ----------
# Состояние сеанса лежит в файле: перезагрузка или перезапуск службы его не теряют.
# The session state lives in a file: a reboot or a service restart does not lose it.
s_t0=""
sess_start() { s_t0=$now; s_c0=$cap; s_tmax=$t; s_sum=0; s_n=0; s_pmax=0; s_typ=""; s_on=0; s_all=0; s_jl=0; jl_t0=""; fb_on=0; fb_for=""; fb_n=0; }
sess_save() {
  [ -n "$s_t0" ] || return 0
  put "$D/session" "s_t0=$s_t0; s_c0=$s_c0; s_tmax=$s_tmax; s_sum=$s_sum; s_n=$s_n; s_pmax=$s_pmax; s_typ=$s_typ; s_on=$s_on; s_all=$s_all; s_jl=$s_jl; s_last=$now; s_cap=$cap; fb_on=$fb_on; fb_for=$fb_for; fb_n=$fb_n"
}
sess_charger() {
  rdv ty $U/real_type; rdv uv $U/voltage_now; rdv ui $U/input_current_now
  case "$ty" in ""|Unknown|*[!A-Za-z0-9_]*) ;; *) s_typ=$ty ;; esac
  case "$uv$ui" in ''|*[!0-9]*) return 0 ;; esac
  p=$(( uv / 1000 * (ui / 1000) / 1000000 )); [ $p -gt $s_pmax ] && s_pmax=$p
  return 0
}
sess_end() {  # $1 = время конца, $2 = заряд в конце / end time, end charge
  [ -n "$s_t0" ] || return 0
  dur=$(($1 - s_t0)); gain=$(($2 - s_c0))
  if [ $dur -ge 300 ] && [ $gain -ge 1 ]; then
    a=0; [ "$s_n" -gt 0 ] && a=$((s_sum / s_n)); so=0; [ "$s_all" -gt 0 ] && so=$((s_on * 100 / s_all))
    if [ "$CC_SMART" = 1 ]; then md=care; else md=fast; fi
    # начало,конец,с%,до%,ср.мА,макс.темп×10,блок,макс.Вт,режим,экран вкл %,задержка JEITA с
    echo "$s_t0,$1,$s_c0,$2,$a,$s_tmax,${s_typ:-?},$s_pmax,$md,$so,$s_jl" >> "$SESS"
    ev sess "$s_c0" "$2" "$((dur / 60))"
  fi
  s_t0=""; rm -f "$D/session"
}

# ---------- расход во сне: тренд и предупреждение / sleep drain: trend and alert ----------
drain_check() {
  r=$(awk -F, -v now="$now" '$4 > 0 && $2 > 0 { age = now - $1; m = $4 * 3600 / $2
      if (age < 7 * 86400) { a += m; na++ } else if (age < 28 * 86400) { b += m; nb++ } }
      END { if (na >= 2 && nb >= 2) { x = a / na; y = b / nb; if (x > y * 1.3 && x - y >= 10) printf "%d %d", x, y } }' "$DRAIN" 2>/dev/null)
  if [ -n "$r" ]; then
    [ -f "$D/drain.alert" ] || { ev drain_alert ${r% *} ${r#* }; notify drain "$(t n_title)" "$(t drain_alert ${r% *} ${r#* })"; }
    put "$D/drain.alert" "$r"
  else rm -f "$D/drain.alert"; fi
}

# ---------- зарядка к времени / charge by time ----------
# Держим лимит, а к заданному часу дозаряжаем до 100%. Нужное время — по мощности блока, с запасом.
# Hold the limit and top up to 100% by the set time. The lead time depends on charger power, with a margin.
fb_check() {  # → fb=1, если пора дозаряжать / fb=1 when it is time to top up
  fb=0
  [ -n "$FULL_BY" ] && [ "$CHARGE_LIMIT" -lt 100 ] || return 0
  [ "$fb_on" = 1 ] && [ "$fb_for" = "$FULL_BY" ] && { fb=1; return 0; }
  fb_on=0
  hm=$(date +%H:%M); h=${hm%%:*}; m=${hm#*:}; th=${FULL_BY%%:*}; tm=${FULL_BY#*:}
  left=$(( ((${th#0} * 60 + ${tm#0}) - (${h#0} * 60 + ${m#0}) + 1440) % 1440 ))
  if [ "${s_pmax:-0}" -ge 15 ]; then per=15; else per=30; fi        # десятые доли минуты на 1% / tenths of a minute per 1%
  need=$(( (100 - cap) * per / 10 + 10 ))
  [ $left -le $need ] && { fb=1; fb_on=1; fb_for=$FULL_BY; fb_n=0; ev fullby_go "$FULL_BY" "$cap"; }
  return 0
}

[ -f "$D/pkgs" ] || awk '{ print $1, $2 }' $PKGL 2>/dev/null | sort > "$D/pkgs"
pk_m=$(stat -c %Y $PKGL 2>/dev/null)
rdv cap $B/capacity; rdv t $B/temp; cap=${cap:-50}; t=${t:-250}; set_chg on
PH=$(ph_edits); desc_key=""; fb_on=0; fb_for=""; fb_n=0
why=""; scr=""; soff_t=""; i=0; last_h=0; last_pl=""; reg=0; tbl=""; L1=4; L2=8; L3=12
# Сеанс, прерванный перезагрузкой: продолжаем, если кабель на месте, иначе закрываем по последней записи.
# A session cut by a reboot: continue if the cable is still in, otherwise close it at the last record.
if [ -f "$D/session" ]; then
  . "$D/session"
  if plugged; then jl_t0=""; else sess_end "${s_last:-$now}" "${s_cap:-$cap}"; fi
fi

while :; do
  if [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]; then stop_all; ev disabled; exit 0; fi
  load_conf
  rdv cap $B/capacity; rdv t $B/temp; rdv st $B/status; cap=${cap:-50}; t=${t:-250}
  now=$(date +%s)

  # Пределы частот: опускаем, если кто-то поднял выше заданного / cap CPU clusters if raised above the limit
  if [ "$LITTLE_MAX" -gt 0 ]; then rdv cur $CPU0/scaling_max_freq; [ "${cur:-0}" -gt "$LITTLE_MAX" ] && echo "$LITTLE_MAX" > $CPU0/scaling_max_freq; fi
  if [ "$BIG_MAX" -gt 0 ]; then rdv cur $CPU6/scaling_max_freq; [ "${cur:-0}" -gt "$BIG_MAX" ] && echo "$BIG_MAX" > $CPU6/scaling_max_freq; fi
  if [ -f $FFC ]; then rdv cur $FFC; [ "$cur" != "$USB_FAST" ] && echo "$USB_FAST" > $FFC; fi

  # ----- зарядка / charging -----
  if plugged; then
    pl=1
    [ -n "$s_t0" ] || sess_start
    sess_charger
    fb_check; lim=$CHARGE_LIMIT; [ $fb = 1 ] && lim=100
    [ $fb = 1 ] && [ "$fb_n" = 0 ] && [ "$cap" -ge 100 ] && { fb_n=1; notify chg "$(t n_title)" "$(t n_fullby)"; }
    if [ "$chg" = off ] && [ -n "$SW" ] && [ $((now - off_t)) -ge 20 ]; then
      if [ "$st" = Charging ] || [ "$cap" -ge $((off_c + 2)) ]; then
        ev sw_nostop "$SW" "$st" "$off_c" "$cap"
        echo "$ON" > "$B/$SW"; drop_sw; chg=on
        if choose; then ev sw_now "$SW"; else ev sw_none; fi
      fi
    fi
    if [ -f "$D/full" ]; then want=on; why=""
    elif [ "$chg" = on ]; then
      want=on
      if [ "$lim" -lt 100 ] && [ "$cap" -ge "$lim" ]; then want=off; why=limit
      elif [ "$HOT_PAUSE" -gt 0 ] && [ "$t" -ge $((HOT_PAUSE * 10)) ]; then want=off; why=hot; fi
    else
      want=off
      if [ "$why" = hot ]; then
        # пауза не меньше 2 минут; датчик у разъёма остывает быстро / at least 2 min; the sensor cools fast
        [ $((now - off_t)) -ge 120 ] && { [ "$HOT_PAUSE" -eq 0 ] || [ "$t" -le $((HOT_RESUME * 10)) ]; } && { [ "$lim" -ge 100 ] || [ "$cap" -lt "$lim" ]; } && want=on
      else
        { [ "$lim" -ge 100 ] || [ "$cap" -le "$CHARGE_RESUME" ]; } && want=on
      fi
    fi
    [ -z "$SW" ] && want=on
  else
    pl=0; want=on; why=""; fb=0; rm -f "$D/full"
  fi
  if [ "$want" != "$chg" ]; then
    set_chg $want
    if [ $want = off ]; then
      if [ "$why" = hot ]; then ev pause_hot "$(deg "$t")" "$HOT_PAUSE" "$cap"; notify chg "$(t n_title)" "$(t pause_hot "$(deg "$t")" "$HOT_PAUSE" "$cap")"
      else ev pause_limit "$lim" "$cap"; notify chg "$(t n_title)" "$(t pause_limit "$lim" "$cap")"; fi
    elif [ $pl = 1 ]; then ev resume "$cap" "$(deg "$t")"; fi
  fi
  [ "$chg" = on ] && why=""

  # ----- ступень тока / current level -----
  reg=0
  if [ $pl = 1 ]; then
    k=$(cc_table); [ "$k" != "$tbl" ] && { tbl=$k; cc_plan "$k"; }
  fi
  if [ $pl = 1 ] && [ "$CC_SMART" = 1 ]; then
    # «Бережно»: ступени по температуре, ослабляем только после остывания ещё на 1°
    # care: levels by temperature; relax only after cooling one more degree
    want_cc=$(care_level "$t")
    [ -n "$cc_cur" ] && [ "$want_cc" -lt "$cc_cur" ] && want_cc=$(care_level $((t + 10)))
    cc_set "$want_cc"
  elif [ $pl = 1 ] && [ "$chg" = on ]; then
    # «Быстро»: держим датчик чуть ниже 45°, где ядро режет ток до 1,95 А (JEITA).
    # Ступени L2…L3 — примерно 2,7…2,0 А по действующей таблице ядра.
    # fast: keep the sensor just below 45 °C where the kernel cuts to 1.95 A (JEITA).
    # Levels L2…L3 are about 2.7…2.0 A in the kernel table in effect.
    c=${cc_cur:-0}
    if [ "$t" -ge $REG_HI ]; then
      if [ "$t" -ge 450 ]; then want_cc=$L3; elif [ "$c" -lt $L2 ]; then want_cc=$L2; elif [ "$c" -lt $L3 ]; then want_cc=$((c + 1)); else want_cc=$L3; fi
    elif [ "$t" -lt $REG_LO ]; then
      if [ "$c" -gt $L2 ]; then want_cc=$((c - 1)); else want_cc=0; fi
    else want_cc=$c; fi
    cc_q=1; cc_set "$want_cc"; cc_q=0
    [ "${cc_cur:-0}" -gt 0 ] && reg=1
    if [ "$c" = 0 ] && [ $reg = 1 ]; then ev hold_on "$cc_cur" "$(deg "$t")"
    elif [ "$c" -gt 0 ] && [ $reg = 0 ]; then ev hold_off "$(deg "$t")"; fi
  else
    cc_set 0
  fi

  # ----- сеанс / session -----
  for f in $R/sys/class/backlight/*/brightness; do rdv bl "$f"; break; done
  if [ "${bl:-1}" -gt 0 ]; then s=on; else s=off; fi
  if [ $pl = 1 ]; then
    [ "$t" -gt "$s_tmax" ] && s_tmax=$t
    if [ "$st" = Charging ]; then
      rdv I $B/current_now; I=${I#-}; I=$((${I:-0} / 1000)); s_sum=$((s_sum + I)); s_n=$((s_n + 1))
      s_all=$((s_all + 1)); [ $s = on ] && s_on=$((s_on + 1))
      # Проверка JEITA: выше 45° ядро должно снизить ток до 1,95 А / JEITA check above 45 °C
      if [ "$t" -ge 451 ] && [ $I -gt 2100 ]; then [ -n "$jl_t0" ] || jl_t0=$now
      elif [ -n "$jl_t0" ]; then l=$((now - jl_t0)); jl_t0=""; [ $l -ge 60 ] && { ev jeita_lag "$l"; [ $l -gt $s_jl ] && s_jl=$l; }; fi
    fi
    sess_save
  elif [ -n "$s_t0" ]; then
    sess_end "$now" "$cap"
  fi
  [ -n "$UEV" ] && ! kill -0 "$UEV" 2>/dev/null && { if [ $uev_n -lt 5 ]; then uev_start && ev uev_restart; else ev uev_fail; UEV=""; fi; }

  # ----- журнал приложений (по желанию) / app install log (optional) -----
  if [ "$APP_LOG" = 1 ]; then
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
  fi
  put "$D/state" "cc=${cc_cur:-0} ccok=$CC_OK reg=$reg chg=$chg why=$why sw=$SW pl=$pl bad=$(echo $BAD | tr ' ' ',') th=$TH fb=$fb tbl=$tbl"

  # ----- статус в списке модулей (только при изменении) / module list status (on change only) -----
  k="$PH|$SW|$CC_OK|$UI_LANG"
  if [ "$k" != "$desc_key" ]; then
    desc_key=$k; pr=""
    [ "$PH" != 3 ] && [ "$PH" != "-" ] && pr="$pr, $(t desc_ph "$PH")"
    [ -z "$SW" ] && pr="$pr, $(t desc_nosw)"
    [ $CC_OK = 2 ] && pr="$pr, $(t desc_skip)"
    if [ -z "$pr" ]; then dsc=$(t desc_ok); else dsc=$(t desc_bad "${pr#, }"); fi
    sed -i "s|^description=.*|description=$dsc|" "$MODDIR/module.prop"
  fi

  # ----- яркость и экономия при смене «кабель есть/нет» / brightness and saver on plug change -----
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

  # ----- расход во сне: экран выключен дольше 30 мин без кабеля / sleep drain: screen off > 30 min, unplugged -----
  [ $pl = 1 ] && pd=1
  if [ "$s" != "$scr" ]; then
    if [ $s = off ]; then
      soff_t=$now; soff_c=$cap; soff_m=$(mono_s); soff_mob=$(net_rx 'rmnet_data*'); soff_wl=$(net_rx 'wlan*'); rdv soff_cc $B/charge_counter; rdv soff_raw $BMS/capacity_raw; pd=$pl
    elif [ -n "$soff_t" ] && [ "$scr" = off ]; then
      dt=$((now - soff_t)); dm=$(( $(mono_s) - soff_m ))
      if [ $dt -ge 1800 ] && [ "$pd" = 0 ] && [ "$cap" -le "$soff_c" ]; then
        # мАч: по точному счётчику заряда (сотые доли процента), если он есть, иначе по грубому charge_counter
        # mAh: from the precise gauge (hundredths of a percent) when present, otherwise the coarse charge_counter
        rdv cc1 $B/charge_counter; rdv raw1 $BMS/capacity_raw; rdv cfull $B/charge_full; mah=0
        case "$soff_raw$raw1$cfull" in ''|*[!0-9]*) raw1="" ;; esac
        if [ -n "$raw1" ] && [ -n "$soff_raw" ] && [ -n "$cfull" ]; then mah=$(( (soff_raw - raw1) * (cfull / 1000) / 10000 ))
        elif [ -n "$soff_cc" ] && [ -n "$cc1" ]; then mah=$(( (soff_cc - cc1) / 1000 )); fi
        [ $mah -lt 0 ] && mah=0
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

  # ----- история раз в 5 минут: время,заряд,темп×10,статус,ток мА,зарядка,экран,кабель,заряд в сотых долях % -----
  # ----- history every 5 minutes: time,charge,temp×10,status,mA,charging,screen,cable,charge in 0.01% -----
  if [ $((now - last_h)) -ge 300 ]; then
    rdv I $B/current_now; rdv raw $BMS/capacity_raw; case "$raw" in *[!0-9]*) raw="" ;; esac
    echo "$now,$cap,$t,$st,$(( ${I:-0} / 1000 )),$chg,$s,$pl,$raw" >> "$HIST"; last_h=$now
  fi

  i=$((i + 1)); [ $((i % 60)) = 0 ] && { trim "$LOG" 400; trim "$DRAIN" 120; trim "$HIST" 3000; trim "$SESS" 60; }
  # SLEEP_CMD — только для тестового стенда / test bench hook only
  if [ $reg = 1 ]; then ${SLEEP_CMD:-sleep} 15; elif [ $pl = 1 ]; then ${SLEEP_CMD:-sleep} 30; else ${SLEEP_CMD:-sleep} 60; fi
done
