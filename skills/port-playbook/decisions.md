# Decision trees

Record each outcome as a Backlog.md decision (`backlog decision create "<title>"`) and in
`port.yaml` `path:`. State the evidence and the fallback.

## 1. Which kernel?

```
Is there a pmaports device package for this exact device using a mainline kernel
(linux-postmarketos-<soc> or a close-to-mainline SoC fork)?
├─ yes → Scenario A: use that kernel repo + commit, its config-* as the base, its DTB name.
│        (Best case: Fairphone 2 on msm8974-mainline.)
└─ no → Is the SoC supported in mainline or a SoC fork (dtsi exists)?
        ├─ yes → Scenario B: write a board DTS from the downstream DT + a sibling board.
        │        Expect weeks, not days. Start with simplefb + USB + eMMC only.
        │        (TB3-710F story: mainline mt8127.dtsi, board support added by hand.)
        └─ no → Scenario C: downstream kernel (LineageOS / vendor source).
                 Check: CONFIG_MODULES=y and no CONFIG_MODULE_SIG enforcement?
                 Kernel ≥ 4.x? Nerves wants headers ≥ 5.4: expect package patches,
                 maybe a custom toolchain (Kobo story). Warn the user about the extra work.
```

Questions to answer for any choice: Does the DTB exist in the tree (name)? What does it enable
(display? USB? eMMC?)? Which config does pmOS use? Last commit date? Known regressions?

## 2. Which boot path?

```
Can the stock bootloader be unlocked (or does it already accept unsigned images)?
├─ no  → STOP: secure boot. Options: a vendor exploit (Kobo-style pivot_root from the stock OS),
│        or choose another device. Never try to bypass signatures by writing bootloader partitions.
└─ yes → Qualcomm SoC supported by lk2nd? (msm8916/8939/8952/8953/8974/8226/8610/…)
         ├─ yes → lk2nd, flashed to `boot` as postmarketOS does (after backing up `boot`).
         │        `fastboot boot lk2nd.img` first when the stock
         │        bootloader allows it. lk2nd then gives us fastboot + `fastboot boot`.
         └─ no  → Does the stock bootloader support `fastboot boot` (temporary boot from RAM)?
                  ├─ yes → Does it load a mainline kernel + DTB fine
                  │        (an Android boot image v0-2 with an appended DTB, or a matching QCDT)?
                  │        ├─ yes → No second stage needed: pack boot.img (TB3-710F: stock LK, appended DTB).
                  │        └─ no / painful (DTB picking, a cmdline it overrides, a size limit)
                  │               → chainloaded U-Boot: `fastboot boot` it first, then `boot`.
                  └─ no (Samsung Exynos download mode, some MTK) →
                           Chainloaded U-Boot available for this SoC?
                           ├─ yes → Flash it to `boot` (after backing up `boot`).
                           └─ no  → Use `boot` as the experiment partition for every test boot image.
```

**Escape route rule:** keeping Android bootable is not a goal; keeping the flash mode and a return
to stock possible is (see `device-safety`). The safety net is `aboot` (with the rest of class A,
never written): it always brings the phone into its flash mode (fastboot on most Qualcomm phones,
download mode on Samsung), which reflashes `boot` with lk2nd, `backups/boot.img` or full stock.
Without a RAM boot, `boot` is the experiment partition; record it as `safety.experiment_partition`.

## 3. Where does the rootfs live?

| Option | When | Notes |
|---|---|---|
| Initramfs only | M7–M8, rescue | Nothing written |
| ext4 on `userdata` | First persistent Buildroot | Simple; `root=/dev/mmcblk0pN rootwait`. Check whether the vendor reserves a tail (MTK BMT pool, encryption footer) and keep the filesystem smaller |
| extlinux + rootfs on `userdata` (lk2nd) | Qualcomm with lk2nd | lk2nd scans for `extlinux/extlinux.conf`; buildroot-android FP2 style |
| Sub-image (MBR inside `userdata`) | Nerves A/B | Partitions mapped by the initramfs with kpartx/losetup; FP2 Nerves style |
| `system` partition | userdata too small or must be kept | Often 1-3 GB, fine for Buildroot/Nerves |

Never repartition (PIT/GPT rewrite) as a first choice: it is `risk-red`.

## 4. Display console

simplefb/simpledrm with the framebuffer the bootloader left behind (`lk2nd` or stock LK often
passes it) → fbcon on tty0. If the bootloader does not leave a framebuffer, a panel driver is needed
(pmOS often has a generated one from `linux-mdss-panel-driver-generator`). Fallbacks: earlycon on a
UART (test points, a Samsung USB jig), or pstore/ramoops read after a warm reboot.
