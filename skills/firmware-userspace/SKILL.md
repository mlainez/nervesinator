---
name: firmware-userspace
description: Finding and packaging what peripherals need beyond the kernel - proprietary firmware blobs (from the device, stock firmware, pmaports firmware-* packages, TheMuppets, linux-firmware), and userspace daemons/configs from postmarketOS (APKBUILD dependencies, OpenRC services, udev rules, ALSA UCM) translated into Buildroot packages. Covers Qualcomm (wcnss/wcn36xx, modem remoteproc, rmtfs, qrtr, tqftpserv, pd-mapper), MediaTek (CONSYS/WMT) and Broadcom WiFi. Use in M10.
---

# Firmware and userspace

## 1. Find out what is requested

From the rescue/persistent system: `dmesg | grep -iE "firmware|direct firmware load|remoteproc|failed to load"`.
Each `Direct firmware load for X failed` names a file the kernel wants under `/lib/firmware/X`.

## 2. Where blobs come from (best first)

1. **pmaports** `firmware-<vendor>-<codename>` / `firmware-qcom-<soc>` APKBUILD: lists the exact
   files, their source (a git repo of blobs or the vendor partitions) and where they must be installed.
   Often it also does the **conversion** (`.mdt` → `.mbn` squashing with `pil-squasher`, renaming).
2. **The device itself:** `adb pull /vendor/firmware`, `/firmware/image` (the `modem`/`NON-HLOS`
   partition, a FAT image: mount the backup copy `backups/modem.img` read-only with `-o loop,ro`),
   `/system/etc/firmware`, `/persist` (WiFi NV, sensor calibration: per-device, never published).
3. **Stock firmware** packages (M3 download): extract `NON-HLOS.bin`, `system.img`, `vendor.img`.
4. **TheMuppets** `proprietary_vendor_<vendor>` repos (the LineageOS `proprietary-files.txt` maps paths).
5. **linux-firmware** (Adreno GPU `a3xx_*`, some WiFi): Buildroot `BR2_PACKAGE_LINUX_FIRMWARE_*`.

Blobs are not redistributable: a script (`board/<id>/scripts/prepare_firmware.sh`) copies them from
the backups/device into `board/<id>/overlay/lib/firmware/` or a package `SITE` path, ignored by git.
Same pattern as `tb3_710f/scripts/prepare_firmware.sh`.

## 3. Translate postmarketOS userspace into Buildroot

First check buildroot-android (`buildroot-port` section 0): `rmtfs`, `qrtr`, `tqftpserv`,
`rpmsgexport`, `hexagonrpc`, `adsp-boot`, `alsa-ucm-conf` and the firmware packages often already
do it; extend them before adding a package.

For each pmOS dependency of the device package (`APKBUILD` `depends=`, the `soc-*` packages):

| pmOS piece | Buildroot equivalent |
|---|---|
| `APKBUILD` with `source=` + `build()` | a package in `buildroot-external/package/<name>/` (`generic-package`, `meson-package`…) |
| OpenRC `*.initd` service | `S??<name>` init script installed by the package (busybox init) |
| udev rules (`*.rules`) | overlay `/etc/udev/rules.d/` (with eudev) or mdev config |
| ALSA UCM (`*.conf` under `ucm2/`) | the `alsa-ucm-conf` package + an overlay with the device's files |
| `deviceinfo_modules_initfs` | kernel modules → set `=y`, or load them in an early init script |
| `/etc/conf.d`, `/usr/share/<x>` configs | overlay |

## 4. Recipes by family

- **Charging (do it first; Qualcomm PMIC chargers in detail).** Symptoms like "charger online but not
  charging", `Discharging` on every supply, or VALID/CHG_GONE flapping every few seconds:
  - Compare with the vendor driver (downstream `qpnp-charger`, `pm8921-charger`, `smb*`) and with what
    the stock bootloader programs: list every register the vendor writes at charger insertion, and
    check each one under mainline.
  - On PM8226/PM8941 (SMBB, mainline `qcom_smbb`): BAT_IF `0x1293` (BATFET_CTRL4) bits 7:6 = 01 is
    BATFET low-power mode. The vendor driver clears it on every insertion and never allows it under a
    charger; mainline leaves it, and the input stays "present but not qualified". Leave LPM whenever
    a supply is present, set it only with no input (fixed this way on samsung-s3ve3g, upstreamable).
  - Check the input current limit (USB_IMAX) is not stuck at 100 mA after an input-arbiter reset.
  - Test the trickle/ATC path at low battery, and test on a wall supply as well as a PC port: do not
    conclude "weak PC port" without a wall supply test.
  - Dump all charger registers, including the ranges behind the SEC_ACCESS override, before and
    after insertion, and diff them.
- **Qualcomm modem / DSP (remoteproc):** firmware `modem.mdt/.bNN` or `.mbn`; daemons `qrtr`
  (QRTR ns), `rmtfs` (gives the modem its EFS from `modemst1/2`/`fsg`: **read the backup, never write
  those partitions from our system unless rmtfs is configured exactly as on pmOS**), `tqftpserv`,
  `pd-mapper`; then ModemManager or QMI tools. In Nerves: `vintage_net_qmi` + an rmtfs replacement (the FP2 story).
- **Qualcomm WCNSS WiFi (wcn36xx, msm8226/8916/8974):** `wcnss.mdt/.bNN` from the modem partition +
  `wlan/prima/WCNSS_qcom_wlan_nv.bin` (per device, from `/persist` or `/system/etc/wifi`); the
  `qcom,wcnss` DT node; the MAC address may come from the NV or `persist`.
- **Qualcomm Adreno GPU (freedreno):** `a3xx_pm4.fw`, `a3xx_pfp.fw` (linux-firmware) + `a3xx_zap.*` on newer ones.
- **Broadcom WiFi (brcmfmac):** `brcmfmac<chip>-sdio.bin` + an NVRAM `.txt` named after the board
  `compatible` (`brcmfmac43430-sdio.<vendor>,<board>.txt`).
- **MediaTek CONSYS (WMT/WiFi/BT):** out-of-tree stack + `WMT_SOC.cfg`, `mt6xxx_patch_*` + a launcher
  that exits non-zero on success: parse its output (the Kobo/TB3 lessons).

Bring-up scripts (MAC address, firmware loaders) follow `buildroot-port` section 6: BusyBox ash, the
image's own applets, results checked, errors never hidden.

Iterate on blobs, daemons and configs by copying them to the running system (`scp -O`), and
checkpoint each working peripheral with a full build (`buildroot-port` section 7).

## 5. Record for Nerves

Every daemon, script, blob and config goes into `dossier/init-inventory.md`:

| Peripheral | Blobs | Daemons | Init order | Config files | Nerves replacement idea |
|---|---|---|---|---|---|
