---
name: port-playbook
description: The map of a port from a stock Android device to a published Nerves system - six stages (S1 Scout, S2 Open, S3 Boot from RAM, S4 Nerves, S5 Peripherals, S6 Share), the three gates where the user decides (G1 costs, G2 write allowlist, G3 publish), what runs in parallel, the optional Buildroot branch, and the decision trees for the kernel and the boot path. Load it when planning, at a gate, or when tools/kit-next.sh output needs explaining.
user-invocable: false
---

# Porting playbook

`tools/kit-next.sh` says where the port stands and which steps are ready; it reads the evidence
on disk, so nothing here is ticked by hand. This skill says what the stages mean.

Each stage has its own skill, backed by its tools. Steps and their evidence: [stages.md](stages.md).
Decision trees (kernel source, boot path, display console): [decisions.md](decisions.md).

## The ladder

| Stage | Skill | What we get | Device risk |
|---|---|---|---|
| **S1 Scout** | `scout` | The dossier: device facts, prior art, the closest existing Nerves system, the unbrick kit, the unlock plan and its costs | none: read-only, key-free reboots |
| → **G1** | | *The user says go and accepts the irreversible costs of the unlock* | |
| **S2 Open** | `open` | Bootloader unlocked, every partition that matters dumped and verified | the unlock wipes the phone (always asked) |
| → **G2** | | *The user types the write allowlist (`allow writes boot userdata …`)* | |
| **S3 Boot from RAM** | `boot-test` | A boot path, our kernel's first light, a rescue shell over USB, the Linux inventory | RAM boots; a second stage flashed to `boot` |
| **S4 Nerves** | `nerves-system` | A Nerves system scaffolded from the closest existing one, A/B updates inside Android partitions, upload and revert proven, charging | writes to allowlisted partitions |
| **S5 Peripherals** | `peripherals` | The peripherals the user wants, one backlog task each | same |
| **S6 Share** | `share` | README, one-command installer, release | none |
| → **G3** | | *The user agrees to what becomes public; then the release and the row in awesome-nerves-systems* | |

## Why only three gates

A gate is where only the user can decide. Everything else is checked by code and recorded as
evidence, so it does not stop:

- **G1** is the last moment to walk away for free: after it, the unlock wipes the phone and may
  blow a fuse.
- **G2** is where the user decides which partitions may be written. After it, a write to one of
  them, backed up, addressed to this device, runs without asking; a mistake there is undone from
  the flash mode with the backup.
- **G3** is where the work leaves this machine.

Between gates the guard still **asks** for what is not covered (an unlock, a wipe, a raw block
write, a partition outside the allowlist) and still **denies** the bootloader chain, calibration
data, relocking and repartitioning (`device-safety`). The user can overrule a denial for their own
device (`override <target…>`), informed of the cost.

## Rules for moving along the ladder

1. **Run what is ready, in parallel.** The S1 steps after recon are independent: give them to
   several `researcher` agents in one message. The S4 scaffold and kernel build start on the host
   as soon as G1 passed, while S2 and S3 use the device.
2. **Temporary before permanent.** Each boot path is proven from RAM before anything is written
   for good; without a RAM boot, `boot` is the experiment partition.
3. **Start from the family.** The closest existing Nerves system is the template
   (`nerves-system` family.md); the port changes what its hardware forces and says which.
4. **Follow the Nerves porting guide.** Its "working Buildroot system first" is the rescue shell
   of S3, with the kernel config and the init inventory saved from it; the Nerves system then has
   the guide's anatomy and layout, **boot A/B and rootfs A/B, never a single boot slot**, checked
   by `tools/check-nerves-system.sh`. A persistent buildroot-android board is an optional branch
   (`path.buildroot_branch: true`, `buildroot-port`), taken when the user wants to contribute one.
5. **Every boot experiment keeps a way back**: the command, the key combo, the backup image.
6. **Going back is normal.** If first light fails because of the kernel choice, change
   `path.kernel_*` and say why in a decision; the evidence model follows.
7. **S5 never blocks S6.** USB networking, updates and charging make a publishable system;
   peripherals keep landing in later releases.
8. **Long or unattended device work needs charging proven** (`checks.charging`); until then
   device sessions stay short (`autonomy`, battery guard rails).
