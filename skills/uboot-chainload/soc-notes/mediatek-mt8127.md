# MediaTek MT8127 (PMIC MT6323): U-Boot chainloaded by stock LK

Proven: mainline v2026.10 in `boot`, chainloaded by LK, boots a Buildroot root through extlinux
(the image confirmed by `/proc/device-tree/chosen/u-boot,version`, a clean reboot, a normal display).
Values for this SoC and PMIC; re-check them on another board.

## Memory map

| What | Value |
|---|---|
| LK's jump address = `CONFIG_TEXT_BASE` | `0x80008000` (no SPL, `SKIP_LOWLEVEL_INIT`, DTB appended, `OF_SEPARATE`) |
| Pre-relocation stack / pre-console buffer | `0x80e00000` / `0x80f00000` |
| Usable top (reserved CONSYS area above) / relocation | `0xbc000000` / `0xbbfb8000` |
| `kernel_addr_r` / `fdt_addr_r` / `ramdisk_addr_r` / `scriptaddr` | `0x80800000` / `0x83f00000` / `0x84000000` / `0x83e00000` |
| `bootm_size` | `0x10000000` (`fdt_high=~0` prints "will likely fail to boot") |
| LK framebuffer (simplefb) | `0xbee00000`, 1024x600 RGB565, stride 2048 |
| `memlog` | `0xbfd00000`, inside LK's reserved video memory (`0xbc0f0000` in CONSYS was wiped by the WiFi firmware) |

## Boot mode bits (MT6323 RTC)

PDN1 bit 13 = fastboot, bit 4 = recovery, written through pwrap. LK clears bit 13 itself but **not**
bit 4 on the boot-mode path (only its power-on/charger check does): U-Boot clears it just before
booting Linux. A hang then becomes a key-free recovery boot through the watchdog (`boot_reason=2`).

## Drivers and timer

- Arch timer: gated by GPT6 (`GPT6_CON` `0x10008060` = `0x31`), which LK leaves off; the SoC patch's
  `mach_cpu_init` ungates it, as Linux's `arch/arm/mach-mediatek/mediatek.c` does.
- MMC: `MMC_MTK` with an `mediatek,mt8135-mmc` compatible, 8-bit, 52 MHz SDR. **No DDR52**: it
  corrupted writes on this eMMC.
- Watchdog: `mtk_wdt`, autostart, 15 s timeout, fed every second by `cyclic`.
- MTK MBR + EBR are read as DOS partitions numbered exactly like Linux (`mmc 0:7` = `mmcblk0p7`).

## Not available yet

USB gadget (ACM console or fastboot) needs MT8127 MUSB glue and USB2 PHY init in U-Boot. The
MediaTek AIoT BSP fork had nothing usable for MT8127/MT6323.
