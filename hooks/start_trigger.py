#!/usr/bin/env python3
"""UserPromptSubmit hook: when the user types a start/resume word, point the agent at the start skill."""
import json
import sys

TRIGGERS = {"start", "/start", "resume", "continue", "let's start", "lets start"}


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 0
    prompt = (data.get("prompt") or "").strip().lower().rstrip(".!")
    if prompt in TRIGGERS:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": "The user wants to start or resume a port. Invoke the `start` skill "
                                 "now and follow it exactly. If a gate is pending, 'go'/'continue' "
                                 "only counts as approval when it answers that gate's question."}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
