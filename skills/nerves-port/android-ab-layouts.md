# A/B layouts inside a fixed Android partition table

## Layout 1: sub-image in userdata (Fairphone 2 Nerves style)

```
userdata (several GB)
 ├─ MBR (of the sub-image)
 ├─ fwup env (U-Boot env format, 128 KiB)        ← fw_env.config points here
 ├─ p1 boot  (FAT/ext2: kernel, DTB, extlinux.conf) [optional, only with lk2nd/extlinux]
 ├─ p2 rootfs A (squashfs)
 ├─ p3 rootfs B (squashfs)
 └─ p4 app data (f2fs, the rest)
```

- `fastboot flash userdata nerves.img` (lk2nd/stock fastboot), or `dd` from the rescue system.
- An initramfs maps the inner partitions: `losetup -P -f /dev/mmcblk0pNN` → `/dev/loop0p2…`, or
  `kpartx -a`. `NERVES_FW_DEVPATH=/dev/loop0` (as seen after mapping) or the raw userdata partition
  with fwup offsets relative to it.
- The kernel + initramfs live in `boot` (stock boot.img or lk2nd → extlinux in p1).
- Watch out for vendor-reserved tails (MediaTek BMT, an encryption footer): size the image smaller
  than the partition.

## Layout 2: boot / system / userdata split

```
boot      kernel + initramfs (boot.img), rewritten only on kernel changes, or by both slots
system    rootfs A + rootfs B as two squashfs blobs at fixed offsets (raw, no filesystem)
userdata  app data (f2fs), or rootfs B + app data if system is too small
```

- Simple and uses real partitions; the initramfs picks the squashfs offset from the env.
- The kernel itself is not A/B here: the stock bootloader always starts `boot`, so a bad kernel
  update cannot be reverted automatically. When the kernel must be A/B too, use lk2nd + extlinux
  (layout 1), which can choose between two kernels.

## Layout 3: Kobo-style pivot (no custom boot possible)

Stock kernel + a hook in the stock init that `losetup`s an image file and `pivot_root`s into it.
Only when the bootloader is locked; needs unsigned module loading for squashfs/f2fs.

## Existing Android A/B (boot_a/boot_b)

Some phones already have Android A/B slots (`boot_a`/`boot_b`, `ro.boot.slot_suffix`,
`fastboot getvar current-slot`). Nerves does **not** use them for its own A/B: its A/B stays the
standard fwup one inside `userdata` (layout 1). The Android slot machinery is neutralised instead:

- **Pin slot a, write slot a only.** The install runs `fastboot set_active a` first (slot a must
  hold a bootable image, never an empty slot), then writes only slot-a partitions and `userdata`:
  `boot` (the second stage), and `dtbo` when the stock bootloader applies Android's per-slot dtbo
  overlays to whatever it boots: a dummy overlay there (nerves_system_fp3 uses z3ntu/dtbo-fp3).
  `dtbo` is not in the default writable set: back it up and allowlist it with the user's agreement.
  Order in nerves_system_fp3's README: `set_active a`, `flash dtbo`, `flash boot`, `flash userdata`.
- Mark the current slot successful once boot is stable, on every boot. Otherwise the bootloader's
  per-slot retry counter (in the GPT attributes on Qualcomm) drains at each boot, the slot becomes
  unbootable, and the phone ends in fastboot. Reference: nerves_system_fp3 ships `qbootctl`
  (`packages/qbootctl`: version 0.2.2 from linux-msm/qbootctl, depends on zlib, enabled by
  `BR2_PACKAGE_QBOOTCTL=y` in `nerves_defconfig`, installed as `/usr/bin/qbootctl`) and the Elixir app
  [mlainez/ex_qbootctl](https://github.com/mlainez/ex_qbootctl) runs `qbootctl -m` once the system
  is up.
- Non-Qualcomm A/B: find the equivalent boot-control mechanism (the vendor's boot_control HAL; on
  MediaTek or Samsung, slot metadata in `misc` or a `para`-type partition) and do the same.
- Nerves A/B stays inside `userdata` (the fp3 initramfs runs `kpartx -asf` on it to expose the
  sub-image's partitions).
- The Buildroot board (M9) needs the same mark-successful step as an init script on such a device.

## Checklist for any layout

- [ ] Every offset is in 512-byte blocks and fits inside the partition minus reserved tails
- [ ] `fw_env.config`, `NERVES_FW_DEVPATH`, `NERVES_FW_APPLICATION_PART0_DEVPATH`, erlinit `-m` agree
- [ ] `fwup -t complete` tested on a file image, partitions inspected with `fdisk -l` / `unsquashfs -s`
- [ ] Revert tested on the device
- [ ] The rescue boot still works (RAM boot or a key combo), so a broken Nerves image is never a brick
