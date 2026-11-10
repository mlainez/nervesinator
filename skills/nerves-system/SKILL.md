---
name: nerves-system
description: Stage S4 of a port - the Nerves system, started from the closest existing system in the awesome-nerves-systems family rather than from scratch. Covers the family index and the scaffold tool, the A/B layout inside fixed Android partitions (a sub-image in userdata mapped by an initramfs), fwup.conf and fwup-ops.conf, erlinit, slot switching with lk2nd/extlinux or U-Boot, the test app generated with mix nerves.new, the first flash, mix upload and revert. Use when tools/kit-next.sh shows stage S4, as soon as gate G1 has passed for the host part.
---

# S4 Nerves

Two rules frame this stage. The system follows the
[Nerves porting guide](https://hexdocs.pm/nerves/porting-guide.html) and looks like an official
system (porting.md, "What compliant means"). And its layout is **boot A/B plus rootfs A/B**, never
a single boot slot: the kernel is updated and reverted with its root filesystem.
`tools/check-nerves-system.sh` enforces both.

The guide's "working Buildroot system first" is the rescue shell of S3; from there the port goes
to Nerves, whose system is a Buildroot defconfig of its own. (A persistent buildroot-android
board is an optional branch, `buildroot-port`.)

| Need | Reference |
|---|---|
| Which existing system to start from | [family.md](family.md), `tools/scaffold-system.sh --port <id> --list` |
| What is different on phones; config review against the official systems; first flash | [porting.md](porting.md) |
| A/B inside Android partitions, phones with Android A/B slots | [android-ab-layouts.md](android-ab-layouts.md) |
| The test app and the device's Elixir bits | [app.md](app.md) |

## Steps

1. **Scaffold** (host, as soon as G1 passed):
   ```bash
   tools/scaffold-system.sh --port <id>          # from path.reference_system
   ```
   It copies the reference system into `ports/<id>/nerves_system_<name>/`, renames it, and lists
   every line that still carries the reference device (partition numbers, DTB names, firmware
   packages, U-Boot defconfig). Replace each with this port's facts; keep the reference's structure,
   fwup layout and initramfs unless a hardware fact forces a change, and say which.
   With no similar system, start from `nerves_system_bootstrap` (porting.md section 1).
2. **Kernel and config**: the kernel from `path.kernel_repo` at a pinned ref, the config reviewed
   against the official systems (porting.md section 2b). Build in the background
   (`tools/br-make.sh` caches), waiting by PID.
3. **Compliance**: `tools/check-nerves-system.sh --port <id>` until it reports no FAIL; each WARN
   is fixed or justified in `dossier/nerves-config-review.md`. Run it again after every change to
   the defconfig, the kernel config or the fwup files.
4. **Layout**: sizes and offsets in 512-byte blocks checked against the partition sizes and the
   reserved tails, `path.nerves_layout` recorded, and proven on a file image before any device
   write: `templates/nerves/host-check-fwup.sh` → `checks.fwup_host`.
5. **Test app**: `mix nerves.new` plus the device's bits (app.md), `mix firmware`.
6. **First flash**: `tools/safe-flash.sh` to the allowlisted partitions (or fwup to the second
   stage's USB disk, `tools/ums-target.sh`), then
   `tools/await-boot.sh --port <id> --watch-only --stage nerves --host nerves.local`.
7. **Prove updates**: `mix upload` of a firmware with a changed kernel or DTB, a reboot into the new
   slot (the boot slot switched too), `Nerves.Runtime.revert`; record
   `checks.upload` and `checks.revert` with their proof.
8. **Charging** (`peripherals` firmware.md, Charging): voltage readable, charges on a PC port and a
   wall supply, across every reboot and flash path → `checks.charging`. Long unattended device work
   waits for it.

Init work the device needs (firmware loading, module order, daemons) is written in Elixir from
the start; shell stays in the initramfs only.
