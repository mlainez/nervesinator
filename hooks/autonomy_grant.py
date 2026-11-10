"""The full-autonomy grant of the active port: ports/<id>/.autonomy-grant (JSON).

Only the user sets it: hooks/start_trigger.py from a prompt they typed (`autonomous full <goal>`), or
tools/user-mode.sh run by them;
device_guard.py reads it and denies any agent command or file tool that touches it. While it is
valid, the guard turns its ASK decisions into ALLOW. DENY decisions never change.
"""
import json
import os
from datetime import datetime, timedelta, timezone

GRANT_NAME = ".autonomy-grant"
DEFAULT_HOURS = 168


def active_port(ports_dir):
    try:
        with open(os.path.join(ports_dir, ".active")) as f:
            return f.read().strip() or None
    except OSError:
        return None


def grant_path(ports_dir):
    port = active_port(ports_dir)
    return os.path.join(ports_dir, port, GRANT_NAME) if port else None


def write_grant(ports_dir, goal, hours, prompt):
    path = grant_path(ports_dir)
    if not path or not os.path.isdir(os.path.dirname(path)):
        return None
    now = datetime.now(timezone.utc)
    grant = {"mode": "full", "goal": goal, "granted_at": now.isoformat(timespec="seconds"),
             "expires_at": (now + timedelta(hours=hours)).isoformat(timespec="seconds"),
             "typed_by_user": prompt}
    with open(path, "w") as f:
        json.dump(grant, f, indent=2)
    return grant


def clear_grant(ports_dir):
    path = grant_path(ports_dir)
    if path and os.path.exists(path):
        os.remove(path)
        return True
    return False


def valid_grant(ports_dir):
    path = grant_path(ports_dir)
    if not path:
        return None
    try:
        with open(path) as f:
            grant = json.load(f)
        if grant.get("mode") != "full":
            return None
        if datetime.fromisoformat(grant["expires_at"]) <= datetime.now(timezone.utc):
            return None
        return grant
    except (OSError, ValueError, KeyError, TypeError):
        return None


# "hands off": the user is working on the device themselves (e.g. a write over USB mass storage).
# Only the prompt hook creates or removes the marker; while it exists the guard denies every device
# command, whatever the grant says.
HANDS_OFF_NAME = ".hands-off"


def hands_off_path(ports_dir):
    port = active_port(ports_dir)
    return os.path.join(ports_dir, port, HANDS_OFF_NAME) if port else None


def set_hands_off(ports_dir, prompt):
    path = hands_off_path(ports_dir)
    if not path or not os.path.isdir(os.path.dirname(path)):
        return False
    with open(path, "w") as f:
        json.dump({"since": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                   "typed_by_user": prompt}, f)
    return True


def clear_hands_off(ports_dir):
    path = hands_off_path(ports_dir)
    if path and os.path.exists(path):
        os.remove(path)
        return True
    return False


def hands_off_active(ports_dir):
    path = hands_off_path(ports_dir)
    return bool(path) and os.path.exists(path)


# A user override of a safety invariant: `override <target…> [for <N>m]` names what the user,
# informed of the consequences, decides to do anyway (a partition, `lock`, `repartition`…). Only the
# prompt hook or tools/user-mode.sh (run by the user) writes it. The guard then asks, with the consequences, instead of denying commands that
# name a target; it never allows them silently, even under the full-autonomy grant.
OVERRIDE_NAME = ".override"
DEFAULT_OVERRIDE_MINUTES = 60
ALLOWLIST_NAME = ".write-allowlist"
PENDING_NAME = ".pending-ask"
APPROVAL_NAME = ".approved-ask"
PROTECTED_NAMES = (GRANT_NAME, HANDS_OFF_NAME, OVERRIDE_NAME, ALLOWLIST_NAME, APPROVAL_NAME)
APPROVAL_MINUTES = 10


def override_path(ports_dir):
    port = active_port(ports_dir)
    return os.path.join(ports_dir, port, OVERRIDE_NAME) if port else None


def write_override(ports_dir, targets, minutes, prompt):
    path = override_path(ports_dir)
    if not path or not os.path.isdir(os.path.dirname(path)) or not targets:
        return None
    now = datetime.now(timezone.utc)
    override = {"targets": targets, "granted_at": now.isoformat(timespec="seconds"),
                "expires_at": (now + timedelta(minutes=minutes)).isoformat(timespec="seconds"),
                "typed_by_user": prompt}
    with open(path, "w") as f:
        json.dump(override, f, indent=2)
    return override


def clear_override(ports_dir):
    path = override_path(ports_dir)
    if path and os.path.exists(path):
        os.remove(path)
        return True
    return False


def valid_override(ports_dir):
    path = override_path(ports_dir)
    if not path:
        return None
    try:
        with open(path) as f:
            override = json.load(f)
        if datetime.fromisoformat(override["expires_at"]) <= datetime.now(timezone.utc):
            return None
        return override if override.get("targets") else None
    except (OSError, ValueError, KeyError, TypeError):
        return None


# The user's write allowlist: `allow writes <partition…> [no backup <partition…>]` names the
# partitions the port may write. Only the prompt hook (or tools/user-mode.sh) writes it. The guard
# then allows, without asking, a write to a listed partition that has a backup in
# backups/SHA256SUMS or whose loss the user accepted (`no backup`); safe-flash.sh reads the same
# file. Forbidden partitions are never listed: they need an override.
def allowlist_path(ports_dir, port=None):
    port = port or active_port(ports_dir)
    return os.path.join(ports_dir, port, ALLOWLIST_NAME) if port else None


def forbidden_names(kit_dir):
    names = set()
    try:
        with open(os.path.join(kit_dir, "tools", "lib", "forbidden-partitions.txt")) as f:
            for line in f:
                line = line.split("#", 1)[0].strip().lower()
                if line:
                    names.add(line)
    except OSError:
        pass
    return names


def slotless(name):
    name = name.lower().strip()
    return name[:-2] if name.endswith(("_a", "_b")) else name


def write_allowlist(ports_dir, partitions, no_backup, prompt, forbidden=()):
    """Returns (allowlist, refused): refused holds the forbidden names that were left out."""
    path = allowlist_path(ports_dir)
    if not path or not os.path.isdir(os.path.dirname(path)):
        return None, []
    wanted = list(dict.fromkeys(slotless(p) for p in list(partitions) + list(no_backup)))
    refused = [p for p in wanted if p in forbidden]
    kept = [p for p in wanted if p not in forbidden]
    if not kept:
        return None, refused
    allow = {"partitions": kept,
             "no_backup": [p for p in dict.fromkeys(slotless(n) for n in no_backup) if p in kept],
             "granted_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
             "typed_by_user": prompt}
    with open(path, "w") as f:
        json.dump(allow, f, indent=2)
    return allow, refused


def clear_allowlist(ports_dir):
    path = allowlist_path(ports_dir)
    if path and os.path.exists(path):
        os.remove(path)
        return True
    return False


# The user's yes without a harness hook. Where the guard runs as PATH shims (tools/with-guard.sh)
# it cannot show a prompt, so a command it would ask about is refused and recorded as pending; the
# user approves it with `tools/user-mode.sh approve`, and the next run of that exact command goes
# through, once.
def _port_file(ports_dir, name):
    port = active_port(ports_dir)
    return os.path.join(ports_dir, port, name) if port else None


def command_id(command):
    import hashlib
    return hashlib.sha256(command.encode()).hexdigest()


def record_pending(ports_dir, command, reasons):
    path = _port_file(ports_dir, PENDING_NAME)
    if not path or not os.path.isdir(os.path.dirname(path)):
        return False
    with open(path, "w") as f:
        json.dump({"id": command_id(command), "command": command, "reasons": reasons,
                   "asked_at": datetime.now(timezone.utc).isoformat(timespec="seconds")}, f, indent=2)
    return True


def read_pending(ports_dir):
    path = _port_file(ports_dir, PENDING_NAME)
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError, TypeError):
        return None


def approve_pending(ports_dir, typed):
    """The user approves the pending command; returns it, or None when nothing is pending."""
    pending, path = read_pending(ports_dir), _port_file(ports_dir, APPROVAL_NAME)
    if not pending or not path:
        return None
    expires = datetime.now(timezone.utc) + timedelta(minutes=APPROVAL_MINUTES)
    with open(path, "w") as f:
        json.dump({"id": pending["id"], "command": pending["command"],
                   "expires_at": expires.isoformat(timespec="seconds"), "typed_by_user": typed}, f, indent=2)
    os.remove(_port_file(ports_dir, PENDING_NAME))
    return pending


def consume_approval(ports_dir, command):
    """True, once, when the user approved this exact command and the approval has not expired."""
    path = _port_file(ports_dir, APPROVAL_NAME)
    try:
        with open(path) as f:
            approval = json.load(f)
        ok = approval["id"] == command_id(command) and \
            datetime.fromisoformat(approval["expires_at"]) > datetime.now(timezone.utc)
    except (OSError, ValueError, KeyError, TypeError):
        return False
    if ok:
        os.remove(path)
    return ok


def read_allowlist(ports_dir, port=None):
    path = allowlist_path(ports_dir, port)
    if not path:
        return None
    try:
        with open(path) as f:
            allow = json.load(f)
        return allow if isinstance(allow.get("partitions"), list) and allow["partitions"] else None
    except (OSError, ValueError, AttributeError):
        return None
