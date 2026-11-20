#!/system/bin/sh
# Late check: some modules mount their own audio config after post-fs-data runs, which can
# drop the effect entry again. Re-check once the system has settled and repair only if the
# chain is actually broken.

MODDIR=${0%/*}
[ -z "$MODDIR" ] || [ "$MODDIR" = "$0" ] && MODDIR="/data/adb/modules/oplusdolby"

DATA_DIR=/data/adb/oplusdolby
LOG=$DATA_DIR/log.txt
[ -f "$DATA_DIR/disable" ] && exit 0

while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

CFG=/odm/etc/audio_effects_config.xml
SNDFX=/odm/lib64/soundfx
STOCK=$DATA_DIR/stock
EFFECT_UUID=41f6c0f4-5d8f-11ec-bf63-0242ac130002

broken=0
for lib in libOplusAudioxAidl.so libOplusSpatializerAidl.so; do
    [ -f "$STOCK/$lib" ] || continue
    [ -f "$SNDFX/$lib" ] || { broken=1; continue; }
    want=$(md5sum "$STOCK/$lib" | cut -d' ' -f1)
    cur=$(md5sum "$SNDFX/$lib" | cut -d' ' -f1)
    [ "$want" = "$cur" ] || broken=1
done
[ -f "$CFG" ] && ! grep -q "$EFFECT_UUID" "$CFG" && broken=1

if [ "$broken" = "1" ]; then
    echo "$(date '+%m-%d %H:%M:%S') late check found a broken chain, re-running repair" >> "$LOG"
    sh "$MODDIR/post-fs-data.sh"
fi
