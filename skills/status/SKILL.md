---
name: status
description: Show where the active port stands - milestone ladder progress, current and blocked tasks, safety flags, the next step. Use when the user asks /status or "where are we?".
---

# Port status

1. Read `ports/.active`, then `ports/<id>/port.yaml`.
2. From `ports/<id>/`, run `backlog milestone list --plain` and `backlog task list --plain`.
3. Show, compactly:
   - The ladder M0–M12 with ✅ for passed gates (`gates_passed`), 👉 for the current milestone, ⬜ for the rest.
   - The current task, any `Needs User` or `Blocked` task and why.
   - The safety panel: `unbrick_kit_ready`, `bootloader_unlocked`, `backups_verified`,
     `writable_partitions`, `experiment_partition`, how we boot our kernel (`path.boot_method`).
   - The chosen path: kernel source, bootloader, rootfs placement.
   - The next step, in one sentence.
4. Do not start working. Offer to continue ("Start" resumes).
