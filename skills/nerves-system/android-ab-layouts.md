# A/B layouts inside a fixed Android partition table

The layout is the one of the Nerves porting guide and the official systems, placed inside an
Android partition instead of on an SD card:

```
U-Boot env │ Boot A │ Boot B │ Rootfs A │ Rootfs B │ Application data
```

**Boot A/B and rootfs A/B, always.** The kernel, the device tree and the initramfs live in the
boot slot and are updated and reverted together with their root filesystem. A system with one
boot slot is not accepted: an update that changes the kernel could not be reverted.
`tools/check-nerves-system.sh` fails a system whose upgrade tasks do not write the boot slot.

## The layout: a sub-image in userdata

```
userdata (several GB)
 ├─ MBR of the sub-image: three entries, rewritten by fwup at each upgrade
 │     p1 → the active boot slot      p2 → the active rootfs slot      p3 → application data
 ├─ fwup env (U-Boot env format)                  ← fw_env.config points here
 ├─ Boot A    (FAT, or ext2 for lk2nd: kernel, DTB, initramfs, extlinux.conf or boot.scr)
 ├─ Boot B
 ├─ Rootfs A  (squashfs)
 ├─ Rootfs B
 └─ Application data (f2fs, the rest or a fixed size)
```

- Two MBR definitions (`mbr-a`, `mbr-b`) each list the boot and rootfs slots of one side plus the
  application partition; `upgrade.a`/`upgrade.b` write the inactive boot and rootfs slots, then
  switch the MBR, and `revert` switches it back. So nested p1 is always the active boot slot and
  p2 the active root filesystem, as on an official system.
- The Android `boot` partition holds only the **second stage** (lk2nd or a chainloaded U-Boot),
  written once. It reads nested p1: lk2nd through `extlinux/extlinux.conf`, U-Boot through `blkmap`
  and `sysboot` or `boot.scr`. It is the bootloader, not a Nerves boot slot.
- A device whose stock bootloader can only start one fixed `boot.img` therefore needs a second
  stage. When neither lk2nd nor a chainloaded U-Boot is possible, stop and ask the user: do not
  fall back to a single boot slot on your own.
- An initramfs (in the boot slot) maps the inner partitions (`kpartx -a`, `losetup -P`, or
  `dmsetup`), mounts the active root filesystem and `switch_root`s to erlinit.
- `fastboot flash userdata nerves.img`, heimdall, or fwup to the second stage's USB disk.
- Watch out for vendor-reserved tails (MediaTek BMT, an encryption footer): size the image smaller
  than the partition.

## Not Nerves layouts

- **`boot` + `system` + `userdata` split** (the kernel in Android's `boot`, root filesystems in
  `system`): one boot slot, so a kernel update cannot be reverted. Not used.
- **Stock kernel with a pivot from the stock init** (for a locked bootloader): no boot slot at
  all. Only as an explicit decision of the user for a device that cannot run anything else.

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
- The Buildroot board (the Buildroot branch) needs the same mark-successful step as an init script on such a device.

## Checklist for any layout

- [ ] Every offset is in 512-byte blocks and fits inside the partition minus reserved tails
- [ ] `fw_env.config`, `NERVES_FW_DEVPATH`, `NERVES_FW_APPLICATION_PART0_DEVPATH`, erlinit `-m` agree
- [ ] `fwup -t complete` tested on a file image, partitions inspected with `fdisk -l` / `unsquashfs -s`
- [ ] `tools/check-nerves-system.sh` reports no FAIL (boot A/B, rootfs A/B, the porting guide's requirements)
- [ ] `templates/nerves/host-check-fwup.sh` passes with this layout (copy it with its .conf): upgrade and revert move both the boot and the rootfs slot
- [ ] With a vendor tail (BMT pool, encryption footer): fixed-size app partition, nothing written past it
- [ ] Revert tested on the device
- [ ] The rescue boot still works (RAM boot or a key combo), so a broken Nerves image is never a brick
