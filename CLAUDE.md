@AGENTS.md

## Claude Code specifics

- Skills in `skills/` and agents in `agents/` are exposed through the `.claude/skills` and
  `.claude/agents` symlinks: invoke skills with the Skill tool and agents with the Agent tool.
- `hooks/device_guard.py` runs as a PreToolUse hook on every Bash call, including calls made by
  agents. `hooks/start_trigger.py` reminds you to load the `start` skill when the user types `Start`.
- Use AskUserQuestion for choices at gates and device selection. Agents cannot use it.
- Do not run this kit in bypassPermissions mode: the guard's `ask` decisions are the human
  confirmation step for device writes.
