#!/usr/bin/env bash
# Regression tests for the session hooks, on a scratch copy of the kit with a scratch port.
# Usage: tests/test_hooks.sh
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); cp -r "$KIT/hooks" "$KIT/tools" "$T"/; mkdir -p "$T/ports/x"
fail=0
check() { # label, command…
  local label=$1; shift
  if "$@" >/dev/null 2>&1; then echo "ok   $label"; else echo "FAIL $label"; fail=1; fi
}
say() { echo "{\"prompt\": \"$1\"}" | python3 -I "$T/hooks/start_trigger.py"; }

# No active port: the hooks stay silent
[ -z "$(echo '{}' | python3 -I "$T/hooks/session_context.py")" ] && echo "ok   session start is silent without a port" \
  || { echo "FAIL session start without a port"; fail=1; }
check "checkpoint is a no-op without a port" python3 -I "$T/hooks/checkpoint.py"

echo x > "$T/ports/.active"
printf 'device:\n  serial: "X"\n' > "$T/ports/x/port.yaml"
echo '{}' | python3 -I "$T/hooks/session_context.py" | grep -q 'port x: stage S1 Scout' \
  && echo "ok   session start reports the stage" || { echo "FAIL session start context"; fail=1; }

# The user's words set and clear the write allowlist; forbidden names are left out
say "allow writes boot, userdata and aboot no backup userdata" | grep -q 'need an override instead: aboot' \
  && echo "ok   allow writes reports the forbidden name" || { echo "FAIL allow writes message"; fail=1; }
check "allowlist holds boot and userdata" python3 -I -c "
import json; a = json.load(open('$T/ports/x/.write-allowlist'))
assert a['partitions'] == ['boot', 'userdata'] and a['no_backup'] == ['userdata'], a"
say "allow writes off" >/dev/null
check "allow writes off clears it" test ! -e "$T/ports/x/.write-allowlist"

# The checkpoint commits a changed port workspace and nothing else
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.org GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.org
git -C "$T/ports/x" init -q
git -C "$T/ports/x" add -A; git -C "$T/ports/x" commit -q -m init
python3 -I "$T/hooks/checkpoint.py"
[ "$(git -C "$T/ports/x" rev-list --count HEAD)" = 1 ] && echo "ok   a clean port is not committed" \
  || { echo "FAIL clean port committed"; fail=1; }
echo note > "$T/ports/x/dossier.md"
python3 -I "$T/hooks/checkpoint.py"
git -C "$T/ports/x" log -1 --format=%s | grep -q '^Checkpoint: stage S1 Scout' \
  && echo "ok   a changed port is checkpointed" || { echo "FAIL checkpoint commit"; fail=1; }
rm -rf "$T"
exit $fail
