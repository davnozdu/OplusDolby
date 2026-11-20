#!/system/bin/sh
# Installer hooks for KernelSU / Magisk.

SKIPUNZIP=1

ui_print() { echo "$1"; }

ui_print "- Oplus Dolby (stock)"
mkdir -p "$MODPATH/system" 2>/dev/null

unzip -o "$ZIPFILE" 'module.prop' 'post-fs-data.sh' 'service.sh' 'action.sh' 'uninstall.sh' 'README.md' 'bin/*' 'webroot/*' -d "$MODPATH" >/dev/null 2>&1
rm -rf "$MODPATH/system"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
[ -f "$MODPATH/bin/oplusdolby.sh" ] && set_perm "$MODPATH/bin/oplusdolby.sh" 0 0 0755

mkdir -p /data/adb/oplusdolby
ui_print "- switches: su -c 'sh /data/adb/modules/oplusdolby/bin/oplusdolby.sh status'"
ui_print "- done, reboot to let it check the effect libraries"

# Dolby max is what the module is installed for, so a fresh install starts in that mode.
mkdir -p /data/adb/oplusdolby
if [ ! -f /data/adb/oplusdolby/state.conf ]; then
    printf 'mode=dolby\naudio=on\neq=off\nprofile=2\n' > /data/adb/oplusdolby/state.conf
    ui_print "- default mode: Dolby max (profile 2)"
fi
