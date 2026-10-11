#!/usr/bin/env bash
# Read-only device reconnaissance over adb.
# Usage: collect.sh <serial> <output-dir>
# Never writes to the device. Uses su only if the device is already rooted, and only for reads.
set -u
SER=${1:?serial}; OUT=${2:?output dir}
mkdir -p "$OUT"
A() { adb -s "$SER" "$@"; }
sh_() { A shell "$1" 2>&1 | tr -d '\r'; }
save() { # name command
  sh_ "$2" > "$OUT/$1"
  [ -s "$OUT/$1" ] && echo "ok   $1" || { echo "--   $1 (empty/unreadable)"; }
}

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
save dumpsys-display.txt    "dumpsys display | head -80"
save dumpsys-battery.txt    "dumpsys battery"
save i2c-devices.txt        "for d in /sys/bus/i2c/devices/*; do echo \"\$(basename \$d) name=\$(cat \$d/name 2>/dev/null) driver=\$(basename \$(readlink \$d/driver) 2>/dev/null)\"; done"
save platform-devices.txt   "for d in /sys/bus/platform/devices/*; do echo \"\$(basename \$d) driver=\$(basename \$(readlink \$d/driver) 2>/dev/null)\"; done"
save dt-compatible.txt      "cat /proc/device-tree/compatible 2>/dev/null | tr '\\0' '\\n'; echo; cat /proc/device-tree/model 2>/dev/null"
save firmware-list.txt      "ls -lR /firmware /firmware-mdm /persist 2>/dev/null | head -400"
save vendor-firmware-list.txt "ls -lR /vendor/firmware /system/etc/firmware /system/vendor/firmware /vendor/etc/firmware /lib/firmware 2>/dev/null | head -800"
save dmesg.txt              "dmesg 2>&1 | tail -3000"
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
