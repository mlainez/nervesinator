---
name: autonomy
description: Attended, unattended and full-autonomy work - what the orchestrator may do on its own while the user is away (host work, read-only device commands, key-free mode reboots, RAM test boots judged by await-boot), what it queues for the user, the full-autonomy grant the user types (/autonomous full <goal>) under which it asks nothing until the goal, the battery guard rails, and how it notifies. Load it when the user switches mode ("/autonomous on|off|full", "I'm away", "I'm back") and when resuming a port whose session.autonomy is not attended.
---

# Attended and unattended work

The mode lives in `port.yaml`:

```yaml
session:
  autonomy: attended        # attended | unattended | full
  goal: ""                  # full: what "done" means
  since: ""                 # ISO time of the last switch
  set_by: ""                # the user's words that switched it
```

The user switches it at any moment: `/autonomous on` or "I'm away" → `unattended`;
`/autonomous full <goal> [for <N>h]` → `full`; `/autonomous off` or "I'm back" → `attended`.
Record the switch in `port.yaml` and in `journal/sessions.md`, then say in one line what will and
will not happen from now on.

## Attended (default)

The normal work loop of the `start` skill: explain, act, ask at every device write and every gate.

## Unattended

Never block waiting for the user on something the kit can check itself. Keep working through the
current milestone's tasks in order, and put everything that needs a human in the queue below.

**Allowed on its own** (the guard allows these, or they are host-only):

- everything host-only: research, builds, docs, lessons, backlog upkeep;
- read-only device commands: `adb shell` reads, `fastboot getvar` / `oem log` / `get_staged`,
  `heimdall print-pit`, `tools/recon/collect.sh`, `tools/detect-devices.sh`;
- reboots between modes that need no keys: `adb reboot bootloader|recovery|download`,
  `fastboot reboot`, `fastboot reboot-bootloader`, `reboot-mode <mode>` from a kit image;
- RAM-only test boots through `tools/await-boot.sh` (it runs `safe-flash.sh --execute boot`, so
  every dry-run check applies, including the lk2nd device-tree check), and `--return` to bring the
  phone back to its flash mode afterwards.

**Never on its own** (queue it): any write (flash, erase, `dd` to a block device, unlock), crossing
a `GATE`, anything that needs keys or a battery pull, accepting an irreversible cost. The guard
still asks for every write; while the user is away that prompt would just wait, so do not start
one: queue it instead.

## Full autonomy

When the user types `/autonomous full <goal>`, the prompt hook writes `ports/<id>/.autonomy-grant`
(goal, expiry, the exact words typed; 7 days unless `for <N>h`). Only that hook can create it: the
guard denies any command or file tool touching it, so a grant always comes from the user's own
keyboard. While it is valid, the guard **allows what it would otherwise ask about** and still
**denies what it always denies** (class A/B/C partitions, relocking, repartitioning, raw host disks).

Under the grant, work towards the goal without asking the user anything:

- **Gates up to the goal pass on their own.** Write the gate summary, the proof and the lesson to
  `journal/sessions.md` (and the lesson file), note "passed under the full-autonomy grant" in the
  gate task, add it to `gates_passed`, notify, and go on. The gate at the goal stops.
- **Device writes** go through `safe-flash.sh --execute` with every dry-run check green: the target
  allowlisted, a verified backup or a recorded `safety.accepted_loss`, size, magic, the lk2nd DTB
  check, serial and product.
- **Keep the key-free way back.** Write only what the running bootloader path can undo by command
  (under lk2nd: `--mode fastboot flash boot|userdata`). Overwriting the partition that holds the
  second-stage bootloader, or any write whose undo needs keys, is queued, not done.
- **Verify every write:** a verification boot right after it (`await-boot.sh --watch-only` after a
  reboot), and on failure restore the backup through the same key-free path. Log both to
  `journal/` and notify.
- **Irreversible costs** (an unlock that trips a fuse, a wipe) only when already listed in
  `learner.accepted_costs`; otherwise queue.
- **Stop** when the goal is reached, when the grant expires, or when nothing can progress without
  hands: write the session entry, notify, and switch `session.autonomy` back to `attended`.

## Battery guard rails (unattended and full)

A drained battery stops everything and needs hands. Before each device step, read the battery
(`/sys/class/power_supply/*/voltage_now` and `capacity` from a kit image or Linux, `dumpsys
battery` from Android, the `await-boot` console transcript):

- below 3.6 V or 20 %: pause device work, do host work only, notify;
- at 3.45 V or 5 %: park the phone where it charges (the vendor flash mode, e.g. Samsung download
  mode or fastboot, when the stock bootloader charges there; or power-off when the device charges
  off-mode) and notify.

Before any long unattended device work, charging must be proven on this port (see M10 in the
playbook): on the supplies the user will use, across every reboot and flash path the port uses.

## The queue and notifications

For each item that needs the user: set its backlog task to `Needs User` with a note (what, why,
the exact command or question, what was already checked), then notify:

- Claude Code: the `PushNotification` tool, one short line ("s3ve3g: M7 first light PASS; GATE M7
  waits for you").
- Other tools: the line goes to `journal/sessions.md` under a `## Needs you` heading.

Notify on: a queued item, a gate reached, an `await-boot` HUNG (the phone needs hands), and
anything that stops all progress. Do not notify for routine progress. After notifying, keep working
on whatever does not depend on the queued item; when nothing is left, write the session entry and
stop.

## What needs hands, honestly

A test image that hangs hard with no working watchdog cannot recover on its own:
`await-boot` reports HUNG, and only a forced power-off (`device.modes` in `port.yaml`) or a battery
pull brings the phone back. Every kit image limits this (panic reboot, watchdog, a return to the
flash mode when USB never comes up; see `rescue-initramfs`), so the queue-and-notify path is the
fallback, not the plan.

## Harness permissions

The guard's grant covers only the guard. The host tool may still ask its own permission questions;
before leaving, the user picks a permission mode that lets the work run (in Claude Code, auto mode
or allow rules; never bypassPermissions, which would also silence the guard).
