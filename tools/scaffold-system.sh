#!/usr/bin/env bash
# Start a port's Nerves system from the closest existing one in the awesome-nerves-systems family.
# Usage:
#   tools/scaffold-system.sh [--port <id>] --list       rank the indexed systems by similarity to
#                                                       this device (SoC, arch, flash mode, second stage)
#   tools/scaffold-system.sh [--port <id>] [--from <repo URL>] [--name <name>]
#                                                       copy the reference (path.reference_system, or
#                                                       --from) into ports/<id>/nerves_system_<name>/,
#                                                       rename it, and list what still carries the
#                                                       reference device in dossier/scaffold-todo.txt
#   tools/scaffold-system.sh --refresh                  systems on the awesome-nerves-systems page
#                                                       that tools/lib/family.tsv does not index yet
# Host-only. The reference is cloned (shallow) into cache/family/.
[ $# -ge 1 ] || { sed -n '2,13p' "$0"; exit 2; }
python3 -I "$(cd "$(dirname "$0")" && pwd)/lib/family.py" "$@"; rc=$?
[ $rc = 2 ] && sed -n '2,13p' "$0"
exit $rc
