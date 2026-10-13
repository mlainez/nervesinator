#!/usr/bin/env bash
# Build a test initramfs for a port from the prebuilt generic image plus a small device cpio.
# Usage: tools/mk-test-initramfs.sh --port <id> --image rescue|firstlight --arch aarch64|armv7
#                                   [--prebuilt <dir>] [--overlay <dir>]…
#
# The device cpio holds /etc/kit-image filled from port.yaml (port id, device.serial,
# device.return_mode) and the files of each --overlay directory (firmware, modules, panel bits).
# The kernel accepts concatenated cpio archives and the later file wins, so the device cpio is
# appended after the generic one. Writes ports/<id>/output/<image>-initramfs.cpio.gz and prints
# its path and sha256; boot-images packs it with the device's kernel and DTB.
set -uo pipefail
KIT=$(cd "$(dirname "$0")/.." && pwd)
PORT=""; IMAGE=""; ARCH=""; PRE=""; OVERLAYS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT=$2; shift 2 ;;
    --image) IMAGE=$2; shift 2 ;;
    --arch) ARCH=$2; shift 2 ;;
    --prebuilt) PRE=$2; shift 2 ;;
    --overlay) OVERLAYS+=("$2"); shift 2 ;;
    *) sed -n '2,11p' "$0"; exit 2 ;;
  esac
done
[ -n "$PORT" ] && [ -n "$IMAGE" ] && [ -n "$ARCH" ] || { sed -n '2,11p' "$0"; exit 2; }
P="$KIT/ports/$PORT"; Y="$P/port.yaml"
[ -f "$Y" ] || { echo "no such port: $PORT"; exit 1; }
cfg() { python3 -I "$KIT/tools/lib/portcfg.py" "$Y" "$1"; }
if [ -z "$PRE" ]; then
  PRE=$("$KIT/tools/fetch-prebuilt.sh" --arch "$ARCH" | tail -1) || { echo "$PRE"; exit 1; }
fi
BASE="$PRE/$IMAGE-$ARCH.cpio.gz"
[ -f "$BASE" ] || { echo "no $BASE: fetch it (tools/fetch-prebuilt.sh) or import a local build"; exit 1; }

STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/etc"
for o in "${OVERLAYS[@]}"; do cp -a "$o/." "$STAGE/"; done
RETURN=$(cfg device.return_mode); RETURN=${RETURN:-bootloader}
sed -e "s/@ID@/$PORT/" -e "s/@IMAGE@/$IMAGE/" -e "s/@SERIAL@/$(cfg device.serial)/" \
    -e "s/^KIT_RETURN_MODE=.*/KIT_RETURN_MODE=$RETURN/" "$KIT/templates/rescue/kit-image" > "$STAGE/etc/kit-image"

mkdir -p "$P/output"
OUT="$P/output/$IMAGE-initramfs.cpio.gz"
(cd "$STAGE" && find . -mindepth 1 | sort | cpio -o -H newc --owner=0:0 --quiet | gzip -9n) > "$STAGE.device.cpio.gz"
cat "$BASE" "$STAGE.device.cpio.gz" > "$OUT"
rm -f "$STAGE.device.cpio.gz"
echo "$OUT $(sha256sum "$OUT" | cut -d' ' -f1)"
