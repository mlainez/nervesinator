---
name: nerves-system
description: Stage S4 of a port - the Nerves system, started from the closest existing system in the awesome-nerves-systems family rather than from scratch. Covers the family index and the scaffold tool, the A/B layout inside fixed Android partitions (a sub-image in userdata mapped by an initramfs), fwup.conf and fwup-ops.conf, erlinit, slot switching with lk2nd/extlinux or U-Boot, the test app generated with mix nerves.new, the first flash, mix upload and revert. Use when tools/kit-next.sh shows stage S4, as soon as gate G1 has passed for the host part.
---

# S4 Nerves

The port goes from the rescue shell straight to Nerves: the Nerves system is a Buildroot
defconfig of its own, so a persistent Buildroot system first would be built twice. (A
buildroot-android board is an optional branch, `buildroot-port`.)

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
3. **Layout**: sizes and offsets in 512-byte blocks checked against the partition sizes and the
   reserved tails, `path.nerves_layout` recorded, and proven on a file image before any device
   write: `templates/nerves/host-check-fwup.sh` → `checks.fwup_host`.
4. **Test app**: `mix nerves.new` plus the device's bits (app.md), `mix firmware`.
5. **First flash**: `tools/safe-flash.sh` to the allowlisted partitions (or fwup to the second
   stage's USB disk, `tools/ums-target.sh`), then
   `tools/await-boot.sh --port <id> --watch-only --stage nerves --host nerves.local`.
6. **Prove updates**: `mix upload`, a reboot into the new slot, `Nerves.Runtime.revert`; record
   `checks.upload` and `checks.revert` with their proof.
7. **Charging** (`peripherals` firmware.md, Charging): voltage readable, charges on a PC port and a
   wall supply, across every reboot and flash path → `checks.charging`. Long unattended device work
   waits for it.

Init work the device needs (firmware loading, module order, daemons) is written in Elixir from
the start; shell stays in the initramfs only.
