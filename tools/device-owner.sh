#!/usr/bin/env bash
# Record which agent works on the port's device, so only one does at a time.
# Usage:
#   tools/device-owner.sh --port <id> show
#   tools/device-owner.sh --port <id> claim <agent> <purpose…>   refuses while another agent owns it
#   tools/device-owner.sh --port <id> release <agent>
# The record is ports/<id>/.device-owner. The orchestrator hands the device over; agents claim it
# before any device command and release it when they report, saying what state they left it in.
set -uo pipefail
KIT=$(cd "$(dirname "$0")/.." && pwd)
[ "${1:-}" = --port ] && [ -n "${2:-}" ] || { sed -n '2,8p' "$0"; exit 2; }
P="$KIT/ports/$2"; shift 2
[ -d "$P" ] || { echo "no such port: $P"; exit 2; }
F="$P/.device-owner"
owner() { [ -f "$F" ] && sed -n 's/^agent: //p' "$F"; }

case "${1:-show}" in
  show)
    [ -f "$F" ] && cat "$F" || echo "free" ;;
  claim)
    agent=${2:?agent}; shift 2; purpose=${*:-unspecified}
    cur=$(owner)
    if [ -n "$cur" ] && [ "$cur" != "$agent" ]; then
      echo "the device is owned by $cur:"; cat "$F"; exit 1
    fi
    printf 'agent: %s\nsince: %s\npurpose: %s\n' "$agent" "$(date -Is)" "$purpose" > "$F"
    echo "$agent owns the device" ;;
  release)
    agent=${2:?agent}; cur=$(owner)
    if [ -n "$cur" ] && [ "$cur" != "$agent" ]; then
      echo "$agent does not own the device ($cur does)"; exit 1
    fi
    rm -f "$F"; echo "device released by $agent" ;;
  *) sed -n '2,8p' "$0"; exit 2 ;;
esac
