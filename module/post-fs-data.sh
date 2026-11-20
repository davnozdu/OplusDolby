#!/system/bin/sh
# Oplus Dolby (stock)
#
# The phone ships its "Dolby"/HoloAudio processing as the Oplus audiox effect:
#   library  /odm/lib64/soundfx/libOplusAudioxAidl.so   (config name oplus_audiox_sw)
#   effect   41f6c0f4-5d8f-11ec-bf63-0242ac130002       (config name oplusaudiox)
#   declared in /odm/etc/audio_effects_config.xml
# The audio policy creates it on session 0, so it processes everything that goes to the
# speaker. It stops working the moment that library file or that config entry is replaced -
# which is exactly what a "Dolby mod" that puts its own binary in the slot does.
#
# This module owns no processing. It only puts the stock pieces back when they are missing
# or replaced, and leaves the phone untouched when they are fine.

MODDIR=${0%/*}
[ -z "$MODDIR" ] || [ "$MODDIR" = "$0" ] && MODDIR="/data/adb/modules/oplusdolby"

DATA_DIR=/data/adb/oplusdolby
LOG=$DATA_DIR/log.txt
mkdir -p "$DATA_DIR"
: > "$LOG"

log() { echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"; }

[ -f "$DATA_DIR/disable" ] && { log "disabled by flag"; exit 0; }

SNDFX=/odm/lib64/soundfx
STOCK=$DATA_DIR/stock
mkdir -p "$STOCK"
LIBS="libOplusAudioxAidl.so libOplusSpatializerAidl.so"
CFG=/odm/etc/audio_effects_config.xml
EFFECT_UUID=41f6c0f4-5d8f-11ec-bf63-0242ac130002

# First run: remember the stock binaries. They are the reference the later checks use.
for lib in $LIBS; do
    [ -f "$STOCK/$lib" ] && continue
    [ -f "$SNDFX/$lib" ] || continue
    cp -f "$SNDFX/$lib" "$STOCK/$lib" && log "baseline saved: $lib"
done

restore_lib() {
    lib=$1
    want=$2
    cur=$3
    [ -f "$STOCK/$lib" ] || { log "no baseline for $lib, cannot restore"; return 1; }
    # /odm is mounted read-write, but a module may have bind-mounted over the directory:
    # copy into a staging dir and bind the single file so the mount wins either way.
    stage=$DATA_DIR/stage/$lib
    mkdir -p "$DATA_DIR/stage"
    cp -f "$STOCK/$lib" "$stage" || return 1
    chmod 0644 "$stage"
    chcon u:object_r:vendor_file:s0 "$stage" 2>/dev/null
    if mount --bind "$stage" "$SNDFX/$lib" 2>>"$LOG"; then
        log "restored $lib by bind mount (was $cur, want $want)"
    elif cp -f "$STOCK/$lib" "$SNDFX/$lib" 2>>"$LOG"; then
        log "restored $lib by copy (was $cur, want $want)"
    else
        log "FAILED to restore $lib"
        return 1
    fi
    return 0
}

# Device guard: this module only makes sense where the vendor effect already exists. On any
# other phone there is nothing to repair, and touching /odm there would be wrong.
if [ ! -f /odm/lib64/soundfx/libOplusAudioxAidl.so ] && [ ! -f "$DATA_DIR/stock/libOplusAudioxAidl.so" ]; then
    log "no Oplus audiox library on this device, nothing to do"
    exit 0
fi

changed=0
for lib in $LIBS; do
    [ -f "$STOCK/$lib" ] || continue
    if [ ! -f "$SNDFX/$lib" ]; then
        log "missing: $lib"
        restore_lib "$lib" "$(md5sum "$STOCK/$lib" | cut -d' ' -f1)" "absent" && changed=1
        continue
    fi
    want=$(md5sum "$STOCK/$lib" | cut -d' ' -f1)
    cur=$(md5sum "$SNDFX/$lib" | cut -d' ' -f1)
    [ "$want" = "$cur" ] && continue
    restore_lib "$lib" "$want" "$cur" && changed=1
done

# The effect has to be declared in the config the audio service reads, otherwise the
# library sits on disk unloaded. Other modules are known to rewrite this file.
if [ -f "$CFG" ]; then
    if ! grep -q "$EFFECT_UUID" "$CFG"; then
        OUT=$DATA_DIR/audio_effects_config.xml
        cp -f "$CFG" "$OUT" || OUT=
        if [ -n "$OUT" ]; then
            awk '
            /<\/libraries>/ && !lib_done {
                print "        <library name=\"oplus_audiox_sw\" path=\"libOplusAudioxAidl.so\"/>"
                lib_done=1
            }
            /<\/effects>/ && !eff_done {
                print "        <effect name=\"oplusaudiox\" library=\"oplus_audiox_sw\" uuid=\"41f6c0f4-5d8f-11ec-bf63-0242ac130002\"/>"
                eff_done=1
            }
            { print }
            ' "$OUT" > "$OUT.new" && mv -f "$OUT.new" "$OUT"
            chmod 0644 "$OUT"
            chcon u:object_r:vendor_configs_file:s0 "$OUT" 2>/dev/null
            if mount --bind "$OUT" "$CFG" 2>>"$LOG"; then
                log "effect entry was missing, config re-asserted"
                changed=1
            else
                log "config re-assert FAILED"
            fi
        fi
    fi
else
    log "no $CFG on this device"
fi

# A freshly created effect only reaches the chain after the audio service rebuilds its
# effect list, so restart it once and only when something was actually repaired.
if [ "$changed" = "1" ]; then
    log "restarting audioserver"
    setprop ctl.restart audioserver 2>/dev/null
fi

log "done (changed=$changed)"
