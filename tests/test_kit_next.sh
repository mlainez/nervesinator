#!/usr/bin/env bash
# Regression tests for tools/lib/kit_next.py: the next step follows the evidence on disk.
# Usage: tests/test_kit_next.sh
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd)
N="$KIT/tools/lib/kit_next.py"
P=$(mktemp -d); D="$P/x"; mkdir -p "$D/dossier/raw" "$D/backups/stock" "$D/journal/boots"
echo x > "$P/.active"
fail=0
ready() { python3 -I "$N" --ports "$P" --json | python3 -I -c 'import json,sys; s=json.load(sys.stdin); print(s["stage"], ",".join(s["ready"]))'; }
t() { # expected "stage ready-ids", label
  got=$(ready)
  if [ "$got" != "$1" ]; then echo "FAIL want='$1' got='$got' :: $2"; fail=1; else echo "ok   $2: $1"; fi
}
yaml() { cat > "$D/port.yaml"; }

yaml <<'Y'
device:
  serial: "X"
gates_passed: []
Y
t "S1 recon" "empty port"

echo f > "$D/dossier/device.md"; echo f > "$D/dossier/partitions.md"
yaml <<'Y'
device:
  serial: "X"
  soc: "qcom msm8916"
  arch: "armv7"
  flash_mode: "fastboot"
  product: "p"
gates_passed: []
Y
t "S1 prior-art,reference,unbrick,unlock-plan" "after recon the scout steps are independent"

echo f > "$D/dossier/prior-art.md"; echo f > "$D/dossier/unbrick.md"; echo f > "$D/dossier/unlock.md"
echo f > "$D/backups/stock/firmware.zip"
yaml <<'Y'
device:
  serial: "X"
  soc: "qcom msm8916"
  arch: "armv7"
  flash_mode: "fastboot"
  product: "p"
  return_mode: "bootloader"
gates_passed: []
path:
  kernel_repo: "https://example.org/linux"
  bootloader: "lk2nd"
  reference_system: "none"
Y
t "S1 G1" "scout complete: the first gate"

sed -i 's/^gates_passed: \[\]/gates_passed: [G1]/' "$D/port.yaml"
t "S2 unlock,system" "after G1: unlock, and the Nerves scaffold on the host"

cat >> "$D/port.yaml" <<'Y'
safety:
  bootloader_unlocked: yes
  backups_verified: true
  ram_boot: lk2nd
Y
echo "abc  boot.img" > "$D/backups/SHA256SUMS"
t "S2 G2,system" "backups verified: the write allowlist gate"

printf '{"partitions": ["boot", "userdata"], "no_backup": ["userdata"]}' > "$D/.write-allowlist"
t "S3 boot-path,system" "allowlist typed: boot path"

sed -i 's|^  reference_system: "none"|  reference_system: "none"\n  boot_method: "fastboot boot"|' "$D/port.yaml"
mkdir -p "$D/journal/boots/20260101-000000-firstlight"
echo '{"result": "FAIL"}' > "$D/journal/boots/20260101-000000-firstlight/result.json"
t "S3 first-light,system" "a FAIL record is not first light"
mkdir -p "$D/journal/boots/20260101-000100-firstlight" "$D/journal/boots/20260101-000200-rescue"
echo '{"result": "PASS"}' > "$D/journal/boots/20260101-000100-firstlight/result.json"
echo '{"result": "PASS"}' > "$D/journal/boots/20260101-000200-rescue/result.json"
t "S3 inventory,system" "PASS records: inventory"

out=$(python3 -I "$N" --ports "$P"); echo "$out" | grep -q "^port x: stage S3 Boot from RAM" || { echo "FAIL text header: $out"; fail=1; }
python3 -I "$N" --ports "$P/none" >/dev/null; [ $? = 1 ] || { echo "FAIL: no active port should exit 1"; fail=1; }
rm -r "$P"
exit $fail
