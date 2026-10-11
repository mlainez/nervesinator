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
└─ yes → Does the stock bootloader support `fastboot boot` (temporary boot from RAM)?
         ├─ yes → Does it load a mainline kernel + DTB fine
         │        (an Android boot image v0-2 with an appended DTB, or a matching QCDT)?
         │        ├─ yes → No second stage needed: pack boot.img (TB3-710F: stock LK, appended DTB).
         │        └─ no / painful (QCDT picking, a cmdline it overrides, a size limit)
         │               → lk2nd (Qualcomm) or chainloaded U-Boot: `fastboot boot` it first.
         └─ no (Samsung download mode, some MTK) →
                  Is lk2nd/U-Boot available for this SoC? (Samsung msm8916/msm8226/msm8974: often yes)
                  ├─ yes → Flash it to a spare boot-type partition (recovery first, so Android
                  │        still boots from boot), then lk2nd gives us fastboot + `fastboot boot`.
                  └─ no  → Use `recovery` as the experiment partition for every test boot image;
                           `boot` stays stock as the escape route.
```

**Experiment partition rule:** if there is no RAM boot, use **one** partition (normally
`recovery`) for experiments and keep the other one stock. Record it as `safety.experiment_partition`.

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
