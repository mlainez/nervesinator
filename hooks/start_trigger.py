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
OVERRIDE_RE = re.compile(r"^/override\s+(?P<targets>.+?)(?:\s+for\s+(?P<minutes>\d+)\s*m)?$", re.I | re.S)
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
    elif prompt in ("/override off", "/override clear"):
        cleared = autonomy_grant.clear_override(PORTS)
        context("The user ended their override%s: the guard denies the safety invariants again."
                % ("" if cleared else " (none was active)"))
    elif OVERRIDE_RE.match(raw):
        m = OVERRIDE_RE.match(raw)
        targets = [t.lower() for t in m.group("targets").split()]
        minutes = int(m.group("minutes") or autonomy_grant.DEFAULT_OVERRIDE_MINUTES)
        override = autonomy_grant.write_override(PORTS, targets, minutes, raw)
        if override:
            context("The user OVERRIDES a safety invariant for: %s (until %s). Commands naming these "
                    "targets are now asked, not denied; each still needs the user's yes, even under "
                    "the full-autonomy grant. Before each one, state its consequences plainly (what can "
                    "be lost, whether it can be undone, how), record the user's decision as a backlog "
                    "decision and in safety.irreversible_done when it is irreversible, then proceed "
                    "only on their yes. Do not argue or refuse: it is their device."
                    % (", ".join(targets), override["expires_at"]))
        else:
            context("The user asked for an override, but there is no active port or no target: "
                    "nothing was set. The form is /override <target…> [for <N>m].")
    elif prompt in ("hands off", "/hands off"):
        if autonomy_grant.set_hands_off(PORTS, raw):
            context("HANDS OFF: the user is working on the device. The guard now denies every device "
                    "command from every session. Tell all agents to stop device work, do host work "
                    "only, and wait until the user types \"hands on\".")
        else:
            context("The user said hands off, but there is no active port: nothing was set.")
    elif prompt in ("hands on", "/hands on"):
        cleared = autonomy_grant.clear_hands_off(PORTS)
        context("HANDS ON: the user has finished with the device%s; device work may resume."
                % ("" if cleared else " (no hands-off marker was set)"))
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
