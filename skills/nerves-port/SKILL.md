---
name: nerves-port
description: Turning the working Buildroot port into a Nerves system for an Android device - nerves_system_bootstrap, nerves_defconfig changes, the toolchain choice, required kernel options, A/B layouts inside fixed Android partitions (sub-image in userdata mapped by an initramfs, or boot+system+userdata), fwup.conf/fwup-ops.conf, erlinit.config, slot switching with lk2nd/extlinux or boot.img, replacing init scripts with OTP apps, and the first flash/upload/revert tests. Use in M11.
---

# Nerves on an Android device

Prerequisites: M9 done (a persistent Buildroot system that boots), `dossier/init-inventory.md`
complete. Read the [porting guide](https://hexdocs.pm/nerves/porting-guide.html) sections that apply:
this skill covers what is different on phones. Details on layouts: [android-ab-layouts.md](android-ab-layouts.md).

## 1. Bootstrap

```bash
mix archive.install hex nerves_bootstrap
git clone https://github.com/mlainez/nerves_system_bootstrap cache/nerves_system_bootstrap
# follow its README: point it at buildroot-android/buildroot-external/configs/<id>_defconfig
```

It produces `nerves_system_<id>/` (mix.exs, nerves_defconfig, linux config, fwup.conf, fwup-ops.conf,
rootfs_overlay, post-build.sh). It knows standard SD-card boards; for a phone, adapt the generated
fwup and boot pieces as below. If it can't handle the defconfig, build the system by hand from the
porting guide, starting from `nerves_system_bbb` (armv7) or an aarch64 system.

## 2. nerves_defconfig

- Strip the options listed in the porting guide (toolchain, init, rootfs, overlays…); keep the
  architecture, the kernel (repo + SHA + config + DTB), board packages (firmware, qrtr/rmtfs…).
- Toolchain: `BR2_arm=y` + Cortex-A7/A9/A15 → `nerves_toolchain_armv7_nerves_linux_gnueabihf`;
  `BR2_aarch64=y` → `nerves_toolchain_aarch64_nerves_linux_gnu`. Downstream kernel < 5.4 headers →
  expect patches or a custom toolchain (the Kobo lesson); warn the user.
- Kernel: `SQUASHFS=y`, `SQUASHFS_LZ4=y`, `F2FS_FS=y`, `USB_GADGET=y`, `USB_ETH=y` (or configfs NCM
  via an Elixir gadget setup), `DM_*`/`BLK_DEV_LOOP=y` if the initramfs maps a sub-image.

## 3. Pick the A/B layout (ADR)

Android's partition table is fixed: don't repartition (risk-red). Keep the port's default of writing
only `boot` (lk2nd) and `userdata`. Choose from android-ab-layouts.md:
- **Sub-image in userdata** (FP2 style, most common).
- **Split across boot / system / userdata** when partitions are big enough.
Record the choice, the offsets and the device paths in the decision and in `port.yaml` `path.nerves_layout`.

## 4. Boot flow and slot switching

Whoever starts the kernel must know the active slot:
- **lk2nd + extlinux:** the fwup `on-finish` rewrites `extlinux.conf` (or two labels `nerves_a`/`nerves_b`
  with `default` switched) on a small FAT/ext partition inside the sub-image.
- **Stock LK + boot.img:** a single boot.img with an initramfs that reads the fwup env
  (`nerves_fw_active`) and mounts rootfs A or B, then `switch_root` to erlinit. Revert = env change.
- The **initramfs** (a small busybox cpio, like FP2's) does: mount the parent partition, map the
  sub-image (`losetup -P` / `kpartx -a`), pick the slot from the U-Boot-format env, mount squashfs,
  `switch_root /newroot /sbin/init`.

## 5. erlinit.config and fwup

- `--ctty tty1` (screen) or the gadget's serial ACM; `--hostname-pattern nerves-%s`;
  `-m` mounts for `/root` (the f2fs app partition at its real device path, e.g. `/dev/loop0p4` or
  `/dev/mmcblk0pNN`).
- `fw_env.config`: the device + offset of the env region **inside** the sub-image path as seen by Linux.
- `NERVES_FW_DEVPATH`: the partition (or loop device) holding the image, not the whole eMMC.
- fwup `complete` writes the sub-image; `upgrade` writes the inactive slot and flips the env;
  `fwup-ops.conf` revert flips it back. Test each task on a **file** first
  (`fwup -a -i x.fw -t complete -d test.img`), then on the device.

## 6. Replace init scripts with Elixir

For each row of `init-inventory.md`: VintageNet (WiFi/ethernet/QMI cellular), `nerves_ssh`, OTP apps
for firmware loaders/daemons (supervised `MuonTrap`/port processes for rmtfs/qrtr, or native Elixir
rewrites), `Circuits.GPIO/I2C` for power sequencing. Vendor binaries lie about exit codes: parse their output.
Do the work in Elixir rather than shell once the BEAM runs; any shell left (initramfs, erlinit hooks)
follows `buildroot-port` section 6 and is checked against the Nerves system's own BusyBox config,
which is smaller than the Buildroot board's.

## 7. First flash and tests (orange)

`mix firmware` → `mix firmware.image <id>.img` → `flash-guardian` flashes it to the allowlisted
partition (fastboot/heimdall/`dd` from the rescue system) → boot → IEx over ssh on 10.0.42.1/USB →
`mix upload` → reboot into the new slot → `Nerves.Runtime.revert()` → confirm it boots the old slot.
