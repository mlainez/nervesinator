# Nerves Porting Kit

An agentic system that takes you by the hand to port **mainline Linux → Buildroot → Elixir Nerves**
onto an Android phone or tablet you own. It does the work **and teaches you** what it is doing and
why, so that by the end you can port the next device yourself.

It encodes the method behind [buildroot-android](https://github.com/Spin42/buildroot-android), the
[Nerves porting guide](https://hexdocs.pm/nerves/porting-guide.html) and the
["Will it run Nerves?"](https://github.com/mlainez/NervesMeetupEU-Will-it-run-nerves) talk.

## Quick start

1. Plug in the phone with **USB debugging** enabled (Settings → About → tap "Build number" 7× →
   Developer options → USB debugging).
2. Open this folder in your coding agent (Claude Code: `claude` from this directory).
3. Type **`Start`**.

The guide checks your computer, finds the phone, asks which device to work on, creates a workspace
with a task backlog, asks a few questions about you (experience, how deep you want explanations,
language), and starts the first milestone. You can stop at any time; typing `Start` again resumes
from the backlog. Other commands: `/status` (where are we?) and `/explain <topic>` (a lesson on anything).

## The journey: 13 milestones, each ending at a gate

```
 M0 Setup ─ M1 Recon ─ M2 Prior art ─ M3 Unbrick kit ─ M4 Unlock ─ M5 Backup ─ M6 Boot path
   🟢          🟢          🟢              🟢/🟡           🟠           🟢/🟡        🟡/🟠
 ─ M7 First light ─ M8 Rescue shell ─ M9 Persistent Buildroot ─ M10 Hardware ─ M11 Nerves ─ M12 Share
        🟡                🟡                    🟠                    🟠             🟠           🟢
```

| Color | Meaning |
|---|---|
| 🟢 green | read-only or host-only |
| 🟡 yellow | temporary: a reboot undoes it (RAM boot) |
| 🟠 orange | writes a replaceable partition (`boot`, `recovery`, `userdata`) **that has a verified backup** |
| 🔴 red | bootloader chain, calibration data, partition tables, relocking: **never automated** |

The order is chosen so that risk only increases after the safety net has been checked: an unbrick kit
(M3) before the first irreversible step (M4), full verified backups (M5) before any write, RAM-only
boots (M6–M8) before anything persistent (M9+). Every milestone ends with a **gate**: the guide shows
proof of what was achieved, teaches the milestone's lesson, explains what the next step risks, and
**waits for your "go"**.

Full details: [`skills/port-playbook/milestones.md`](skills/port-playbook/milestones.md).

## How it is built

```
                 you ⇄ Orchestrator ("Porting Guide", AGENTS.md)
                          │  owns the conversation, the gates and the backlog
     ┌──────────┬─────────┼────────────┬───────────────┬──────────────┐
 device-recon  prior-art  bootloader-  flash-guardian  buildroot-     boot-debugger
 (read-only)   -scout     strategist   (only one that  engineer       firmware-hunter
                          (plans)      writes devices) (host builds)  nerves-architect, tutor
     └──────────┴─────────┴────────────┴───────────────┴──────────────┘
                 skills/  (playbook, safety, procedures, teaching)
                 tools/   (scripts the agents run)
                 ports/<id>/  (per-device git repo: backlog, dossier, backups, journal)
```

### Agents (`agents/`)

| Agent | Job |
|---|---|
| `device-recon` | Read-only collection of device facts over adb/ssh into the dossier, a source for every fact |
| `prior-art-scout` | pmaports, the postmarketOS wiki, mainline/SoC forks, lk2nd, LineageOS → a feasibility verdict |
| `bootloader-strategist` | Unbrick kit, unlock procedure, second-stage bootloader, boot image format: plans only |
| `flash-guardian` | The only agent that changes the device: pre-flight checklist → plan file → executes after your yes |
| `buildroot-engineer` | Kernel, first-light and rescue initramfs, the buildroot-android board, packages, docs |
| `boot-debugger` | Reads screen photos, ramoops, lk2nd logs and dmesg; proposes the next minimal experiment |
| `firmware-hunter` | Blobs and pmOS userspace (rmtfs, qrtr, UCM…) → Buildroot packages |
| `nerves-architect` | A/B layout inside Android partitions, fwup, erlinit, initramfs slot switching, Elixir replacements |
| `tutor` | Lessons tied to your device, at your level, saved to the journal |

### Skills (`skills/`)

| Skill | What it holds |
|---|---|
| `start`, `status`, `explain` | The user-facing entry points |
| `port-playbook` | Milestones, risk levels, gate rules, decision trees (kernel / boot path / rootfs) |
| `device-safety` | Partition classes, pre-flight checklist, vendor traps, backups, the unbrick ladder |
| `backlog-workflow` | Backlog.md conventions: statuses, labels, gates, decisions, resumability |
| `teach` | Teaching format and tone, analogies, lesson template, a checked reading list |
| `adb-recon`, `prior-art-search`, `bootloader-unlock`, `boot-images`, `rescue-initramfs`, `buildroot-port`, `firmware-userspace`, `nerves-port` | Procedures for each phase |

### Tools (`tools/`)

| Script | Purpose |
|---|---|
| `check-host.sh` | Host prerequisites, grouped by the milestone that needs them |
| `detect-devices.sh` | Every phone in adb, fastboot, Samsung download, EDL or BROM mode (read-only) |
| `new-port.sh <id> <serial>` | Creates `ports/<id>/`: git repo, `port.yaml`, and a Backlog.md project with 13 milestones and 70 tasks |
| `recon/collect.sh` | Read-only device recon over adb (root-enhanced if already rooted) |
| `backup-partitions.sh` | Partition dumps verified by comparing the sha256 on the device with the local copy |
| `safe-flash.sh` | Guarded `boot` / `flash` / `unlock`: dry run by default; checks the serial, product, forbidden list, allowlist, backup and size |
| `usbnet.sh` | Finds the phone's USB network interface and checks `10.0.42.1` |
| `lib/bootimg_info.py` | Decodes an Android boot image (v0–v4, QCDT, appended DTB, Samsung footer) into `mkbootimg` args |
| `lib/forbidden-partitions.txt` | The single list of partitions nothing may ever write |

### Safety layers

1. **Process:** gates, risk colors, RAM before flash, the experiment partition, and the backup +
   allowlist requirement (`skills/device-safety`).
2. **Role separation:** only `flash-guardian` executes device writes, from a plan file you approved.
3. **`tools/safe-flash.sh`:** re-checks everything right before writing.
4. **`hooks/device_guard.py`:** inspects every shell command. It **denies** bootloader/calibration
   writes, relocking, repartitioning, EDL/BROM writes and raw writes to the host's disks, and **asks
   you** before any other flash, unlock, wipe or block write. Regression tests:
   `tests/test_device_guard.sh`.

> Don't run the kit with permission checks disabled (Claude Code's bypassPermissions mode): the
> guard's "ask" decisions are your confirmation step.

## Using it with other coding agents

The content is tool-neutral; the tool-specific glue is thin:

| Tool | How it finds the kit |
|---|---|
| Claude Code | `CLAUDE.md` imports `AGENTS.md`; `.claude/skills` → `skills/`, `.claude/agents` → `agents/`; `.claude/settings.json` wires the guard and the "Start" hook |
| Agents reading `AGENTS.md` + `.agents/skills` (Codex, opencode, …) | `AGENTS.md` at the root, `.agents/skills` → `skills/` |
| Anything else | Point it at `AGENTS.md`. If it has no subagents, it reads `agents/<name>.md` and plays that role itself. If it has no hook system, `AGENTS.md` requires running `hooks/device_guard.py --check "<cmd>"` before device commands, and `safe-flash.sh` enforces the same checks |

## A port's workspace

```
ports/<vendor>-<codename>/        its own git repo
  port.yaml                       device facts, safety flags, chosen path, learner profile
  backlog/                        Backlog.md (run `backlog board` here)
  dossier/                        recon, prior art, partition map, unbrick plan, init inventory
  backups/                        partition dumps + SHA256SUMS (not in git; keep a copy elsewhere)
  journal/                        sessions.md, lessons/, plans/ (flash plans + logs), photos/
  buildroot-android/              your fork, branch port/<id> (M9+)
  nerves_system_<id>/             the Nerves system (M11)
```

## Requirements

adb + fastboot, git, python3, curl, lsusb, and the [Backlog.md](https://github.com/MrLesk/Backlog.md)
CLI (`npm i -g backlog.md`). Later milestones need the Buildroot build dependencies, Elixir + Nerves
+ fwup, and device-specific tools (heimdall, mkbootimg…). `tools/check-host.sh` tells you what is
missing and when it will be needed.

## Installing and updating the kit

The kit is this repository: clone it and run the agent from its root, with ports under `ports/`.
To use it inside another project, copy the repository's top-level files (`AGENTS.md`, `CLAUDE.md`,
`agents/`, `skills/`, `hooks/`, `tools/`, `templates/`, `tests/`, `.claude/`) to that project's
root, never into a subdirectory such as `tools/` (`tools/check-host.sh` warns about a nested copy).
`.claude/` is the Claude Code adapter: `agents` and `skills` are symlinks and `settings.json` wires
the guard and start hooks. Symlinks do not survive many copy methods (`cp -r` without `-a`, zip,
some file managers): copy with `cp -a` or `rsync -a`, then run `tools/check-host.sh`, which checks
the adapter and prints the fix.
To update a copied kit, compare each file with the kit's history first (`git hash-object` of the
local file against the kit's blobs) so local changes are never overwritten.

## Where to run the tools

Run the kit where its tools were installed. On an immutable desktop (Bluefin, Silverblue) the
build tools and an asdf-managed `fwup` usually live in a distrobox/toolbox, and the host's copy
may not run there (e.g. `libconfuse.so.2` missing); `tools/check-host.sh` warns when `fwup` cannot
start.

## Phones as USB disks

When a port's second stage exposes `userdata` as a USB disk, keep the desktop from auto-mounting
it: install `templates/udev/99-porting-kit-no-automount.rules` with the phone's serial (the file
says how). `tools/ums-target.sh` finds the disk and refuses while anything on it is mounted.

## Extending the kit

- A new vendor trap or partition name → `skills/device-safety/SKILL.md` and
  `tools/lib/forbidden-partitions.txt`, plus a case in `tests/test_device_guard.sh`.
- A new milestone task → `templates/backlog-seed.json` and `skills/port-playbook/milestones.md`.
- A new reading → `skills/teach/reading-list.md` (check that the link resolves).
- After finishing a port, add what you learned to the relevant skill: the kit gets smarter with every device.
