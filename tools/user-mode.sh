#!/usr/bin/env bash
# The user's switches, for agents without a prompt hook, or typed by the user in their own shell.
# Run it yourself: the guard denies any agent command that mentions this tool.
# Usage:
#   tools/user-mode.sh autonomous full <goal…> [--hours N]   grant full autonomy (7 days by default)
#   tools/user-mode.sh autonomous off                         end it
#   tools/user-mode.sh override <target…> [--minutes N]       overrule a safety invariant (60 min)
#   tools/user-mode.sh override off                           end it
#   tools/user-mode.sh writes <partition…> [--no-backup <partition…>]
#                                                             partitions the port may write without asking
#   tools/user-mode.sh writes off                             ask for every write again
#   tools/user-mode.sh approve                                your yes to the command the guard is asking
#                                                             about (where the guard runs as PATH shims)
#   tools/user-mode.sh hands off | hands on                   freeze / resume device work
#   tools/user-mode.sh status
# Acts on the active port (ports/.active). Where a prompt hook is wired, the same words work typed
# as a prompt.
set -uo pipefail
KIT=$(cd "$(dirname "$0")/.." && pwd)
[ $# -ge 1 ] || { sed -n '2,17p' "$0"; exit 2; }
python3 -I - "$KIT" "$@" <<'EOF'
import importlib.util, json, os, sys
kit, args = sys.argv[1], sys.argv[2:]
spec = importlib.util.spec_from_file_location("g", os.path.join(kit, "hooks", "autonomy_grant.py"))
g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
ports = os.path.join(kit, "ports")
typed = "tools/user-mode.sh " + " ".join(args)
if not g.active_port(ports):
    sys.exit("no active port (ports/.active): start or resume a port first")


def option(name, default):
    if name in args:
        i = args.index(name)
        value = int(args[i + 1])
        del args[i:i + 2]
        return value
    return default


cmd = args[:2]
if cmd == ["autonomous", "full"]:
    hours = option("--hours", g.DEFAULT_HOURS)
    goal = " ".join(args[2:]) or "the next gate"
    grant = g.write_grant(ports, goal, hours, typed)
    print("full autonomy until: %s (expires %s)" % (goal, grant["expires_at"]))
elif cmd == ["autonomous", "off"]:
    print("full autonomy ended" if g.clear_grant(ports) else "no full-autonomy grant was active")
elif cmd == ["override", "off"]:
    print("override ended" if g.clear_override(ports) else "no override was active")
elif args[:1] == ["override"] and len(args) > 1:
    minutes = option("--minutes", g.DEFAULT_OVERRIDE_MINUTES)
    targets = [t.lower() for t in args[1:]]
    o = g.write_override(ports, targets, minutes, typed)
    print("override of %s until %s: each command naming them still asks you, with its consequences"
          % (", ".join(targets), o["expires_at"]))
elif cmd == ["writes", "off"]:
    print("write allowlist cleared" if g.clear_allowlist(ports) else "no write allowlist was set")
elif args[:1] == ["writes"] and len(args) > 1:
    rest, lost = args[1:], []
    if "--no-backup" in rest:
        i = rest.index("--no-backup")
        rest, lost = rest[:i], rest[i + 1:]
    allow, refused = g.write_allowlist(ports, rest, lost, typed, g.forbidden_names(kit))
    if refused:
        print("left out (forbidden list, they need an override): " + ", ".join(refused))
    if not allow:
        sys.exit("nothing was set")
    print("writes allowed without asking: %s%s" % (
        ", ".join(allow["partitions"]),
        " (no backup needed for: %s)" % ", ".join(allow["no_backup"]) if allow["no_backup"] else ""))
elif args == ["approve"]:
    done = g.approve_pending(ports, typed)
    if not done:
        sys.exit("nothing is waiting for your yes")
    print("approved, once, for %d minutes:\n  %s" % (g.APPROVAL_MINUTES, done["command"]))
elif cmd == ["hands", "off"]:
    g.set_hands_off(ports, typed)
    print("hands off: every device command is denied until `tools/user-mode.sh hands on`")
elif cmd == ["hands", "on"]:
    print("hands on" if g.clear_hands_off(ports) else "hands were not off")
elif cmd == ["status"]:
    print("port:", g.active_port(ports))
    print("full autonomy:", json.dumps(g.valid_grant(ports)) if g.valid_grant(ports) else "no")
    print("override:", json.dumps(g.valid_override(ports)) if g.valid_override(ports) else "no")
    print("hands off:", "yes" if g.hands_off_active(ports) else "no")
    print("write allowlist:", json.dumps(g.read_allowlist(ports)) if g.read_allowlist(ports) else "none")
    pending = g.read_pending(ports)
    print("waiting for your yes:", pending["command"] if pending else "nothing")
    if pending:
        print("  why: " + " ".join(pending["reasons"]) + "\n  approve with: tools/user-mode.sh approve")
else:
    sys.exit("unknown: %s (run without arguments for the usage)" % " ".join(args))
EOF
