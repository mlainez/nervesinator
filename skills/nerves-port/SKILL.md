---
name: nerves-port
description: Turning the working Buildroot port into a Nerves system for an Android device - nerves_system_bootstrap, nerves_defconfig changes, the toolchain choice, required kernel options, A/B layouts inside fixed Android partitions (sub-image in userdata mapped by an initramfs, or boot+system+userdata), fwup.conf/fwup-ops.conf, erlinit.config, slot switching with lk2nd/extlinux or boot.img, replacing init scripts with OTP apps, and the first flash/upload/revert tests. Use in M11.
---

# Nerves on an Android device

Prerequisites: M9 done (a persistent Buildroot system that boots), `dossier/init-inventory.md`
complete. Read the [porting guide](https://hexdocs.pm/nerves/porting-guide.html) sections that apply:
this skill covers what is different on phones. Details on layouts: [android-ab-layouts.md](android-ab-layouts.md).

## 0. Reference systems

Start from the **official** systems and docs, which define what a Nerves system is:

- [github.com/nerves-project](https://github.com/nerves-project): `nerves_system_rpi*`,
  `nerves_system_bbb` (armv7), `nerves_system_x86_64`, `nerves_system_qemu_*`, and
  `nerves_system_br` (its default Buildroot, BusyBox and kernel requirements);
- hexdocs.pm/nerves: the porting guide and "Customizing your Nerves system".

Use the user's phone systems only for what is specific to Android phones (lk2nd/extlinux boot, A/B
inside `userdata`, firmware taken from vendor partitions): Spin42/nerves_system_fairphone2,
mlainez/nerves_system_fp3, nerves_system_tickwatch_pro3, Spin42/nerves_system_grouper, and
mlainez/nerves_system_bootstrap to generate the skeleton. Reuse their structure, fwup A/B layout,
erlinit config and firmware handling rather than designing from scratch.

## 1. Bootstrap

```bash
mix archive.install hex nerves_bootstrap
git clone https://github.com/mlainez/nerves_system_bootstrap cache/nerves_system_bootstrap
# follow its README: point it at buildroot-android/buildroot-external/configs/<id>_defconfig
```

It produces `nerves_system_<id>/` (mix.exs, nerves_defconfig, linux config, fwup.conf, fwup-ops.conf,
rootfs_overlay, post-build.sh). It knows standard SD-card boards; for a phone, adapt the generated
fwup and boot pieces as below. If it can't handle the defconfig, build the system by hand from the
porting guide, starting from `nerves_system_bbb` (armv7) or an aarch64 official system.

## 2. nerves_defconfig

- Strip the options listed in the porting guide (toolchain, init, rootfs, overlays…); keep the
  architecture, the kernel (repo + SHA + config + DTB), board packages (firmware, qrtr/rmtfs…).
- Toolchain: `BR2_arm=y` + Cortex-A7/A9/A15 → `nerves_toolchain_armv7_nerves_linux_gnueabihf`;
  `BR2_aarch64=y` → `nerves_toolchain_aarch64_nerves_linux_gnu`. Downstream kernel < 5.4 headers →
  expect patches or a custom toolchain (the Kobo lesson); warn the user.
- Kernel: `SQUASHFS=y`, `SQUASHFS_LZ4=y`, `F2FS_FS=y`, `USB_GADGET=y`, `USB_ETH=y` (or configfs NCM
  via an Elixir gadget setup), `DM_*`/`BLK_DEV_LOOP=y` if the initramfs maps a sub-image.

## 2b. Review against the official systems (and productize)

The board's `linux.config` and overlay come from a Buildroot port with first-light and debug aids.
Never copy them verbatim. Diff the kernel config against the official systems' defconfigs and the
`nerves_system_br` requirements, and justify every difference in `dossier/nerves-config-review.md`:

| Option | Buildroot port | Official Nerves | Chosen | Why |
|---|---|---|---|---|

- **Remove** what a Buildroot port carries but Nerves systems do not: first-light aids
  (`# CONFIG_LOGO is not set`, as nerves_system_fp3 does; framebuffer console extras), a verbose
  console (`loglevel=7/8`, `ignore_loglevel` on the cmdline), debug options (`DEBUG_INFO`,
  `KALLSYMS_ALL` extras), unused filesystems, module signing or compression that conflicts with
  Nerves.
- **Add** what Nerves needs, as the official systems enable it: squashfs with the chosen compression,
  f2fs or ext4 for `/root`, devtmpfs, the USB gadget, the watchdog, the RTC, cgroups and namespaces.
- Put the cleanup in a fragment (`linux-nerves.fragment`) so the board's config stays the source.
- Do the same for `erlinit.config`, `fwup.conf`, `fwup-ops.conf` and the rootfs overlay: compare with
  the official templates first, then with the phone systems, and record each difference.

## 3. Pick the A/B layout (ADR)

A/B is introduced here, with the standard Nerves mechanism (fwup env, rootfs A/B, app partition);
the Buildroot board stays single-root as it is.
Android's partition table is fixed: don't repartition (risk-red). Keep the port's default of writing
only `boot` (the second stage or `boot.img`) and `userdata`. Choose from android-ab-layouts.md:
- **Sub-image in userdata** (FP2 style, most common).
- **Split across boot / system / userdata** when partitions are big enough.
Record the choice, the offsets and the device paths in the decision and in `port.yaml` `path.nerves_layout`.

## 4. Boot flow and slot switching

If the phone already has Android A/B slots (`device.android_ab`), Nerves does not use them:
neutralise them (active slot only, mark it successful on every boot with qbootctl or the vendor
equivalent, as nerves_system_fp3 and ex_qbootctl do). See android-ab-layouts.md, "Existing
Android A/B".

Whoever starts the kernel must know the Nerves active slot:
- **Chainloaded U-Boot** (no lk2nd for the SoC): its env lives where fwup writes it (`fw_env.config`),
  `nerves_fw_active` picks the slot, and `sysboot` reads extlinux from the sub-image through `blkmap`
  (`uboot-chainload`).
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

Check what the screen shows, not only the logs: stderr of early scripts and BEAM warnings go to the
console. Over ssh, `File.cp!("/dev/fb0", "/tmp/fb.raw")`, fetch it (`scp -O` or sftp), and convert it to
PNG with the bits per pixel and stride from `/sys/class/graphics/fb0/` (`bits_per_pixel`, `stride`,
`virtual_size`).

Logger on recent Elixir (1.20 warns that the `:backends` key of `:logger` is deprecated, which
`nerves_bootstrap`-generated apps still use for RingLogger): add `{:logger_backends, "~> 1.0"}`, set
`config :logger, :default_handler, false` in `target.exs`, and in `config/runtime.exs` under
`if config_target() != :host`: `Application.ensure_all_started(:logger_backends)` then
`LoggerBackends.add(RingLogger)` (RingLogger 0.11.7 changelog). RingLogger keeps the boot logs and the
console stays clean.

`mix firmware` → `mix firmware.image <id>.img` → `flash-guardian` flashes it to the allowlisted
partition (fastboot/heimdall/`dd` from the rescue system) → boot → IEx over ssh on 10.0.42.1/USB →
`mix upload` → reboot into the new slot → `Nerves.Runtime.revert()` → confirm it boots the old slot.

## 8. Ship it: dependencies, a one-command installer, releases (M12)

Every port's Nerves system ships so that someone else can put Nerves on a **pristine stock phone**
safely, in one command:

1. **README "Dependencies"**: host packages per distribution (adb, fastboot, heimdall…), udev rules
   for every USB mode the install uses, what to do once on the phone (Developer options, USB
   debugging, OEM unlock toggle), and the battery and cable rules (charged above 50 %, a data cable,
   a wall supply nearby).
2. **`install.sh`**, from stock to Nerves:
   - a dry run by default that prints the exact plan; a typed confirmation that names the
     irreversible costs (data wipe, warranty/KNOX fuse) before anything is written;
   - preflight identity checks (model, codename, bootloader version) and one device only, by serial;
   - the vendor unlock when needed;
   - backups of the class B partitions (calibration, IMEI) through a temporary or custom recovery,
     kept on the user's computer, before any write;
   - the second-stage bootloader and the latest Nerves release image from GitHub, written to the
     port's allowlisted partitions only (`boot`, `userdata` by default), through the port's proven
     key-free path (on a Samsung, for example: `adb reboot download`, heimdall, `adb reboot recovery`);
     on an Android A/B phone, `set_active a` first and slot-a partitions only (android-ab-layouts.md);
   - every downloaded asset verified (the release's `SHA256SUMS`; upstream signatures or checksums
     for third-party images such as TWRP) before use;
   - the kit's rules built in, since the kit's guard does not run on the user's computer: the
     forbidden partition list, no relock, no repartition;
   - at every step that can fail, what state the phone is in and how to recover.
3. **A release recipe** so each GitHub release carries what the installer needs: the raw image (and
   `.fw`), the bootloader image, `SHA256SUMS`, and the source references for the GPL parts (kernel
   commit, Buildroot and package versions).
