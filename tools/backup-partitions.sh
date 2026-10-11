#!/usr/bin/env bash
# Dump device partitions over adb into ports/<id>/backups/, verifying each one by comparing the
# sha256 computed on the device with the sha256 of the local copy. Read-only on the device.
#
# Usage: tools/backup-partitions.sh --port <id> --method root|recovery [--only a,b,c] [--include-large]
#   root      Android running, already rooted (su)
#   recovery  a recovery booted from RAM (adb runs as root there)
# Default skips large reproducible/personal partitions: userdata system super vendor product
# system_ext odm cache. Existing backups are never overwritten (they are re-verified instead).
set -uo pipefail
KIT=$(cd "$(dirname "$0")/.." && pwd)
PORT=""; METHOD=""; ONLY=""; LARGE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT=$2; shift 2 ;;
    --method) METHOD=$2; shift 2 ;;
    --only) ONLY=$2; shift 2 ;;
    --include-large) LARGE=1; shift ;;
    *) sed -n '2,11p' "$0"; exit 2 ;;
  esac
done
[ -n "$PORT" ] && [[ "$METHOD" =~ ^(root|recovery)$ ]] || { sed -n '2,11p' "$0"; exit 2; }
P="$KIT/ports/$PORT"; B="$P/backups"; mkdir -p "$B"
SER=$(python3 -I "$KIT/tools/lib/portcfg.py" "$P/port.yaml" device.serial)
if [ "$METHOD" = root ]; then R() { adb -s "$SER" shell "su -c '$1'" | tr -d '\r'; }; X() { adb -s "$SER" exec-out "su -c 'cat $1'"; }
else R() { adb -s "$SER" shell "$1" | tr -d '\r'; }; X() { adb -s "$SER" exec-out "cat $1"; }; fi

[ "$(R id | grep -o 'uid=0')" = "uid=0" ] || { echo "no root shell on $SER with method '$METHOD'"; exit 1; }
DIR=$(R 'for d in /dev/block/by-name /dev/block/bootdevice/by-name /dev/block/platform/*/by-name /dev/block/platform/*/*/by-name; do [ -d $d ] && echo $d && break; done')
[ -n "$DIR" ] || { echo "cannot find a by-name directory on the device"; exit 1; }
NAMES=$(R "ls $DIR")
SKIP="userdata system super vendor product system_ext odm cache"
# Irreplaceable data first
FIRST="efs modemst1 modemst2 fsg fsc persist nvram nvdata proinfo ta param devinfo sec_efs cpefs"
ordered=$( (for n in $FIRST; do echo "$NAMES" | grep -x "$n"; done; echo "$NAMES") | awk '!seen[$0]++')
[ -n "$ONLY" ] && ordered=$(echo "$ONLY" | tr ',' '\n')

echo "device $SER, partitions in $DIR, method $METHOD"
failed=0
for n in $ordered; do
  [ -z "$n" ] && continue
  if [ $LARGE = 0 ] && [ -z "$ONLY" ] && echo " $SKIP " | grep -q " $n "; then echo "skip  $n (large/reproducible)"; continue; fi
  dev="$DIR/$n"
  remote=$(R "sha256sum $dev" | awk '{print $1}')
  [ -n "$remote" ] || { echo "FAIL  $n (cannot hash on device)"; failed=1; continue; }
  if [ -f "$B/$n.img" ]; then
    local_sum=$(sha256sum "$B/$n.img" | awk '{print $1}')
    [ "$local_sum" = "$remote" ] && echo "ok    $n (already backed up, verified)" || { echo "DIFF  $n: existing backup differs from the device (kept untouched; investigate)"; failed=1; }
    continue
  fi
  X "$dev" > "$B/$n.img.part"
  local_sum=$(sha256sum "$B/$n.img.part" | awk '{print $1}')
  if [ "$local_sum" = "$remote" ]; then
    mv "$B/$n.img.part" "$B/$n.img"
    echo "$local_sum  $n.img" >> "$B/SHA256SUMS"
    echo "ok    $n ($(stat -c %s "$B/$n.img") bytes)"
  else
    echo "FAIL  $n (hash mismatch, partial file kept as $n.img.part)"; failed=1
  fi
done
echo "verify all: (cd $B && sha256sum -c SHA256SUMS)"
(cd "$B" && sha256sum -c --quiet SHA256SUMS) && echo "SHA256SUMS verifies" || failed=1
exit $failed
