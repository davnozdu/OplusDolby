#!/system/bin/sh
# Undo the bind mounts so nothing points at this module after removal.
for f in /odm/etc/audio_effects_config.xml /odm/lib64/soundfx/libOplusAudioxAidl.so /odm/lib64/soundfx/libOplusSpatializerAidl.so; do
    umount "$f" 2>/dev/null
done
rm -rf /data/adb/oplusdolby
