#!/usr/bin/env bash
# Boot a test image from RAM and judge the result from the host, with nobody at the phone.
# Usage:
#   tools/await-boot.sh --port <id> --image <img> [--stage <name>] [--timeout S] [--return]
#   tools/await-boot.sh --port <id> --watch-only [--stage <name>] [--timeout S] [--return]
#
# Without --watch-only it runs `tools/safe-flash.sh --execute boot <img>` (RAM only, every dry-run
# check first). --watch-only judges a boot started otherwise (after a flash and a reboot).
# Then it watches USB until one of:
#   PASS     the kit gadget with this port's serial shows up and its console says KIT-READY  (exit 0)
#   FAIL     the phone is back in fastboot / download mode, or in Android/recovery            (exit 1)
#   HUNG     nothing within the timeout: needs a human (force power off, battery pull)        (exit 2)
#   REFUSED  safe-flash refused the image in its dry run                                      (exit 3)
# --return sends a passing image back to its flash mode over the console (reboot-mode).
# Results: ports/<id>/journal/boots/<time>-<stage>/ (result.json, result.md, logs).
set -uo pipefail
KIT=$(cd "$(dirname "$0")/.." && pwd)
. "$KIT/tools/lib/kit_gadget.sh"
PORT=""; IMG=""; STAGE=test; TIMEOUT=120; WATCH=0; RETURN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT=$2; shift 2 ;;
    --image) IMG=$2; shift 2 ;;
    --stage) STAGE=$2; shift 2 ;;
    --timeout) TIMEOUT=$2; shift 2 ;;
    --watch-only) WATCH=1; shift ;;
    --return) RETURN=1; shift ;;
    *) sed -n '2,16p' "$0"; exit 3 ;;
  esac
done
[ -n "$PORT" ] && { [ -n "$IMG" ] || [ $WATCH = 1 ]; } || { sed -n '2,16p' "$0"; exit 3; }
P="$KIT/ports/$PORT"; Y="$P/port.yaml"
[ -f "$Y" ] || { echo "no such port: $P"; exit 3; }
SER=$(python3 -I "$KIT/tools/lib/portcfg.py" "$Y" device.serial)
OUT="$P/journal/boots/$(date +%Y%m%d-%H%M%S)-$STAGE"; mkdir -p "$OUT"

finish() { # result exit-code detail
  local tty_log=""
  [ -s "$OUT/console.txt" ] && tty_log="console.txt"
  python3 -I - "$OUT" "$1" "$3" "$STAGE" "${IMG:-}" "$SECONDS" "$tty_log" <<'EOF'
import json, sys
out, result, detail, stage, img, secs, console = sys.argv[1:8]
lines = open(out + "/" + console, errors="replace").read().splitlines() if console else []
battery = [l.split(" ", 1)[1] for l in lines if l.startswith("KIT-BATTERY-NOW ")] or \
          [l.split(" ", 1)[1] for l in lines if l.startswith("KIT-BATTERY ")]
r = {"result": result, "detail": detail, "stage": stage, "image": img, "seconds": int(secs),
     "console": console or None, "battery": battery}
json.dump(r, open(out + "/result.json", "w"), indent=2)
with open(out + "/result.md", "w") as f:
    f.write("# Boot %s: %s\n\n%s\n\nImage: `%s`, %s s.%s\n" % (
        stage, result, detail, img or "(watch only)", secs,
        "\nConsole transcript: `console.txt`." if console else ""))
    if battery:
        f.write("\nPower supplies:\n\n" + "".join("- `%s`\n" % b for b in battery))
EOF
  echo "$1: $3"
  echo "record: $OUT/result.md"
  exit "$2"
}

lk2nd_log() { # read-only: lk2nd's own log, when lk2nd is running
  fastboot -s "$SER" getvar lk2nd:version 2>&1 | grep -q '^lk2nd:version:' || return
  fastboot -s "$SER" oem log >/dev/null 2>&1 && fastboot -s "$SER" get_staged "$OUT/lk2nd-oem-log.txt" >/dev/null 2>&1
}

in_fastboot() { timeout 5 fastboot devices 2>/dev/null | awk '{print $1}' | grep -qx "$SER"; }
in_download() { lsusb 2>/dev/null | grep -q '04e8:685d'; }
in_android() { adb devices 2>/dev/null | awk -v s="$SER" '$1==s && ($2=="device" || $2=="recovery"){f=1} END{exit !f}'; }

SECONDS=0
if [ $WATCH = 0 ]; then
  "$KIT/tools/safe-flash.sh" --port "$PORT" --execute boot "$IMG" > "$OUT/safe-flash.log" 2>&1; rc=$?
  cat "$OUT/safe-flash.log"
  grep -q '^REFUSED:' "$OUT/safe-flash.log" && finish REFUSED 3 "safe-flash refused the image (see safe-flash.log)"
  [ $rc = 0 ] || { lk2nd_log; finish FAIL 1 "the boot command failed (rc=$rc), see safe-flash.log and lk2nd-oem-log.txt"; }
fi

# The phone leaves the flash mode after the boot command; only a later return counts as a failure
left=$WATCH; ready_wait=0
while [ $SECONDS -lt "$TIMEOUT" ]; do
  gadget=$(kit_gadgets | awk -v s="$SER" '$1==s' | head -1)
  if [ -n "$gadget" ]; then
    left=1
    read -r _ prod tty net <<< "$gadget"
    if [ "$tty" != - ]; then
      args=("$tty" --timeout 20); [ $RETURN = 1 ] && args+=(--return)
      if python3 -I "$KIT/tools/lib/acm_probe.py" "${args[@]}" > "$OUT/console.txt" 2>&1; then
        detail="$prod answered on $tty (net: $net): $(grep -m1 '^KIT-READY' "$OUT/console.txt")"
        if [ $RETURN = 1 ]; then
          for _ in $(seq 1 30); do in_fastboot || in_download && break; sleep 2; done
          if in_fastboot || in_download; then detail+="; returned to the flash mode"
          else detail+="; did NOT return to the flash mode within 60 s"; fi
        fi
        finish PASS 0 "$detail"
      fi
    fi
    ready_wait=$((ready_wait + 1))
    [ $ready_wait -ge 15 ] && finish PASS 0 "$prod enumerated (net: $net) but its console gave no KIT-READY: check console.txt"
  elif in_fastboot || in_download; then
    if [ $left = 1 ]; then
      lk2nd_log
      finish FAIL 1 "the phone came back to its flash mode: the image crashed or rebooted (lk2nd-oem-log.txt, pstore on the next good boot)"
    fi
  else
    left=1
    in_android && finish FAIL 1 "the phone booted Android or recovery instead of the test image"
  fi
  sleep 2
done
[ $left = 1 ] || finish FAIL 1 "the phone never left its flash mode"
finish HUNG 2 "nothing within ${TIMEOUT}s: the phone needs a human (force power off: device.modes in port.yaml, or a battery pull)"
