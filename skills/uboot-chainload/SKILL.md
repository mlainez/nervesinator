---
name: uboot-chainload
description: Mainline U-Boot as a second-stage bootloader chainloaded by the stock Android bootloader, for devices without lk2nd (MediaTek LK, Exynos, Tegra…) - choosing lk2nd vs U-Boot vs nothing, the closest mainline SoC/board, a pinned release built by Buildroot with a format-patch series (no fork), packing it as the kernel of the vendor boot image, console without a UART, watchdog, eMMC, extlinux/sysboot, an env compatible with Nerves fwup, the boot-once guard, optional U-Boot fastboot, and the test procedure. Use in M6 when lk2nd does not support the SoC, and in M11 for the Nerves boot flow.
---

# Mainline U-Boot chainloaded by the stock bootloader

## 1. When

From decisions.md section 2: lk2nd supports the SoC → lk2nd, stop here. Otherwise U-Boot is worth it
when the stock bootloader cannot boot a kernel and DTB from a filesystem (so Nerves could not keep
kernel + DTB A/B inside `userdata`), has no `fastboot boot`, or picks DTBs badly. When the stock
bootloader already boots our `boot.img` well and the port stays single-kernel, nothing is needed.
Record the choice as a decision.

## 2. Sources and how they are delivered

- A **pinned mainline release** (`BR2_TARGET_UBOOT_CUSTOM_VERSION_VALUE="2024.10"` style), built by
  Buildroot (`BR2_TARGET_UBOOT=y`, `BR2_TARGET_UBOOT_BOARD_DEFCONFIG`).
- Device support as a **`git format-patch` series** in the buildroot-android external tree
  (`board/<id>/patches/uboot/`, picked up through `BR2_GLOBAL_PATCH_DIR`): board files, DTS,
  defconfig, drivers. Never a separate U-Boot fork branch. The Nerves system reuses the same series.
- Start from the closest mainline support: the same SoC (`arch/arm/mach-*`, `configs/*_defconfig`,
  `arch/arm/dts/`), else the same SoC family, then community trees (postmarketOS, the SoC's mainline
  group) for drivers to port as patches.

Shape that worked (MediaTek LK, mainline v2026.10):

- `BR2_TARGET_UBOOT_CUSTOM_GIT` from source.denx.de at a release tag,
  `BR2_TARGET_UBOOT_BUILD_SYSTEM_KCONFIG`, the board defconfig, `NEEDS_OPENSSL` when the build asks.
- The series, one concern per patch: the MMC driver (often only a compatible string), the SoC
  support with its `mach_cpu_init` (what the vendor bootloader leaves undone, e.g. the timer), the
  board DT, the board file and defconfig (boot-once guard in `board_early_init_f`, video console,
  watchdog, MMC, extlinux).
- `u-boot.bin` packed as the boot image's kernel with the **same** `mkbootimg` arguments as the
  Linux boot image.
- `/boot/extlinux/extlinux.conf` (kernel + fdt) in the Buildroot board overlay: the existing
  single-root system becomes U-Boot-booted with no layout change.

## 3. Chainloading design

- **No SPL, no DRAM init:** the stock bootloader has set up DRAM and clocks
  (`CONFIG_SKIP_LOWLEVEL_INIT` on arm32; on arm64 boot as a kernel-image payload).
- **Load address:** `CONFIG_TEXT_BASE` = the address where the stock bootloader puts the boot image's
  kernel (`device.bootimg` base + kernel offset), or position-independent where supported.
- **Memory map:** pre-relocation stack and pre-console buffer in low RAM nothing else uses;
  relocation below the usable top of RAM, under any carve-out the vendor reserves (firmware areas
  listed in the vendor DT's `reserved-memory`); `kernel_addr_r`, `fdt_addr_r`, `ramdisk_addr_r`,
  `scriptaddr` spaced so none overlaps; `bootm_size` rather than `fdt_high=~0`. Per-SoC values:
  `soc-notes/`.
- **Packing:** U-Boot (with its DTB appended when the bootloader expects zImage-dtb) becomes the
  "kernel" of an Android boot image built with the stock `mkbootimg` arguments, plus any vendor
  header or footer (`boot-images`).
- **DT:** a board DTS for U-Boot, ideally the same file the kernel uses.
- **Console:** a UART if one is reachable; otherwise the framebuffer the stock bootloader leaves
  (a `simple-framebuffer` node, video console, mapped write-through), so the screen shows U-Boot's
  output. Add `memlog` to stdout (`stdout=vidconsole,memlog`) in a RAM area no firmware or vendor
  kernel touches; read it from Linux with busybox `devmem` after a good boot (`dd` on `/dev/mem`
  fails). A stock bootloader may clear it on reset, so it explains good boots only.
- **Watchdog:** keep the vendor watchdog fed (its driver in U-Boot, autostart, `cyclic` feeding),
  or the phone resets mid-boot. Feeding is timer-driven: a stopped timer means no feeding.
- **Storage:** the SoC's MMC driver at conservative settings first (8-bit SDR, no DDR/HS modes until
  writes are verified: DDR corrupted writes on one eMMC); check that U-Boot numbers partitions like
  Linux (`mmc 0:N` = `mmcblk0pN`); find `userdata` by name. Buildroot: `sysboot`/distro boot of
  `/extlinux/extlinux.conf` on the single root. Nerves (M11): partition 1 of the sub-image MBR inside
  `userdata`, exposed with `blkmap` over the `userdata` slice.
- **Environment:** where Nerves fwup can write it too: a region inside the sub-image that
  `fw_env.config` describes, so `nerves_fw_active` selects the slot (`ENV_IS_IN_MMC` at a fixed raw
  offset matching `fw_env.config`; `ENV_IS_NOWHERE` is fine while only Buildroot boots).
- **Defconfig checklist:** the MMC driver, the partition table type (DOS for MTK MBR/EBR, EFI for
  GPT), ext4 and FAT, `BLKMAP`, `SYSBOOT`, `BOOTZ`/`BOOTI`, `SYSRESET_WATCHDOG`, `VIDEO_SIMPLE`,
  `CONSOLE_MUX`, `SYS_DEVICE_NULLDEV`, `PANIC_HANG`, no network and no EFI unless needed, a short
  `bootdelay`.
- **Fallback:** a `bootmode fastboot|recovery` command (set the boot-mode bit and reset) and a
  `bootcmd` that ends in it when extlinux fails, so a broken root lands in the flash mode.
- **Nerves (M11):** `blkmap map <n> 0 <sectors> linear mmc 0 <partition start + sub-image offset>`,
  then `sysboot blkmap <n>:1`; a USB gadget (ACM console or fastboot) needs the SoC's USB glue and
  PHY init in U-Boot.

## 4. Boot-once guard

At U-Boot start, set the boot-mode bit the stock bootloader reads (a PMIC/RTC register or the
reboot-reason word, as the vendor's `reboot-mode` values give) to recovery or its flash mode; clear
it just before handing over to Linux. A hang followed by a watchdog reset then lands in the
flash/recovery mode instead of a boot loop. Find the register and values from the vendor kernel's
reboot driver or the device tree's `reboot-mode` node, and test that the bit survives the reset.
Check which bits the stock bootloader clears itself: a bit it leaves set must be cleared by U-Boot
before Linux, or every later reset lands in that mode.

## 5. Optional: U-Boot fastboot

`CONFIG_USB_FUNCTION_FASTBOOT` with the SoC's USB gadget driver gives an lk2nd-like flash mode
(`fastboot flash boot`, `fastboot boot`) reachable by command, and `ums` exposes `userdata` as a
USB disk. Both are part of the definition of done (section 8), not options.

## 6. Testing

- RAM first when the stock bootloader can (`fastboot boot`); otherwise through the port's key-free
  flash path to `boot`, after checking the escape route by hand (the vendor flash mode reachable
  with keys or by command, `backups/boot.img` verified).
- Steps that each must pass before the next: U-Boot prints on the console (with its `In/Out/Err`
  lines), the timer runs (the countdown moves), the watchdog does not fire, MMC lists the partitions, `sysboot` finds extlinux, Linux starts with the expected cmdline,
  the boot-once guard turns a deliberate hang into the flash mode.
- Each image goes through `safe-flash.sh` and `await-boot.sh` like any other.
- Buildroot gotchas: a brand-new release may have no tarball yet (use `BR2_TARGET_UBOOT_CUSTOM_GIT`
  with the tag); an older Buildroot's U-Boot license-file handling may not match a newer U-Boot
  (override it in the external tree's `external.mk`); `make uboot` plus the packing script avoids
  a full rebuild when the kernel uses `LINUX_OVERRIDE_SRCDIR`.
- Bring U-Boot up against the **existing** single-root Buildroot system first (an M6/M9 re-run);
  Nerves comes after.
- Run the exact binary in QEMU `virt` (e.g. `-M virt,highmem=off -m 3G`) at the same load address to debug the console and relocation
  without the device (it finds wiring bugs such as a missing nulldev). QEMU hides SoC clock
  gating, so hardware tests stay mandatory.
- One change per flash, each with a predicted screen transcript the user compares against
  ("you should see X, then Y").
- The kernel's `arch/arm/mach-<vendor>` init code is the checklist of what the vendor bootloader
  leaves undone (timer ungating, SMP pens…): U-Boot must do the same before relying on it.

## 7. Checks learned on hardware

Proven so far on MediaTek LK (MT8127: U-Boot in `boot`, extlinux on `userdata`, Linux booted).
Each item is a check to run on the device, not an assumption.

- **Prove the boot-once guard first.** Set the bit, hang on purpose, and see the stock bootloader
  honour it after the watchdog reset (seen: the PMIC RTC recovery bit, MT6323 RTC PDN1 bit 4 via
  pwrap, turned every hang into a key-free recovery boot in about 40 s).
- **Console wiring:** check that U-Boot prints its `In:/Out:/Err:` lines. With `stdin=nulldev` but
  `CONFIG_SYS_DEVICE_NULLDEV` off, console setup fails silently and output goes to a missing serial
  port: only the logo shows.
- **Colours:** some video consoles default to black on white; a white screen can be a working console.
- **Timer:** print a sanity line (frequency, running or STOPPED) early, and check on hardware that the
  autoboot countdown moves. Some SoCs gate the arch timer behind a block the stock bootloader leaves
  off (seen on MT6589/MT7623/MT8135/MT8127: GPT6, enabled by Linux's `arch/arm/mach-mediatek`):
  `get_timer()` then never advances, the countdown freezes, watchdog servicing never runs and the
  watchdog fires. Read the SoC's `mach-*` code in Linux for what it does before `timer_probe`. QEMU
  does not reproduce this.
- **Display after a watchdog reset** can stay stalled until a clean reboot (seen on MediaTek: a
  white halo, `vblank wait timed out`): judge the display only after a clean reboot.
- **The user's eyes are a debug channel:** without a UART, a photo of the screen is the log. Logs
  left in RAM at a fixed address can be overwritten by the next (vendor) kernel.
- **One device, by serial:** flash by serial and check the product (MediaTek reports a platform
  name, e.g. `HQ8127_TB_B2B_L`); refuse when another device is in the same mode.

## 8. Definition of done: truly usable

A ported second stage is **not done when it merely boots Linux**. It is done when someone can work
with the phone through it without keys, screen photos or the vendor's tools:

1. **USB device mode** works in U-Boot: the SoC's gadget controller (MUSB/DWC2/DWC3) and its USB PHY
   init, often ported from the Linux PHY driver's register sequence. Prove enumeration on the host
   (`lsusb`, `journalctl -k`).
2. **U-Boot fastboot**, restricted: `flash`/`erase` only on the port's allowlisted raw regions
   (`boot`, `userdata` by default); every other name, `dev:part` number and `mbr`/`gpt` target is
   refused, and `getvar partition-size:<forbidden>` fails. `fastboot boot` from RAM works (RAM test
   boots even where the vendor bootloader has none). A distinct product and serial
   (`device.second_stage_product`, `device.second_stage_serial`) so it is never confused with the
   vendor fastboot or another phone. **Never** `fastboot oem run` or any arbitrary-command channel:
   it bypasses the allowlist (the guard denies it). Read-only `oem console` (the log) and extra
   getvars (keys, boot path) are welcome: they replace screen photos.
3. **64-bit sizes:** on ARM32, sizes over 4 GiB truncate in 32-bit arithmetic (seen: userdata
   `0x144340000` reported as `0x44340000`); use 64-bit sizes and bounds, and test `getvar` against the
   real size.
4. **A boot menu:** holding a hardware key opens an on-screen menu with at least Fastboot, USB disk
   (`ums` of `userdata`), Recovery (the vendor's) and Continue boot; volume keys move, the power key
   selects (often read through the PMIC). The watchdog stays fed and the boot-once guard disarmed
   while it waits. Find the key wiring in the vendor board files (dct/keypad), then prove it with a
   read-only sampler on Linux while the user presses each key; read the GPIO input register
   directly rather than a keypad controller whose clock Linux may gate.
5. **A key window, not an instant:** show a prompt ("Hold Volume-Down for the menu, Volume-Up for
   recovery") and poll keys through a ~3 s window plus the autoboot countdown; accept a key already
   held at entry. Do not tell users to hold a key from power-on when the vendor bootloader reads it
   too (MediaTek LK: Volume-Down = factory mode).
6. **USB disk (`ums`) is the Nerves flashing path:** expose **only** `userdata` through a `blkmap`
   bounded to its vendor size (never a vendor tail or another partition), so the host runs
   `fwup -d $(tools/ums-target.sh --port <id> | cut -d' ' -f1) <app>.fw` or `mix burn` directly: no
   `.img`, no sparse, no fastboot buffer limit. Offer `fastboot oem ums` to switch without keys.
   Fastboot stays for `flash boot` (self-update), RAM boot and diagnostics.
7. **Entry without keys:** a DRAM/RTC flag so `fastboot reboot-bootloader` and Linux (write the flag,
   reboot) land back in U-Boot's fastboot; `reboot-recovery` and the vendor's fastboot through the
   boot-mode bits; with nothing bootable, fall into U-Boot's fastboot rather than the vendor's.
8. **Test order:** key-free steps first (allowed unattended): normal boot, enter fastboot from Linux,
   getvars including refused names, `flash boot` through U-Boot's own fastboot with a read-back from
   Linux, `fastboot boot`, `reboot-bootloader`, a large `fastboot stage` transfer for reliability. Then
   the key tests, with the user present and exact instructions. Then the first `userdata` write, with
   its own go.
9. **Artifact hygiene:** name each build `boot-uboot-<sha8>.img` and never overwrite a rollback image.
   A lost known-good image can be recovered by a read-only raw read of the boot region from Linux,
   checked against its sha256.
10. **Unclean resets and the display:** every reboot-mode, guard or forced reset is an unclean reset
    and can leave the vendor display pipeline or panel in a bad state. That is a kernel/panel
    power-sequencing bug, not the bootloader's: track it separately.
