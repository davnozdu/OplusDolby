#!/system/bin/sh
# Installer hooks for KernelSU / Magisk.

SKIPUNZIP=1

ui_print() { echo "$1"; }

ui_print "- Oplus Dolby (stock)"
mkdir -p "$MODPATH/system" 2>/dev/null

unzip -o "$ZIPFILE" 'module.prop' 'post-fs-data.sh' 'service.sh' 'uninstall.sh' 'README.md' -d "$MODPATH" >/dev/null 2>&1
rm -rf "$MODPATH/system"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

mkdir -p /data/adb/oplusdolby
ui_print "- done, reboot to let it check the effect libraries"
