# Nerves Porting Kit

An agentic kit that takes an Android phone or tablet you own from stock to a published
**Elixir Nerves** system, starting from the closest device that already runs Nerves in the
[awesome-nerves-systems](https://github.com/mlainez/awesome-nerves-systems) family, and adds the
result back to that family.

It encodes the method behind [buildroot-android](https://github.com/Spin42/buildroot-android), the
[Nerves porting guide](https://hexdocs.pm/nerves/porting-guide.html) and the
["Will it run Nerves?"](https://github.com/mlainez/NervesMeetupEU-Will-it-run-nerves) talk.

## Quick start

1. Plug in the phone with **USB debugging** enabled (Settings → About → tap "Build number" 7× →
   Developer options → USB debugging). Copy your personal data off it: the port wipes it.
2. Open this folder in your coding agent (Claude Code: `claude` from this directory).
3. Type **`Start`**.

The guide checks your computer, finds the phone, creates a workspace and starts scouting. You
can stop at any time: the next session picks up from the evidence on disk. Other words:
`status` (where are we?), `explain <topic>` (a lesson on anything), `teach on` (lessons along the
way; off by default).

## The journey: six stages, three gates

```
 S1 Scout ──G1──▶ S2 Open ──G2──▶ S3 Boot from RAM ──▶ S4 Nerves ──▶ S5 Peripherals ──▶ S6 Share ──G3──▶ published
 read-only       unlock, backups   first light, shell   from the closest   one task each     README, installer,
 in parallel                                            existing system                      release, family row
```

| Gate | You decide |
|---|---|
| **G1** | Go or no-go, and the irreversible costs of unlocking (data wipe, a warranty fuse) |
| **G2** | Which partitions may be written: you type `allow writes boot userdata …` once |
| **G3** | What becomes public |

Everything else runs without stopping, because it is checked by code instead of by asking:
scouting is read-only and runs in parallel, boots are proven from RAM and judged from the host,
and after G2 a write to an allowlisted, backed-up partition of *this* device needs no further
yes. The Nerves system is built on the host while the device work goes on. A persistent
buildroot-android board is an optional branch, not a step on the way.

Details: [`skills/port-playbook/SKILL.md`](skills/port-playbook/SKILL.md) and
[`stages.md`](skills/port-playbook/stages.md).

## How it is built: tools, hooks, skills

**Tools** do the work and hold the state.

| Script | Purpose |
|---|---|
| `kit-next.sh` | Where the port stands and which steps are ready, derived from the evidence on disk |
| `check-host.sh`, `detect-devices.sh`, `new-port.sh` | Host prerequisites, attached phones in any mode, a new port workspace |
| `recon/collect.sh`, `prior-art.sh` | Read-only device recon; a scan of pmaports, lk2nd and the family for the device and SoC |
| `scaffold-system.sh` | Ranks the existing Nerves systems by similarity and scaffolds the port's system from the closest one |
| `backup-partitions.sh` | Partition dumps verified by sha256 on the device and on the host |
| `safe-flash.sh` | Guarded `boot` / `flash` / `unlock`: serial, product, forbidden list, allowlist, backup, size, image format |
| `await-boot.sh`, `usbnet.sh`, `return-to-flash.sh` | Boot a test image and judge it from the host; USB networking; a key-free way back to the flash mode |
| `mk-test-initramfs.sh`, `fetch-prebuilt.sh`, `publish-prebuilt.sh`, `br-make.sh` | Test images from a prebuilt initramfs; shared Buildroot caches |
| `with-guard.sh`, `user-mode.sh`, `checkpoint.sh` | The guard, your switches and the port checkpoint for harnesses without hooks (the first two are run by you, never by the agent) |

**Hooks** enforce the rules, so they do not depend on the agent remembering them.

| Hook | When | What |
|---|---|---|
| `device_guard.py` | every shell command | **Denies** bootloader-chain and calibration writes, relocking, repartitioning, raw writes to your disks. **Allows** writes covered by your allowlist. **Asks** you for the rest (an unlock, a wipe, a raw block write) |
| `start_trigger.py` | every prompt | Your words: `Start`, `allow writes …`, `override …`, `hands off`, `autonomous …` |
| `session_context.py` | session start | Hands the agent the state of the active port |
| `checkpoint.py` | when the agent stops | Commits the port workspace |

All four are wired in `.claude/settings.json` (`PreToolUse`, `UserPromptSubmit`, `SessionStart`,
`Stop`); `tools/check-host.sh` verifies it. The checkpoint commits only the port's own repository
under `ports/<id>/`, with a `Checkpoint: <stage>` message, and only when something changed.

**Skills** hold the method: one per stage, with the knowledge in reference files loaded only
when needed.

| Skill | What it holds |
|---|---|
| `start`, `status`, `explain` | The entry points |
| `scout`, `open`, `boot-test`, `nerves-system`, `peripherals`, `share` | One per stage S1 to S6: its steps, its tools, and references (recon, prior art, unlock by vendor, boot images, test images, U-Boot chainloading, the family, A/B layouts, firmware, kernel work) |
| `port-playbook` | The ladder, the gates, the decision trees |
| `device-safety` | Partition classes, who enforces what, backups, the unbrick ladder, one file of traps per vendor |
| `autonomy`, `hands-on-test`, `backlog-workflow`, `teach`, `buildroot-port` | Working while you are away; tests that need your hands; discovered work; lessons on request; the optional Buildroot branch |

Three **agents** do focused work in parallel: `researcher` (read-only: recon, prior art,
firmware), `builder` (host builds: kernel, test images, U-Boot, the Nerves system) and
`boot-debugger`. Only the orchestrator flashes.

> Don't run the kit in a mode that skips hooks or permission checks (Claude Code's
> bypassPermissions, for example): the guard's "ask" decisions are your confirmation step.

## Your switches

| You type | Effect |
|---|---|
| `allow writes <partition…> [no backup <partition…>]` | The partitions the port may write without asking (gate G2); `allow writes off` clears it |
| `override <target…> [for <N>m]` | Overrule a safety invariant for those targets, informed of the cost: the guard asks instead of denying |
| `hands off` / `hands on` | You are working on the device yourself: every device command is denied meanwhile |
| `autonomous on` / `autonomous full <goal>` / `autonomous off` | Work while you are away, queueing what needs you, or asking nothing until a goal |
| `teach on` / `teach off` | Lessons along the way |

## Harness agnostic

Nothing in the kit needs a particular coding agent: the instructions (`AGENTS.md`), the skills
(Agent Skills), the agents' briefs and the tools are plain files and scripts. A harness plugs in
four behaviours, with its own hooks when it has them and with the kit's tools when it does not:

| Behaviour | With hooks | Without hooks |
|---|---|---|
| The guard in front of every device command | `hooks/device_guard.py` before each shell command | Start the agent with `tools/with-guard.sh <agent command>`: shims in front of fastboot, adb, heimdall… run the guard. A command that needs your yes is refused until you run `tools/user-mode.sh approve` |
| Your switches (`allow writes`, `override`, `hands off`, `autonomous`) | `hooks/start_trigger.py` on each prompt | You run `tools/user-mode.sh …` |
| The port's state at session start | `hooks/session_context.py` | The agent runs `tools/kit-next.sh` (`AGENTS.md` requires it) |
| The port committed when work stops | `hooks/checkpoint.py` | The agent runs `tools/checkpoint.sh` |

| Harness | How it finds the kit |
|---|---|
| Claude Code | `CLAUDE.md` imports `AGENTS.md`; `.claude/skills` → `skills/`, `.claude/agents` → `agents/`; `.claude/settings.json` wires the four hooks |
| Agents reading `AGENTS.md` and `.agents/skills` (Codex, opencode, …) | `AGENTS.md` at the root, `.agents/skills` → `skills/`; start them through `tools/with-guard.sh` unless you wire the hooks in their own configuration |
| Anything else | Point it at `AGENTS.md`. Without skill loading it reads `skills/<name>/SKILL.md`; without subagents it follows `agents/<name>.md` itself |

An adapter for another harness is its instruction file importing `AGENTS.md` plus the wiring of
those four scripts; nothing else in the kit changes.

## A port's workspace

```
ports/<vendor>-<codename>/        its own git repo
  port.yaml                       device facts, safety flags, the chosen path, checks
  dossier/                        recon, prior art, partition map, unlock and unbrick plans
  backups/                        partition dumps + SHA256SUMS (not in git; keep a copy elsewhere)
  journal/                        boot records, sessions, lessons
  backlog/                        Backlog.md: peripherals and discovered work
  nerves_system_<name>/           the Nerves system, scaffolded from the closest existing one
```

## Requirements

adb + fastboot, git, python3, curl, lsusb. Later stages need the Buildroot build dependencies,
Elixir + Nerves + fwup, device-specific tools (heimdall, mkbootimg…) and, for peripherals, the
[Backlog.md](https://github.com/MrLesk/Backlog.md) CLI. `tools/check-host.sh` tells you what is
missing and when it will be needed.

## Installing and updating the kit

The kit is this repository: clone it and run the agent from its root, with ports under `ports/`.
To use it inside another project, copy the repository's top-level files (`AGENTS.md`, `CLAUDE.md`,
`agents/`, `skills/`, `hooks/`, `tools/`, `templates/`, `tests/`, `.claude/`) to that project's
root, never into a subdirectory such as `tools/` (`tools/check-host.sh` warns about a nested copy).
`.claude/` is the Claude Code adapter: `agents` and `skills` are symlinks and `settings.json` wires
the hooks. Symlinks do not survive many copy methods (`cp -r` without `-a`, zip, some file
managers): copy with `cp -a` or `rsync -a`, then run `tools/check-host.sh`, which checks the
adapter and prints the fix.
To update a copied kit, compare each file with the kit's history first (`git hash-object` of the
local file against the kit's blobs) so local changes are never overwritten. Then run
`tools/update-port.sh --port <id>` for each existing port: it adds the new ignore rules to the
port's `.gitignore` and stops tracking files they now cover (kept on disk). A port created before
the write allowlist existed needs its allowlist typed once (`allow writes …`).

## Moving an existing port to this version

A port started with the thirteen-milestone version keeps all its work; what changes is where the
kit looks:

| Before | Now |
|---|---|
| Milestones M0 to M12, a gate after each | Stages S1 to S6, gates G1 to G3; `tools/kit-next.sh` shows the stage from the files already in the port |
| `safety.writable_partitions` and `safety.accepted_loss` in `port.yaml` | Your typed allowlist: `allow writes boot userdata no backup userdata` (once per port) |
| `safety.unbrick_kit_ready` | `dossier/unbrick.md` plus `G1` in `gates_passed` |
| Seeded backlog tasks per milestone | Not needed any more: close or delete them; keep the peripheral tasks |
| Proofs written in task notes (upload, revert, charging) | `checks:` in `port.yaml`, as `<name>: "<proof>"` |
| Agents `device-recon`, `prior-art-scout`, `bootloader-strategist`, `firmware-hunter` | `researcher` |
| Agents `buildroot-engineer`, `uboot-engineer`, `kernel-engineer`, `nerves-architect`, `nerves-app-engineer` | `builder` |
| Agent `flash-guardian` and its plan files | The orchestrator, through `tools/safe-flash.sh` (its dry run is the pre-flight) |
| Persistent Buildroot before Nerves | Optional: `path.buildroot_branch: true` |

Run `tools/kit-next.sh --port <id>`: every line marked `later` or `READY` names the file or the
`port.yaml` value it is waiting for. Add `G1` to `gates_passed` when the unlock was already
accepted, and set `path.reference_system` (`none` when the port did not start from another system).

## Prebuilt test images

First light and the rescue shell use one generic initramfs per architecture, so a port builds only
its kernel. `tools/fetch-prebuilt.sh` downloads the release pinned in `tools/lib/prebuilt.conf`;
until one is pinned, the images are built from source once and imported with `--from-dir`.
To publish a release (maintainers): `tools/publish-prebuilt.sh --tree <buildroot-android checkout>
--tag <tag>` builds and packs the four images and prints the release command, `--only-pack
--execute` creates it; then set `PREBUILT_VERSION`.

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

- A new vendor trap or partition name → `skills/device-safety/vendors/<vendor>.md` and
  `tools/lib/forbidden-partitions.txt`, plus a case in `tests/test_device_guard.sh`.
- A new step of the ladder → `tools/lib/kit_next.py` (its evidence) and
  `skills/port-playbook/stages.md`, plus a case in `tests/test_kit_next.sh`.
- A new system in the family → a line in `tools/lib/family.tsv`
  (`tools/scaffold-system.sh --refresh` shows what the awesome-nerves-systems page has that the
  index lacks).
- A new reading → `skills/teach/reading-list.md` (check that the link resolves).
- After finishing a port, add what you learned to the relevant skill as a generic rule: the kit
  gets smarter with every device.

Tests: `tests/test_device_guard.sh`, `tests/test_kit_next.sh`, `tests/test_hooks.sh`,
`tests/test_shims.sh`.
