---
name: autonomy
description: Attended, unattended and full-autonomy work - what the orchestrator does on its own while the user is away (host work, read-only device commands, key-free mode reboots, RAM test boots, writes covered by the user's allowlist), what it queues for them, the full-autonomy grant the user types (autonomous full <goal>) under which gates G1 and G2's consequences are already decided, the battery guard rails, and how it notifies. Load it when the user switches mode ("autonomous on|off|full", "I'm away", "I'm back", or tools/user-mode.sh) and when resuming a port whose session.autonomy is not attended.
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

The user switches it at any moment: `autonomous on` or "I'm away" → `unattended`;
`autonomous full <goal> [for <N>h]` → `full`; `autonomous off` or "I'm back" → `attended`
(plain words; without a prompt hook, as in Codex, the user runs `tools/user-mode.sh autonomous …`).
Record the switch in `port.yaml`, then say in one line what will and will not happen from now on.

## Attended (default)

The work loop of the `start` skill. It already stops only at the three gates and at what the
guard asks about; the difference with the modes below is that the user is there to answer.

## Unattended

Never block waiting for the user on something the kit can check itself. Keep taking the READY
steps of `tools/kit-next.sh`, and put what needs a human in the queue below.

**On its own** (the guard allows these, or they are host-only):

- everything host-only: research, builds, the Nerves system, docs, backlog upkeep;
- read-only device commands and reboots between modes that need no keys
  (`adb reboot bootloader|recovery|download`, `fastboot reboot`, `tools/return-to-flash.sh`);
- RAM-only test boots through `tools/await-boot.sh`;
- once G2 is typed: writes to allowlisted, backed-up partitions through `tools/safe-flash.sh`,
  each followed by a verification boot (`await-boot.sh --watch-only`), restoring the backup
  through the same key-free path when it fails.

**Queued, never done on its own:** a gate, anything the guard would ask about (an unlock, a wipe,
a raw write, a partition outside the allowlist: the prompt would just wait, so do not start it),
anything that needs keys or a battery pull, and overwriting the partition that holds the second
stage or any write whose undo needs keys.

## Full autonomy

When the user types `autonomous full <goal>` (or runs `tools/user-mode.sh autonomous full <goal>`),
the prompt hook (or the tool) writes the grant of the active port (goal, expiry, the exact words
typed; 7 days unless `for <N>h`). Only the user's words create it: the guard denies any command or
file tool touching it. While it is valid, the guard **allows what it would otherwise ask about**
and still **denies what it always denies**.

Under the grant, work towards the goal without asking the user anything:

- **G1 and G3 up to the goal pass on their own**, with the summary and the proof written to
  `journal/sessions.md`, a note "passed under the full-autonomy grant", and a notification.
  Irreversible costs only when already listed in `learner.accepted_costs`; otherwise queue. G3
  never passes on its own unless the goal names publishing.
- **G2 stays the user's**: only their words write the allowlist. Without one, writes go through
  `safe-flash.sh --execute` under the grant, to `boot` and `userdata` only, with every dry-run
  check green.
- **Keep the key-free way back** and **verify every write**, as in unattended mode.
- **Choices the playbook asks the user** (which peripherals, the Buildroot branch) are made from
  the goal, else from the kit's default; each is recorded as a decision marked "chosen under the
  full-autonomy grant".
- **Stop** when the goal is reached, when the grant expires, or when nothing can progress without
  hands: write the session entry, notify, and switch `session.autonomy` back to `attended`.

## Battery guard rails (unattended and full)

A drained battery stops everything and needs hands. Before each device step, read the battery
(`/sys/class/power_supply/*/voltage_now` and `capacity` from a kit image or Linux, `dumpsys
battery` from Android, the `await-boot` record):

- below 3.6 V or 20 %: pause device work, do host work only, notify;
- at 3.45 V or 5 %: park the phone where it charges (the vendor flash mode when the stock
  bootloader charges there, or power-off when the device charges off-mode) and notify.

Before any long unattended device work, charging must be proven on this port (`checks.charging`):
on the supplies the user will use, across every reboot and flash path the port uses. Until then,
unattended device sessions stay short, and between them the phone waits where the stock
bootloader charges it, not in a kit image.

## The queue and notifications

For each item that needs the user: a backlog task in `Needs User` with a note (what, why, the
exact command or question, what was already checked), then notify:

- Claude Code: the `PushNotification` tool, one short line ("<id>: rescue shell PASS; gate G1
  waits for you").
- Other tools: the line goes to `journal/sessions.md` under a `## Needs you` heading.

Notify on: a queued item, a gate reached, an `await-boot` HUNG (the phone needs hands), and
anything that stops all progress. Do not notify for routine progress. After notifying, keep working
on whatever does not depend on the queued item; when nothing is left, stop.

## What needs hands, honestly

A test image that hangs hard with no working watchdog cannot recover on its own: `await-boot`
reports HUNG, and only a forced power-off (`device.modes` in `port.yaml`) or a battery pull brings
the phone back. Every kit image limits this (panic reboot, watchdog, a return to the flash mode
when USB never comes up; see `boot-test` test-images.md), so the queue-and-notify path is the
fallback, not the plan.

## Harness permissions

The guard's decisions cover only the guard. The host tool may still ask its own permission
questions; before leaving, the user picks a permission mode that lets the work run (in Claude
Code, auto mode or allow rules; never bypassPermissions, which would also silence the guard).
