---
name: adb-recon
description: Read-only reconnaissance of an Android device over adb - what to collect (with and without root), the collector script, and how to interpret getprop, cpuinfo, partitions, kernel config, boot image headers and dmesg to identify the SoC, board, peripherals, flash mode and boot image format. Use in M1 and whenever device facts are missing.
---

# ADB reconnaissance

Everything here is **read-only**. No `setprop`, no `settings put`, no `pm`, no writes under
`/dev/block`. Root (`su`) is used only if the phone is already rooted, and only for reads.

## 1. Collect

```bash
tools/recon/collect.sh <serial> ports/<id>/dossier/raw
```

It saves, one file per command: `getprop.txt`, `cpuinfo.txt`, `meminfo.txt`, `cmdline.txt`,
`partitions.txt`, `by-name.txt`, `mounts.txt`, `version.txt`, `modules.txt`, `input-devices.txt`,
`dumpsys-display.txt`, `dumpsys-battery.txt`, `i2c-devices.txt`, `platform-devices.txt`,
`dt-compatible.txt`, `firmware-list.txt`, `vendor-firmware-list.txt`, `soc0.txt`, `emmc.txt`,
`power-supply.txt`, `asound.txt`, `partnames-sysfs.txt`, `config.gz`→`kernel.config` (if
readable), `dmesg.txt` (if allowed), `lsusb-host.txt`. With root it adds `dmesg-root.txt`,
`boot.img`/`recovery.img` reads into the dossier, `devicetree.dtb` from `/sys/firmware/fdt`, and the
full firmware lists. Missing files are fine: note what could not be read and why (SELinux, no root).

## 2. Interpret

| Question | Where to look |
|---|---|
| SoC | `soc0.txt` (`soc_id`, `family`, `revision` on Qualcomm), `ro.board.platform`, `ro.hardware`, `ro.boot.hardware`, `ro.soc.model` (Android 12+), `Hardware:` in cpuinfo (old kernels), `compatible` of `/proc/device-tree` root (`dt-compatible.txt`) |
| CPU arch | `ro.product.cpu.abi`; cpuinfo `CPU architecture: 7` (armv7) / `8` (aarch64). A 64-bit SoC running a 32-bit Android is common (msm8916): the mainline port can be aarch64 |
| Board / model | `ro.product.device`, `ro.product.model`, `ro.product.board`, `ro.boot.hwrev`/`ro.revision`; the DT `model` string |
| RAM / storage | meminfo `MemTotal`; `partitions.txt` (mmcblk0 = eMMC, sda = UFS); `emmc.txt` (eMMC name, CID, manufacturer) |
| Partition map | `by-name.txt` (`/dev/block/by-name` or `/dev/block/platform/*/by-name`), `partnames-sysfs.txt` (`mmcblk0pN` ↔ name from sysfs) + `partitions.txt` sizes (1 KiB blocks) |
| A/B slots | `ro.boot.slot_suffix`, `ro.build.ab_update`; `_a/_b` names in by-name |
| Dynamic partitions | `ro.boot.dynamic_partitions`, a `super` partition |
| Bootloader / lock | `ro.boot.verifiedbootstate` (green=locked, orange=unlocked), `ro.boot.flash.locked`, `ro.oem_unlock_supported`, `ro.boot.warranty_bit` + `ro.warranty_bit` (Samsung KNOX), `ro.bootloader` (Samsung BL version), `ro.boot.bootloader` |
| Flash mode | Samsung → download mode + heimdall; MediaTek (`ro.board.platform` mtXXXX) → fastboot from LK and BROM; Qualcomm → fastboot (most) or Samsung download mode |
| Boot image | With a dumped `boot.img`: `python3 -I tools/lib/bootimg_info.py boot.img` (header version, page size, offsets, cmdline, kernel format, appended DTB or QCDT `dt.img`, Samsung SEANDROID footer). Without: pmaports `deviceinfo` for this device |
| Kernel | `version.txt`, `kernel.config` (`CONFIG_MODULES`, `CONFIG_MODULE_SIG_FORCE`, `CONFIG_PSTORE_RAM`) |
| Display | `dumpsys-display.txt` (resolution, density), panel name in `cmdline.txt` (`mdss_mdp.panel=…`, `lcd=`), `dmesg` |
| Touch / sensors / charger | `input-devices.txt` names, `i2c-devices.txt` (bus-address + driver name), `platform-devices.txt`, `power-supply.txt` (battery, charger, fuel gauge) |
| Audio | `asound.txt` (sound cards and their names) |
| WiFi / BT | `vendor-firmware-list.txt` (`wcnss`, `bcmdhd`, `WCNSS_qcom_wlan_nv.bin`, `wlan/prima`), `modules.txt` (`wlan.ko`, `bcmdhd`), the `wifi.interface` prop |
| Modem | `gsm.version.baseband`, `ro.baseband`, `persist.radio.*`, the `modem`/`NON-HLOS` partition |
| USB IDs | `lsusb-host.txt` (the phone as seen by the computer) |

## 3. Write the dossier

`ports/<id>/dossier/device.md`, with one table per area (SoC, memory, storage, partitions, boot,
display, input, connectivity, power, sensors, camera, audio). **Every fact has a source** column
(file + line/prop name), and a confidence level when inferred. Then fill `device:` in `port.yaml`.

Also write `dossier/partitions.md`: name, block device, size, class A/B/C/D (see `device-safety`),
and a note. Partitions you can't classify → class A until proven otherwise.

## 4. Linux-side recon (M8, over ssh from the rescue initramfs)

```bash
ssh root@10.0.42.1 'dmesg' > dossier/raw/linux-dmesg.txt
ssh root@10.0.42.1 'cat /proc/partitions; ls -l /sys/class/block/*/; for d in /sys/class/block/mmcblk0p*; do echo "$d $(cat $d/uevent | grep PARTNAME)"; done'
ssh root@10.0.42.1 'grep -r . /sys/bus/platform/drivers/*/uevent 2>/dev/null | head -200'
```

Look for `deferred probe pending`, `Direct firmware load for … failed`, `supply … not found`, and
devices without drivers. Write `dossier/partitions-linux.md` (`mmcblk0pN` ↔ PARTNAME ↔ class).
