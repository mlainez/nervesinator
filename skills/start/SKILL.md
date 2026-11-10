---
name: start
description: Entry point of the porting kit. Detects attached devices (adb, fastboot, Samsung download, EDL/BROM), creates or resumes the port workspace, then runs the work loop - whatever tools/kit-next.sh says is ready, in parallel where possible - until a gate. Use when the user types Start, Resume or continue.
argument-hint: "[port-id]"
---

# Start / resume a port

## 1. Which port

```bash
tools/kit-next.sh            # the active port, if any
ls ports/*/port.yaml 2>/dev/null
```

- An active port, or an argument (`start <id>`: `echo <id> > ports/.active`): go to **the loop**.
- Several ports and no argument: ask which one, or a new device.
- None: continue below.

## 2. A new port

```bash
tools/check-host.sh          # fix only the ❌ items; ⏳ ones are for later stages
tools/detect-devices.sh
```

- **Nothing found:** Developer options (tap "Build number" 7 times), USB debugging, another cable
  (many only charge); run it again.
- **`unauthorized`:** the user accepts the "Allow USB debugging?" prompt on the phone.
- **One device:** confirm it in the same message as the port id. **Several:** ask which one.

Then read its identity (`adb -s <serial> shell getprop ro.product.manufacturer`, `…device`,
`…model`; in fastboot, `getvar product`), check no port has this serial already
(`grep -l "serial: <serial>" ports/*/port.yaml`), and create the workspace:

```bash
tools/new-port.sh <vendor>-<codename> <serial>
```

No questionnaire: the language is the one the user writes in (`learner.language`), teaching is off
until they ask (`teach on`, `explain <topic>`), and the one thing to say now is to copy their
personal data off the phone, because S2 wipes it. Go straight to the loop.

### Adopting a port already under way

`tools/new-port.sh`, then put the existing evidence where `kit-next` looks for it (dossier files,
`port.yaml` values, `checks:`), and **re-run the safety checks instead of trusting the history**:
the backups against `device-safety` (every class A/B partition), the unbrick kit, the product and
partition sizes. The user types their write allowlist again.

## 3. The loop

Repeat until a gate, or until nothing is ready without the user:

1. `tools/kit-next.sh`: take **every** READY step. Load the stage's skill once.
2. **Say what is starting**, in one or two lines for all of them: what and why.
3. **Run them.** Independent host or read-only steps go to agents in one message (`researcher`,
   `builder`), with the port id and path, the `port.yaml` facts they need, the serials, the return
   mode and the exact deliverable. Long builds run in the background. Device steps run one at a
   time, by the orchestrator, through `tools/safe-flash.sh` and `tools/await-boot.sh`.
4. **Check the evidence yourself**: open what was produced; never take an agent's word for what
   can be checked. Write the facts to `port.yaml`, and proofs without a file under `checks:`.
5. **Say what it showed**, in a line. New work that appeared becomes a backlog task
   (`backlog-workflow`), not a detour.
6. **At a gate** (`port-playbook`): show what was achieved with its proof, what the next stage
   risks and how it is undone, and wait for the user. G2 is typed by the user, never by you.

Nothing needs closing by hand: the Stop hook commits the port workspace, and the next session
starts from `tools/kit-next.sh`. Add a line to `journal/sessions.md` only for what the evidence
does not show: a decision, an open question, something to try next.
