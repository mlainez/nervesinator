#!/usr/bin/env bash
# Guarded device writes. Dry run by default: prints the checks and the command.
# With --execute, re-runs every check and then runs the command.
#
# Usage:
#   tools/safe-flash.sh --port <id> [--execute] boot  <image>              # fastboot boot (RAM only)
#   tools/safe-flash.sh --port <id> [--execute] [--resume] flash <partition> <image>  # fastboot or heimdall
#   tools/safe-flash.sh --port <id> [--execute] unlock [flashing|oem]      # bootloader unlock (wipes data)
#
# Checks: device present by serial and alone in its mode, product matches port.yaml, partition not
# forbidden, partition allowlisted, verified backup present, image fits, boot image magic.
# The partition size comes from port.yaml device.partition_sizes (bytes), else from the M1 recon
# (dossier/raw/by-name.txt or partnames-sysfs.txt + partitions.txt), else from the backup, which is
# right only when the backup is a full dump, not a stock image.
#
# heimdall flashes run with --no-reboot. The next heimdall command in the same download mode session
# needs --resume; without it, reboot into download mode first.
set -uo pipefail
KIT=$(cd "$(dirname "$0")/.." && pwd)
EXEC=0; PORT=""; RESUME=0
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT=$2; shift 2 ;;
    --execute) EXEC=1; shift ;;
    --resume) RESUME=1; shift ;;
    *) break ;;
  esac
done
OP=${1:-}; shift || true
[ -n "$PORT" ] && [ -n "$OP" ] || { sed -n '2,17p' "$0"; exit 2; }
P="$KIT/ports/$PORT"; Y="$P/port.yaml"
[ -f "$Y" ] || { echo "no such port: $P"; exit 2; }
cfg() { python3 -I "$KIT/tools/lib/portcfg.py" "$Y" "$1"; }
SER=$(cfg device.serial); PRODUCT=$(cfg device.product); MODE=$(cfg device.flash_mode)
LOG="$P/journal/plans/safe-flash.log"; mkdir -p "$(dirname "$LOG")"

fails=0
ok()   { echo "  ✅ $*"; }
bad()  { echo "  ❌ $*"; fails=$((fails+1)); }
lower() { echo "$1" | tr 'A-Z' 'a-z'; }
forbidden() {
  local n; n=$(lower "$1"); n=${n%_a}; n=${n%_b}
  grep -v '^\s*#' "$KIT/tools/lib/forbidden-partitions.txt" | awk 'NF{print tolower($1)}' | grep -qx "$n"
}

check_fastboot_device() {
  local devs others prod
  devs=$(timeout 10 fastboot devices 2>/dev/null | awk '{print $1}')
  echo "$devs" | grep -qx "$SER" && ok "device $SER is in fastboot mode" || { bad "device $SER not in fastboot mode"; return; }
  others=$(echo "$devs" | grep -vx "$SER" | grep . || true)
  [ -z "$others" ] && ok "no other fastboot device attached" || bad "other fastboot devices attached: $others (unplug them)"
  if [ -n "$PRODUCT" ]; then
    prod=$(fastboot -s "$SER" getvar product 2>&1 | awk -F': ' '/^product:/{print $2}')
    [ "$prod" = "$PRODUCT" ] && ok "product '$prod' matches port.yaml" || bad "product '$prod' != port.yaml '$PRODUCT'"
  else
    bad "device.product is empty in port.yaml (set it from 'fastboot getvar product' first)"
  fi
}

check_heimdall_device() {
  local n
  command -v heimdall >/dev/null || { bad "heimdall not installed"; return; }
  n=$(lsusb 2>/dev/null | grep -c '04e8:685d')
  [ "$n" = 1 ] && ok "exactly one Samsung device in download mode" || bad "$n Samsung devices in download mode (need exactly 1)"
  heimdall detect >/dev/null 2>&1 && ok "heimdall detects the device" || bad "heimdall detect failed"
  echo "  ⚠️  heimdall cannot address a device by serial: make sure the right phone is the only one in download mode"
}

partition_size() { # partition -> "<bytes> <source>", or nothing when unknown
  local n R dev blocks size
  n=$(lower "$1"); R="$P/dossier/raw"
  size=$(cfg device.partition_sizes 2>/dev/null | awk -F= -v n="$n" 'tolower($1)==n{print $2; exit}')
  [ -n "$size" ] && { echo "$size port.yaml device.partition_sizes"; return; }
  [ -f "$R/by-name.txt" ] && dev=$(awk -v n="$n" '{for (i=1; i<NF; i++) if (tolower($i)==n && $(i+1)=="->") {d=$(i+2); sub(/.*\//,"",d); print d; exit}}' "$R/by-name.txt")
  [ -z "${dev:-}" ] && [ -f "$R/partnames-sysfs.txt" ] && dev=$(awk -v n="$n" 'tolower($2)==n{print $1; exit}' "$R/partnames-sysfs.txt")
  if [ -n "${dev:-}" ] && [ -f "$R/partitions.txt" ]; then
    blocks=$(awk -v d="$dev" '$4==d{print $3; exit}' "$R/partitions.txt")
    [ -n "$blocks" ] && echo "$((blocks * 1024)) dossier/raw/partitions.txt ($dev)"
  fi
}

check_image() { # image partition
  local img=$1 part=${2:-} bsize isize psize src
  [ -f "$img" ] && ok "image exists: $img ($(stat -c %s "$img") bytes)" || { bad "image not found: $img"; return; }
  if [ -z "$part" ] || [[ "$(lower "$part")" =~ ^(boot|recovery|boot_a|boot_b|recovery_a|recovery_b)$ ]]; then
    [ "$(head -c 8 "$img")" = "ANDROID!" ] && ok "Android boot image magic present" || bad "no ANDROID! magic: not a boot image"
  fi
  [ -n "$part" ] || return
  isize=$(stat -c %s "$img")
  read -r psize src <<< "$(partition_size "$part")"
  if [ -n "$psize" ]; then
    [ "$isize" -le "$psize" ] && ok "image fits the partition ($isize <= $psize bytes, from $src)" \
      || bad "image ($isize) larger than the partition ($psize bytes, from $src)"
  elif [ -f "$P/backups/$part.img" ]; then
    bsize=$(stat -c %s "$P/backups/$part.img")
    [ "$isize" -le "$bsize" ] && ok "image fits backups/$part.img ($isize <= $bsize; partition size unknown, valid only if the backup is a full dump)" \
      || bad "image ($isize) larger than backups/$part.img ($bsize) and the partition size is unknown: set device.partition_sizes.$part (bytes) in port.yaml"
  else
    bad "partition size unknown: set device.partition_sizes.$part (bytes) in port.yaml"
  fi
}

check_partition() { # partition
  local part=$1 line
  forbidden "$part" && bad "'$part' is on the forbidden list (tools/lib/forbidden-partitions.txt)" || ok "'$part' is not forbidden"
  cfg safety.writable_partitions | grep -qix "$part" && ok "'$part' is in safety.writable_partitions" \
    || bad "'$part' is not in safety.writable_partitions"
  if [ -f "$P/backups/$part.img" ]; then
    line=$(cd "$P/backups" && grep -E "[ *]$part\.img$" SHA256SUMS 2>/dev/null)
    if [ -n "$line" ] && (cd "$P/backups" && echo "$line" | sha256sum -c --quiet - >/dev/null 2>&1); then
      ok "backup backups/$part.img verifies against SHA256SUMS"
    else
      bad "backup backups/$part.img does not verify against SHA256SUMS"
    fi
  else
    bad "no backup: backups/$part.img"
  fi
}

CMD=()
echo "safe-flash: port=$PORT serial=$SER mode=${MODE:-?} op=$OP $*"
echo "checks:"
case "$OP" in
  boot)
    IMG=${1:?image}
    check_fastboot_device; check_image "$IMG"
    CMD=(fastboot -s "$SER" boot "$IMG") ;;
  flash)
    PART=${1:?partition}; IMG=${2:?image}
    check_partition "$PART"; check_image "$IMG" "$PART"
    if [ "$MODE" = "samsung-download" ]; then
      check_heimdall_device
      CMD=(heimdall flash "--$(echo "$PART" | tr 'a-z' 'A-Z')" "$IMG" --no-reboot)
      [ $RESUME = 1 ] && CMD+=(--resume)
    else
      [ $RESUME = 1 ] && bad "--resume only applies to heimdall (samsung-download mode)"
      check_fastboot_device
      CMD=(fastboot -s "$SER" flash "$PART" "$IMG")
    fi ;;
  unlock)
    how=${1:-flashing}
    [ "$(cfg safety.unbrick_kit_ready)" = "true" ] && ok "unbrick kit ready (M3)" || bad "safety.unbrick_kit_ready is not true (finish M3 first)"
    check_fastboot_device
    if [ "$how" = "oem" ]; then CMD=(fastboot -s "$SER" oem unlock); else CMD=(fastboot -s "$SER" flashing unlock); fi
    echo "  ⚠️  unlocking WIPES ALL USER DATA and may be irreversible (warranty bits, DRM keys)" ;;
  *) echo "unknown op: $OP"; exit 2 ;;
esac

echo "command: ${CMD[*]}"
if [ $fails -gt 0 ]; then
  echo "REFUSED: $fails check(s) failed."; echo "$(date -Is) REFUSED $OP $* ($fails failed)" >> "$LOG"; exit 1
fi
if [ $EXEC = 0 ]; then
  echo "dry run: all checks passed. Re-run with --execute after the user approved this exact command."; exit 0
fi
echo "$(date -Is) EXECUTE ${CMD[*]}" >> "$LOG"
"${CMD[@]}" 2>&1 | tee -a "$LOG"; rc=${PIPESTATUS[0]}
echo "$(date -Is) RESULT rc=$rc" >> "$LOG"
exit $rc
