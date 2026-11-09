#!/system/bin/sh
# Davinci Control — бэкенд панели: JSON, текстовый отчёт, журнал, сохранение логов и команды настроек.
# Davinci Control panel backend: JSON, text report, log, saving logs and setting commands.
MODDIR=${MODDIR:-$R/data/adb/modules/davinci-control}
[ "$(id -u)" = 0 ] || [ -n "$R" ] || exec su -c "sh $MODDIR/tune.sh $*"
# WebUI запускает обычный sh — переходим в BusyBox, как загрузочные скрипты. / run under BusyBox like boot scripts.
if [ -z "$ASH_STANDALONE" ] && [ -z "$R" ]; then
  for b in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
    [ -x $b ] && ASH_STANDALONE=1 exec $b sh "$0" "$@"
  done
fi
. "$MODDIR/common.sh"
load_conf

setc() {  # KEY VALUE
  write_default_conf
  if grep -q "^$1=" "$CONF"; then sed -i "s|^$1=.*|$1=$2|" "$CONF"; else echo "$1=$2" >> "$CONF"; fi
}
num() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; }
bit() { case "$1" in 0|1) return 0 ;; esac; return 1; }
mhz() { echo $(( ${1:-0} / 1000 )); }
STATE=$(rd "$D/state")
stv() { v=${STATE#*"$1"=}; [ "$v" = "$STATE" ] && return; echo "${v%% *}"; }
fail() { t "$@"; exit 1; }

# ---------- текстовый отчёт / text report ----------
report() {
  header report
  echo "uptime: $(awk '{ printf "%d h %d min", $1 / 3600, $1 % 3600 / 60 }' $R/proc/uptime)"
  echo
  echo "-- $(t r_checks)"
  echo "powerhint: $(ph_edits)/3"
  if [ -n "$(daemon_pid)" ]; then echo "$(t r_daemon_ok) (pid $(daemon_pid))"; else t r_daemon_bad; fi
  echo "thermal: $(rd "$D/thermal.state") · disable_thermal=$(rd $DISABLE_THERMAL || echo —) · skip_thermal=$(rd $SKIP_THERMAL || echo —)"
  echo
  echo "-- $(t r_charge)"
  echo "switch: $(stv sw) · bad: $(stv bad | tr ',' ' ')"
  echo "limit: $CHARGE_LIMIT% ($CHARGE_RESUME%) · hot: $HOT_PAUSE° ($HOT_RESUME°) · mode: $([ "$CC_SMART" = 1 ] && echo care || echo fast)"
  echo "state: chg=$(stv chg) why=$(stv why) plugged=$(stv pl) full=$([ -f "$D/full" ] && echo 1 || echo 0)"
  echo "level: ${CCL##*/}=$(rd "$CCL")/$(rd "$CCLMAX") own=$(stv cc) ok=$(stv ccok) hold=$(stv reg)"
  echo "kernel: health=$(sed -n 's/^POWER_SUPPLY_HEALTH=//p' $B/uevent 2>/dev/null) die=$(sed -n 's/^POWER_SUPPLY_DIE_HEALTH=//p' $B/uevent 2>/dev/null)"
  echo "temp °C×10: battery=$(rd $B/temp) pm6150=$(t_pmic) smb1390=$(t_cp) connector=$(t_conn)"
  echo
  echo "-- $(t r_batt)"
  cf=$(rd $B/charge_full); cfd=$(rd $B/charge_full_design)
  [ -n "$cf" ] && [ -n "$cfd" ] && echo "health: $((cf / 1000))/$((cfd / 1000)) mAh ($((cf * 100 / cfd))%) · cycles: $(rd $B/cycle_count)"
  echo "now: $(rd $B/capacity)% $(rd $B/status) · $(rd $B/current_now) µA · $(rd $B/voltage_now) µV"
  echo
  echo "-- CPU / GPU"
  echo "little: $(mhz "$(rd $CPU0/scaling_cur_freq)")/$(mhz "$(rd $CPU0/scaling_max_freq)") MHz (set $(mhz "$LITTLE_MAX")) · big: $(mhz "$(rd $CPU6/scaling_cur_freq)")/$(mhz "$(rd $CPU6/scaling_max_freq)") MHz (set $(mhz "${BIG_MAX:-0}"))"
  echo "gpu: $(( $(rd $K/gpuclk) / 1000000 )) MHz · cpu $(zt cpu-1-0-usr)° · body $(zt quiet_therm)°"
}

# ---------- JSON для панели / JSON for the panel ----------
esc() { sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'; }
jlines() { if [ -f "$1" ]; then tail -n "$2" "$1" | esc | awk 'BEGIN { printf "[" } { printf "%s\"%s\"", (NR > 1 ? "," : ""), $0 } END { printf "]" }'; else printf '[]'; fi; }
jnum() { case "$1" in ''|*[!0-9-]*) printf null ;; *) printf %s "$1" ;; esac; }
jstr() { printf '"%s"' "$(printf %s "$1" | esc)"; }
jdist() { awk -v d="$2" '{ t[NR] = $2; f[NR] = $1; s += $2 } END { printf "["; n = 0; for (i = 1; i <= NR; i++) if (s && t[i] * 1000 / s >= 5) { printf "%s[%d,%.1f]", (n++ ? "," : ""), f[i] / d, t[i] * 100 / s } printf "]" }' "$1"; }
juev() {
  f=$1; shift
  awk -F= -v keys=" $* " 'BEGIN { printf "{" } { k = $1; sub(/^POWER_SUPPLY_/, "", k); if (index(keys, " " k " ")) { v = $2; gsub(/["\\]/, "", v); printf "%s\"%s\":\"%s\"", (n++ ? "," : ""), k, v } } END { printf "}" }' "$f" 2>/dev/null || printf '{}'
}
jarr() { printf '[%s]' "$(echo $1 | tr ' ' ',')"; }
jcommon() {
  [ -n "$(daemon_pid)" ] && dm=true || dm=false
  [ -f "$D/full" ] && full=true || full=false
  [ -n "$(getprop vendor.powerhal.rendering 2>/dev/null)" ] && er=true || er=false
  u=$(rd "$D/uev.pid"); if [ -n "$u" ] && kill -0 "$u" 2>/dev/null; then u=true; else u=false; fi
  printf '"time":%s,"uptime":%s,"daemon":%s,' "$(date +%s)" "$(boot_s)" $dm
  printf '"charge":{"switch":"%s","bad":"%s","state":"%s","why":"%s","plugged":%s,"full":%s,"ffc":%s},' \
    "$(stv sw)" "$(stv bad)" "$(stv chg)" "$(stv why)" "$(jnum "$(stv pl)")" $full "$(jnum "$(rd $FFC)")"
  printf '"batt":{"cap":%s,"status":"%s","temp":%s,"current":%s,"voltage":%s,"counter":%s},' \
    "$(jnum "$(rd $B/capacity)")" "$(rd $B/status)" "$(jnum "$(rd $B/temp)")" "$(jnum "$(rd $B/current_now)")" "$(jnum "$(rd $B/voltage_now)")" "$(jnum "$(rd $B/charge_counter)")"
  printf '"chips":{"pmic":%s,"cp":%s,"conn":%s},' "$(jnum "$(t_pmic)")" "$(jnum "$(t_cp)")" "$(jnum "$(t_conn)")"
  printf '"now":{"er":%s,"gpu":%s,"gpuBusy":%s,"little":%s,"littleMax":%s,"big":%s,"bigMax":%s,"tQuiet":%s,"tCpu":%s},' \
    $er "$(jnum "$(rd $K/gpuclk)")" "$(jnum "$(rd $K/gpu_busy_percentage | tr -dc 0-9)")" "$(jnum "$(rd $CPU0/scaling_cur_freq)")" "$(jnum "$(rd $CPU0/scaling_max_freq)")" \
    "$(jnum "$(rd $CPU6/scaling_cur_freq)")" "$(jnum "$(rd $CPU6/scaling_max_freq)")" "$(jnum "$(zt quiet_therm)")" "$(jnum "$(zt cpu-1-0-usr)")"
  printf '"usb":%s,"bat":%s,' "$(juev $U/uevent REAL_TYPE ONLINE PRESENT VOLTAGE_NOW INPUT_CURRENT_NOW INPUT_CURRENT_SETTLED PD_ACTIVE QUICK_CHARGE_TYPE HVDCP3_TYPE)" \
    "$(juev $B/uevent HEALTH CHARGE_TYPE DIE_HEALTH INPUT_CURRENT_LIMITED VOLTAGE_MAX)"
  printf '"bl":{"raw":%s,"max":%s},' "$(jnum "$(backlight)")" "$(jnum "$(backlight_max)")"
  printf '"cc":{"smart":%s,"lvl":%s,"max":%s,"ok":%s,"own":%s,"uev":%s,"reg":%s},' "${CC_SMART:-1}" "$(jnum "$(rd "$CCL")")" "$(jnum "$(rd "$CCLMAX")")" "$(jnum "$(stv ccok)")" "$(jnum "$(stv cc)")" $u "$(jnum "$(stv reg)")"
  printf '"diag":%s' "$(jstr "$(rd "$D/diag.status")")"
}
jhist() {
  [ -f "$HIST" ] || { printf '[]'; return; }
  awk -F, -v from=$(( $(date +%s) - 86400 )) 'BEGIN { printf "[" } $1 >= from { printf "%s[%s,%s,%s,%s,%d,%d,%d,%d]", (n++ ? "," : ""), $1, $2, $3, $5, ($6 == "off"), ($7 != "off"), ($8 == 1), ($4 == "Charging") } END { printf "]" }' "$HIST"
}
json() {
  m=$(mono_s); b=$(boot_s); ds=null; [ -n "$m" ] && [ "${b:-0}" -gt 0 ] && { ds=$((100 - m * 100 / b)); [ $ds -lt 0 ] && ds=0; }
  printf '{"version":"%s","lang":"%s","skin":"%s",' "$(version)" "$(ui_lang)" "$SKIN"
  printf '"ok":{"powerhint":"%s","thermal":"%s"},' "$(ph_edits)" "$(rd "$D/thermal.state")"
  printf '"conf":{"limit":%s,"resume":%s,"hot":%s,"hotResume":%s,"usbFast":%s,"littleMax":%s,"bigMax":%s,"bright":%s,"autoBatt":%s,"saverBatt":%s,"thermalChg":%s,"drainAlert":%s,"uiLang":"%s"},' \
    "$CHARGE_LIMIT" "$CHARGE_RESUME" "$HOT_PAUSE" "$HOT_RESUME" "$USB_FAST" "$LITTLE_MAX" "${BIG_MAX:-0}" "$BRIGHT_CHARGE" "$AUTO_BATT" "$SAVER_BATT" "$THERMAL_CHG" "$DRAIN_ALERT" "$UI_LANG"
  printf '"full":%s,"design":%s,"cycles":%s,"sleep":%s,"sims":%s,"saver":%s,"brMode":%s,' "$(jnum "$(rd $B/charge_full)")" "$(jnum "$(rd $B/charge_full_design)")" "$(jnum "$(rd $B/cycle_count)")" $ds "$(jnum "$(sims)")" "$(jnum "$(saver_get)")" "$(jnum "$(sget system screen_brightness_mode)")"
  printf '"littleFreqs":%s,"bigFreqs":%s,' "$(jarr "$(rd $CPU0/scaling_available_frequencies)")" "$(jarr "$(rd $CPU6/scaling_available_frequencies)")"
  printf '"dist":{"little":%s,"big":%s,"gpu":%s},' "$(jdist $CPU0/stats/time_in_state 1000)" "$(jdist $CPU6/stats/time_in_state 1000)" \
    "$(awk '/^[* ] *[0-9]+:/ { sub(/^[* ]+/, ""); sub(/:/, ""); print $1, $NF }' $K/devfreq/trans_stat 2>/dev/null | jdist /dev/stdin 1000000)"
  dt_cache 2>/dev/null
  printf '"dt":{"fcc":%s,"dcp":%s,"qc2":%s},' "$(jarr "$(sed -n 's/^fcc=//p' "$D/dt.tables" 2>/dev/null)")" "$(jarr "$(sed -n 's/^dcp=//p' "$D/dt.tables" 2>/dev/null)")" "$(jarr "$(sed -n 's/^qc2=//p' "$D/dt.tables" 2>/dev/null)")"
  printf '"drainAlert":%s,' "$(jarr "$(rd "$D/drain.alert")")"
  printf '"history":%s,"drain":%s,"sessions":%s,"events":%s,' "$(jhist)" "$(jlines "$DRAIN" 60)" "$(jlines "$SESS" 10)" "$(jlines "$LOG" 60)"
  jcommon; printf '}\n'
}
live() { printf '{"live":true,'; jcommon; printf '}\n'; }
# Строки сообщений для панели / message strings for the panel
jstrings() { awk -F'\t' 'BEGIN { printf "{" } NF >= 3 && $1 !~ /^#/ { for (i = 2; i <= 3; i++) { gsub(/\\/, "\\\\", $i); gsub(/"/, "\\\"", $i) } printf "%s\"%s\":[\"%s\",\"%s\"]", (n++ ? "," : ""), $1, $2, $3 } END { printf "}\n" }' "$STR"; }

logs() {
  report
  echo; echo "-- config"; grep -v '^#' "$CONF" 2>/dev/null
  echo; echo "-- $(t r_events)"; render_log "$LOG"
  echo; echo "-- sessions (start,end,from%,to%,avg mA,max temp×10,charger,max W,mode,screen on %,JEITA lag s)"; cat "$SESS" 2>/dev/null
  echo; echo "-- drain (end,seconds,−%,mAh,deep sleep %,mobile MB,mobile share %,SIMs)"; cat "$DRAIN" 2>/dev/null
  echo; echo "-- history (time,%,temp×10,status,mA,charging,screen,cable), last 60"; tail -n 60 "$HIST" 2>/dev/null
}
fname() { echo "$OUT/davinci-control_$(version)_$1_$(date +%Y-%m-%d_%H%M).txt"; }

cmd=$1; shift
case "$cmd" in
  ""|panel) report; echo; echo "-- $(t r_events)"; render_log "$LOG" 10 ;;
  json) json ;;
  live) live ;;
  strings) jstrings ;;
  logs) logs ;;
  savelogs)
    PANEL_HOST=$1; mkdir -p "$OUT"; f=$(fname log)
    logs > "$f" && { ev log_saved "${f#"$R"}"; echo "${f#"$R"}"; } ;;
  diag)
    case "$(rd "$D/diag.status")" in [0-9]*/*)
      [ -n "$(find "$D/diag.status" -mmin -5 2>/dev/null)" ] && { echo busy; exit 0; } ;; esac
    echo "0/12" > "$D/diag.status"
    PANEL_HOST=$1 nohup sh "$MODDIR/diag.sh" >/dev/null 2>&1 &
    echo started ;;
  changelog) cat "$MODDIR/changelog.tsv" ;;
  full)
    mkdir -p "$D"
    if [ "$1" = off ]; then rm -f "$D/full"; ev set_full_off; else touch "$D/full"; ev set_full; fi
    wake_daemon ;;
  limit)
    num "$1" && [ "$1" -ge 50 ] && [ "$1" -le 100 ] || fail e_range 50 100
    setc CHARGE_LIMIT "$1"; setc CHARGE_RESUME $(( $1 - 5 )); wake_daemon; ev set_limit "$1" ;;
  hot)
    num "$1" && { [ "$1" = 0 ] || { [ "$1" -ge 38 ] && [ "$1" -le 50 ]; }; } || fail e_range 38 50
    setc HOT_PAUSE "$1"; setc HOT_RESUME $(( $1 > 0 ? $1 - 4 : 38 )); wake_daemon; ev set_hot "$1" ;;
  little|big)
    num "$1" || fail e_range 0 3000
    if [ "$cmd" = little ]; then pol=$CPU0; key=LITTLE_MAX; else pol=$CPU6; key=BIG_MAX; fi
    if [ "$1" = 0 ]; then setc $key 0; rd $pol/cpuinfo_max_freq > $pol/scaling_max_freq
    else
      f=$(for x in $(rd $pol/scaling_available_frequencies); do [ $(( x / 1000 )) -le "$1" ] && echo "$x"; done | tail -n 1)
      [ -n "$f" ] || fail e_freq
      setc $key "$f"; echo "$f" > $pol/scaling_max_freq
    fi
    ev "set_freq_$cmd" "$1" ;;
  profile)
    case "$1" in perf) l=0; b=0 ;; balance) l=1612; b=0 ;; eco) l=1324; b=1708 ;; *) fail e_arg ;; esac
    sh "$0" little $l >/dev/null && sh "$0" big $b >/dev/null && ev "set_profile_$1" ;;
  chgmode)
    case "$1" in
      care) setc CC_SMART 1; setc HOT_PAUSE 42; setc HOT_RESUME 38 ;;
      fast) setc CC_SMART 0; setc HOT_PAUSE 48; setc HOT_RESUME 44 ;;
      *) fail e_arg ;;
    esac
    wake_daemon; ev "set_mode_$1" ;;
  thermalchg) bit "$1" || fail e_arg; setc THERMAL_CHG "$1"; ev "set_thermal_$1" ;;
  brightcharge|autobatt)
    bit "$1" || fail e_arg
    k=BRIGHT_CHARGE; [ "$cmd" = autobatt ] && k=AUTO_BATT
    setc $k "$1"; ev "set_${cmd}_$1"
    if plugged; then [ $k = BRIGHT_CHARGE ] && [ "$1" = 1 ] && bright_max
    else [ $k = AUTO_BATT ] && [ "$1" = 1 ] && bright_auto; fi; true ;;
  saver) bit "$1" || fail e_arg; setc SAVER_BATT "$1"; ev "set_saver_$1"; [ "$1" = 1 ] && ! plugged && saver_on; true ;;
  usbfast) bit "$1" || fail e_arg; setc USB_FAST "$1"; [ -f $FFC ] && echo "$1" > $FFC; ev "set_usb_$1" ;;
  drainalert) bit "$1" || fail e_arg; setc DRAIN_ALERT "$1" ;;
  lang) case "$1" in auto|ru|en) setc UI_LANG "$1"; UI_LANG=$1; wake_daemon ;; *) fail e_arg ;; esac ;;
  skin) case "$1" in blue|red|black) setc SKIN "$1" ;; *) fail e_arg ;; esac ;;
  resetsw) rm -f "$D/bad_switches"; ev set_resetsw ;;
  *) echo "panel json live strings logs savelogs diag changelog full [off] limit N hot N little N big N profile perf|balance|eco chgmode care|fast thermalchg 0|1 brightcharge 0|1 autobatt 0|1 saver 0|1 usbfast 0|1 drainalert 0|1 lang auto|ru|en skin blue|red|black resetsw" ;;
esac
