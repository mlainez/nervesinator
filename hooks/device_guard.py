#!/usr/bin/env python3
"""Guard for shell commands that can modify a phone (or the host's disks).

Usage:
  As a Claude Code PreToolUse hook: reads the hook JSON on stdin (wired in .claude/settings.json).
  Standalone, for any other agent tool or a human:
      device_guard.py --check "<shell command>"
  prints ALLOW / ASK / DENY with the reasons; exit code 0, 1 (ask) or 2 (deny).

Decisions:
  deny  - can hard-brick or destroy irreplaceable data (bootloader chain, calibration,
          partition tables, relocking), or writes raw devices on the host.
  ask   - modifies the device but can be undone with a backup (flash boot/recovery/userdata,
          unlock, wipe); forces a human confirmation.
  (none)- everything else; normal permission rules apply.

A full-autonomy grant (hooks/autonomy_grant.py), created only from the user's own typed
`/autonomous full <goal>`, turns ask into allow for the active port until it is revoked or expires.
Agents can never create or edit that grant: any command or file tool touching it is denied.

This is a seatbelt, not a sandbox: it parses commands heuristically. The agents are instructed
never to work around it.
"""
import json
import os
import re
import shlex
import sys
import importlib.util
from datetime import datetime, timezone

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
FORBIDDEN_FILE = os.path.join(PROJECT_DIR, "tools", "lib", "forbidden-partitions.txt")
PORTS_DIR = os.path.join(PROJECT_DIR, "ports")

# python3 -I leaves the script directory off sys.path: load the sibling module by path
_spec = importlib.util.spec_from_file_location(
    "autonomy_grant", os.path.join(os.path.dirname(os.path.realpath(__file__)), "autonomy_grant.py"))
autonomy_grant = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(autonomy_grant)
FILE_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}

DENY, ASK = 2, 1


def load_forbidden():
    names = set()
    try:
        with open(FORBIDDEN_FILE) as f:
            for line in f:
                line = line.split("#", 1)[0].strip().lower()
                if line:
                    names.add(line)
    except OSError:
        pass
    return names


FORBIDDEN = load_forbidden()


def norm_part(name):
    name = name.lower().strip()
    name = re.sub(r"^format(:[a-z0-9]+)*$", "", name)
    name = re.sub(r"_(a|b)$", "", name)
    return name


def is_forbidden(name):
    n = norm_part(name)
    return n in FORBIDDEN or n.lstrip("-") in FORBIDDEN


class Verdict:
    def __init__(self):
        self.level = 0
        self.reasons = []

    def add(self, level, reason):
        self.level = max(self.level, level)
        self.reasons.append(reason)


SPLIT_RE = re.compile(r"\|\||&&|;|\||\n")
WRAPPERS = {"sudo", "doas", "env", "nice", "nohup", "time", "command", "exec", "stdbuf", "ionice"}


def tokens_of(segment):
    try:
        toks = shlex.split(segment, posix=True)
    except ValueError:
        toks = segment.split()
    # drop leading VAR=value assignments and wrappers (with their simple options)
    i = 0
    while i < len(toks):
        t = toks[i]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
            i += 1
        elif os.path.basename(t) in WRAPPERS:
            i += 1
            while i < len(toks) and toks[i].startswith("-"):
                i += 1
        elif os.path.basename(t) == "timeout":
            i += 1
            while i < len(toks) and (toks[i].startswith("-") or re.match(r"^\d+[smhd]?$", toks[i])):
                i += 1
        else:
            break
    return toks[i:]


def oem_base(what):
    """An oem command without U-Boot's `board:` prefix (its hook for board-specific commands)."""
    return what[len("board:"):] if what.startswith("board:") else what


def check_fastboot(args, v):
    serial = False
    rest = []
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("-s", "-S", "--slot", "-c", "--cmdline", "--base", "--kernel-offset",
                 "--ramdisk-offset", "--tags-offset", "--dtb-offset", "--page-size",
                 "--header-version", "--os-version", "--os-patch-level", "--dtb"):
            if a == "-s":
                serial = True
            i += 2
            continue
        if a.startswith("-s") and len(a) > 2:
            serial = True
        elif a == "-w":
            v.add(ASK, "fastboot -w wipes userdata and cache.")
        elif not a.startswith("-"):
            rest.append(a)
        i += 1
    if not rest:
        return
    sub = rest[0].lower()
    params = [p.lower() for p in rest[1:]]
    writes = {"flash", "erase", "format", "flash:raw"} | {s for s in [sub] if s.startswith("format:")}
    if sub in writes:
        part = params[0] if params else ""
        if sub == "flash:raw":
            part = params[0] if params else ""
        if not part:
            v.add(DENY, "fastboot %s without a partition name." % sub)
        elif is_forbidden(part):
            v.add(DENY, "Partition '%s' is on the forbidden list (bootloader chain, calibration "
                        "or per-device data). Writing it can hard-brick the device." % part)
        else:
            v.add(ASK, "fastboot %s %s modifies the device. Check: verified backup of '%s' exists "
                       "and it is in safety.writable_partitions." % (sub, part, part))
        if not serial:
            v.add(DENY, "Device writes must address the device by serial: add `-s <serial>`.")
    elif sub in ("flashall", "update"):
        v.add(DENY, "fastboot %s writes every partition including the bootloader." % sub)
    elif sub == "wipe-super":
        v.add(DENY, "fastboot wipe-super rewrites the dynamic partition metadata.")
    elif sub in ("create-logical-partition", "delete-logical-partition",
                 "resize-logical-partition", "set_active"):
        v.add(ASK, "fastboot %s changes the partition layout or active slot." % sub)
    elif sub in ("flashing", "oem"):
        what = params[0] if params else ""
        if what in ("lock", "lock_critical", "relock"):
            v.add(DENY, "Relocking the bootloader with non-stock software installed can hard-brick "
                        "the device. Only the user may do this, after restoring stock.")
        elif what == "unlock_critical":
            v.add(DENY, "unlock_critical allows writing bootloader partitions; the kit never needs it.")
        elif what in ("unlock", "unlock-go") or (sub == "oem" and what.startswith("unlock")):
            v.add(ASK, "Unlocking the bootloader WIPES ALL USER DATA and may be irreversible "
                       "(warranty bits, DRM keys). Confirm the pre-unlock checklist is done.")
        elif what in ("edl", "reboot-edl"):
            v.add(ASK, "Rebooting to EDL (emergency download mode).")
        elif sub == "oem" and (oem_base(what) == "run" or oem_base(what).startswith("run:")):
            v.add(DENY, "fastboot oem run executes arbitrary bootloader commands and bypasses the "
                        "partition allowlist; a kit second stage never offers it.")
        elif sub == "oem" and oem_base(what) not in ("device-info", "log", "lk_log", "get_unlock_data",
                                                     "get_identifier_token", "help", "screenshot",
                                                     "console", "ums"):
            v.add(ASK, "Unknown fastboot oem command '%s': vendor oem commands can change settings." % what)
        elif sub == "flashing" and what not in ("get_unlock_ability",):
            v.add(ASK, "fastboot flashing %s" % what)
    elif sub == "reboot" and params and params[0] in ("edl",):
        v.add(ASK, "Rebooting to EDL (emergency download mode).")
    elif sub == "boot" and not serial:
        v.add(DENY, "Address the device by serial: add `-s <serial>`.")


HEIMDALL_FLAGS = {"--no-reboot", "--resume", "--wait", "--verbose", "--stdout-errors",
                  "--usb-log-level", "--tflash", "--skip-size-check", "--help"}


def check_heimdall(args, v):
    if not args:
        return
    sub = args[0].lower()
    if sub != "flash":
        return
    if any(a.lower() in ("--repartition", "--pit") for a in args[1:]):
        v.add(DENY, "heimdall --repartition/--pit rewrites the partition table (PIT): hard-brick risk.")
    parts = [a for a in args[1:] if a.startswith("--") and a.lower() not in HEIMDALL_FLAGS]
    for p in parts:
        name = p[2:]
        if re.match(r"^\d+$", name):
            v.add(DENY, "heimdall flash by partition index is not allowed; use the name.")
        elif is_forbidden(name):
            v.add(DENY, "Partition '%s' is on the forbidden list." % name)
        else:
            v.add(ASK, "heimdall flash %s modifies the device (no RAM boot on Samsung download mode). "
                       "Check the backup and the escape route." % name)
    if not parts:
        v.add(ASK, "heimdall flash")


def check_odin(args, v):
    flags = [a for a in args if a.startswith("-")]
    if "-b" in flags or "-c" in flags:
        v.add(DENY, "Odin BL/CP packages write the bootloader or modem.")
    else:
        v.add(ASK, "Odin flashing modifies the device; CSC (non-HOME) also wipes it.")


EDL_DENY = {"w", "wl", "wf", "ws", "e", "es", "ep", "qfp", "xml", "rawxml", "poke", "memwrite",
            "setbootablestoragedrive", "setactiveslot", "gpt"}
EDL_READ = {"r", "rl", "rf", "rs", "printgpt", "peek", "getstorageinfo", "secureboot", "pbl",
            "qfil-read", "footer", "reset", "nop", "getactiveslot"}


def check_edl(prog, args, v):
    subs = [a for a in args if not a.startswith("-")]
    sub = subs[0].lower() if subs else ""
    if prog in ("mtk", "mtk.py") and sub == "da":
        rest = [s.lower() for s in subs[1:]]
        if rest[:2] == ["seccfg", "unlock"]:
            v.add(ASK, "mtkclient seccfg unlock: unlocks the bootloader and wipes data.")
        elif rest[:1] == ["seccfg"]:
            v.add(DENY, "mtkclient seccfg lock/other: relocking can brick.")
        else:
            v.add(ASK, "mtkclient da %s" % " ".join(rest))
        return
    if sub in EDL_DENY:
        v.add(DENY, "%s %s writes raw storage in EDL/BROM mode: hard-brick risk. If truly needed for "
                    "unbricking, the user runs it themselves." % (prog, sub))
    elif sub in EDL_READ:
        return
    elif sub:
        v.add(ASK, "%s %s: unknown low-level command." % (prog, sub))


BLOCK_TARGET_RE = re.compile(
    r"(?:\bof=|>\s*|adb\s+push\s+\S+\s+)(/dev/(?:block/)?[^\s'\";|&)]+)")


def classify_block_target(path, v, remote):
    p = path.rstrip("/")
    base = os.path.basename(p)
    if not remote:
        if re.match(r"^/dev/(sd[a-z]|nvme|hd[a-z]|vd[a-z]|mmcblk|disk|md|dm-|mapper/|loop)", p):
            v.add(DENY, "Writing %s on the host could destroy your own disks. If intended, run "
                        "it yourself with the `!` prefix." % p)
        return
    if "/by-name/" in p:
        if is_forbidden(base):
            v.add(DENY, "Block write to forbidden partition '%s'." % base)
        else:
            v.add(ASK, "Raw write to device partition '%s'. Check backup + allowlist." % base)
        return
    if re.match(r"^mmcblk\d+boot\d+$", base) or base.endswith("rpmb"):
        v.add(DENY, "%s holds the boot ROM's first-stage loader (or RPMB). Never written." % p)
    elif re.match(r"^(mmcblk\d+|sd[a-z])$", base):
        v.add(DENY, "Writing the whole disk %s overwrites the partition table and bootloaders." % p)
    elif base in ("null", "zero", "tty", "console", "kmsg", "fb0") or base.startswith(("tty", "pts")):
        return
    else:
        v.add(ASK, "Raw write to %s on the device. Make sure this pN is mapped to an allowlisted "
                   "partition name (dossier/partitions-linux.md) and backed up." % p)


REMOTE_RE = re.compile(r"\badb\b.*\b(shell|exec-out|exec-in|push)\b|\bssh\b|\btelnet\b")
REMOTE_DENY_RE = re.compile(
    r"\b(sgdisk|sfdisk|gdisk|fdisk|parted|blkdiscard|flash_erase|mtd_debug|nandwrite)\b"
    r"|force_ro|\bmmc\s+(write|erase|bootpart|rpmb|writeprotect|hwreset)")
REMOTE_ASK_RE = re.compile(r"\b(mkfs(\.\w+)?|mke2fs|mkfs\.f2fs|resize2fs|wipefs|tune2fs)\b")


def check_fwup(args, v):
    """fwup applying to a host block device (a phone in USB mass storage mode, or the wrong disk)."""
    if not any(a in ("-a", "--apply") for a in args):
        return
    target = None
    for i, a in enumerate(args):
        if a in ("-d", "--device") and i + 1 < len(args):
            target = args[i + 1]
        elif a.startswith("--device="):
            target = a.split("=", 1)[1]
    # A computed target ($(...), `...`, $VAR) can be any disk: treat it like /dev/
    if target is None or target.startswith("/dev/") or any(c in target for c in "$`"):
        v.add(ASK, "fwup writes a raw host block device (%s): check it is the phone's USB disk "
                   "(tools/ums-target.sh), not one of this computer's disks."
              % (target or "auto-detected"))


def safe_flash_op(args):
    """The operation of a safe-flash.sh command line (its first non-option word)."""
    i = 0
    while i < len(args):
        if args[i] in ("--port", "--mode"):
            i += 2
        elif args[i].startswith("-"):
            i += 1
        else:
            return args[i]
    return ""


HEREDOC_RE = re.compile(r"^(?P<head>.*?)<<-?\s*(?P<q>['\"]?)(?P<tag>[A-Za-z_][A-Za-z0-9_]*)(?P=q)(?P<tail>.*)$")


def writes_heredoc_to_file(head, tail):
    """True for `cat > f <<EOF` / `tee f <<EOF`: the body is text for a file, never run."""
    last = SPLIT_RE.split(head)[-1]
    toks = tokens_of(last.strip())
    if not toks or os.path.basename(toks[0]) not in ("cat", "tee") or "|" in tail:
        return False
    return os.path.basename(toks[0]) == "tee" or ">" in last + tail


def strip_file_heredocs(cmd):
    lines, out, i = cmd.split("\n"), [], 0
    while i < len(lines):
        m = HEREDOC_RE.match(lines[i])
        if m and writes_heredoc_to_file(m.group("head"), m.group("tail")):
            end = next((j for j in range(i + 1, len(lines)) if lines[j].strip("\t") == m.group("tag")), None)
            if end is not None:
                out += [lines[i], lines[end]]
                i = end + 1
                continue
        out.append(lines[i])
        i += 1
    return "\n".join(out)


def analyse(cmd, v, depth=0):
    if depth > 3:
        return
    if depth == 0:
        if autonomy_grant.GRANT_NAME in cmd:
            v.add(DENY, "The autonomy grant is created only by the user typing /autonomous full.")
        cmd = strip_file_heredocs(cmd)
    remote_whole = bool(REMOTE_RE.search(cmd))
    if remote_whole:
        if REMOTE_DENY_RE.search(cmd):
            v.add(DENY, "Repartitioning, discarding or unlocking eMMC boot areas on the device is "
                        "not allowed (risk-red).")
        if REMOTE_ASK_RE.search(cmd):
            v.add(ASK, "Formatting a filesystem on the device. Check the target is allowlisted.")
        if re.search(r"\breboot\s+edl\b", cmd):
            v.add(ASK, "Rebooting to EDL (emergency download mode).")
        if re.search(r"\badb\b.*\bsideload\b", cmd):
            v.add(ASK, "adb sideload installs a package on the device.")
    for m in BLOCK_TARGET_RE.finditer(cmd):
        classify_block_target(m.group(1), v, remote_whole)

    for seg in SPLIT_RE.split(cmd):
        toks = tokens_of(seg.strip())
        if not toks:
            continue
        prog = os.path.basename(toks[0])
        args = toks[1:]
        if prog in ("bash", "sh", "zsh", "dash") and "-c" in args:
            idx = args.index("-c")
            if idx + 1 < len(args):
                analyse(args[idx + 1], v, depth + 1)
        elif prog == "eval":
            analyse(" ".join(args), v, depth + 1)
        elif prog == "fastboot":
            check_fastboot(args, v)
        elif prog == "heimdall":
            check_heimdall(args, v)
        elif prog in ("odin4", "odin"):
            check_odin(args, v)
        elif prog in ("edl", "edl.py", "mtk", "mtk.py", "mtkclient"):
            check_edl(prog, args, v)
        elif prog == "fwup":
            check_fwup(args, v)
        elif prog == "mix" and args[:1] == ["burn"]:
            v.add(ASK, "mix burn writes a raw host block device: check it is the phone's USB disk "
                       "(tools/ums-target.sh), not one of this computer's disks.")
        elif prog == "safe-flash.sh":
            # "boot" is a RAM-only fastboot boot, allowed like a plain `fastboot boot`;
            # every other operation writes to the device
            if "--execute" in args and safe_flash_op(args) != "boot":
                v.add(ASK, "safe-flash.sh --execute will write to the device: " + " ".join(args))
        elif prog == "await-boot.sh":
            pass  # runs only `safe-flash.sh --execute boot` (RAM) and read-only USB/fastboot/adb probes

    if re.search(r"base64\s+(-d|--decode)[^|]*\|\s*(ba|z|da)?sh\b", cmd) and \
            re.search(r"fastboot|heimdall|edl|mtk|dd\b", cmd):
        v.add(DENY, "Obfuscated device command. Run device commands in plain form.")


def log(decision, cmd, reasons):
    try:
        path = os.path.join(PROJECT_DIR, "ports", "guard.log")
        if not os.path.isdir(os.path.dirname(path)):
            return
        with open(path, "a") as f:
            f.write("%s %s %s | %s\n" % (datetime.now(timezone.utc).isoformat(timespec="seconds"),
                                         decision, cmd.replace("\n", " ")[:300], "; ".join(reasons)))
    except OSError:
        pass


def apply_grant(v, ports_dir):
    """ASK becomes ALLOW under a valid full-autonomy grant; returns the grant used, if any."""
    if v.level != ASK:
        return None
    grant = autonomy_grant.valid_grant(ports_dir)
    if grant:
        v.level = 0
        v.reasons.append("allowed by the full-autonomy grant (goal: %s, until %s)"
                         % (grant.get("goal") or "?", grant.get("expires_at")))
    return grant


def check_cli(cmd, ports_dir=PORTS_DIR):
    v = Verdict()
    analyse(cmd, v)
    if apply_grant(v, ports_dir):
        log("allow-autonomy", cmd, v.reasons)
    label = {0: "ALLOW", ASK: "ASK", DENY: "DENY"}[v.level]
    print(label + ("" if not v.reasons else ": " + " ".join(dict.fromkeys(v.reasons))))
    if v.level:
        log(label.lower(), cmd, v.reasons)
    return v.level


def main():
    if len(sys.argv) >= 5 and sys.argv[1] == "--ports" and sys.argv[3] == "--check":
        return check_cli(" ".join(sys.argv[4:]), sys.argv[2])
    if len(sys.argv) >= 3 and sys.argv[1] == "--check":
        return check_cli(" ".join(sys.argv[2:]))
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 0
    if data.get("tool_name") in FILE_TOOLS:
        path = (data.get("tool_input") or {}).get("file_path") or \
            (data.get("tool_input") or {}).get("notebook_path") or ""
        if os.path.basename(path) == autonomy_grant.GRANT_NAME:
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse", "permissionDecision": "deny",
                "permissionDecisionReason": "[device-guard] The autonomy grant is created only by "
                                            "the user typing /autonomous full."}}))
        return 0
    if data.get("tool_name") != "Bash":
        return 0
    cmd = (data.get("tool_input") or {}).get("command") or ""
    v = Verdict()
    try:
        analyse(cmd, v)
    except Exception as exc:  # never let a parser bug silently allow a device write
        if re.search(r"fastboot|heimdall|odin|edl|mtk|\bdd\b|/dev/block", cmd):
            v.add(ASK, "device_guard could not parse this command (%s); confirm manually." % exc)
    if apply_grant(v, PORTS_DIR):
        log("allow-autonomy", cmd, v.reasons)
    if v.level == 0:
        return 0
    decision = "deny" if v.level == DENY else "ask"
    reason = "[device-guard] " + " ".join(dict.fromkeys(v.reasons))
    if decision == "deny":
        reason += " See the device-safety skill. Do not work around this check."
    log(decision, cmd, v.reasons)
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": reason}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
