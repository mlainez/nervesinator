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
CONFIG_USB_CONFIGFS_ACM=y       # the console the host reads without any network setup
CONFIG_PANIC_TIMEOUT=10         # self-recovery: see below
CONFIG_WATCHDOG=y               # + the SoC driver (CONFIG_QCOM_WDT on Qualcomm)
CONFIG_REBOOT_MODE=y            # + the SoC reboot driver and a reboot-mode node in the DT
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
  busybox (telnetd and watchdog applets), `reboot-mode` (`BR2_PACKAGE_REBOOT_MODE=y`, from
  buildroot-android) and the overlay from `templates/rescue/`: `init-firstlight` as `/init`,
  `kit-common.sh` as `/usr/lib/kit-common.sh`, `usb-gadget.sh`, `udhcpd.conf` and `kit-image` as
  `/etc/kit-image` (`KIT_IMAGE=firstlight`, the port id and `device.serial` filled in),
- a post-image script that packs `boot.img` (see `boot-images`).

Expected: a penguin/logo or the scrolling kernel log, then the init's banner on the screen **and**
on the host: `tools/await-boot.sh` sees the kit gadget and reads `KIT-READY` from its ACM console.
That is the M7 proof; a photo is optional. If neither shows up, hand over to `boot-debugger`.

## Self-verifying test images (every image the kit boots)

The templates make each image report and recover on its own, so a boot can be judged without
anyone looking at the phone:

- **Identity:** the USB gadget is `1d6b:0104`, manufacturer `porting-kit`, product
  `<id>-<image>`, serial `device.serial` (`tools/lib/kit_gadget.sh`; `tools/detect-devices.sh`
  lists it). Functions: ACM (`ttyGS0`: banner, dmesg, then a shell) and NCM (10.0.42.1, telnetd or
  dropbear).
- **Self-recovery:** `panic=10` (`CONFIG_PANIC_TIMEOUT`), soft lockups panic, the hardware watchdog
  is fed from userspace, and without a USB gadget the image returns to the flash mode after
  `KIT_FAIL_REBOOT` s (`kit.fail_reboot=0` on the cmdline keeps the screen for a photo).
- **Way back to the flash mode:** `reboot-mode <KIT_RETURN_MODE>` (LINUX_REBOOT_CMD_RESTART2),
  else `reboot -f`. `bootloader` lands in fastboot (stock or lk2nd), `download` in Samsung
  download mode. The PID 1 shell traps TERM/USR1/USR2, so busybox `reboot`/`poweroff`/`halt` work.
- **Traps:** on Samsung with lk2nd, the stock `aboot` runs first and clears the restart reason, so
  `reboot-mode bootloader` cannot reach lk2nd's fastboot: use `KIT_RETURN_MODE=download` there.
  On Qualcomm, the restart reason lives in IMEM and survives only a **warm** reset; mainline may do
  a hard reset (PM8226 PS_HOLD), which loses it. Check it in M8: write a reason, reboot, see it
  honoured.
- **Limit:** a hard hang without a working watchdog needs a human (force power off or battery pull).
- On-device shell scripts follow `buildroot-port` section 6 (BusyBox ash, the image's own applets, errors never hidden).

## M8: rescue initramfs

`configs/<id>_rescue_defconfig` = first light +:

- `BR2_PACKAGE_DROPBEAR=y` (or busybox `telnetd`), `BR2_TARGET_GENERIC_ROOT_PASSWD="root"`,
- `BR2_PACKAGE_UNUDHCPD=y` (the package exists in buildroot-android: `package/unudhcpd`),
- busybox with `fdisk`, `blkid`, `dd`, `sha256sum`, `devmem`, `i2cdetect` (`BR2_PACKAGE_I2C_TOOLS=y`),
  `e2fsprogs`, `evtest`, `usbutils`,
- the same overlay as first light, with `init-rescue` as `/init` and `KIT_IMAGE=rescue`.

What `usb-gadget.sh` does (configfs): create gadget `g1` with the kit identity above, add the ACM
and NCM functions, bind it to the first UDC in `/sys/class/udc`, configure `usb0` as
10.0.42.1/24, then start `unudhcpd -i usb0 -s 10.0.42.1 -c 10.0.42.2` (busybox `udhcpd` as a
fallback). The phone is always 10.0.42.1 and the computer gets 10.0.42.2 (the buildroot-android
convention).

On the host: `tools/usbnet.sh` finds the new interface, waits for the DHCP lease (or sets
10.0.42.2 itself with the user's approval), and prints the ssh command.

## Writing the rootfs from the rescue system (M9)

The TB3-710F pattern: boot rescue from RAM, `scp -O` the rootfs image (legacy protocol: dropbear has no sftp-server), `dd` it to the allowlisted
partition (the guard asks for confirmation), verify by reading it back and comparing the sha256,
`e2fsck -f` and `resize2fs` to the size noted in the partition map (not into reserved tails).
Keep `/.rescue` (or a key combo) as a way to force the rescue system later.
