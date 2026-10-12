---
name: autonomy
description: Attended vs unattended work - what the orchestrator may do on its own while the user is away (host work, read-only device commands, key-free mode reboots, RAM test boots judged by await-boot), what it must queue for the user (writes, gates, keys, irreversible costs), and how it notifies. Load it when the user switches mode ("/autonomous on|off", "I'm away", "I'm back") and when resuming a port whose session.autonomy is unattended.
---

# Attended and unattended work

The mode lives in `port.yaml`:

```yaml
session:
  autonomy: attended        # attended | unattended
  since: ""                 # ISO time of the last switch
  set_by: ""                # the user's words that switched it
```

The user switches it at any moment: `/autonomous on` or "I'm away" → `unattended`;
`/autonomous off` or "I'm back" → `attended`. Record the switch in `port.yaml` and in
`journal/sessions.md`, then say in one line what will and will not happen while they are away.

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

The kit cannot answer the host tool's own permission prompts. Before leaving, the user picks a
permission mode that lets the allowed actions above run (in Claude Code, auto mode or allow rules;
never bypassPermissions, which would also silence the guard's questions).
