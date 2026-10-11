#!/usr/bin/env python3
"""Create Backlog.md milestones and tasks for a new port from templates/backlog-seed.json.

Usage: seed_backlog.py <port-dir> <seed.json>
Runs the `backlog` CLI inside <port-dir>. Each task depends on the previous one in its milestone;
the first task of a milestone depends on the previous milestone's gate.
"""
import json
import re
import subprocess
import sys


def backlog(port_dir, *args):
    r = subprocess.run(["backlog", *args], cwd=port_dir, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("backlog %s failed:\n%s%s" % (" ".join(args[:3]), r.stdout, r.stderr))
    return r.stdout


def main():
    port_dir, seed_file = sys.argv[1], sys.argv[2]
    with open(seed_file) as f:
        seed = json.load(f)
    prev = None
    count = 0
    for ms in seed["milestones"]:
        backlog(port_dir, "milestone", "add", ms["title"], "-d", ms["description"])
        for i, t in enumerate(ms["tasks"]):
            args = ["task", "create", t["title"], "--plain", "-m", ms["title"], "-l", t["labels"],
                    "-d", "%s\n\nDetails: skills/port-playbook/milestones.md, section %s."
                    % (ms["description"], ms["id"]), "--no-dod-defaults"]
            for ac in t.get("ac", []):
                args += ["--ac", ac]
            if prev:
                args += ["--dep", prev]
            out = backlog(port_dir, *args)
            m = re.search(r"Task\s+([A-Za-z]+-\d+)\s+-", out)
            if not m:
                sys.exit("could not parse task id from:\n" + out)
            prev = m.group(1)
            count += 1
    print("seeded %d milestones, %d tasks" % (len(seed["milestones"]), count))


if __name__ == "__main__":
    main()
