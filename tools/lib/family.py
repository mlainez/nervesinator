#!/usr/bin/env python3
"""The family of existing Nerves systems (tools/lib/family.tsv): rank them by similarity to a
port, list the ones the awesome-nerves-systems page has and the index lacks, and scaffold a new
system from one of them. Driven by tools/scaffold-system.sh."""
import os
import re
import shutil
import subprocess
import sys
import urllib.request

KIT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
INDEX = os.path.join(KIT, "tools", "lib", "family.tsv")
AWESOME = "https://raw.githubusercontent.com/mlainez/awesome-nerves-systems/main/README.md"
FIELDS = ["repo", "device", "soc", "arch", "flash_mode", "second_stage", "layout", "android_ab",
          "template", "notes"]
TEXT_SKIP = (".png", ".jpg", ".img", ".bin", ".gz", ".xz", ".zst", ".dtb", ".fw", ".ico", ".pdf")


def portcfg():
    import importlib.util
    spec = importlib.util.spec_from_file_location("portcfg", os.path.join(KIT, "tools", "lib", "portcfg.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def systems():
    out = []
    with open(INDEX) as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            cells = line.rstrip("\n").split("\t")
            out.append(dict(zip(FIELDS, cells + [""] * (len(FIELDS) - len(cells)))))
    return out


def similarity(system, port):
    """Score and reasons: what this system shares with the port's device."""
    score, why = 0, []
    soc, psoc = system["soc"].split(), (port.get("soc") or "").lower().split()
    if psoc and soc == psoc:
        score, why = score + 6, why + ["same SoC"]
    elif psoc and soc[0] == psoc[0]:
        score, why = score + 3, why + ["same SoC vendor"]
    for key, field, points, label in (("arch", "arch", 2, "same architecture"),
                                      ("flash_mode", "flash_mode", 2, "same flash mode"),
                                      ("bootloader", "second_stage", 3, "same second stage")):
        if port.get(key) and port[key].lower() == system[field]:
            score, why = score + points, why + [label]
    if str(port.get("android_ab")).lower() == "true" and system["android_ab"] == "yes":
        score, why = score + 2, why + ["handles Android A/B slots"]
    if system["template"] != "yes":
        score -= 100
    return score, why


def port_facts(port_dir):
    cfg = portcfg().parse(os.path.join(port_dir, "port.yaml"))
    device, path = cfg.get("device") or {}, cfg.get("path") or {}
    return {"soc": device.get("soc"), "arch": device.get("arch"), "flash_mode": device.get("flash_mode"),
            "android_ab": device.get("android_ab"), "bootloader": path.get("bootloader"),
            "reference": path.get("reference_system")}


def cmd_list(port_dir):
    port = port_facts(port_dir)
    print("device: soc=%s arch=%s flash_mode=%s second_stage=%s android_ab=%s" % (
        port["soc"] or "?", port["arch"] or "?", port["flash_mode"] or "?",
        port["bootloader"] or "?", port["android_ab"]))
    ranked = sorted(((similarity(s, port), s) for s in systems()), key=lambda r: -r[0][0])
    print("closest existing systems (set path.reference_system to one, or to none):")
    for (score, why), s in ranked:
        if s["template"] != "yes":
            continue
        print("  %2d  %s\n      %s: %s, %s, %s, %s\n      shares: %s\n      %s" % (
            score, s["repo"], s["device"], s["soc"], s["arch"], s["flash_mode"], s["second_stage"],
            ", ".join(why) or "nothing specific", s["notes"]))
    others = [s for s in systems() if s["template"] != "yes"]
    if others:
        print("to read for ideas only (outside the kit's invariants):")
        for s in others:
            print("      %s (%s): %s" % (s["repo"], s["device"], s["notes"]))
    return 0


def cmd_refresh():
    with urllib.request.urlopen(AWESOME, timeout=20) as r:
        text = r.read().decode("utf-8", "replace")
    known = {s["repo"].rstrip("/").lower() for s in systems()}
    section, missing = "", []
    for line in text.splitlines():
        if line.startswith("## "):
            section = line[3:].strip()
        m = re.match(r"\|\s*(.+?)\s*\|\s*\[[^\]]+\]\((https?://[^)]+)\)\s*\|\s*(.*?)\s*\|", line)
        if m and m.group(2).rstrip("/").lower() not in known:
            missing.append((section, m.group(1), m.group(2), m.group(3)))
    print("%d system(s) on the awesome-nerves-systems page are not in tools/lib/family.tsv:" % len(missing))
    for section, device, repo, br in missing:
        print("  [%s] %s  %s  (nerves_system_br %s)" % (section, device, repo, br))
    print("To index one: read its README, mix.exs, fwup.conf and defconfig, then add its line.")
    return 0


def camel(name):
    return "".join(part[:1].upper() + part[1:] for part in re.split(r"[_-]+", name) if part)


def cmd_scaffold(port_dir, port_id, source, name):
    port = port_facts(port_dir)
    source = source or port["reference"]
    if not source or source == "none":
        print("no reference system: set path.reference_system (see --list) or pass --from <repo>")
        return 2
    name = name or port_id.replace("-", "_")
    dest = os.path.join(port_dir, "nerves_system_" + name)
    if os.path.exists(dest):
        print("%s already exists" % dest)
        return 1
    cache = os.path.join(KIT, "cache", "family", source.rstrip("/").split("/")[-1])
    if os.path.isdir(os.path.join(cache, ".git")):
        subprocess.run(["git", "-C", cache, "pull", "-q", "--ff-only"], check=False)
    else:
        os.makedirs(os.path.dirname(cache), exist_ok=True)
        subprocess.run(["git", "clone", "-q", "--depth", "1", source, cache], check=True)
    rev = subprocess.run(["git", "-C", cache, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    shutil.copytree(cache, dest, symlinks=True,
                    ignore=shutil.ignore_patterns(".git", "_build", "deps", ".nerves", "*.fw"))
    mix = open(os.path.join(dest, "mix.exs")).read()
    old_app = re.search(r"@app\s+:(\w+)", mix) or re.search(r"app:\s+:(\w+)", mix)
    old_mod = re.search(r"defmodule\s+([\w.]+)\.MixProject", mix)
    if not old_app or not old_mod:
        print("cannot find the app atom or the module in %s/mix.exs: rename by hand" % dest)
        return 1
    old_app, old_mod = old_app.group(1), old_mod.group(1)
    old_short = old_app[len("nerves_system_"):] if old_app.startswith("nerves_system_") else old_app
    new_app, new_mod = "nerves_system_" + name, "NervesSystem" + camel(name)
    leftovers = []
    hints = re.compile(r"/dev/mmcblk\d+p\d+|\.dtb\b|define\(NERVES_FW_(PLATFORM|PRODUCT|AUTHOR)|BR2_LINUX_KERNEL_"
                       r"(CUSTOM_REPO_URL|CUSTOM_REPO_VERSION|CUSTOM_TARBALL_LOCATION|INTREE_DTS_NAME)|"
                       r"BR2_TARGET_UBOOT_(BOARD_DEFCONFIG|CUSTOM)|github_organization|" + re.escape(old_short), re.I)
    for root, _, files in os.walk(dest):
        for fname in files:
            path = os.path.join(root, fname)
            if fname.lower().endswith(TEXT_SKIP) or os.path.islink(path):
                continue
            try:
                text = open(path).read()
            except (UnicodeDecodeError, OSError):
                continue
            new = text.replace(old_app, new_app).replace(old_mod, new_mod)
            if new != text:
                open(path, "w").write(new)
            rel = os.path.relpath(path, dest)
            if rel.startswith(("patches" + os.sep, "linux-patches" + os.sep)) or fname.endswith(".patch"):
                continue
            if rel in ("README.md", "NOTICE", "CHANGELOG.md"):
                leftovers.append("%s: describes the reference device, rewrite it" % rel)
                continue
            for n, line in enumerate(new.splitlines(), 1):
                if hints.search(line) and new_app not in line:
                    leftovers.append("%s:%d: %s" % (rel, n, line.strip()[:140]))
            if old_short in fname:
                leftovers.append("%s: file name carries '%s'" % (rel, old_short))
    if os.path.isfile(os.path.join(dest, "VERSION")):
        open(os.path.join(dest, "VERSION"), "w").write("0.1.0\n")
    todo = os.path.join(port_dir, "dossier", "scaffold-todo.txt")
    os.makedirs(os.path.dirname(todo), exist_ok=True)
    with open(todo, "w") as f:
        f.write("Scaffolded from %s @ %s\n%s -> %s, %s -> %s\n\nLines that still carry the reference "
                "device (replace each with this port's facts):\n%s\n"
                % (source, rev, old_app, new_app, old_mod, new_mod, "\n".join(leftovers)))
    print("scaffolded %s from %s @ %s" % (os.path.relpath(dest, KIT), source, rev[:12]))
    print("%d line(s) still carry the reference device: %s" % (len(leftovers), os.path.relpath(todo, KIT)))
    print("device-specific directories to redo: patches/, packages/*-firmware, rootfs_overlay, the kernel defconfig")
    return 0


def main(argv):
    args = {"--port": None, "--from": None, "--name": None}
    flags, i = set(), 0
    while i < len(argv):
        if argv[i] in args and i + 1 < len(argv):
            args[argv[i]], i = argv[i + 1], i + 2
        elif argv[i] in ("--list", "--refresh"):
            flags.add(argv[i])
            i += 1
        else:
            return 2
    if "--refresh" in flags:
        return cmd_refresh()
    port_id = args["--port"]
    if not port_id:
        try:
            port_id = open(os.path.join(KIT, "ports", ".active")).read().strip()
        except OSError:
            return 2
    port_dir = os.path.join(KIT, "ports", port_id)
    if not os.path.isfile(os.path.join(port_dir, "port.yaml")):
        print("no such port: %s" % port_dir)
        return 2
    if "--list" in flags:
        return cmd_list(port_dir)
    return cmd_scaffold(port_dir, port_id, args["--from"], args["--name"])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
