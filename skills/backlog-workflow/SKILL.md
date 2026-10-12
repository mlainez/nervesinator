---
name: backlog-workflow
description: Conventions for tracking a port with Backlog.md - statuses, labels, milestone and gate tasks, how to create/update/close tasks, decisions (ADRs), notes with evidence, commits, and how to make work resumable. Load it before creating or editing tasks, or when resuming.
user-invocable: false
---

# Backlog.md conventions

Each port has its own Backlog.md project in `ports/<id>/backlog/` (created by `tools/new-port.sh`).
**Always run `backlog` from inside `ports/<id>/`.** Use `--plain` for output you read back.
If unsure about a command, `backlog <command> --help` lists the exact flags.

## Statuses

| Status | Meaning |
|---|---|
| `To Do` | Not started |
| `In Progress` | Someone is working on it (only one or two at a time) |
| `Needs User` | Waiting for a human: a decision, a photo, a physical action (key combo, cable), a gate approval |
| `Blocked` | Cannot progress: write what blocks it and what would unblock it |
| `Done` | Acceptance criteria checked, notes written |

## Labels

- One risk label: `risk-green`, `risk-yellow`, `risk-orange`, `risk-red`.
- One agent label: `agent-recon`, `agent-scout`, `agent-bootloader`, `agent-flash`, `agent-buildroot`,
  `agent-debug`, `agent-firmware`, `agent-nerves`, `agent-tutor`, `agent-orchestrator`,
  `agent-kernel`, `agent-nerves-app`, `agent-uboot`.
- Extras: `gate`, `needs-device` (the phone must be attached), `needs-root`, `lesson`, `peripheral`,
  `deferred` (kept for later by a decision, e.g. peripherals skipped to reach Nerves sooner; the
  work loop skips it, and its dependents do not wait for it).

## Milestones

`M0 Setup` … `M12 Share` (created by `new-port.sh`; see `port-playbook`). Every task belongs to one.
`backlog milestone list --plain` shows progress.

## Task anatomy

A good task can be picked up by someone who has never seen the conversation:

- **Title:** imperative, specific ("Dump class B partitions with root dd").
- **Description:** the why and the context, the inputs (files, facts from `port.yaml`).
- **Acceptance criteria:** checkable facts ("`backups/SHA256SUMS` verifies", "photo shows kernel log").
- **Plan** (`--plan`): set before starting a non-trivial task.
- **Notes** (`--append-notes`): what was found, **with evidence**: a command + its key output line,
  a file path, a URL. Mark guesses as guesses.
- **Final summary** (`--final-summary`): 2-4 lines when Done.
- **Refs** (`--ref`): links and files used.

## Everyday commands

Task ids carry the project prefix: `PORT-12`, not `12` (`backlog task edit 12` fails with "Task 12
not found").

```bash
backlog task list --plain                       # everything, grouped by status
backlog task list --plain -m "M1"               # one milestone
backlog task <id> --plain                       # read one task
backlog task edit <id> -s "In Progress" -a @orchestrator
backlog task edit <id> --plan "1. … 2. …"
backlog task edit <id> --append-notes "getprop ro.board.platform = msm8226 (dossier/raw/getprop.txt)"
backlog task edit <id> --check-ac 1 --check-ac 2
backlog task edit <id> -s Done --final-summary "…"
backlog task create "Enable WiFi (wcn36xx)" -m "M10" -p <M10-parent-id> -l risk-orange,agent-firmware,peripheral \
  --ac "wlan0 appears" --ac "scan lists networks" -d "…"
backlog decision create "Kernel: msm8226-mainline v6.x"    # then edit the file: context, options, decision, consequences
backlog sequence list --plain                   # what can be done next given dependencies
```

## Gates

The last task of each milestone is `GATE Mx: …` (label `gate`). Its ACs are the milestone exit
criteria from `port-playbook`. At the gate: check every AC with evidence, set the status to `Needs User`,
present the gate to the user, and only after their explicit "go" set it to `Done` with their answer
in the notes ("User approved on 2026-10-11: 'go, flash it'"). Then add `Mx` to `gates_passed` in `port.yaml`.

## Decisions (ADRs)

Create one for every choice that would be expensive to reverse or that a newcomer would ask
"why?" about: kernel source, bootloader path, experiment partition, rootfs placement, A/B layout,
adding a name to the forbidden list. Format: Context / Options considered / Decision / Consequences /
Evidence.

## Resumability

- Never keep state only in the conversation. Facts → `port.yaml` or `dossier/`; work → tasks;
  choices → decisions; the narrative → `journal/sessions.md`.
- Commit after every completed task in `ports/<id>` (the user's git identity; follow the user's
  global commit rules if they have any). `backups/`, `cache/` and build outputs are in `.gitignore`.
- New work discovered along the way becomes a new task right away, even if it is for later.
