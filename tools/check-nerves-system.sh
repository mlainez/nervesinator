#!/usr/bin/env bash
# Check a Nerves system against the Nerves porting guide and the kit's layout rule (boot A/B and
# rootfs A/B, never a single boot slot). Static and host-only: it reads files, builds nothing.
# Usage: tools/check-nerves-system.sh [--port <id>] [<nerves system dir>]
#   With --port (or the active port) and no directory: ports/<id>/nerves_system_*/
# Exit 0 when nothing FAILs. WARN lines are differences from the guide or the official systems to
# justify in dossier/nerves-config-review.md.
KIT=$(cd "$(dirname "$0")/.." && pwd)
PORT=""; DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT=$2; shift 2 ;;
    -*) sed -n '2,7p' "$0"; exit 2 ;;
    *) DIR=$1; shift ;;
  esac
done
if [ -z "$DIR" ]; then
  [ -n "$PORT" ] || PORT=$(cat "$KIT/ports/.active" 2>/dev/null)
  DIR=$(ls -d "$KIT/ports/$PORT"/nerves_system_*/ 2>/dev/null | head -1)
fi
[ -n "$DIR" ] && [ -d "$DIR" ] || { echo "no Nerves system directory found"; sed -n '2,7p' "$0"; exit 2; }
exec python3 -I "$KIT/tools/lib/nerves_check.py" "$DIR"
