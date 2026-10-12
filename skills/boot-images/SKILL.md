---
name: boot-images
description: Building and testing bootable images for Android bootloaders - Android boot image headers v0-v4, mkbootimg arguments from the stock image or pmaports deviceinfo, zImage/Image.gz with appended DTB, QCDT dt.img, Samsung footers, lk2nd extlinux.conf, and the RAM-first test procedure (fastboot boot, lk2nd, experiment partition). Use in M6-M9 when packing a kernel for the device.
---

# Boot images

## 1. Know the target format

Take the facts from, in order of trust:
1. The stock `boot.img` (from the M5 backup): `python3 -I tools/lib/bootimg_info.py backups/boot.img`
2. pmaports `deviceinfo`: `deviceinfo_flash_offset_base/kernel/ramdisk/second/tags`,
   `deviceinfo_flash_pagesize`, `deviceinfo_header_version`, `deviceinfo_append_dtb`,
   `deviceinfo_bootimg_qcdt`, `deviceinfo_bootimg_mtk_mkimage`, `deviceinfo_bootimg_dtb_second`.
3. The second-stage bootloader's own expectations (lk2nd: a v0 image with an appended DTB, or
   extlinux; a QCDT only when its ids are the standard Qualcomm ones, see section 3).

Record the result under `device.bootimg` in `port.yaml`.

## 2. Pack

Host tool: `mkbootimg` (AOSP python script; `pip install --user mkbootimg` or Buildroot `host-android-tools`,
or the copy in `buildroot-android/board/tb3_710f/scripts/mkbootimg.py`).

```bash
# 32-bit ARM, appended DTB (most common for old Qualcomm/MediaTek with stock LK)
cat zImage board.dtb > zImage-dtb
mkbootimg --kernel zImage-dtb --ramdisk initramfs.cpio.gz \
  --cmdline "console=tty0 earlycon PMOS_NO_OUTPUT_REDIRECT" \
  <args from bootimg_info: --base --pagesize --kernel_offset --ramdisk_offset --second_offset --tags_offset --header_version> \
  -o boot.img
# arm64: Image.gz + appended DTB works on many LK-based loaders: cat Image.gz board.dtb > Image.gz-dtb
# QCDT: build dt.img with dtbTool (pmOS pmb:dtbtool) and pass --dt dt.img (old mkbootimg forks) or use lk2nd instead
# MediaTek: some LKs want the kernel/ramdisk wrapped with a 512-byte "KERNEL"/"ROOTFS" header (mtk mkimage)
# Samsung: append "SEANDROIDENFORCE" to hide the warning (optional, cosmetic)
```

Check the image fits: `stat -c %s boot.img` ≤ partition size (`dossier/partitions.md`).

In Buildroot, do it in a post-image script (`board/<id>/post-image.sh`) so the build outputs
`boot.img` directly, as `buildroot-android/board/tb3_710f/scripts/create_boot_image.sh` does.

## 3. lk2nd + extlinux (Qualcomm)

lk2nd scans every leaf partition of 16 MiB or more (and its own `boot`) for `/extlinux/extlinux.conf`
and reads it with LK's **ext2** driver, which refuses any `ro_compat` feature other than
`sparse_super` and `large_file` (lk2nd `lib/fs/ext2/ext2.c`). So the filesystem must be real ext2:
`mkfs.ext2`/`genext2fs` or Buildroot `BR2_TARGET_ROOTFS_EXT2_2r1=y`, never ext4 features
(`huge_file`, `dir_nlink`, `extra_isize`, `metadata_csum`, `extents`); check with `dumpe2fs -h`.
Stock ext4 partitions are skipped, which is why the image is flashed whole.

The kit's recommended layout is one such ext2 image flashed to `userdata` (see decisions.md):

```
timeout 1
default buildroot
menu title lk2nd boot menu

label buildroot
    kernel /boot/zImage
    fdt /boot/qcom-<soc>-<vendor>-<codename>.dtb
    initrd /boot/initramfs        # optional
    append console=tty0 root=PARTLABEL=userdata rootwait rw   # match the GPT name's case (USERDATA on Samsung), or root=/dev/mmcblk0pNN
```

This is how buildroot-android boots the Fairphone 2 (`board/fairphone2/overlay/extlinux/extlinux.conf`).
For RAM tests through lk2nd: `fastboot -s <serial> boot boot.img` works like on a stock fastboot,
with an appended DTB (mainline style, as pmaports does for lk2nd devices). lk2nd picks a QCDT entry
by the SMEM ids (chip, platform, subtype); vendor-encoded ids only match the vendor's aboot. A stock
Samsung `boot.img` (QCDT ids like `<0xdd08ff01 4 0x20000>`) therefore fails with "dtb not found"
(lk2nd log: "Unable to find suitable device tree for device (221/0x00020000/…)").
`tools/safe-flash.sh` checks this in its dry run under lk2nd (`tools/lib/lk2nd_dtb_check.py`); record
lk2nd's ids once in `device.qcom_ids` from the "Device info" line of `fastboot oem log`, since lk2nd
prints that line only after a failed boot.

## 4. Test, RAM first

Order of preference (record the method in `port.yaml` `path.boot_method`):

1. `fastboot -s <serial> boot boot.img` (stock or lk2nd): nothing written; a reboot returns to the previous state.
2. On no-RAM-boot devices: install lk2nd to `boot` and use its `fastboot boot`; without lk2nd,
   flash to the **experiment partition** (`boot`) via `tools/safe-flash.sh`; `aboot`, never written, always brings back its flash mode to reflash `boot`.
3. Only once proven, write to the final partition (M9).

Before each test, tell the user what they should see, how long to wait, and how to get out
(force reboot combo → bootloader/download mode). Ask for a photo of the screen when there is output.
