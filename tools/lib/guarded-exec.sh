#!/usr/bin/env bash
# PATH shim for one device program (fastboot, adb, heimdall…): asks the guard, then runs the real
# program. tools/with-guard.sh links this file under each program's name at the front of PATH, so
# the guard works in any agent harness, hooks or not.
SHIMS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROG=$(basename "$0")
[ -n "${KIT_DIR:-}" ] || { echo "$PROG: started outside tools/with-guard.sh (KIT_DIR is not set)" >&2; exit 126; }
real=""
IFS=: read -ra dirs <<< "$PATH"
for d in "${dirs[@]}"; do
  [ "$d" = "$SHIMS" ] && continue
  [ -x "$d/$PROG" ] && [ ! -d "$d/$PROG" ] && { real="$d/$PROG"; break; }
done
[ -n "$real" ] || { echo "$PROG: command not found" >&2; exit 127; }
python3 -I "$KIT_DIR/hooks/device_guard.py" --shim "$PROG" "$@" >&2 || exit 126
exec "$real" "$@"
