@AGENTS.md

## Claude Code specifics

- Skills in `skills/` and agents in `agents/` are exposed through the `.claude/skills` and
  `.claude/agents` symlinks: invoke skills with the Skill tool and agents with the Agent tool.
- Hooks (`.claude/settings.json`): `hooks/device_guard.py` on every Bash call, including calls
  made by agents; `hooks/start_trigger.py` on every prompt (the user's words: start, allow writes,
  override, hands off, autonomous); `hooks/session_context.py` at session start (the state of the
  active port); `hooks/checkpoint.py` at stop (commits the port workspace).
- Use AskUserQuestion for choices at gates G1 and G3 and for device selection. Gate G2 is typed
  by the user. Agents cannot ask.
- Do not run this kit in bypassPermissions mode: the guard's `ask` decisions are the human
  confirmation step for unlocks, wipes and writes outside the allowlist.
