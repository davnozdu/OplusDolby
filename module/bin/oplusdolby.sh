#!/system/bin/sh
# Control the phone's own Dolby/HoloAudio switches (the ones the vendor UI would expose,
# but com.oplus.audio.effectcenter is disabled on this SKU, so there is no screen for them).
#
#   oplusdolby.sh status                show the current values
#   oplusdolby.sh on | off              holo_audio_switch 1 | 0
#   oplusdolby.sh mode <n>              holo_audio_mode
#   oplusdolby.sh device <n>            holo_audio_device_type
#   oplusdolby.sh rate <enter> <exit>   dolby_dynamic_enter_rate / _exit_rate
#   oplusdolby.sh set <key> <value>     any secure setting by name
#   oplusdolby.sh keep <key>            stop forcing this key at boot
#
# Values given here are remembered in settings.conf and re-applied on every boot, because the
# system is free to reset these settings after an update.

DATA_DIR=/data/adb/oplusdolby
CONF=$DATA_DIR/settings.conf
touch "$CONF" 2>/dev/null

KEYS="holo_audio_switch holo_audio_mode holo_audio_device_type dolby_dynamic_enter_rate dolby_dynamic_exit_rate"

conf_set() {
    key=$1
    val=$2
    if grep -q "^$key=" "$CONF" 2>/dev/null; then
        sed -i "s|^$key=.*|$key=$val|" "$CONF"
    else
        echo "$key=$val" >> "$CONF"
    fi
}

conf_del() {
    sed -i "/^$1=/d" "$CONF" 2>/dev/null
}

conf_get() {
    grep "^$1=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-
}

apply() {
    key=$1
    val=$2
    case "$key" in
        holo_audio_switch|holo_audio_mode|holo_audio_device_type|dolby_dynamic_enter_rate|dolby_dynamic_exit_rate) ;;
        *) echo "unknown key: $key"; return 1 ;;
    esac
    if settings put secure "$key" "$val" 2>/dev/null; then
        echo "$key=$val"
        conf_set "$key" "$val"
    else
        echo "failed to write $key"
        return 1
    fi
}

case "$1" in
    status)
        for k in $KEYS; do
            printf '%-26s %s' "$k" "$(settings get secure "$k" 2>/dev/null)"
            forced=$(conf_get "$k")
            [ -n "$forced" ] && printf '   (forced to %s at boot)' "$forced"
            echo
        done
        echo
        if [ -f "$DATA_DIR/disable" ]; then echo "module: disabled"; else echo "module: enabled"; fi
        ;;
    on)  apply holo_audio_switch 1 ;;
    off) apply holo_audio_switch 0 ;;
    mode) [ -n "$2" ] || { echo "usage: mode <n>"; exit 1; }; apply holo_audio_mode "$2" ;;
    device) [ -n "$2" ] || { echo "usage: device <n>"; exit 1; }; apply holo_audio_device_type "$2" ;;
    rate)
        [ -n "$2" ] && [ -n "$3" ] || { echo "usage: rate <enter> <exit>"; exit 1; }
        apply dolby_dynamic_enter_rate "$2"
        apply dolby_dynamic_exit_rate "$3"
        ;;
    set) [ -n "$2" ] && [ -n "$3" ] || { echo "usage: set <key> <value>"; exit 1; }; apply "$2" "$3" ;;
    keep) [ -n "$2" ] || { echo "usage: keep <key>"; exit 1; }; conf_del "$2"; echo "$2 no longer forced" ;;
    *)
        echo "usage: $0 {status|on|off|mode <n>|device <n>|rate <enter> <exit>|set <key> <value>|keep <key>}"
        exit 1
        ;;
esac
