"""The full-autonomy grant of the active port: ports/<id>/.autonomy-grant (JSON).

Only hooks/start_trigger.py writes it, from a prompt the user typed (`/autonomous full <goal>`);
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


# A user override of a safety invariant: `/override <target…> [for <N>m]` names what the user,
# informed of the consequences, decides to do anyway (a partition, `lock`, `repartition`…). Only the
# prompt hook writes it. The guard then asks, with the consequences, instead of denying commands that
# name a target; it never allows them silently, even under the full-autonomy grant.
OVERRIDE_NAME = ".override"
DEFAULT_OVERRIDE_MINUTES = 60
PROTECTED_NAMES = (GRANT_NAME, HANDS_OFF_NAME, OVERRIDE_NAME)


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
