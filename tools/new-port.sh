#!/usr/bin/env bash
# Create the workspace for a new port: ports/<id>/ as a git repo with port.yaml and its folders,
# plus an empty Backlog.md project for discovered work when the backlog CLI is installed.
# Usage: tools/new-port.sh <id> <serial>      e.g. tools/new-port.sh fairphone-fp2 0123abcd
set -euo pipefail
KIT=$(cd "$(dirname "$0")/.." && pwd)
ID=${1:?usage: new-port.sh <id> <serial>}; SER=${2:?usage: new-port.sh <id> <serial>}
[[ "$ID" =~ ^[a-z0-9]+(-[a-z0-9_]+)+$ ]] || { echo "id must look like <vendor>-<codename> (lowercase)"; exit 1; }
P="$KIT/ports/$ID"
[ -e "$P" ] && { echo "ports/$ID already exists: resume it instead"; exit 1; }
# A Claude Code adapter that lost its links or its hook wiring also lost the guard
if [ -d "$KIT/.claude" ] || [ -n "${CLAUDECODE:-}" ]; then
  for l in agents skills; do
    [ "$(cd "$KIT/.claude/$l" 2>/dev/null && pwd -P)" = "$(cd "$KIT/$l" && pwd -P)" ] || \
      { echo ".claude/$l is broken: run tools/check-host.sh and apply its fix first"; exit 1; }
  done
  grep -q device_guard.py "$KIT/.claude/settings.json" 2>/dev/null || \
    { echo ".claude/settings.json does not run the guard: run tools/check-host.sh and apply its fix first"; exit 1; }
fi

mkdir -p "$P"/{dossier/raw,backups/stock,journal/lessons,journal/plans,journal/photos,output}
sed -e "s/@ID@/$ID/" -e "s/@SERIAL@/$SER/" -e "s/@DATE@/$(date +%F)/" "$KIT/templates/port.yaml" > "$P/port.yaml"
cp "$KIT/templates/port-gitignore" "$P/.gitignore"
cat > "$P/journal/sessions.md" <<EOT
# Session journal: $ID

## $(date +%F)
- Port created for device serial $SER.
- Next: tools/kit-next.sh
EOT
cat > "$P/README.md" <<EOT
# Port: $ID

Created with the Nerves porting kit. State: \`port.yaml\`; next step: \`tools/kit-next.sh\` (from the kit).
Facts: \`dossier/\`. Discovered work: \`backlog board\` (run here). Backups (not in git): \`backups/\`.
EOT

cd "$P"
git init -q
if command -v backlog >/dev/null; then
  backlog init "$ID" --defaults --integration-mode none --task-prefix port >/dev/null
  CFG=backlog/config.yml; [ -f "$CFG" ] || CFG=backlog.config.yml
  sed -i 's/^statuses: .*/statuses: ["To Do", "In Progress", "Needs User", "Blocked", "Done"]/' "$CFG"
  backlog config set remoteOperations false >/dev/null
  backlog config set checkActiveBranches false >/dev/null
  backlog config set autoOpenBrowser false >/dev/null
else
  echo "note: backlog CLI not installed (npm i -g backlog.md): discovered work has nowhere to go yet"
fi

echo "$ID" > "$KIT/ports/.active"
git add -A && git commit -q -m "Create port workspace for $ID" && echo "committed initial workspace"
echo "port ready: ports/$ID (active)"
