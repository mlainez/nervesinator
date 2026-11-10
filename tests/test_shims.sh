#!/usr/bin/env bash
# Regression tests for the guard as PATH shims (tools/with-guard.sh), on a scratch copy of the kit
# with fake device programs. Usage: tests/test_shims.sh
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); cp -r "$KIT/hooks" "$KIT/tools" "$T"/; mkdir -p "$T/ports/x/backups" "$T/bin"
echo x > "$T/ports/.active"
printf 'device:\n  serial: "X"\n' > "$T/ports/x/port.yaml"
for p in fastboot adb; do printf '#!/bin/sh\necho "REAL %s $*"\n' "$p" > "$T/bin/$p"; chmod +x "$T/bin/$p"; done
export PATH="$T/bin:$PATH"
fail=0
run() { "$T/tools/with-guard.sh" "$@" 2>&1; }
t() { # label, expected exit code, expected text, command…
  local label=$1 want=$2 text=$3 out rc; shift 3
  out=$(run "$@"); rc=$?
  if [ "$rc" = "$want" ] && echo "$out" | grep -q -- "$text"; then echo "ok   $label"
  else echo "FAIL $label: rc=$rc out=$out"; fail=1; fi
}
approve() { "$T/tools/user-mode.sh" approve; }

t "a read-only command runs"            0   "REAL fastboot -s X getvar all"  fastboot -s X getvar all
t "a RAM boot runs"                     0   "REAL fastboot -s X boot b.img"  fastboot -s X boot b.img
t "a forbidden partition never starts"  126 "DENIED"                         fastboot -s X flash aboot a.img
t "a write waits for the user's yes"    126 "NEEDS THE USER'S YES"           fastboot -s X flash boot b.img
t "a different command stays refused"   126 "NEEDS THE USER'S YES"           fastboot -s X flash recovery r.img
approve | grep -q "flash recovery r.img" && echo "ok   approve names the pending command" || { echo "FAIL approve"; fail=1; }
t "another command is not covered"      126 "NEEDS THE USER'S YES"           fastboot -s X flash boot b.img
approve >/dev/null
t "the approved command runs"           0   "REAL fastboot -s X flash boot b.img" fastboot -s X flash boot b.img
approve >/dev/null 2>&1 && { echo "FAIL approve with nothing pending"; fail=1; } || echo "ok   nothing pending, nothing approved"
t "the approval is used once"           126 "NEEDS THE USER'S YES"           fastboot -s X flash boot b.img
printf 'abc  boot.img\n' > "$T/ports/x/backups/SHA256SUMS"
printf '{"partitions": ["boot"], "no_backup": []}' > "$T/ports/x/.write-allowlist"
t "the write allowlist needs no approval" 0 "REAL fastboot -s X flash boot b.img" fastboot -s X flash boot b.img
t "a compound shell command is covered" 126 "DENIED"                         sh -c 'adb devices; fastboot -s X erase persist'
rm -rf "$T"
exit $fail
