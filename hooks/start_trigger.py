#!/usr/bin/env python3
"""UserPromptSubmit hook: points the agent at the start or autonomy skill when the user types a
trigger, and creates or revokes the full-autonomy grant. Only this hook writes the grant, because
only here is the text certainly typed by the user."""
import importlib.util
import json
import os
import re
import sys

KIT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
_spec = importlib.util.spec_from_file_location("autonomy_grant", os.path.join(KIT, "hooks", "autonomy_grant.py"))
autonomy_grant = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(autonomy_grant)
PORTS = os.path.join(KIT, "ports")

TRIGGERS = {"start", "/start", "resume", "continue", "let's start", "lets start"}
AUTONOMY = {"/autonomous on": "unattended", "i'm away": "unattended", "im away": "unattended",
            "/autonomous off": "attended", "i'm back": "attended", "im back": "attended"}
FULL_RE = re.compile(r"^/autonomous\s+full\b\s*(?P<goal>.*?)(?:\s+for\s+(?P<hours>\d+)\s*h)?$", re.I | re.S)


def context(text):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": text}}))


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 0
    raw = (data.get("prompt") or "").strip()
    prompt = raw.lower().rstrip(".!")
    full = FULL_RE.match(raw)
    if full:
        goal = full.group("goal").strip() or "the current milestone's gate"
        hours = int(full.group("hours") or autonomy_grant.DEFAULT_HOURS)
        grant = autonomy_grant.write_grant(PORTS, goal, hours, raw)
        if grant:
            context("The user granted FULL autonomy for the active port until: %s (expires %s). "
                    "Invoke the `autonomy` skill now and follow its full-autonomy rules: the guard "
                    "now allows what it would ask about, never what it denies; do not ask the user "
                    "anything until the goal is reached." % (goal, grant["expires_at"]))
        else:
            context("The user asked for full autonomy, but there is no active port (ports/.active): "
                    "no grant was created. Tell the user to start or resume a port first.")
    elif prompt in TRIGGERS:
        context("The user wants to start or resume a port. Invoke the `start` skill now and follow "
                "it exactly. If a gate is pending, 'go'/'continue' only counts as approval when it "
                "answers that gate's question.")
    elif prompt in AUTONOMY:
        revoked = autonomy_grant.clear_grant(PORTS)
        context("The user switches the port to %s work%s. Invoke the `autonomy` skill now, record "
                "session.autonomy in port.yaml and follow the skill's rules."
                % (AUTONOMY[prompt], " (the full-autonomy grant is revoked)" if revoked else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
