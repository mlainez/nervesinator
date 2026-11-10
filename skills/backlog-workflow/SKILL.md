---
name: backlog-workflow
description: Conventions for the work the ladder does not know about - one Backlog.md task per peripheral and per piece of discovered work, with acceptance criteria and evidence, plus decisions (ADRs) for choices a newcomer would question. Load it before creating or editing tasks or decisions.
user-invocable: false
---

# Backlog.md: discovered work and decisions

The ladder itself is not tracked here: `tools/kit-next.sh` derives it from the evidence. The
backlog in `ports/<id>/backlog/` holds what only this port knows: each peripheral (S5), a bug
found on the way, a follow-up. **Run `backlog` from inside `ports/<id>/`**, with `--plain` for
output you read back; `backlog <command> --help` lists the exact flags.

## Tasks

A task can be picked up by someone who never saw the conversation:

- **Title:** imperative, specific ("Enable WiFi (wcn36xx)").
- **Acceptance criteria:** checkable facts ("`wlan0` appears", "a scan lists networks"), set
  before the first try.
- **Notes:** what was found, **with evidence** (a command and its key output line, a file path, a
  URL). Mark guesses as guesses.
- **Status:** `To Do`, `In Progress`, `Needs User` (a decision, a photo, a physical action),
  `Blocked` (say what would unblock it), `Done`.
- **Labels:** `peripheral`, `needs-device`, `deferred` (kept for a later release).

```bash
backlog task create "Enable WiFi (wcn36xx)" -l peripheral,needs-device \
  --ac "wlan0 appears" --ac "scan lists networks" -d "…"
backlog task list --plain
backlog task edit <id> -s "In Progress"
backlog task edit <id> --append-notes "wcnss firmware requested: … (dossier/raw/linux-dmesg.txt)"
backlog task edit <id> --check-ac 1 -s Done --final-summary "…"
```

Task ids carry the project prefix (`PORT-12`, not `12`).

## Decisions

One for every choice that would be expensive to reverse or that a newcomer would ask "why?"
about: the kernel source, the boot path, the A/B layout, a departure from the reference system,
a name added to the forbidden list, a user override. `backlog decision create "<title>"`, then
Context / Options considered / Decision / Consequences / Evidence. The result also goes in
`port.yaml` (`path:`), which is what the tools read.

## Resumability

Never keep state only in the conversation: facts go to `port.yaml` and `dossier/`, proofs to
`checks:`, work to tasks, choices to decisions. The Stop hook commits the port workspace.
