#!/usr/bin/env bash
# The user's switches, for tools without a prompt hook (Codex) or typed with `!` in Claude Code.
# Run it yourself: the guard denies any agent command that mentions this tool.
# Usage:
#   tools/user-mode.sh autonomous full <goal…> [--hours N]   grant full autonomy (7 days by default)
#   tools/user-mode.sh autonomous off                         end it
#   tools/user-mode.sh override <target…> [--minutes N]       overrule a safety invariant (60 min)
#   tools/user-mode.sh override off                           end it
#   tools/user-mode.sh hands off | hands on                   freeze / resume device work
#   tools/user-mode.sh status
# Acts on the active port (ports/.active). In Claude Code the same words work typed as a prompt.
set -uo pipefail
KIT=$(cd "$(dirname "$0")/.." && pwd)
[ $# -ge 1 ] || { sed -n '2,12p' "$0"; exit 2; }
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
    goal = " ".join(args[2:]) or "the current milestone's gate"
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
else:
    sys.exit("unknown: %s (run without arguments for the usage)" % " ".join(args))
EOF
