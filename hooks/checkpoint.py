#!/usr/bin/env python3
"""Stop hook: commits the active port's workspace when it changed, so work stopped at any moment
is on record. Never blocks and never fails the session."""
import os
import subprocess
import sys

KIT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))


def vcs(port_dir, *args):
    return subprocess.run(["git", "-C", port_dir] + list(args), capture_output=True, text=True,
                          timeout=20, stdin=subprocess.DEVNULL)


def main():
    try:
        with open(os.path.join(KIT, "ports", ".active")) as f:
            port = f.read().strip()
        port_dir = os.path.join(KIT, "ports", port)
        if not port or not os.path.isdir(os.path.join(port_dir, ".git")):
            return 0
        if not vcs(port_dir, "status", "--porcelain").stdout.strip():
            return 0
        state = subprocess.run(
            [sys.executable, "-I", os.path.join(KIT, "tools", "lib", "kit_next.py"), "--port", port],
            capture_output=True, text=True, timeout=8).stdout.splitlines()
        stage = state[0].split(": ", 1)[1] if state and ": " in state[0] else "work in progress"
        vcs(port_dir, "add", "-A")
        vcs(port_dir, "commit", "-q", "-m", "Checkpoint: %s" % stage)
    except (OSError, subprocess.SubprocessError):
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
