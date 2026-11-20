#!/system/bin/sh
# Control the phone's own Dolby/HoloAudio switches. The vendor UI for them
# (com.oplus.audio.effectcenter) is disabled on this SKU, so there is no screen for any of it.
#
#   oplusdolby.sh status                 everything at a glance
#   oplusdolby.sh on | off               holo_audio_switch          (secure)
#   oplusdolby.sh dolby on | off         system_dolby               (system, master switch)
#   oplusdolby.sh geq on | off           system_dolby_geq_state     (system, graphic EQ)
#   oplusdolby.sh eq                     print the 10 EQ bands
#   oplusdolby.sh eq <band> <dB>         set one band, 1..10 (negative cuts, positive boosts)
#   oplusdolby.sh eq set <10 dB>         replace the whole curve
#   oplusdolby.sh audio on | off         real master switch (AudioEffect.setEnabled)
#   oplusdolby.sh eq flat                all bands back to 0
#   oplusdolby.sh mode <n>               holo_audio_mode
#   oplusdolby.sh device <n>             holo_audio_device_type
#   oplusdolby.sh rate <enter> <exit>    dolby_dynamic_enter_rate / _exit_rate (ms, -1 = off)
#   oplusdolby.sh set <key> <value>      any key from the table below
#   oplusdolby.sh keep <key>             stop forcing this key on boot
#
# Whatever you set here is remembered in settings.conf and re-applied on every boot, because an
# OTA or a "reset sound settings" clears these values.

DATA_DIR=/data/adb/oplusdolby
CONF=$DATA_DIR/settings.conf
DEX=/data/adb/modules/oplusdolby/bin/audioxctl.dex
EQ_FILE=$DATA_DIR/eq.txt
STATE=$DATA_DIR/state.conf
touch "$CONF" 2>/dev/null

EQ_KEY=system_dolby_music_geq
EQ_BANDS=10

# key -> namespace. Only these are accepted: writing an unknown key could wake up parts of the
# vendor audio stack that are deliberately off on this device.
ns_of() {
    case "$1" in
        system_dolby|system_dolby_geq_state|system_dolby_music_geq|sound_effects_enabled) echo system ;;
        holo_audio_switch|holo_audio_mode|holo_audio_device_type) echo secure ;;
        dolby_dynamic_enter_rate|dolby_dynamic_exit_rate|oplus_camera_record_dolby) echo secure ;;
        *) echo "" ;;
    esac
}

sec_keys() {
    echo "holo_audio_switch holo_audio_mode holo_audio_device_type dolby_dynamic_enter_rate dolby_dynamic_exit_rate oplus_camera_record_dolby"
}
sys_keys() {
    echo "system_dolby system_dolby_geq_state system_dolby_music_geq sound_effects_enabled"
}

conf_set() {
    if grep -q "^$1=" "$CONF" 2>/dev/null; then
        sed -i "s|^$1=.*|$1=$2|" "$CONF"
    else
        echo "$1=$2" >> "$CONF"
    fi
}

conf_del() { sed -i "/^$1=/d" "$CONF" 2>/dev/null; }

conf_get() { grep "^$1=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-; }

apply() {
    key=$1
    val=$2
    ns=$(ns_of "$key")
    [ -n "$ns" ] || { echo "unknown key: $key"; return 1; }
    if settings put "$ns" "$key" "$val" 2>/dev/null; then
        echo "$key=$val ($ns)"
        conf_set "$key" "$val"
    else
        echo "failed to write $key"
        return 1
    fi
}

# The settings keys above only change how the vendor stack *would* behave; nothing audible
# happens until the effect itself gets parameters. This runs our dex, which speaks the effect's
# own protocol (same keys the disabled vendor app would send).
audiox() {
    if [ ! -f "$DEX" ]; then echo "audioxctl.dex missing"; return 1; fi
    if [ "$1" = "info" ]; then
        CLASSPATH=$DEX app_process /system/bin --nice-name=audioxctl OplusAudiox info 2>&1
    else
        CLASSPATH=$DEX app_process /system/bin --nice-name=audioxctl OplusAudiox "$@" 2>&1 | grep -v '^attached '
    fi
}

# What the user chose, kept across reboots: the effect itself forgets everything when
# audioserver recreates it, and the vendor stack does not remember our choices either.
state_set() {
    touch "$STATE" 2>/dev/null
    if grep -q "^$1=" "$STATE" 2>/dev/null; then
        sed -i "s|^$1=.*|$1=$2|" "$STATE"
    else
        echo "$1=$2" >> "$STATE"
    fi
}

state_get() {
    grep "^$1=" "$STATE" 2>/dev/null | tail -1 | cut -d= -f2-
}

eq_store() {
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$@" > "$EQ_FILE"
}

eq_load() {
    [ -f "$EQ_FILE" ] && cat "$EQ_FILE" || echo "0,0,0,0,0,0,0,0,0,0"
}

# The GEQ curve is stored per media-volume bucket. The vendor app computes the bucket as
# streamVolume, halved when the stream max is above 100 (this phone has max 160), so the curve
# has to travel with the *current* bucket or it lands in a shelf that is not in use.
vol_index() {
    out=$(dumpsys audio 2>/dev/null)
    cur=$(echo "$out" | awk '/STREAM_MUSIC:/{f=1} f&&/streamVolume:/{gsub(/[^0-9]/,"");print;exit}')
    max=$(echo "$out" | awk '/STREAM_MUSIC:/{f=1} f&&/Max:/{gsub(/[^0-9]/,"");print;exit}')
    [ -n "$cur" ] || cur=0
    if [ -n "$max" ] && [ "$max" -gt 100 ]; then cur=$((cur / 10)); fi
    echo "$cur"
}

eq_push() {
    set -- $(echo "$(eq_load)" | tr ',' ' ')
    idx=$(vol_index)
    # GEQ only exists inside profile 0 - its own state dump shows Geq=1 there and Geq=0
    # everywhere else, and without that flag the bands are accepted and then ignored.
    audiox profile 0 >/dev/null 2>&1
    audiox eq on >/dev/null 2>&1
    state_set profile 0
    state_set eq on
    audiox eqset "$idx" "$@" >/dev/null && echo "eq applied at volIdx $idx: $(eq_load)"
}

show() {
    key=$1
    ns=$(ns_of "$key")
    printf '%-26s %-7s %s' "$key" "$ns" "$(settings get "$ns" "$key" 2>/dev/null)"
    forced=$(conf_get "$key")
    [ -n "$forced" ] && printf '   (forced %s)' "$forced"
    echo
}

eq_show() {
    cur=$(settings get system "$EQ_KEY" 2>/dev/null)
    echo "bands: $cur"
    n=1
    echo "$cur" | tr ',' '\n' | while read -r v; do
        printf '  %2d: %s dB\n' "$n" "${v:-0}"
        n=$((n + 1))
    done
}

eq_set_one() {
    band=$1
    val=$2
    case "$band" in ''|*[!0-9]*) echo "band must be 1..$EQ_BANDS"; return 1 ;; esac
    [ "$band" -ge 1 ] && [ "$band" -le "$EQ_BANDS" ] || { echo "band must be 1..$EQ_BANDS"; return 1; }
    cur=$(settings get system "$EQ_KEY" 2>/dev/null)
    [ -n "$cur" ] || cur=$(printf '0,%.0s' $(seq 1 $((EQ_BANDS - 1))); echo 0)
    new=$(echo "$cur" | awk -F, -v b="$band" -v v="$val" -v n="$EQ_BANDS" '{
        for (i = 1; i <= n; i++) {
            x = (i <= NF) ? $i : 0
            printf "%s%s", (i == b ? v : x), (i < n ? "," : "\n")
        }
    }')
    apply "$EQ_KEY" "$new"
}

case "$1" in
    status)
        for k in $(sec_keys); do show "$k"; done
        for k in $(sys_keys); do show "$k"; done
        [ "$(settings get system "$EQ_KEY" 2>/dev/null)" != "" ] && eq_show
        echo
        echo "curve:  $(eq_load)"
        echo "saved:  audio=$(state_get audio) eq=$(state_get eq) profile=$(state_get profile)"
        echo "effect: $(audiox info | tr '\n' ' ')"
        [ -f "$DATA_DIR/disable" ] && echo "module: disabled" || echo "module: enabled"
        ;;
    restore)
        prof=$(state_get profile); [ -n "$prof" ] || prof=0
        audiox profile "$prof" >/dev/null 2>&1
        if [ "$(state_get audio)" = "off" ]; then audiox off >/dev/null 2>&1; else audiox on >/dev/null 2>&1; fi
        if [ "$(state_get eq)" = "off" ]; then
            audiox eq off >/dev/null 2>&1
            echo "restored: audio=$(state_get audio) eq=off profile=$prof"
        else
            eq_push
        fi
        ;;
    on)    apply holo_audio_switch 1 ;;
    off)   apply holo_audio_switch 0 ;;
    dolby) [ -n "$2" ] || { echo "usage: dolby {on|off}"; exit 1; }
           case "$2" in on) apply system_dolby 1 ;; off) apply system_dolby 0 ;; *) echo "usage: dolby {on|off}"; exit 1 ;; esac ;;
    geq)   [ -n "$2" ] || { echo "usage: geq {on|off}"; exit 1; }
           case "$2" in on) apply system_dolby_geq_state 1 ;; off) apply system_dolby_geq_state 0 ;; *) echo "usage: geq {on|off}"; exit 1 ;; esac ;;
    eq)
        case "$2" in
            '') eq_show ;;
            on) audiox eq on; state_set eq on; apply system_dolby_geq_state 1 ;;
            off) audiox eq off; state_set eq off; apply system_dolby_geq_state 0 ;;
            flat|reset) apply "$EQ_KEY" "0,0,0,0,0,0,0,0,0,0"; eq_store 0 0 0 0 0 0 0 0 0 0; eq_push ;;
            set) shift 2; [ $# -eq 10 ] || { echo "usage: eq set <10 values in dB>"; exit 1; }
                 eq_store "$@"; apply "$EQ_KEY" "$(echo "$*" | tr ' ' ',')"; eq_push ;;
            *) [ -n "$3" ] || { echo "usage: eq <band> <dB> | eq flat | eq set <10 dB> | eq on|off"; exit 1; }
               eq_set_one "$2" "$3"; eq_push ;;
        esac
        ;;
    audio)  case "$2" in
                on) audiox on; state_set audio on ;;
                off) audiox off; state_set audio off ;;
                *) echo "usage: audio {on|off}" ;;
            esac ;;
    profile) [ -n "$2" ] || { echo "usage: profile <0..14>"; exit 1; }
             audiox profile "$2"; state_set profile "$2" ;;
    atten)  [ -n "$2" ] || { echo "usage: atten <dB>"; exit 1; }; audiox atten "$2" ;;
    enhance) [ -n "$2" ] || { echo "usage: enhance {on|off}"; exit 1; }; audiox enhance "$2" ;;
    mode)   [ -n "$2" ] || { echo "usage: mode <n>"; exit 1; }; apply holo_audio_mode "$2" ;;
    device) [ -n "$2" ] || { echo "usage: device <n>"; exit 1; }; apply holo_audio_device_type "$2" ;;
    rate)
        [ -n "$2" ] && [ -n "$3" ] || { echo "usage: rate <enter> <exit>"; exit 1; }
        apply dolby_dynamic_enter_rate "$2"
        apply dolby_dynamic_exit_rate "$3"
        ;;
    set)  [ -n "$2" ] && [ -n "$3" ] || { echo "usage: set <key> <value>"; exit 1; }; apply "$2" "$3" ;;
    keep) [ -n "$2" ] || { echo "usage: keep <key>"; exit 1; }; conf_del "$2"; echo "$2 no longer forced" ;;
    *)    sed -n '3,20p' "$0" ;;
esac
