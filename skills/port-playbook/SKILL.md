---
name: port-playbook
description: The milestone map for porting mainline Linux, Buildroot and Nerves to an Android device (M0 to M12), with the risk level, tasks, exit criteria and gate of each milestone, plus the decision tree for kernel and bootloader paths. Load it when picking the next task, at a gate, or when planning.
user-invocable: false
---

# Porting playbook

The port is a ladder. Every rung is a **milestone** that ends with a **gate**: a stop where the
user checks what happened, learns the lesson and says "go" before anything riskier happens. The
ladder is ordered so that **risk only goes up after the safety net has been checked**.

Details for each milestone (tasks, commands, exit criteria, lesson topics): [milestones.md](milestones.md).
Decision trees (kernel source, bootloader path, rootfs placement): [decisions.md](decisions.md).

## Risk levels

Every task carries one `risk-*` label. The level of a milestone is that of its riskiest task.

| Label | Meaning | Examples | Who may run it |
|---|---|---|---|
| `risk-green` | Read-only, or host only | `getprop`, cloning pmaports, building | Any agent |
| `risk-yellow` | Temporary: a reboot undoes it | `fastboot boot`, rebooting into a bootloader or download mode | The orchestrator, after telling the user |
| `risk-orange` | Writes to a partition that can be replaced and **has a verified backup** | flashing `boot`, `recovery` or `userdata`, unlocking (wipes data) | `flash-guardian`, after an explicit user yes |
| `risk-red` | Bootloader chain, irreversible fuses, partition table, radio calibration | `aboot`, `sbl1`, `preloader`, `tz`, `efs`, PIT/GPT rewrites, relocking | **Never automated.** It needs an ADR, the user must type the command, and the unbrick kit must be tested |

## The ladder

| # | Milestone | Risk | What we get at the end |
|---|---|---|---|
| M0 | Setup & safety briefing | green | Host tools ready, workspace + backlog created, learner profile, safety rules explained |
| M1 | Reconnaissance | green | `dossier/` with SoC, board, partitions, boot image format, kernel config, display/touch/WiFi/modem chips |
| M2 | Prior art & feasibility | green | `dossier/prior-art.md`, kernel path chosen (ADR), go/no-go verdict |
| M3 | Unbrick kit | green / yellow | Stock firmware located and downloaded, the flash tool works, every boot mode key combo tested, recovery procedure written |
| M4 | Bootloader unlock | orange | Bootloader reports unlocked; the user knows what they gave up (warranty, data, KNOX fuse…) |
| M5 | Full backup | green / yellow | Every partition except `userdata`/`system` dumped with sha256, verified, stored safely |
| M6 | Boot path proven | yellow (orange if a 2nd stage has to be written) | We can load our own kernel without touching the bootloader chain: `fastboot boot`, lk2nd, or an experiment partition |
| M7 | First light | yellow | Our mainline kernel prints its boot log on the phone screen |
| M8 | Rescue shell | yellow | A Buildroot initramfs running from RAM with USB networking (unudhcpd) and a shell over ssh/telnet; hardware inventory under Linux |
| M9 | Persistent Buildroot | orange | A Buildroot system in `buildroot-android` style, booting from flash, reflashable, rescue path kept |
| M10 | Hardware enablement | orange | One task per peripheral (display, touch, WiFi, modem, audio, battery…): firmware and userspace daemons packaged |
| M11 | Nerves system | orange | `nerves_system_<id>` with A/B in an Android partition, `mix firmware`, first flash, `mix upload` and revert tested |
| M12 | Share it | green | Docs, a PR to buildroot-android, the learner's journal, a write-up |

## Rules for moving along the ladder

1. **One milestone at a time.** Finish its tasks (Done, or Done with "N/A because…" in the notes),
   then run its `GATE` task.
2. **A gate is a conversation.** Show: what we achieved (with proof: a log line, a photo, a hash),
   what we learned (the milestone lesson, see the `teach` skill), what the next milestone will
   risk and how we will undo it. Ask for "go". Record the answer in the gate task notes and add
   the milestone to `gates_passed` in `port.yaml`.
3. **Going back is normal.** If M7 fails because of the kernel choice, reopen M2 tasks. Record why
   in a decision.
4. **Skipping is allowed only when the step is truly not needed**, for example M6 with an
   already-open U-Boot. Write why.
5. **Hard prerequisites** (the gate refuses otherwise):
   - M4 needs M3 done (an unbrick kit before the first change that cannot be undone).
   - Any `risk-orange` task needs M5 done and the target partition listed in
     `safety.writable_partitions`.
   - M9 needs M8 (never make a persistent system you cannot get a shell into).
   - M11 needs M9 and a working list of everything the Buildroot init scripts do.
6. **Every boot experiment keeps an escape route.** Before a boot test, write down how we get back:
   which key combo, which command, which backup image.
