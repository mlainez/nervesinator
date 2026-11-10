#!/usr/bin/env bash
# Regression tests for tools/safe-flash.sh on a scratch copy of the kit, with a fake fastboot that
# answers like a phone in fastboot mode. Usage: tests/test_safe_flash.sh
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); cp -r "$KIT/hooks" "$KIT/tools" "$T"/
P="$T/ports/x"; mkdir -p "$P/backups" "$P/dossier" "$T/bin"
echo x > "$T/ports/.active"
cat > "$P/port.yaml" <<'EOF'
device:
  serial: "X"
  product: "testphone"
  flash_mode: "fastboot"
  partition_sizes:
    boot: 16777216
    userdata: 1073741824
gates_passed: [G1]
EOF
cat > "$T/bin/fastboot" <<'EOF'
#!/bin/sh
# A phone with serial X and product "testphone" in fastboot mode
case "$*" in
  devices) echo "${FAKE_SERIAL-X}	fastboot" ;;
  *"getvar product") echo "product: testphone" >&2 ;;
  *getvar*) echo "getvar: unknown" >&2 ;;
  *) echo "FLASHED $*" ;;
esac
EOF
chmod +x "$T/bin/fastboot"
export PATH="$T/bin:$PATH"
{ printf 'ANDROID!'; head -c 4088 /dev/zero; } > "$T/new-boot.img"
head -c 8192 /dev/urandom > "$P/backups/boot.img"
(cd "$P/backups" && sha256sum boot.img > SHA256SUMS)
echo plan > "$P/dossier/unbrick.md"
fail=0
t() { # label, expected exit code, expected text, safe-flash arguments…
  local label=$1 want=$2 text=$3 out rc; shift 3
  out=$("$T/tools/safe-flash.sh" --port x "$@" 2>&1); rc=$?
  if [ "$rc" = "$want" ] && echo "$out" | grep -q -- "$text"; then echo "ok   $label"
  else echo "FAIL $label: rc=$rc"; echo "$out" | tail -6; fail=1; fi
}

t "not allowlisted: refused"             1 "not in the user's write allowlist"  flash boot "$T/new-boot.img"
printf '{"partitions": ["boot", "userdata"], "no_backup": ["userdata"]}' > "$P/.write-allowlist"
t "allowlisted, backed up: dry run passes" 0 "dry run: all checks passed"       flash boot "$T/new-boot.img"
t "the dry run names the exact command"  0 "command: fastboot -s X flash boot"  flash boot "$T/new-boot.img"
t "--execute runs the flash"             0 "FLASHED -s X flash boot"            --execute flash boot "$T/new-boot.img"
t "a RAM boot passes its checks"         0 "dry run: all checks passed"         boot "$T/new-boot.img"
t "a forbidden partition is refused"     1 "is on the forbidden list"           flash aboot "$T/new-boot.img"
t "an image without the boot magic is refused" 1 "no ANDROID! magic"            flash boot "$P/backups/boot.img"
t "userdata without a backup: its loss was accepted" 0 "the user accepted its loss" flash userdata "$T/new-boot.img"
head -c 100 /dev/urandom > "$P/backups/boot.img"
t "a backup that no longer verifies is refused" 1 "does not verify against SHA256SUMS" flash boot "$T/new-boot.img"
(cd "$P/backups" && sha256sum boot.img > SHA256SUMS)
head -c 17000000 /dev/zero > "$T/big.img"; printf 'ANDROID!' | dd of="$T/big.img" conv=notrunc status=none
t "an image larger than the partition is refused" 1 "larger than the partition" flash boot "$T/big.img"
export FAKE_SERIAL=OTHER
t "another phone attached: refused, without hanging" 1 "not in fastboot mode"   flash boot "$T/new-boot.img"
unset FAKE_SERIAL
t "unlock: its checks pass with the kit and G1" 0 "dry run: all checks passed"  unlock
sed -i 's/gates_passed: \[G1\]/gates_passed: []/' "$P/port.yaml"
t "unlock before gate G1 is refused"     1 "gate G1 not passed"                 unlock
rm -rf "$T"
exit $fail
