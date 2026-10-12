#!/usr/bin/env bash
# Print the host block device of the phone in USB mass storage mode (U-Boot `ums`), so a host-side
# write (`fwup -d`, `mix burn`) never targets one of this computer's disks.
# Usage: tools/ums-target.sh --port <id>
#
# Matches the USB serial number against device.second_stage_serial (else device.serial). Prints
# "/dev/sdX <bytes>" and checks the size against device.partition_sizes.userdata when it is set.
# Exit 0 with exactly one match, 1 otherwise. Read-only.
set -uo pipefail
KIT=$(cd "$(dirname "$0")/.." && pwd)
PORT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT=$2; shift 2 ;;
    *) sed -n '2,9p' "$0"; exit 1 ;;
  esac
done
[ -n "$PORT" ] || { sed -n '2,9p' "$0"; exit 1; }
Y="$KIT/ports/$PORT/port.yaml"
[ -f "$Y" ] || { echo "no such port: $PORT"; exit 1; }
cfg() { python3 -I "$KIT/tools/lib/portcfg.py" "$Y" "$1"; }
SER=$(cfg device.second_stage_serial); [ -n "$SER" ] || SER=$(cfg device.serial)
WANT=$(cfg device.partition_sizes 2>/dev/null | awk -F= 'tolower($1)=="userdata"{print $2}')

found=()
for b in "${KIT_SYS_BLOCK:-/sys/block}"/sd*; do
  [ -e "$b" ] || continue
  d=$(readlink -f "$b/device" 2>/dev/null) || continue
  # Walk up to the USB device node (the directory holding idVendor and serial)
  while [ -n "$d" ] && [ "$d" != / ] && [ ! -f "$d/idVendor" ]; do d=$(dirname "$d"); done
  [ -f "$d/serial" ] && [ "$(cat "$d/serial")" = "$SER" ] || continue
  bytes=$(( $(cat "$b/size") * 512 ))
  found+=("/dev/${b##*/} $bytes")
done

if [ ${#found[@]} -ne 1 ]; then
  echo "expected exactly one USB disk with serial $SER, found ${#found[@]}: is the phone in USB disk (ums) mode?" >&2
  exit 1
fi
read -r dev bytes <<< "${found[0]}"
if [ -n "$WANT" ] && [ "$bytes" != "$WANT" ]; then
  echo "$dev is $bytes bytes, device.partition_sizes.userdata says $WANT: not the expected range" >&2
  exit 1
fi
echo "$dev $bytes"
