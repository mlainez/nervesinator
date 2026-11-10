#!/usr/bin/env python3
"""Where a port stands and what comes next, derived from the evidence on disk.

Usage: kit_next.py [--port <id>] [--json] [--ports <dir>]

Each step of the ladder (skills/port-playbook/stages.md) is done when its evidence exists: a
dossier file, a value in port.yaml, a boot record, the user's write allowlist. Nothing has to be
ticked by hand. Facts that leave no file are recorded in port.yaml under `checks:` as
`<name>: "<proof>"` (a boot record, a log line, a URL).
"""
import glob
import importlib.util
import json
import os
import sys

KIT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))


def load(name, *path):
    spec = importlib.util.spec_from_file_location(name, os.path.join(KIT, *path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


portcfg = load("portcfg", "tools", "lib", "portcfg.py")
grants = load("autonomy_grant", "hooks", "autonomy_grant.py")

STAGES = [("S1", "Scout", "scout"), ("S2", "Open", "open"), ("S3", "Boot from RAM", "boot-test"),
          ("S4", "Nerves", "nerves-system"), ("S6", "Share", "share")]


class Port:
    def __init__(self, ports_dir, port):
        self.ports_dir, self.id = ports_dir, port
        self.dir = os.path.join(ports_dir, port)
        self.cfg = portcfg.parse(os.path.join(self.dir, "port.yaml"))

    def get(self, dotted, default=""):
        cur = self.cfg
        for part in dotted.split("."):
            if not isinstance(cur, dict) or part not in cur:
                return default
            cur = cur[part]
        return cur

    def has(self, *rel):
        path = os.path.join(self.dir, *rel)
        return os.path.isfile(path) and os.path.getsize(path) > 0

    def glob(self, pattern):
        return sorted(glob.glob(os.path.join(self.dir, pattern)))

    def check(self, name):
        value = self.get("checks." + name)
        return value if isinstance(value, str) and value else ""

    def gate(self, name):
        return name in (self.get("gates_passed") or [])

    def boot_pass(self, stage):
        """The newest PASS record of await-boot for this stage, if any."""
        for path in reversed(self.glob("journal/boots/*-%s/result.json" % stage)):
            try:
                with open(path) as f:
                    if json.load(f).get("result") == "PASS":
                        return os.path.relpath(os.path.dirname(path), self.dir)
            except (OSError, ValueError):
                pass
        return ""


def missing(port, files=(), keys=()):
    """What is still missing among files and port.yaml keys, as a short text ('' when complete)."""
    lacks = [f for f in files if not port.has(*f.split("/"))]
    lacks += [k for k in keys if port.get(k) in ("", "unknown", [], {})]
    return ", ".join(lacks)


def recon(p):
    m = missing(p, ["dossier/device.md", "dossier/partitions.md"],
                ["device.soc", "device.arch", "device.flash_mode", "device.product"])
    return (not m, m or "dossier/device.md, dossier/partitions.md")


def prior_art(p):
    m = missing(p, ["dossier/prior-art.md"], ["path.kernel_repo", "path.bootloader"])
    return (not m, m or "%s, bootloader %s" % (p.get("path.kernel_repo"), p.get("path.bootloader")))


def reference(p):
    ref = p.get("path.reference_system")
    return (bool(ref), ref or "path.reference_system (tools/scaffold-system.sh --port %s --list)" % p.id)


def unbrick(p):
    stock = [f for f in p.glob("backups/stock/*") if os.path.isfile(f)] or p.check("stock_firmware")
    m = missing(p, ["dossier/unbrick.md"], ["device.return_mode"])
    if not stock:
        m = (m + ", " if m else "") + "stock firmware in backups/stock/ (or checks.stock_firmware)"
    return (not m, m or "dossier/unbrick.md, stock firmware on disk")


def unlock_plan(p):
    if p.get("safety.bootloader_unlocked") in ("yes", "not-needed"):
        return True, "bootloader_unlocked: %s" % p.get("safety.bootloader_unlocked")
    return p.has("dossier", "unlock.md"), "dossier/unlock.md"


def gate_costs(p):
    return p.gate("G1"), "G1 in gates_passed (the user accepts the costs listed in dossier/unlock.md)"


def unlocked(p):
    state = p.get("safety.bootloader_unlocked")
    return state in ("yes", "not-needed"), "safety.bootloader_unlocked: %s" % (state or "unknown")


def backups(p):
    ok = p.has("backups", "SHA256SUMS") and str(p.get("safety.backups_verified")).lower() == "true"
    return ok, "backups/SHA256SUMS" if ok else "backups/SHA256SUMS and safety.backups_verified: true"


def gate_writes(p):
    allow = grants.read_allowlist(p.ports_dir, p.id)
    if allow:
        return True, "write allowlist: " + ", ".join(allow["partitions"])
    return False, "the user types: allow writes <partition…> [no backup <partition…>]"


def boot_path(p):
    m = missing(p, [], ["path.boot_method", "safety.ram_boot"])
    return (not m, m or p.get("path.boot_method"))


def boot_record(stage):
    def check(p):
        record = p.boot_pass(stage)
        return bool(record), record or "no PASS record in journal/boots/*-%s" % stage
    return check


def inventory(p):
    m = missing(p, ["dossier/partitions-linux.md", "dossier/raw/linux-dmesg.txt"])
    return (not m, m or "dossier/partitions-linux.md")


def system(p):
    found = p.glob("nerves_system_*/mix.exs")
    return bool(found), (os.path.relpath(os.path.dirname(found[0]), p.dir) if found
                         else "nerves_system_<name>/ (tools/scaffold-system.sh --port %s)" % p.id)


def layout(p):
    m = missing(p, [], ["path.nerves_layout"])
    if not p.check("fwup_host"):
        m = (m + ", " if m else "") + "checks.fwup_host (host-check-fwup.sh on a file image)"
    return (not m, m or p.get("path.nerves_layout"))


def firmware(p):
    found = p.glob("*/_build/*/nerves/images/*.fw")
    return bool(found), (os.path.relpath(found[-1], p.dir) if found else "mix firmware in the test app")


def nerves_boot(p):
    proof = p.boot_pass("nerves") or p.check("nerves_boot")
    return bool(proof), proof or "no PASS record in journal/boots/*-nerves (await-boot --stage nerves --host nerves.local)"


def checks(*names):
    def check(p):
        lacks = [n for n in names if not p.check(n)]
        return (not lacks, ", ".join("checks." + n for n in lacks) if lacks
                else "; ".join(p.check(n) for n in names))
    return check


def docs(p):
    systems = p.glob("nerves_system_*/")
    lacks = []
    for name in ("README.md", "install.sh", "LICENSE"):
        if not any(os.path.isfile(os.path.join(s, name)) for s in systems):
            lacks.append(name)
    return (not lacks, ", ".join(lacks) + " in the Nerves system" if lacks else "README, install.sh, LICENSE")


def gate_publish(p):
    return p.gate("G3"), "G3 in gates_passed (the user agrees to publish)"


# id, stage, title, who (host | device | user), needs, check, how
STEPS = [
    ("recon", "S1", "Device recon", "device", [], recon,
     "tools/recon/collect.sh, then the dossier (scout/recon.md)"),
    ("prior-art", "S1", "Prior art and kernel path", "host", ["recon"], prior_art,
     "tools/prior-art.sh --port <id>, then dossier/prior-art.md (scout/prior-art.md)"),
    ("reference", "S1", "Closest existing Nerves system", "host", ["recon"], reference,
     "tools/scaffold-system.sh --port <id> --list (nerves-system/family.md)"),
    ("unbrick", "S1", "Unbrick kit", "host", ["recon"], unbrick,
     "stock firmware download in the background, mode entries, dossier/unbrick.md (open/unlock.md)"),
    ("unlock-plan", "S1", "Unlock plan and its costs", "host", ["recon"], unlock_plan,
     "dossier/unlock.md (open/unlock.md)"),
    ("G1", "S1", "GATE G1: go and accepted costs", "user",
     ["prior-art", "reference", "unbrick", "unlock-plan"], gate_costs,
     "show the verdict and the irreversible costs, wait for the user's go"),
    ("unlock", "S2", "Unlock the bootloader", "device", ["G1"], unlocked,
     "tools/safe-flash.sh --port <id> --execute unlock (the guard asks)"),
    ("backups", "S2", "Verified backups", "device", ["unlock"], backups,
     "tools/backup-partitions.sh --port <id> (device-safety, Backups)"),
    ("G2", "S2", "GATE G2: the write allowlist", "user", ["backups"], gate_writes,
     "propose the partitions (default boot + userdata); the user types the allowlist"),
    ("boot-path", "S3", "Boot path", "device", ["G2"], boot_path,
     "second stage or stock, RAM boot method (boot-test, port-playbook/decisions.md)"),
    ("first-light", "S3", "First light", "device", ["boot-path"], boot_record("firstlight"),
     "tools/await-boot.sh --port <id> --image <img> --stage firstlight"),
    ("rescue", "S3", "Rescue shell", "device", ["first-light"], boot_record("rescue"),
     "tools/await-boot.sh --port <id> --image <img> --stage rescue, tools/usbnet.sh"),
    ("inventory", "S3", "Linux hardware inventory", "device", ["rescue"], inventory,
     "over ssh from the rescue shell (scout/recon.md, Linux-side recon)"),
    ("system", "S4", "Nerves system scaffold", "host", ["G1"], system,
     "tools/scaffold-system.sh --port <id> (nerves-system)"),
    ("layout", "S4", "A/B layout checked on a file image", "host", ["system", "inventory"], layout,
     "nerves-system/android-ab-layouts.md, templates/nerves/host-check-fwup.sh"),
    ("firmware", "S4", "Firmware built", "host", ["layout"], firmware, "mix firmware (nerves-system/app.md)"),
    ("nerves-boot", "S4", "First Nerves boot", "device", ["firmware", "G2"], nerves_boot,
     "safe-flash, then tools/await-boot.sh --watch-only --stage nerves --host nerves.local"),
    ("update", "S4", "Upload and revert", "device", ["nerves-boot"], checks("upload", "revert"),
     "mix upload, then Nerves.Runtime.revert; record the proofs under checks:"),
    ("charging", "S4", "Charging and battery", "device", ["nerves-boot"], checks("charging"),
     "peripherals/firmware.md, Charging; record the proof under checks:"),
    ("docs", "S6", "README, installer, licence", "host", ["update", "charging"], docs, "share"),
    ("G3", "S6", "GATE G3: publish", "user", ["docs"], gate_publish,
     "show what will become public, wait for the user's go"),
    ("release", "S6", "Release", "host", ["G3"], checks("release"), "share, Release"),
    ("list", "S6", "Row in awesome-nerves-systems", "host", ["release"], checks("awesome_row"),
     "share, The family list"),
]


def open_backlog_tasks(port):
    count = 0
    for path in port.glob("backlog/tasks/*.md"):
        try:
            with open(path) as f:
                head = f.read(2000)
        except OSError:
            continue
        status = [l.split(":", 1)[1].strip().strip("'\"") for l in head.splitlines()
                  if l.startswith("status:")]
        if status and status[0].lower() != "done":
            count += 1
    return count


def survey(ports_dir, port_id):
    port = Port(ports_dir, port_id)
    steps, done = [], set()
    for sid, stage, title, who, needs, check, how in STEPS:
        ok, evidence = check(port)
        if ok:
            done.add(sid)
        steps.append({"id": sid, "stage": stage, "title": title, "who": who, "needs": needs,
                      "done": ok, "evidence": evidence, "how": how.replace("<id>", port_id)})
    for step in steps:
        step["ready"] = not step["done"] and all(n in done for n in step["needs"])
    pending = [s for s in steps if not s["done"]]
    current = pending[0]["stage"] if pending else "done"
    return {"port": port_id, "stage": current, "steps": steps,
            "ready": [s["id"] for s in steps if s["ready"]],
            "open_tasks": open_backlog_tasks(port),
            "autonomy": port.get("session.autonomy", "attended"),
            "teach": port.get("learner.teach", "off"),
            "buildroot_branch": str(port.get("path.buildroot_branch", "")).lower() == "true"}


def render(state):
    names = {sid: (name, skill) for sid, name, skill in STAGES}
    out = []
    if state["stage"] == "done":
        out.append("port %s: every step of the ladder is done" % state["port"])
    else:
        name, skill = names[state["stage"]]
        out.append("port %s: stage %s %s (skill: %s)" % (state["port"], state["stage"], name, skill))
    for sid, name, _ in STAGES:
        steps = [s for s in state["steps"] if s["stage"] == sid]
        ok = sum(s["done"] for s in steps)
        out.append("%s %-14s %d/%d%s" % (sid, name, ok, len(steps), " done" if ok == len(steps) else ""))
        if ok == len(steps) and sid != state["stage"]:
            continue
        for s in steps:
            mark = "done " if s["done"] else ("READY" if s["ready"] else "later")
            out.append("   %s %-36s %s" % (mark, s["title"], s["evidence"]))
    ready = [s for s in state["steps"] if s["ready"]]
    if ready:
        out.append("next (independent steps can run in parallel):")
        out += ["   %s [%s]: %s" % (s["title"], s["who"], s["how"]) for s in ready]
    out.append("backlog: %d open task(s) (S5 peripherals and discovered work)" % state["open_tasks"])
    if state["buildroot_branch"]:
        out.append("Buildroot branch: on (buildroot-port skill)")
    out.append("autonomy: %s, teaching: %s" % (state["autonomy"], state["teach"]))
    return "\n".join(out)


def main(argv):
    ports_dir, port, as_json = os.path.join(KIT, "ports"), None, False
    i = 0
    while i < len(argv):
        if argv[i] == "--port" and i + 1 < len(argv):
            port, i = argv[i + 1], i + 2
        elif argv[i] == "--ports" and i + 1 < len(argv):
            ports_dir, i = argv[i + 1], i + 2
        elif argv[i] == "--json":
            as_json, i = True, i + 1
        else:
            print(__doc__.strip().splitlines()[2])
            return 2
    port = port or grants.active_port(ports_dir)
    if not port or not os.path.isfile(os.path.join(ports_dir, port, "port.yaml")):
        print("no active port (ports/.active): run tools/new-port.sh <id> <serial>")
        return 1
    state = survey(ports_dir, port)
    print(json.dumps(state, indent=2) if as_json else render(state))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
