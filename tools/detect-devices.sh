#!/usr/bin/env bash
# List every phone visible to this computer, in any mode. Read-only.
# Usage: tools/detect-devices.sh
set -u
found=0
echo "== adb"
if command -v adb >/dev/null; then
  while read -r ser state rest; do
    [ -z "$ser" ] && continue
    found=1
    if [ "$state" = "device" ]; then
      p() { adb -s "$ser" shell getprop "$1" 2>/dev/null | tr -d '\r'; }
      printf "  %-20s %-12s %s %s (%s) platform=%s android=%s\n" "$ser" "$state" \
        "$(p ro.product.manufacturer)" "$(p ro.product.model)" "$(p ro.product.device)" \
        "$(p ro.board.platform)" "$(p ro.build.version.release)"
    else
      hint=""
      [ "$state" = "unauthorized" ] && hint="-> unlock the phone and accept the 'Allow USB debugging?' prompt"
      [ "$state" = "no" ] && hint="-> no permissions: udev rules missing (see tools/check-host.sh)"
      printf "  %-20s %-12s %s\n" "$ser" "$state" "$hint"
    fi
  done < <(adb devices 2>/dev/null | tail -n +2 | awk 'NF')
else
  echo "  adb not installed"
fi

echo "== fastboot"
if command -v fastboot >/dev/null; then
  while read -r ser mode; do
    [ -z "$ser" ] && continue
    found=1
    prod=$(fastboot -s "$ser" getvar product 2>&1 | awk -F': ' '/^product:/{print $2}')
    unl=$(fastboot -s "$ser" getvar unlocked 2>&1 | awk -F': ' '/^unlocked:/{print $2}')
    printf "  %-20s %-10s product=%s unlocked=%s\n" "$ser" "$mode" "${prod:-?}" "${unl:-?}"
  done < <(timeout 10 fastboot devices 2>/dev/null)
else
  echo "  fastboot not installed"
fi

echo "== kit test images (first light / rescue / system)"
. "$(dirname "$0")/lib/kit_gadget.sh"
while read -r ser prod tty net; do
  [ -z "$ser" ] && continue
  found=1
  printf "  %-20s %-24s console=%s net=%s (phone 10.0.42.1)\n" "$ser" "$prod" "$tty" "$net"
done < <(kit_gadgets)

echo "== USB (special modes)"
if command -v lsusb >/dev/null; then
  lsusb | while read -r line; do
    id=$(echo "$line" | grep -oE 'ID [0-9a-f]{4}:[0-9a-f]{4}' | cut -d' ' -f2)
    case "$id" in
      04e8:685d) echo "  Samsung DOWNLOAD MODE (heimdall/odin): $line" ;;
      04e8:6860) echo "  Samsung phone (MTP/adb): $line" ;;
      05c6:9008) echo "  Qualcomm EDL (emergency download) mode: $line  !! stop and read device-safety" ;;
      05c6:900e) echo "  Qualcomm crash dump (ramdump) mode: $line" ;;
      0e8d:0003) echo "  MediaTek BROM mode: $line" ;;
      0e8d:2000) echo "  MediaTek preloader mode: $line" ;;
      18d1:4ee0|18d1:d00d) echo "  Android fastboot: $line" ;;
      18d1:d001) echo "  USB networking gadget (older rescue initramfs?): $line" ;;
    esac
  done
  lsusb | grep -qE '04e8:685d|05c6:9008|0e8d:0003|0e8d:2000' && found=1
else
  echo "  lsusb not installed"
fi
if command -v heimdall >/dev/null && lsusb 2>/dev/null | grep -q 04e8:685d; then
  echo "== heimdall"; heimdall detect 2>&1 | sed 's/^/  /'
fi
[ $found = 1 ] || { echo; echo "No phone found. Check: USB debugging enabled, a data-capable cable, accept the prompt on the phone."; exit 1; }
