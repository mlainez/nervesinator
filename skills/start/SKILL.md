---
name: start
description: Entry point of the porting kit. Detects attached devices (adb, fastboot, Samsung download, EDL/BROM), lets the user pick one, creates or resumes the port workspace (git repo, Backlog.md milestones and tasks, port.yaml), then runs the work loop until the next gate. Use when the user types Start, Resume or continue.
argument-hint: "[port-id]"
---

# Start / resume a port

Follow these steps in order. Narrate briefly as you go (one line per step), in the user's language
once it is known.

## 1. Look for existing ports

```bash
cat ports/.active 2>/dev/null; ls ports/*/port.yaml 2>/dev/null
```

- If an argument was given (`/start <id>`), use that port and go to **step 5 (Resume)**.
- If ports exist, show them (id, model, current milestone from `port.yaml`) and ask: resume one
  of them, or start a new device?

## 2. Check the host (first time per machine, or if a tool fails)

```bash
tools/check-host.sh
```

Fix the blocking items with the user (it prints install commands for the distribution it finds).
Tools needed only for later milestones are reported as "later": don't block on them now.

## 3. Detect devices

```bash
tools/detect-devices.sh
```

It lists every phone it can see over adb, fastboot, Samsung download mode (heimdall) and USB
vendor IDs (EDL/BROM). Then handle the result:

- **Nothing found:** teach the user how to enable Developer options (tap "Build number" 7 times)
  and **USB debugging**, try another cable/port (many cables only charge), then run it again.
- **`unauthorized`:** ask them to unlock the phone and accept the "Allow USB debugging?" prompt
  (tick "Always allow"). Explain in one sentence what the RSA key prompt protects against. Run it again.
- **One or more devices:** ask which one to work on (a multiple-choice question listing model +
  serial). If only one, still confirm it: this is the device we may modify later.

## 4. New port: create the workspace

1. Read the identity of the chosen device (read-only):
   ```bash
   adb -s <serial> shell getprop ro.product.manufacturer
   adb -s <serial> shell getprop ro.product.device
   adb -s <serial> shell getprop ro.product.model
   ```
   (If the device is only in fastboot/download mode, use `fastboot -s <serial> getvar product` or ask the user.)
2. Propose the port id `<vendor>-<codename>` in lowercase (e.g. `fairphone-fp2`). Check
   `grep -l "serial: <serial>" ports/*/port.yaml` first: if this serial already has a port, resume it.
3. Create it:
   ```bash
   tools/new-port.sh <id> <serial>
   ```
   It creates `ports/<id>/` (a git repo), `port.yaml` from `templates/port.yaml`, the dossier/journal
   folders, and a Backlog.md project with the milestones M0–M12 and their seeded tasks
   (from `templates/backlog-seed.json`), and writes `ports/.active`.
4. Do the M0 tasks with the user, in this order:
   - **Learner profile.** Ask (multiple choice when possible): Linux/command-line experience
     (none / some / daily), embedded/electronics experience, Elixir experience, explanation depth
     (short / normal / deep), language. Store it under `learner:` in `port.yaml`.
   - **Safety briefing.** Load `device-safety`. Explain soft vs hard brick, the four risk colors,
     the gates, and that unlocking will wipe the phone: ask them to save their personal data now.
     Ask whether they are OK with losing warranty/KNOX status, and record the answer.
   - **Root preference.** Explain what root is (a uid 0 shell on Android), what it would give the
     port (full recon and raw partition backups) and what it usually costs (an unlock or a custom
     recovery flash, KNOX/warranty). Ask: already rooted / root it if possible / no root. Record it
     in `safety.root` (`already` / `wanted` / `declined`). If wanted, the M3 research finds a
     standard method for this device and the M5 root shell task carries it out.
   - **Kickoff lesson.** Load `teach`. Give the "three pillars" lesson (bootloader, kernel, rootfs)
     and draw the map of the whole journey (the ladder from `port-playbook`).
   - Then go to the **work loop** (step 6), which will reach GATE M0.

## 5. Resume an existing port

1. `echo <id> > ports/.active`; read `ports/<id>/port.yaml` and the tail of `ports/<id>/journal/sessions.md`.
   If `session.autonomy` is `unattended`, load the `autonomy` skill and follow it.
2. From `ports/<id>/`:
   ```bash
   backlog milestone list --plain
   backlog task list --plain -s "In Progress"
   backlog task list --plain -s "Needs User"
   backlog task list --plain -s "Blocked"
   ```
3. Check that the device is still attached (`tools/detect-devices.sh`) and that its serial matches
   `device.serial`. If not, the work can still continue on host-only tasks (green tasks without a device).
4. Give a 5-line "previously on…" recap: where we are on the ladder, the last thing achieved, what is
   pending, and the next task. Remind the user of one concept from the last lesson (spaced repetition).
5. Go to the **work loop**.

## 5b. Adopt the kit on a port already under way

When the user has already done part of the work without the kit:

1. `tools/new-port.sh <id> <serial>`, then backfill M0 to the milestone reached: each task Done
   with a note "Backfilled <date>" pointing at the evidence (files, commits, logs); gate tasks get
   a note that the user drove them before adoption.
2. **Re-run the safety checks instead of trusting the history**: verify the backups against M5
   (every class A/B partition, not only `boot`/`recovery`), the allowlist, the unbrick kit. Missing
   backups are done now, before any new write (`device-safety`, Backups).
3. Fill `port.yaml` from the existing dossier and re-check the facts that matter for writes
   (product, partition sizes, flash mode, return mode).

## 6. The work loop

Repeat until a gate is reached or the user wants to stop:

1. **Pick the next task:** the In Progress one, otherwise the first To Do task of the current
   milestone whose dependencies are Done (`backlog sequence list --plain` helps). Load
   `port-playbook` for its details.
2. **Announce it:** what we will do, why it matters, its risk color, and which agent will do it.
   Mark it `In Progress`.
3. **Do it:** delegate to the agent named in the playbook, with the port id, task id, the needed
   `port.yaml` facts and the expected deliverable (file paths). Run long builds in the background
   and teach meanwhile. For any device write: `flash-guardian` prepares the plan → you show it →
   the user says yes → it runs.
4. **Check the result yourself:** open the files it produced, check the acceptance criteria. Never
   tick a criterion on an agent's word alone when it can be checked.
5. **Record it:** tick the ACs, write notes (what was found, the evidence, the sources), set Done.
   Update `port.yaml` when a fact or a safety flag changed. Add new tasks if new work appeared.
   Commit in `ports/<id>` (`git add -A && git commit -m "<task id>: <summary>"`; backups are ignored by git).
6. **Teach a bit:** one short "what we learned" line, plus a link from the reading list when relevant.
7. **At a GATE task:** follow the gate rules in `port-playbook` and **stop**. Set the gate task to
   `Needs User` until the user answers.

When the user stops (or the context gets long), append a session entry to `journal/sessions.md`:
date, what was done, the current task, the next step, any open question. Then "Start" will pick up
exactly from there.
