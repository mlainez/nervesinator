---
name: open
description: Stage S2 of a port - unlock the bootloader (the one write that always asks), dump and verify every partition that matters, then gate G2 where the user types the write allowlist. Holds the vendor-by-vendor unlock knowledge (Google/AOSP fastboot, Qualcomm OEMs, Samsung download mode, MediaTek, Motorola/Sony/Xiaomi tokens, Huawei) and the unbrick-kit requirements. Use when tools/kit-next.sh shows stage S2, and in S1 for the unlock plan.
---

# S2 Open

Load `device-safety` first, and the vendor file it points to. Reference: [unlock.md](unlock.md).

## 1. Unlock

Needs gate G1 (the user accepted the costs in `dossier/unlock.md`) and the unbrick kit.

```bash
tools/safe-flash.sh --port <id> unlock            # dry run: the checks and the command
tools/safe-flash.sh --port <id> --execute unlock  # the guard asks the user: it wipes the phone
```

Vendors without a fastboot unlock (Samsung, token-based vendors, MediaTek seccfg) follow
`dossier/unlock.md`; each device command still passes the guard. Afterwards: check the state the
bootloader reports, set `safety.bootloader_unlocked` (`yes`, or `not-needed` when the bootloader
accepts unsigned images as it is), and record anything irreversible in `safety.irreversible_done`.

## 2. Backups

```bash
tools/backup-partitions.sh --port <id> --method root|recovery
```

Class B first, then class A (for reference, never restored by the kit), then class D
(`device-safety`, Backups). A root shell comes from a RAM-booted recovery when the bootloader
allows it; when it needs a write (Samsung), the target's backup is the matching image from the
stock firmware and the guard asks for that one flash. Without stock firmware, dump everything.
When `backups/SHA256SUMS` verifies, set `safety.backups_verified: true` and tell the user to copy
`backups/` off this machine (once; do not wait for it).

## 3. Gate G2: the write allowlist

Propose the partitions the port will write, `boot` and `userdata` by default, another one only
with its reason. `userdata` is personal and huge: the user either accepts its loss or it is dumped
first. The user then types, in their own words:

```
allow writes boot userdata no backup userdata
```

(`tools/user-mode.sh writes boot userdata --no-backup userdata` where there is no prompt hook.)
Never type or run it for them. From then on a write to a listed partition with a backup, through
`tools/safe-flash.sh` or a plain flash command addressed to this port's serial, runs without
asking; everything else still asks, and the forbidden list still denies.
