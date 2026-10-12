#!/usr/bin/env bash
#
# host-check-fwup.sh [work-dir]
#
# Exercises a Nerves system's fwup.conf and fwup-ops.conf on files, without the device:
#
#   1. builds .fw archives of three versions from the real images in $BINARIES_DIR (a Buildroot
#      images directory), or from stand-ins;
#   2. runs `complete` into an image file, the way `mix firmware.image` does, and copies it to the
#      start of a sparse file the size of the target partition;
#   3. checks the nested MBR, the U-Boot-format environment, the boot slots (when they are FAT) and
#      the squashfs;
#   4. runs upgrade, status, revert, validate, prevent-revert and factory-reset and checks each
#      result, and that nothing is written past the layout (a vendor tail stays untouched).
#
# Copy it to <nerves_system>/scripts/ with host-check-fwup.conf next to fwup.conf (see
# templates/nerves/host-check-fwup.conf). Needs: fwup, mksquashfs, unsquashfs, mtools, sfdisk,
# python3. With an asdf-managed fwup, select a version (.tool-versions or ASDF_FWUP_VERSION).

set -euo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
. "$HERE/host-check-fwup.conf"
LIMIT_BLOCKS=${LIMIT_BLOCKS:-$TARGET_BLOCKS}
MARGIN_BLOCKS=${MARGIN_BLOCKS:-2048}
ENV_OFFSET=${ENV_OFFSET:-2048}
ENV_BYTES=${ENV_BYTES:-8192}
BOOT_FS=${BOOT_FS:-none}
WORK=${1:-$(mktemp -d /tmp/fwup-check.XXXXXX)}
mkdir -p "$WORK"
cd "$WORK"

pass=0
check() {
    local what=$1; shift
    if "$@"; then
        echo "PASS  $what"
        pass=$((pass + 1))
    else
        echo "FAIL  $what" >&2
        exit 1
    fi
}

# --enable-trim matches how nerves_runtime calls ops.fw.
fwup_ops() {
    fwup -q -U --enable-trim -a -i ops.fw -t "$1" -d target.img 2>&1
}

# The last info() line a task printed, e.g. "a" for status.
ops_info() {
    fwup_ops "$1" | sed -n 's/^fwup: //p' | grep -v '^ignoring --enable-trim' | tail -1
}

# --- system images ----------------------------------------------------------------------
mkdir -p system/images/extlinux
export NERVES_SYSTEM=$WORK/system
export NERVES_SDK_IMAGES=$HERE

if [ -n "${BINARIES_DIR:-}" ]; then
    for f in $BOOT_FILES rootfs.squashfs; do
        cp "$BINARIES_DIR/$f" "system/images/$f"
    done
    [ -f "$BINARIES_DIR/extlinux/extlinux.conf" ] && cp "$BINARIES_DIR/extlinux/extlinux.conf" system/images/extlinux/
else
    for f in $BOOT_FILES; do
        head -c $((1024 * 1024)) /dev/urandom > "system/images/$f"
    done
    [ -f "$HERE/extlinux/extlinux.conf" ] && cp "$HERE/extlinux/extlinux.conf" system/images/extlinux/
    mkdir -p rootfs/srv/erlang
    echo "stand-in" > rootfs/srv/erlang/README
    mksquashfs rootfs system/images/rootfs.squashfs -comp gzip -noappend -quiet
fi

NERVES_SDK_VERSION=0.0.1 fwup -c -f "$HERE/fwup.conf" -o v1.fw
NERVES_SDK_VERSION=0.0.2 fwup -c -f "$HERE/fwup.conf" -o v2.fw
NERVES_SDK_VERSION=0.0.3 fwup -c -f "$HERE/fwup.conf" -o v3.fw
fwup -c -f "$HERE/fwup-ops.conf" -o ops.fw
check "fwup.conf and fwup-ops.conf compile" true

# --- complete, as mix firmware.image + a raw write to the target partition --------------
rm -f nerves.img
fwup -q -a -i v1.fw -t complete -d nerves.img
img_bytes=$(stat -c %s nerves.img)
echo "image: $img_bytes bytes ($((img_bytes / 1024 / 1024)) MiB)"
check "the image ends before the usable end of the partition" \
    test $((img_bytes / 512)) -lt "$LIMIT_BLOCKS"
check "the layout ends before the usable end, with a margin" \
    test $((APP + APP_COUNT)) -le $((LIMIT_BLOCKS - MARGIN_BLOCKS))
truncate -s $((TARGET_BLOCKS * 512)) target.img
dd if=nerves.img of=target.img conv=notrunc,sparse bs=1M status=none

# Prints "partN start size type bootflag" for each MBR entry, then the env.
inspect() {
    python3 -I - "$1" "$ENV_OFFSET" "$ENV_BYTES" <<'PY'
import struct, sys, zlib
path, env_offset, env_bytes = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
with open(path, "rb") as f:
    mbr = f.read(512)
    f.seek(env_offset * 512)
    env = f.read(env_bytes)
assert mbr[510:512] == b"\x55\xaa", "no MBR signature"
for i in range(4):
    e = mbr[446 + 16 * i: 446 + 16 * (i + 1)]
    status, ptype = e[0], e[4]
    start, size = struct.unpack("<II", e[8:16])
    print(f"part{i} {start} {size} {ptype:#x} {status:#x}")
crc = struct.unpack("<I", env[:4])[0]
data = env[4:]
assert zlib.crc32(data) & 0xffffffff == crc, "env CRC mismatch"
for kv in data.split(b"\0"):
    if not kv:
        break
    print("env " + kv.decode())
PY
}

part() { inspect target.img | awk -v p="part$1" '$1 == p {print $2, $3}'; }
env_get() { inspect target.img | sed -n "s/^env $1=//p"; }
# The slot at $1 starts with 0xff bytes, as raw_memset leaves it.
scrubbed() { dd if=target.img bs=512 skip="$1" count=1 status=none | od -An -tx1 | head -1 | grep -q '^ ff ff'; }
# Nothing but zeros (the sparse holes) from block $1 to the end.
zero_from() {
    python3 -I -c 'import sys
f = open(sys.argv[1], "rb"); f.seek(int(sys.argv[2]) * 512)
while True:
    b = f.read(1 << 20)
    if not b: sys.exit(0)
    if b.strip(b"\0"): sys.exit(1)' target.img "$1"
}
# Reads a file from the FAT boot slot that nested partition 1 points to.
boot_cat() {
    local start count
    read -r start count < <(part 0)
    dd if=target.img of=boot.vfat bs=512 skip="$start" count="$count" status=none
    mtype -i boot.vfat "::$1"
}
boot_has() { boot_cat /extlinux/extlinux.conf | grep -q -- "$1"; }
boot_file_matches() { boot_cat "/$1" | cmp -s - "system/images/$1"; }

if [ "$BOOT_FS" = fat ]; then
    check "MBR slot A: boot $BOOT_A+$BOOT_COUNT, rootfs $ROOTFS_A+$ROOTFS_COUNT" \
        test "$(part 0)/$(part 1)" = "$BOOT_A $BOOT_COUNT/$ROOTFS_A $ROOTFS_COUNT"
    check "MBR app partition $APP+$APP_COUNT" test "$(part 2)" = "$APP $APP_COUNT"
else
    check "MBR slot A: rootfs $ROOTFS_A+$ROOTFS_COUNT" test "$(part 1)" = "$ROOTFS_A $ROOTFS_COUNT"
fi
check "env nerves_fw_active=a" test "$(env_get nerves_fw_active)" = a
check "env a.nerves_fw_version=0.0.1" test "$(env_get a.nerves_fw_version)" = 0.0.1
check "env a.nerves_fw_validated=1" test "$(env_get a.nerves_fw_validated)" = 1
check "env nerves_fw_devpath=$DEVPATH" test "$(env_get nerves_fw_devpath)" = "$DEVPATH"
check "env app devpath $APP_DEVPATH" \
    test "$(env_get a.nerves_fw_application_part0_devpath)" = "$APP_DEVPATH"
if [ "$BOOT_FS" = fat ]; then
    check "boot slot A extlinux.conf points at rootfs A" boot_has "$BOOT_A_MARKER"
    for f in $BOOT_FILES; do
        check "boot slot A $f matches the build" boot_file_matches "$f"
    done
    check "boot slot B is scrubbed" scrubbed "$BOOT_B"
fi
check "rootfs B is scrubbed" scrubbed "$ROOTFS_B"

dd if=target.img of=rootfs.img bs=512 skip="$ROOTFS_A" count="$ROOTFS_COUNT" status=none
check "rootfs A is a squashfs" sh -c 'unsquashfs -s rootfs.img >/dev/null 2>&1'
rm -f rootfs.img
check "sfdisk reads the nested MBR" sh -c "sfdisk -d target.img | grep -q 'start='"

check "status says a" test "$(ops_info status)" = a
check "revert refused with nothing to revert to" \
    sh -c '! fwup -q -U -a -i ops.fw -t revert -d target.img 2>/dev/null'

# --- upgrade to B -----------------------------------------------------------------------
fwup -q -U -a -i v2.fw -t upgrade -d target.img
check "upgrade wrote slot B into the MBR" test "$(part 1)" = "$ROOTFS_B $ROOTFS_COUNT"
check "app partition unchanged" test "$(part 2)" = "$APP $APP_COUNT"
check "env active=b, b version 0.0.2, b not yet validated" \
    test "$(env_get nerves_fw_active)/$(env_get b.nerves_fw_version)/$(env_get b.nerves_fw_validated)" = "b/0.0.2/0"
check "slot A metadata kept for revert" test "$(env_get a.nerves_fw_version)" = 0.0.1
if [ "$BOOT_FS" = fat ]; then
    check "boot slot B extlinux.conf points at rootfs B" boot_has "$BOOT_B_MARKER"
fi
check "status says b" test "$(ops_info status)" = b
fwup_ops validate >/dev/null
check "validate sets b.nerves_fw_validated" test "$(env_get b.nerves_fw_validated)" = 1

# --- revert to A and back ---------------------------------------------------------------
fwup_ops revert >/dev/null
check "revert switched MBR and env to A" \
    test "$(part 1)/$(env_get nerves_fw_active)" = "$ROOTFS_A $ROOTFS_COUNT/a"
fwup_ops revert >/dev/null
check "revert again goes back to B" \
    test "$(part 1)/$(env_get nerves_fw_active)" = "$ROOTFS_B $ROOTFS_COUNT/b"

# --- upgrade from B back to A -----------------------------------------------------------
fwup -q -U -a -i v3.fw -t upgrade -d target.img
check "second upgrade lands in A" \
    test "$(part 1)/$(env_get nerves_fw_active)/$(env_get a.nerves_fw_version)" = "$ROOTFS_A $ROOTFS_COUNT/a/0.0.3"

# --- prevent-revert, factory-reset ------------------------------------------------------
fwup_ops prevent-revert >/dev/null
check "prevent-revert removes b platform" test -z "$(env_get b.nerves_fw_platform)"
check "revert refused after prevent-revert" \
    sh -c '! fwup -q -U -a -i ops.fw -t revert -d target.img 2>/dev/null'
fwup_ops factory-reset >/dev/null
check "factory-reset erases the start of the app partition" scrubbed "$APP"
check "nothing written past the layout (margin and any vendor tail untouched)" zero_from $((APP + APP_COUNT))

echo "$pass checks passed in $WORK"
