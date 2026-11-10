---
name: scout
description: Stage S1 of a port - everything that can be learned without changing the device, run in parallel - read-only recon over adb, prior art (pmaports, mainline, lk2nd, U-Boot), the closest existing Nerves system, the unbrick kit and the unlock plan with its costs. Ends at gate G1 (go and accepted costs). Use when tools/kit-next.sh shows stage S1, or when a device fact is missing later.
---

# S1 Scout

Nothing here writes to the device, so nothing here waits for the user: run it all, in parallel
where the steps are independent, and stop only at gate G1. `tools/kit-next.sh` lists what is left.

## 1. Recon (first: the others need its facts)

```bash
tools/recon/collect.sh <serial> ports/<id>/dossier/raw
```

Interpret it with [recon.md](recon.md) into `dossier/device.md`, `dossier/partitions.md` (each
partition with its class A/B/C/D, `device-safety`) and the `device:` section of `port.yaml`.
Every fact carries its source; a guess is marked as one.

## 2. In parallel, once the SoC and codename are known

Give each of these to a `researcher` agent in one message (they are independent), or do them
yourself when the tool has no subagents:

| Step | Tool and reference | Evidence |
|---|---|---|
| Prior art and kernel path | `tools/prior-art.sh --port <id>`, then [prior-art.md](prior-art.md) and `port-playbook` decisions.md | `dossier/prior-art.md`, `path.kernel_repo`, `path.kernel_ref`, `path.dtb`, `path.bootloader` |
| Closest existing Nerves system | `tools/scaffold-system.sh --port <id> --list` ([family.md](../nerves-system/family.md)) | `path.reference_system` (a repo, or `none`) |
| Unbrick kit | Stock firmware downloaded to `backups/stock/` in the background (URL and sha256 recorded), the flash tool tested read-only, mode entries and the return mode; `open` unlock.md, "Unbrick kit requirements" | `dossier/unbrick.md`, `device.return_mode`, `device.modes` |
| Unlock plan | `open` unlock.md and the vendor file of `device-safety`; at least two sources for anything irreversible | `dossier/unlock.md`: the procedure, and each irreversible cost in plain words |

When no stock firmware can be found, plan a full dump of every partition in S2 instead and record
`checks.stock_firmware: "full dump planned"` (`device-safety`, invariants).

Mode entries that need keys are a hands-on test (`hands-on-test`): batch them into one short
session with the user instead of one interruption per mode.

## 3. Gate G1: go, and the costs

Show, in a few lines: the feasibility verdict (scenario A/B/C, what already works according to the
sources), the system the port will start from, and **each irreversible cost of the unlock** (data
wipe, a warranty fuse, DRM keys). On the user's go, record `G1` in `gates_passed` and the accepted
costs in `learner.accepted_costs`. A no-go ends the port here, with the dossier kept.
