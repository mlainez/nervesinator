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
- Kernel: `SQUASHFS=y` with gzip (as the official systems; `mix firmware` rebuilds the squashfs with
  gzip), `F2FS_FS=y`, `USB_GADGET=y` with the built-in legacy `g_ether` (`USB_ETH=y`, RNDIS) as the
  official device-port systems use, no ACM serial (rpi0 dropped `g_cdc` for stability),
  `DM_*`/`BLK_DEV_LOOP=y` if the initramfs maps a sub-image.

## 2b. Review against the official systems (and productize)

**Compliance checklist**, against an official system built on the **same `nerves_system_br`
version**: `erlinit.config`; `fw_env.config`, the board-id and provisioning setup; the fwup metadata
and every `nerves_fw_*` variable `nerves_runtime` expects; the `nerves_defconfig` must-haves; the
`nerves_package` fields of `mix.exs`; the USB gadget and console against an official system with a
device port (rpi0, bbb); networking as `nerves_pack` sets it (no static 10.0.42.x, no DHCP server).
The app is checked against a fresh `mix nerves.new` (`nerves-app-engineer`). Compliance means no
carry-over from the Buildroot board unless the hardware requires it, each one justified. Results
go into `dossier/nerves-config-review.md`.

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
- **Add** what Nerves needs, as the official systems enable it: gzip squashfs, f2fs or ext4 for
  `/root`, devtmpfs, the USB gadget, the watchdog, the RTC, cgroups and namespaces (`MEMCG`,
  `BLK_CGROUP`, `CGROUP_PIDS`), `PSTORE_PMSG`.
- **Common carry-overs from a Buildroot board** (remove unless the hardware needs them): an LZ4
  squashfs; Buildroot debug tools in the rootfs (`iw`, `i2c-tools`, `evtest`, libgpiod tools,
  `usbutils`); a configfs NCM/ACM gadget instead of `g_ether`; a static address and DHCP server;
  fixed gadget MACs; a build-time Wi-Fi secrets file; erlinit mounting debugfs. Also check what
  the official systems have that a board lacks: the memory cgroup mounted by erlinit, `libp11` and
  `unixODBC`, `wpa_supplicant` options as rpi0/bbb, the `Toolchain` `:env` with the CPU flags in
  `mix.exs`.
- **Justified differences** look like: the console on `tty1` when there is no UART or ACM; an
  initramfs recovery shell keeping a rescue address (it is not Nerves); a nested-firmware
  initramfs (kpartx, or `losetup -P` to drop multipath-tools/eudev); `kmod` for `modprobe.d`
  remove rules; `STRICT_DEVMEM` off only for a documented tool.
- **Traps seen:** `CONFIG_CMDLINE_FORCE=y` in the board config silently ignores the bootloader's
  and extlinux's `append`: remove it. `MEDIA_SUPPORT=m` builds a hundred-odd unused DVB modules:
  select only what the hardware has. `mix firmware` rebuilds the squashfs with gzip, so
  `SQUASHFS_ZLIB` is needed even when the Buildroot rootfs used LZ4.
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
  (`uboot-chainload`). Its `ums` mode exposes only `userdata`, so the host writes the firmware with
  `fwup -a -i <app>.fw -t complete -d $(tools/ums-target.sh --port <id> | cut -d' ' -f1)`
  (the firmware goes with `-i`; a bare `x.fw` argument fails with "unexpected parameter"), or
  `mix burn`, and its own
  fastboot handles `flash boot` and RAM boots. The disk must not be mounted on the host (the
  desktop may mount the boot FAT or the app partition): `ums-target.sh` refuses then; finish with
  `sync` and `udisksctl power-off -b /dev/sdX` before leaving UMS.
- **lk2nd + extlinux:** the fwup `on-finish` rewrites `extlinux.conf` (or two labels `nerves_a`/`nerves_b`
  with `default` switched) on a small FAT/ext partition inside the sub-image.
- **Stock LK + boot.img:** a single boot.img with an initramfs that reads the fwup env
  (`nerves_fw_active`) and mounts rootfs A or B, then `switch_root` to erlinit. Revert = env change.
- The **initramfs** (a small busybox cpio, like FP2's) does: mount the parent partition, map the
  sub-image (`losetup -P` / `kpartx -a`), pick the slot from the U-Boot-format env, mount squashfs,
  `switch_root /newroot /sbin/init`.

## 5. erlinit.config and fwup

- `--ctty tty1` (screen) when there is no UART (official device-port systems have no ACM console);
  `--hostname-pattern nerves-%s`;
  `-m` mounts for `/root` (the f2fs app partition at its real device path, e.g. `/dev/loop0p4` or
  `/dev/mmcblk0pNN`).
- `fw_env.config`: the device + offset of the env region **inside** the sub-image path as seen by Linux.
- `NERVES_FW_DEVPATH`: the partition (or loop device) holding the image, not the whole eMMC.
- fwup `complete` writes the sub-image; `upgrade` writes the inactive slot and flips the env;
  `fwup-ops.conf` revert flips it back. Test each task on a **file** first with
  `templates/nerves/host-check-fwup.sh` (complete, upgrade, revert twice, validate,
  prevent-revert, factory-reset on a sparse file the size of the target partition, and nothing
  written past the layout), then on the device. An asdf-managed fwup needs a version selected
  (`.tool-versions` or `ASDF_FWUP_VERSION`), or every call fails with "No version is set".
- With a vendor tail at the end of the partition (MediaTek BMT pool), the app partition has a fixed
  size (no `expand`) and the host check asserts nothing lands past the layout.
- Boot slots inside the sub-image can be FAT, filled with fwup `fat_write`, when U-Boot reads them;
  ext2 is only needed for lk2nd.
- Board packages can come from a pinned buildroot-android commit tarball rather than copied
  sources; non-redistributable firmware lives in a git-ignored `firmware/` directory; an
  unpublished kernel fork goes through `local.mk` `LINUX_OVERRIDE_SRCDIR`, documented in a
  committed `local.mk.example`.
- Package versions drift between the board's Buildroot and `nerves_system_br`'s: patches pinned
  to one release (e.g. libcamera 0.5) may not apply to the next; check each board patch.
- **Networking is official Nerves, unchanged.** The kit's 10.0.42.1/10.0.42.2 convention belongs to
  its first-light, rescue and Buildroot images only. A Nerves system and app use `nerves_pack`'s
  defaults: `usb0` through `VintageNetDirect`, `mdns_lite` with the hostname and `nerves.local`,
  `ssh nerves.local`, `mix upload nerves.local`. The USB gadget follows an official system with a
  device port (rpi0, bbb): compare their kernel gadget config and console.

## 6. Replace init scripts with Elixir

For each row of `init-inventory.md`: VintageNet (WiFi/ethernet/QMI cellular), `nerves_ssh`, OTP apps
for firmware loaders/daemons (supervised `MuonTrap`/port processes for rmtfs/qrtr, or native Elixir
rewrites), `Circuits.GPIO/I2C` for power sequencing. Vendor binaries lie about exit codes: parse their output.
Do the work in Elixir rather than shell once the BEAM runs; any shell left (initramfs, erlinit hooks)
follows `buildroot-port` section 6 and is checked against the Nerves system's own BusyBox config,
which is smaller than the Buildroot board's.

## 7. First flash and tests (orange)

The test app is generated with `mix nerves.new` (it brings `nerves_pack`: `nerves_runtime`, ssh,
MOTD, VintageNet), then gets the device's bits. A hand-assembled app misses pieces the system
expects (e.g. `iex.exs` calling `NervesMOTD.print` with no `nerves_motd`).

The raw write to the phone's USB disk may be blocked by the host tool's permission rules (Claude
Code's auto mode refuses it): expect the user to run it. Give them the exact command with the
target check inline (`fwup -a -i <app>.fw -t complete -d $(tools/ums-target.sh --port <id> | cut -d' ' -f1)`), or they add a permission rule for it.

Load the display stack from the initramfs: loaded late (as a module after the BEAM starts) its
takeover blink lands after the MOTD. Loading modules from the initramfs needs `modules.dep`
generated at build time (`depmod` for the initramfs tree); an initramfs package that empties its
module list or ships no `modules.dep` cannot load them. Gadget MACs stay random as in the
official systems; fixed `dev_addr`/`host_addr` only after measuring a real reconnect problem on
the user's host, and recorded as a justified difference.

Wi-Fi: no build-time secrets file; `VintageNetWiFi.quick_configure/2` at runtime (VintageNet
persists it). Before changing networking through `mix upload`, check for persisted VintageNet
configuration (`/root/vintage_net`, `VintageNet.get_configuration/1`): it overrides new defaults.

A clean console: vendor drivers that print debug at warning level (e.g. MediaTek CONSYS
`[STP-PSM]`, `[wlan]`) flood `tty1` over the IEx prompt. Set their debug levels through
`/etc/modprobe.d` in the Nerves system and pick a cmdline `loglevel`, so the panel shows the MOTD
and a prompt.

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
partition (fastboot/heimdall/`dd` from the rescue system, or the second stage's USB disk) → boot →
`tools/await-boot.sh --watch-only --host nerves.local` → IEx over `ssh nerves.local` →
`mix upload nerves.local` → reboot into the new slot → `Nerves.Runtime.revert()` → confirm it boots the old slot.

## 8. Ship it: dependencies, a one-command installer, releases (M12)

With a U-Boot second stage, the installer flashes `boot` once through the vendor path, then uses
U-Boot's `ums` for `userdata` (fwup straight to the USB disk, found by serial, never a guessed
`/dev/sdX`) and U-Boot's fastboot for later `boot` updates.

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
