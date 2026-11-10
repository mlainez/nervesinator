# The family: start from the closest existing system

[awesome-nerves-systems](https://github.com/mlainez/awesome-nerves-systems) lists the Nerves
systems people have published. It is the guide for a new device: as soon as a listed device is
similar, the new port starts from it and changes only what its hardware forces.

## What makes a device similar

In order of weight: the **SoC** (same chip, then same vendor), the **second stage** (lk2nd,
chainloaded U-Boot, none), the **flash mode** (fastboot, Samsung download mode, MediaTek
fastboot), the **architecture**, and whether the phone has **Android A/B slots**. Two systems on
different SoCs with the same boot path share their fwup layout, initramfs and installer; two on
the same SoC also share kernel tree, firmware handling and daemons.

`tools/lib/family.tsv` indexes the phone and tablet systems by those properties, with what each
one is a good example of. `tools/scaffold-system.sh` works from it:

```bash
tools/scaffold-system.sh --port <id> --list     # ranked by similarity, with what is shared
tools/scaffold-system.sh --port <id>            # scaffold from path.reference_system
tools/scaffold-system.sh --refresh              # systems on the page not indexed yet
```

## Choosing (S1)

1. Run `--list` once recon and prior art gave the SoC, architecture, flash mode and second stage.
2. Read the top candidates' README and `fwup.conf` before choosing: the score only says what is
   shared. Prefer the system with the same boot path when no system has the same SoC.
3. Record the choice in `path.reference_system` (the repository URL, or `none`), with one line in
   `dossier/prior-art.md` on what is shared and what will differ.
4. A second system can serve as the example for one piece (an installer, an Android A/B phone's
   slot handling, a MediaTek layout): say so next to the choice.

The systems marked `template: no` replace the vendor bootloader or have no A/B: read them for
ideas, never scaffold from them, since that path breaks the kit's invariants.

Beyond phones, the page also lists consoles, single-board computers and other devices; the
official `nerves_system_*` repositories remain the reference for what a Nerves system is
(porting.md section 0).

## Scaffolding (S4)

The tool copies the reference at its current commit, renames the app and the module, resets the
version, and writes `dossier/scaffold-todo.txt`: every line that still names the reference device
(block devices, DTB names, kernel source, U-Boot defconfig, firmware packages, fwup platform).
Work through that file with this port's facts. Keep the structure, the fwup layout and the
initramfs; redo the kernel config, the patches, the firmware packages and the overlay. Each
departure from the reference gets a reason (a decision when a newcomer would ask why).

## Growing the family (S6)

A finished port adds its row to the awesome-nerves-systems page and its line to
`tools/lib/family.tsv` (`share`), so the next similar device starts from it. When `--refresh`
shows a phone or tablet system that is not indexed, have a `researcher` read its README, mix.exs,
fwup.conf and defconfig, and add its line.
