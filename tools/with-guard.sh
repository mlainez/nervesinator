#!/usr/bin/env bash
# Start a coding agent (or a shell) with the device guard in front of every device program, for
# harnesses that have no hook to run it before each command.
# Usage: tools/with-guard.sh <agent command…>      e.g. tools/with-guard.sh codex
#        tools/with-guard.sh bash                  a guarded shell
#
# It puts shims for fastboot, adb, heimdall, odin, edl, mtk, fwup, ssh, scp and mix at the front
# of PATH. Each one asks hooks/device_guard.py about its own command line, then runs the real
# program: denied commands never start, and a command that needs your yes is refused until you run
# `tools/user-mode.sh approve` in your own terminal. Where the harness runs the guard as a hook
# (Claude Code, .claude/settings.json), do not use this: the hook already asks you.
set -uo pipefail
KIT=$(cd "$(dirname "$0")/.." && pwd)
[ $# -ge 1 ] || { sed -n '2,11p' "$0"; exit 2; }
S="$KIT/cache/shims"; mkdir -p "$S"
for p in fastboot adb heimdall odin odin4 edl mtk fwup ssh scp mix; do
  ln -sfn "$KIT/tools/lib/guarded-exec.sh" "$S/$p"
done
export KIT_DIR="$KIT" PATH="$S:$PATH"
exec "$@"
