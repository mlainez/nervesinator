#!/usr/bin/env python3
"""SessionStart hook: tells the agent where the active port stands (tools/kit-next.sh), so a
session resumes from the evidence on disk instead of a recap ritual."""
import json
import os
import subprocess
import sys

KIT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))


def main():
    if not os.path.isfile(os.path.join(KIT, "ports", ".active")):
        return 0
    try:
        run = subprocess.run([sys.executable, "-I", os.path.join(KIT, "tools", "lib", "kit_next.py")],
                             capture_output=True, text=True, timeout=8)
    except (OSError, subprocess.SubprocessError):
        return 0
    if run.returncode != 0 or not run.stdout.strip():
        return 0
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": "Porting kit, state of the active port (tools/kit-next.sh):\n%s\n"
                             "When the user wants to go on, load the `start` skill."
                             % run.stdout.strip()}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
