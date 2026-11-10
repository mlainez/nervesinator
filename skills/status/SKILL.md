---
name: status
description: Show where the active port stands - the stage, the gates, what is done with its evidence, what is ready next, open backlog tasks and the safety state. Use when the user asks /status or "where are we?".
---

# Port status

1. Run `tools/kit-next.sh` (add `--port <id>` for another port).
2. Show it compactly, in the user's language: the six stages with what is done, the three gates,
   the steps that are ready, and the open backlog tasks (`backlog task list --plain` from
   `ports/<id>/` when the user wants them listed).
3. Add the safety state from `port.yaml`: `bootloader_unlocked`, `backups_verified`, the write
   allowlist (from the kit-next G2 line), how our kernel boots (`path.boot_method`), anything in
   `safety.irreversible_done`.
4. Do not start working. "Start" resumes.
