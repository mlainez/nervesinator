---
name: rescue-initramfs
description: Build the in-RAM test systems - the first-light kernel that prints boot messages on the screen, and the rescue initramfs with USB gadget networking (configfs NCM/RNDIS), unudhcpd and ssh/telnet - using Buildroot defconfigs and the templates in templates/rescue. Use in M7 and M8, and whenever a safe RAM-only system is needed for investigation or for writing the rootfs.
---

# First light and the rescue initramfs

Both systems live **only in RAM** (the rootfs is the initramfs packed in the boot image). Nothing
on the phone's storage changes, so a reboot always gives the phone back.

## Kernel config essentials (both stages)

Start from the chosen base config (pmaports `config-*`, or `qcom_defconfig`/`multi_v7_defconfig`/
`defconfig`) and make sure these are `=y`:

```
CONFIG_BLK_DEV_INITRD=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_FB_SIMPLE=y              # or CONFIG_DRM_SIMPLEDRM=y: the framebuffer the bootloader left
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_FRAMEBUFFER_CONSOLE_ROTATION=y
CONFIG_VT=y
CONFIG_VT_CONSOLE=y
CONFIG_PSTORE=y
CONFIG_PSTORE_RAM=y             # ramoops: read the last log after a warm reboot
CONFIG_PSTORE_CONSOLE=y
CONFIG_USB_GADGET=y
CONFIG_USB_CONFIGFS=y
CONFIG_USB_CONFIGFS_NCM=y
CONFIG_USB_CONFIGFS_RNDIS=y
CONFIG_USB_CONFIGFS_ECM=y
CONFIG_CONFIGFS_FS=y
CONFIG_PRINTK_TIME=y
CONFIG_MAGIC_SYSRQ=y
```

Put device-specific extras (USB PHY/controller like `USB_CHIPIDEA`/`USB_DWC3`, the eMMC host,
regulators, the PMIC) as listed in the pmOS config. A **config fragment** in
`board/<id>/linux-firstlight.fragment` keeps the delta readable.

Kernel cmdline for first light: `console=tty0 earlycon loglevel=8 ignore_loglevel` (+
`fbcon=rotate:N` if the panel is rotated, + the vendor-specific `earlycon=…` if a UART is wired).

## M7: first light

A Buildroot defconfig `configs/<id>_firstlight_defconfig` in the port's buildroot-android tree:

- the kernel (from the chosen repo/commit, config + fragment, the DTB),
- a tiny rootfs as initramfs (`BR2_TARGET_ROOTFS_CPIO=y`, `BR2_TARGET_ROOTFS_CPIO_GZIP=y`) with
  busybox and `templates/rescue/init-firstlight` as `/init`: it mounts proc/sys/dev, prints
  `uname -a`, the memory, the block devices, then loops printing the uptime every 10 s (so a photo
  shows that the system is alive, not frozen),
- a post-image script that packs `boot.img` (see `boot-images`).

Expected: a penguin/logo or the scrolling kernel log, then the init's banner. If the screen stays
black, hand over to `boot-debugger`.

## M8: rescue initramfs

`configs/<id>_rescue_defconfig` = first light +:

- `BR2_PACKAGE_DROPBEAR=y` (or busybox `telnetd`), `BR2_TARGET_GENERIC_ROOT_PASSWD="root"`,
- `BR2_PACKAGE_UNUDHCPD=y` (the package exists in buildroot-android: `package/unudhcpd`),
- busybox with `fdisk`, `blkid`, `dd`, `sha256sum`, `devmem`, `i2cdetect` (`BR2_PACKAGE_I2C_TOOLS=y`),
  `e2fsprogs`, `evtest`, `usbutils`,
- the overlay from `templates/rescue/`: `/init` (`init-rescue`) and `/usr/sbin/usb-gadget.sh`.

What `usb-gadget.sh` does (configfs): create gadget `g1` with the vendor/product IDs `0x18d1:0xd001`,
add an NCM function (and RNDIS for Windows/macOS hosts), bind it to the first UDC in `/sys/class/udc`,
configure `usb0` as 10.0.42.1/24, then start `unudhcpd -i usb0 -s 10.0.42.1 -c 10.0.42.2`. The phone
is always 10.0.42.1 and the computer gets 10.0.42.2 (the buildroot-android convention).

On the host: `tools/usbnet.sh` finds the new interface, waits for the DHCP lease (or sets
10.0.42.2 itself with the user's approval), and prints the ssh command.

## Writing the rootfs from the rescue system (M9)

The TB3-710F pattern: boot rescue from RAM, `scp` the rootfs image, `dd` it to the allowlisted
partition (the guard asks for confirmation), verify by reading it back and comparing the sha256,
`e2fsck -f` and `resize2fs` to the size noted in the partition map (not into reserved tails).
Keep `/.rescue` (or a key combo) as a way to force the rescue system later.
