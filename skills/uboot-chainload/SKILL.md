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

## 3. Chainloading design

- **No SPL, no DRAM init:** the stock bootloader has set up DRAM and clocks
  (`CONFIG_SKIP_LOWLEVEL_INIT` on arm32; on arm64 boot as a kernel-image payload).
- **Load address:** `CONFIG_TEXT_BASE` = the address where the stock bootloader puts the boot image's
  kernel (`device.bootimg` base + kernel offset), or position-independent where supported.
- **Packing:** U-Boot (with its DTB appended when the bootloader expects zImage-dtb) becomes the
  "kernel" of an Android boot image built with the stock `mkbootimg` arguments, plus any vendor
  header or footer (`boot-images`).
- **DT:** a board DTS for U-Boot, ideally the same file the kernel uses.
- **Console:** a UART if one is reachable; otherwise the framebuffer the stock bootloader leaves
  (a `simple-framebuffer` node, video console), so the screen shows U-Boot's output.
- **Watchdog:** keep the vendor watchdog fed (its driver in U-Boot), or the phone resets mid-boot.
- **Storage:** the SoC's MMC driver; find `userdata` by name. Buildroot: `sysboot`/distro boot of
  `/extlinux/extlinux.conf` on the single root. Nerves (M11): partition 1 of the sub-image MBR inside
  `userdata`, exposed with `blkmap` over the `userdata` slice.
- **Environment:** where Nerves fwup can write it too: a region inside the sub-image that
  `fw_env.config` describes, so `nerves_fw_active` selects the slot.

## 4. Boot-once guard

At U-Boot start, set the boot-mode bit the stock bootloader reads (a PMIC/RTC register or the
reboot-reason word, as the vendor's `reboot-mode` values give) to recovery or its flash mode; clear
it just before handing over to Linux. A hang followed by a watchdog reset then lands in the
flash/recovery mode instead of a boot loop. Find the register and values from the vendor kernel's
reboot driver or the device tree's `reboot-mode` node, and test that the bit survives the reset.

## 5. Optional: U-Boot fastboot

`CONFIG_USB_FUNCTION_FASTBOOT` with the SoC's USB gadget driver gives an lk2nd-like flash mode
(`fastboot flash userdata`, `fastboot boot`) reachable by command, which helps key-free and
unattended work. It also needs the guard's rules: only allowlisted partitions.

## 6. Testing

- RAM first when the stock bootloader can (`fastboot boot`); otherwise through the port's key-free
  flash path to `boot`, after checking the escape route by hand (the vendor flash mode reachable
  with keys or by command, `backups/boot.img` verified).
- Steps that each must pass before the next: U-Boot prints on the console (with its `In/Out/Err`
  lines), the timer runs (the countdown moves), the watchdog does not fire, MMC lists the partitions, `sysboot` finds extlinux, Linux starts with the expected cmdline,
  the boot-once guard turns a deliberate hang into the flash mode.
- Each image goes through `safe-flash.sh` and `await-boot.sh` like any other.

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
