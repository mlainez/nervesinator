#!/usr/bin/env bash
# Read-only device reconnaissance over adb.
# Usage: collect.sh <serial> <output-dir>
# Never writes to the device. Uses su only if the device is already rooted, and only for reads.
# Device-side commands stay within cat, ls, getprop, dumpsys and shell built-ins: old Android
# (toolbox, 4.4 and earlier) has no head, tail, tr, basename or which. Text is processed on the host.
set -u
SER=${1:?serial}; OUT=${2:?output dir}
mkdir -p "$OUT"
A() { adb -s "$SER" "$@"; }
sh_() { A shell "$1" 2>&1 | tr -d '\r'; }
save() { # name command [host-filter-function]
  sh_ "$2" | "${3:-cat}" > "$OUT/$1"
  [ -s "$OUT/$1" ] && echo "ok   $1" || { echo "--   $1 (empty/unreadable)"; }
}
# Host-side filters
first80() { head -80; }
first400() { head -400; }
first800() { head -800; }
last3000() { tail -3000; }
nul2nl() { tr '\0' '\n'; }
# "<path>|<name>|<ls -l of the driver link>" -> "<device> name=<name> driver=<driver>"
devlinks() { awk -F'|' '{ n=split($1,p,"/"); d=$3; sub(/.*\//,"",d); if ($3=="") d=""; print p[n], ($2!="" ? "name=" $2 " " : "") "driver=" d }'; }
# sysfs uevent dumps -> "<devname> <partname>"
partnames() { awk -F= '/^DEVNAME=/{d=$2} /^PARTNAME=/{print d, $2}'; }

state=$(A get-state 2>&1)
[ "$state" = "device" ] || { echo "device $SER is not in adb 'device' state: $state"; exit 1; }

save getprop.txt            "getprop"
save cpuinfo.txt            "cat /proc/cpuinfo"
save meminfo.txt            "cat /proc/meminfo"
save cmdline.txt            "cat /proc/cmdline"
save version.txt            "cat /proc/version"
save partitions.txt         "cat /proc/partitions"
save by-name.txt            "ls -l /dev/block/by-name/ 2>/dev/null || ls -l /dev/block/platform/*/by-name/ 2>/dev/null || ls -l /dev/block/platform/*/*/by-name/"
save mounts.txt             "cat /proc/mounts"
save modules.txt            "cat /proc/modules"
save input-devices.txt      "cat /proc/bus/input/devices"
save dumpsys-display.txt    "dumpsys display" first80
save dumpsys-battery.txt    "dumpsys battery"
save i2c-devices.txt        "for d in /sys/bus/i2c/devices/*; do echo \"\$d|\$(cat \$d/name 2>/dev/null)|\$(ls -l \$d/driver 2>/dev/null)\"; done" devlinks
save platform-devices.txt   "for d in /sys/bus/platform/devices/*; do echo \"\$d||\$(ls -l \$d/driver 2>/dev/null)\"; done" devlinks
save dt-compatible.txt      "cat /proc/device-tree/compatible 2>/dev/null; echo; cat /proc/device-tree/model 2>/dev/null" nul2nl
save firmware-list.txt      "ls -lR /firmware /firmware-mdm /persist 2>/dev/null" first400
save vendor-firmware-list.txt "ls -lR /vendor/firmware /system/etc/firmware /system/vendor/firmware /vendor/etc/firmware /lib/firmware 2>/dev/null" first800
save dmesg.txt              "dmesg 2>&1" last3000
save soc0.txt               "for f in /sys/devices/soc0/*; do [ -f \$f ] && echo \"\$f=\$(cat \$f 2>/dev/null)\"; done"
save emmc.txt               "for f in name cid csd manfid oemid date type serial; do echo \"\$f=\$(cat /sys/block/mmcblk0/device/\$f 2>/dev/null)\"; done"
save power-supply.txt       "for d in /sys/class/power_supply/*; do echo \"== \$d\"; cat \$d/uevent 2>/dev/null; done"
save asound.txt             "cat /proc/asound/cards 2>/dev/null; ls /proc/asound 2>/dev/null"
save partnames-sysfs.txt    "for d in /sys/block/mmcblk0/mmcblk0p*; do cat \$d/uevent 2>/dev/null; done" partnames
save selinux.txt            "getenforce; id"

if sh_ "ls /proc/config.gz" | grep -q '^/proc/config.gz$'; then
  A exec-out "cat /proc/config.gz" > "$OUT/config.gz" 2>/dev/null && gzip -dc "$OUT/config.gz" > "$OUT/kernel.config" 2>/dev/null \
    && echo "ok   kernel.config" || echo "--   kernel.config (unreadable)"
fi

lsusb 2>/dev/null > "$OUT/lsusb-host.txt"

# Root-enhanced reads (only if su already works; never installs anything)
if sh_ "su -c id" | grep -q "uid=0"; then
  echo "root available: collecting root-only reads"
  sh_ "su -c 'dmesg'" > "$OUT/dmesg-root.txt"
  sh_ "su -c 'ls -lR /vendor/firmware /firmware /persist 2>/dev/null'" > "$OUT/firmware-list-root.txt"
  A exec-out "su -c 'cat /sys/firmware/fdt'" > "$OUT/devicetree.dtb" 2>/dev/null
  for p in boot recovery; do
    dev=$(sh_ "ls /dev/block/by-name/$p /dev/block/platform/*/by-name/$p /dev/block/platform/*/*/by-name/$p 2>/dev/null" | head -1)
    [ -n "$dev" ] && A exec-out "su -c 'cat $dev'" > "$OUT/$p.img" 2>/dev/null && echo "ok   $p.img (read from $dev)"
  done
  ( cd "$OUT" && sha256sum *.img *.dtb 2>/dev/null > SHA256SUMS.recon )
else
  echo "no root: skipping root-only reads (that's fine)"
fi
find "$OUT" -type f -empty -delete
echo "done: $OUT"
