#!/usr/bin/env bash
# Send a phone running a kit image or the port's Linux back to its flash mode, with no keys.
# Usage: tools/return-to-flash.sh --port <id> [--timeout S]
#
# The target is device.return_mode in port.yaml: `bootloader` (fastboot, stock or second stage) by
# default, `download` where the stock bootloader clears the restart reason before a second stage
# sees it (seen on Samsung with lk2nd; download mode + heimdall stay reachable). The phone runs `reboot-mode <mode>`, and
# `reboot -f` as the last resort. Over the kit gadget's ACM console when present (no login), else
# over ssh to 10.0.42.1 with a short ServerAlive timeout (the session dies mid-command).
# Exit 0 once the flash mode shows up, 1 otherwise.
set -uo pipefail
KIT=$(cd "$(dirname "$0")/.." && pwd)
. "$KIT/tools/lib/kit_gadget.sh"
PORT=""; TIMEOUT=60
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT=$2; shift 2 ;;
    --timeout) TIMEOUT=$2; shift 2 ;;
    *) sed -n '2,11p' "$0"; exit 1 ;;
  esac
done
[ -n "$PORT" ] || { sed -n '2,11p' "$0"; exit 1; }
Y="$KIT/ports/$PORT/port.yaml"
[ -f "$Y" ] || { echo "no such port: $PORT"; exit 1; }
cfg() { python3 -I "$KIT/tools/lib/portcfg.py" "$Y" "$1"; }
SER=$(cfg device.serial); MODE=$(cfg device.return_mode); MODE=${MODE:-bootloader}

in_flash_mode() {
  timeout 5 fastboot devices 2>/dev/null | awk '{print $1}' | grep -qx "$SER" && return 0
  [ "$MODE" = download ] && lsusb 2>/dev/null | grep -q '04e8:685d'
}

tty=$(kit_gadgets | awk -v s="$SER" '$1==s {print $3}' | head -1)
if [ -n "$tty" ] && [ "$tty" != - ]; then
  echo "asking the kit image on $tty: reboot-mode $MODE"
  python3 -I "$KIT/tools/lib/acm_probe.py" "$tty" --timeout 10 --return >/dev/null 2>&1
else
  echo "asking root@10.0.42.1 over ssh: reboot-mode $MODE"
  ssh -o ConnectTimeout=5 -o ServerAliveInterval=2 -o ServerAliveCountMax=2 -o BatchMode=yes \
    root@10.0.42.1 "sync; reboot-mode $MODE || reboot -f" >/dev/null 2>&1
fi

for _ in $(seq 1 $((TIMEOUT / 2))); do
  in_flash_mode && { echo "the phone is in its flash mode ($MODE)"; exit 0; }
  sleep 2
done
echo "the phone did not reach its flash mode within ${TIMEOUT}s: check device.return_mode, the"
echo "reboot-mode DT node and the warm reset (rescue-initramfs: Traps); keys may be needed"
exit 1
