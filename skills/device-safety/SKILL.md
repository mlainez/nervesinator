---
name: device-safety
description: Brick-prevention rules for Android devices. Covers the partition classes (what may never be touched), the pre-flight checklist before any device write, backup requirements, vendor traps (Samsung KNOX/PIT, Sony TA, MediaTek preloader/nvram, Qualcomm EFS/persist, relocking) and the unbrick ladder. Load it before any command run in fastboot/download/EDL/BROM/recovery mode or that writes to a device, and when planning unlocks, backups or flashes.
---

# Device safety

A **soft brick** is a phone that doesn't boot Android anymore but still reaches a bootloader,
download mode or recovery. It is fixed by flashing the right image back. A **hard brick** is a
phone whose first-stage bootloader no longer runs: black screen, no mode reachable. It is fixed,
if at all, by a vendor emergency mode (Qualcomm EDL, MediaTek BROM, Samsung has nothing
equivalent for most models) with signed loaders that are often not public.

**Our promise to the user: we only ever risk soft bricks, and every soft brick has a tested way back.**

Two invariants, whatever happens:

1. **The flash mode is never broken.** `aboot` (download mode on Samsung, fastboot elsewhere) and
   the rest of class A are never written, so the phone can always be put back into it.
2. **A return to stock is never made impossible.** Class B is never written and is backed up, the
   kit never relocks or repartitions, never flashes an older stock bootloader (anti-rollback), and
   the stock firmware for this exact model is downloaded in M3 before the first write.

Android does not need to stay bootable during the work: `boot`, `recovery`, `system` and `userdata`
are ours once backed up.

## The four partition classes

Classify every partition in M1 (in `dossier/partitions.md`) and refer to the classes, not to memory.

| Class | Examples | Rule |
|---|---|---|
| **A: boot chain** | `sbl1`, `xbl`, `aboot`, `abl`, `rpm`, `tz`, `hyp`, `preloader`, `lk`, `bootloader`, `mmcblk0boot0/1`, the GPT/PIT itself | **Never written.** Not even with "the same version". A wrong byte = hard brick |
| **B: irreplaceable data** | `efs`, `modemst1/2`, `fsg`, `persist`, `nvram`, `nvdata`, `proinfo`, `TA` (Sony), `param` (Samsung), `devinfo`, `frp` | **Never written. Backed up first.** Holds the IMEI, WiFi/BT MAC, sensor and radio calibration, DRM keys. It exists nowhere else on the planet |
| **C: replaceable firmware** | `modem`/`NON-HLOS`, `dsp`, `vendor`, `vbmeta`, `dtbo` | Not written by default (on the forbidden list where it applies). Reading them is how we get firmware blobs |
| **D: our playground** | `boot`, `recovery`, `userdata`, `cache`, `system` (and `super` with care) | Written **only** after a verified backup, when allowlisted in `safety.writable_partitions` |

The machine-readable list of class A/B/C names is `tools/lib/forbidden-partitions.txt`. Both the
guard and `tools/safe-flash.sh` refuse those names. If a device uses an unusual name for a class A/B
partition, **add it to that file** (a commit in the kit) before going further.

## Pre-flight checklist (before every device write)

`flash-guardian` runs it and shows the result to the user. Each line must be ✅:

1. Exactly one device in the target mode, and its serial matches `port.yaml` `device.serial`.
2. The product/model reported by the bootloader matches `device.product` (fastboot `getvar product`,
   `heimdall print-pit` device info).
3. The target partition is class D **and** listed in `safety.writable_partitions`.
4. `backups/<partition>.img` exists and its line in `backups/SHA256SUMS` verifies.
5. The image fits the partition (size), and has the expected format (`ANDROID!` magic for boot
   images, the lk2nd/U-Boot image built for **this** SoC/device).
6. The escape route is written in the plan: the key combo + the command + the backup image that
   restores the previous state, and it was tested in M3.
7. Battery > 50 % (`adb shell dumpsys battery` or the bootloader screen); a USB cable plugged
   straight into the computer, not a hub.
8. The user has seen the exact command and said yes.

## Vendor traps (read the one for your device)

- **Relocking** (`fastboot flashing lock`, `oem lock`) with custom images installed bricks many
  devices (the bootloader refuses its own content). The kit never relocks. If the user wants to
  relock at the end: restore full stock first, and they type it themselves.
- **Samsung:** no `fastboot boot`; download mode (Vol- + Home/Bixby + Power, or `adb reboot download`)
  with Heimdall/Odin. **Never** `--repartition`/`--pit`. Flashing anything unofficial trips the
  **KNOX warranty e-fuse** (irreversible, Samsung Pay/Knox features gone). Newer models: the "OEM
  unlock" toggle + FRP + "RMM/KG state: prenormal" can block flashing ("Only official released
  binaries are allowed"). lk2nd and test images go to `BOOT`. Keeping Android is not a goal: download
  mode lives in the untouched `aboot` and can always reflash `BOOT`. Flash per partition only: an AP
  tar can carry class B images (`persist.img.ext4` on some Qualcomm models), so a whole-AP Odin
  flash overwrites calibration. The PIT's `PGPT`, `PIT`, `MD5` and `SGPT` entries are not partitions
  to flash. After a heimdall command with `--no-reboot`, the next one in the same download mode
  session needs `--resume` (`tools/safe-flash.sh --resume`), or reboot into download mode first.
- **Sony:** unlocking erases the **TA partition DRM keys** forever: back up TA (needs an exploit,
  before unlock) if the user cares about camera quality/DRM. Ask them.
- **MediaTek:** `preloader`, `nvram`, `nvdata`, `proinfo`, `protect*`, `seccfg` are untouchable;
  SP Flash Tool "Format All + Download" erases calibration: never use it. mtkclient reads are fine.
  Many MTK devices reserve a tail of `userdata` (BMT pool/encryption footer): do not grow
  filesystems into it.
- **Qualcomm:** `fastboot flash` to `aboot`/`sbl1` = hard brick, and only EDL with a signed firehose
  programmer for this exact device saves it. `modemst1/2`, `fsg`, `fsc`, `persist` = IMEI/calibration.
  Anti-rollback (`ro.boot.anti_rollback`, Pixel/OnePlus ARB): flashing an *older* stock bootloader
  can brick: when restoring, use the same or a newer stock build. Under lk2nd, `getvar product` is
  the SoC board name (`msm8226`): `safe-flash.sh` then matches `getvar lk2nd:compatible` against
  `device.lk2nd_compatible`. On some SoCs (msm8226), holding Vol Up + Vol Down while lk2nd starts
  reboots into EDL (`05c6:9008`); a battery pull (or a long power-key hold) gets out of it.
- **A/B devices:** know the active slot (`getvar current-slot`). Flash the inactive slot's
  `boot_x` only on purpose; never `set_active` to an empty slot.
- **AVB / dm-verity:** on Android 8+ devices, booting a custom kernel may need a `vbmeta` with
  verification disabled (`--disable-verity --disable-verification`). That is a write to class C:
  treat it as orange, back up `vbmeta` first.
- **eMMC boot areas:** `/sys/block/mmcblk0boot*/force_ro` stays 1. Never write the `mmcblk0boot*`,
  `rpmb` or whole-disk devices from Linux.
- **Host safety:** `dd of=/dev/sdX` on the computer can erase the user's own disk. The guard denies
  it; the user runs host raw writes themselves, after checking `lsblk`.

## Backups (M5)

- Dump every partition **except** `userdata` (huge, personal) and `system`/`super` (downloadable as
  stock). Class B first, then class A (for reference and forensics, never to restore by us), then
  class D.
- Methods, safest first: root `dd if=/dev/block/by-name/X` over adb → a temporarily booted recovery
  (`fastboot boot twrp.img`, never flashed just for backups) → vendor tools in read mode
  (`edl r`, `mtk r`, `heimdall` cannot read partitions: use one of the others).
- When getting root (M5) must write a class D partition before it can be dumped, its backup is the
  matching image from the stock firmware downloaded in M3, copied to `backups/<name>.img` and
  added to `SHA256SUMS`.
- `tools/backup-partitions.sh` writes `backups/<name>.img` + `backups/SHA256SUMS` and re-reads to
  verify. The user then copies `backups/` somewhere else (a USB stick, the cloud). Backups are never
  committed to git and never deleted by the kit.

## The unbrick ladder (written per device in M3 as `dossier/unbrick.md`)

1. **Bootloop / boots to a black screen:** force reboot (key combo, often Power 10–20 s) → bootloader
   or download mode → restore `backups/boot.img` (or recovery).
2. **Android broken, bootloader fine:** reflash stock firmware with the official tool (fastboot
   factory image / the stock images of class D partitions only, per partition with Heimdall/Odin (an AP
   tar may hold class B images) / SP Flash Tool "Download only" with the stock scatter).
3. **Nothing on screen, PC sees a vendor USB ID** (`05c6:9008` Qualcomm EDL, `0e8d:0003` MediaTek
   BROM): stop and research. EDL needs a signed firehose programmer for the device; BROM can use
   mtkclient. **The user runs these, never the agents** (the guard denies writes).
4. **Nothing at all:** battery fully drained? Try charging 30 min. Then a service center or a JTAG/ISP
   repair shop. Being honest about this level is part of the briefing in M0.
