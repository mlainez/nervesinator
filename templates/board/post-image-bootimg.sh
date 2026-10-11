#!/usr/bin/env bash
# Buildroot post-image script: pack the kernel (+ appended DTB) and the initramfs into an Android
# boot.img for this device's bootloader. Copy to board/<id>/post-image.sh and fill the values from
# port.yaml device.bootimg (tools/lib/bootimg_info.py on the stock boot.img prints them).
# Hook it with: BR2_ROOTFS_POST_IMAGE_SCRIPT="$(BR2_EXTERNAL_ANDROID_PATH)/board/<id>/post-image.sh"
set -euo pipefail
BINARIES_DIR=${BINARIES_DIR:?run from Buildroot}

KERNEL=zImage                       # Image.gz on arm64
DTB=REPLACE_ME.dtb                  # BR2_LINUX_KERNEL_INTREE_DTS_NAME basename
CMDLINE="console=tty0 earlycon loglevel=8"
MKBOOTIMG_ARGS="--base 0x00000000 --pagesize 2048 --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 --second_offset 0x00f00000 --tags_offset 0x00000100 --header_version 0"
MKBOOTIMG=${MKBOOTIMG:-mkbootimg}

cat "$BINARIES_DIR/$KERNEL" "$BINARIES_DIR/$DTB" > "$BINARIES_DIR/kernel-dtb"
RAMDISK="$BINARIES_DIR/rootfs.cpio.gz"
[ -f "$RAMDISK" ] || { : | gzip > "$BINARIES_DIR/empty.cpio.gz"; RAMDISK="$BINARIES_DIR/empty.cpio.gz"; }
# shellcheck disable=SC2086
"$MKBOOTIMG" --kernel "$BINARIES_DIR/kernel-dtb" --ramdisk "$RAMDISK" --cmdline "$CMDLINE" \
  $MKBOOTIMG_ARGS -o "$BINARIES_DIR/boot.img"
echo "boot.img: $(stat -c %s "$BINARIES_DIR/boot.img") bytes"
