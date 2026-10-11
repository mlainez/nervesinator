---
name: bootloader-unlock
description: Vendor-by-vendor knowledge for unlocking Android bootloaders and choosing a boot path - Google/AOSP fastboot, Qualcomm OEMs, Samsung download mode (Heimdall/Odin, KNOX, OEM unlock, RMM/KG), MediaTek (fastboot, mtkclient seccfg), Motorola/Sony/Xiaomi tokens, Huawei - plus second-stage bootloaders (lk2nd, U-Boot) and the unbrick-kit requirements. Use in M3, M4 and M6.
---

# Bootloader unlock and boot path

Always combine this generic knowledge with **device-specific** sources (pmOS wiki page, XDA thread,
LineageOS install guide for the device). Write the device's procedure in
`dossier/unlock.md` with the sources, the irreversible effects, and the exact command sequence.
`flash-guardian` executes; the user approves.

## Questions to answer first (M3/M4)

1. How does this device enter its flash mode(s)? (keys, `adb reboot bootloader|download|recovery`)
2. Does the stock bootloader enforce signatures at all? (Old Samsung Qualcomm: often no "unlock";
   the bootloader warns and boots unsigned images, with the KNOX fuse tripped.)
3. What does unlocking cost? (data wipe, KNOX e-fuse, Sony TA keys, Widevine L1 → L3, banking apps,
   warranty)
4. Is there a waiting period / account / token? (Xiaomi Mi Unlock days, Motorola/Sony codes, carrier locks)
5. Does it support `fastboot boot` (RAM boot)?
6. What is the stock firmware package and the official restore tool?

## By vendor

**Generic AOSP/Qualcomm fastboot** (Google, OnePlus, Fairphone, Nokia, many Qualcomm OEMs)
1. Settings → Developer options → *OEM unlocking* on (needs internet on some devices).
2. `adb reboot bootloader`; `fastboot -s <serial> flashing unlock` (newer) or `fastboot oem unlock`
   (older), confirm with the volume keys on the phone. Data is wiped.
3. Check: `fastboot -s <serial> getvar unlocked` → `yes`, or `fastboot oem device-info`.
   `fastboot boot` usually works.

**Samsung** (Qualcomm or Exynos), no fastboot on stock
- Modes: download mode (Vol- + Home + Power on old models, Vol- + Vol+ + USB cable on newer ones), recovery (Vol+ + Home + Power).
- Old models (≈ before 2015, e.g. Galaxy S3/S4 era): no unlock step; Heimdall/Odin flashes a custom
  boot/recovery image; KNOX warranty bit trips (irreversible), "custom binary" warning.
- Newer models: Developer options → *OEM unlocking*; then long-press Vol+ in download mode to unlock
  (wipe). "RMM/KG state: Prenormal" blocks custom binaries until the 7-day online check passes.
- Tools: Heimdall (`heimdall print-pit` reads the partition table: read-only and safe; the
  `--repartition` flag is forbidden), or Odin on Windows. Partition names are uppercase in PIT
  (`BOOT`, `RECOVERY`).
- No RAM boot: test images go to `RECOVERY` first (Android stays bootable from `BOOT`), until lk2nd
  is installed (on supported Qualcomm Samsungs lk2nd then provides fastboot and `fastboot boot`).

**MediaTek**
- Many expose fastboot from LK: `fastboot flashing unlock` (or `oem unlock`) after the OEM toggle.
- Others: mtkclient via BROM: `mtk da seccfg unlock` (the guard asks for confirmation). BROM
  access depends on the SoC/protections (SLA/DAA); read about the device first.
- Never SP Flash Tool "Format All". Keep the scatter file from the stock firmware.
- TB3-710F story: stock LK was used as-is after `fastboot oem unlock`, with a mainline kernel + appended DTB in boot.img.

**Motorola / Sony / Xiaomi / others**
- Motorola: `fastboot oem get_unlock_data` → website → code → `fastboot oem unlock <code>`.
- Sony: an unlock code from the Sony site; **back up TA first** (DRM keys are erased by unlocking).
- Xiaomi: Mi Unlock tool + account binding + waiting period.
- Huawei/Honor (post-2018): no official unlock. Treat as "secure boot: STOP" unless the community has a proven method.

## Second-stage bootloaders (M6)

**Why:** the stock bootloader may pick the wrong DTB (QCDT), impose a size limit, rewrite the cmdline,
lack `fastboot boot`, or only boot Android images. A second stage running *as the kernel* of a boot
image gives us a modern, open bootloader without touching the bootloader chain.

- **lk2nd** (Qualcomm): flashed to `boot` (or `recovery`), it gives fastboot (with `fastboot boot`)
  and boots `extlinux/extlinux.conf` from a partition, or a second Android boot image placed 512 KiB
  into `boot`. Its `fastboot oem log` shows its own log: great for debugging. Try
  `fastboot boot lk2nd.img` before flashing it, when the stock bootloader allows that.
- **U-Boot** chainloaded (Qualcomm newer SoCs, some Exynos/Tegra): same idea, packed as an Android boot image.
- **Mainline U-Boot replacing the bootloader** (Tegra grouper style): requires class A writes →
  `risk-red`, never automated. Only with a documented, community-proven procedure and the user typing the commands.

## Unbrick kit requirements (M3)

Before M4, all must be true and recorded in `dossier/unbrick.md`:

- Stock firmware for the exact model/region downloaded and checksummed (`backups/stock/`).
- The official or community flash tool installed and tested **in read-only mode** against the phone.
- All the mode entries tested by the user (and the "force power-off" combo).
- A written procedure for: restore boot, restore recovery, full stock reflash, what to do in EDL/BROM.
