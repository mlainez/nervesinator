#!/usr/bin/env bash
# Create the workspace for a new port: ports/<id>/ as a git repo with port.yaml, folders and a
# seeded Backlog.md project (milestones M0-M12 and their tasks).
# Usage: tools/new-port.sh <id> <serial>      e.g. tools/new-port.sh fairphone-fp2 0123abcd
set -euo pipefail
KIT=$(cd "$(dirname "$0")/.." && pwd)
ID=${1:?usage: new-port.sh <id> <serial>}; SER=${2:?usage: new-port.sh <id> <serial>}
[[ "$ID" =~ ^[a-z0-9]+(-[a-z0-9_]+)+$ ]] || { echo "id must look like <vendor>-<codename> (lowercase)"; exit 1; }
P="$KIT/ports/$ID"
[ -e "$P" ] && { echo "ports/$ID already exists: resume it instead"; exit 1; }
command -v backlog >/dev/null || { echo "backlog CLI missing: npm i -g backlog.md (or bun add -g backlog.md)"; exit 1; }

mkdir -p "$P"/{dossier/raw,backups/stock,journal/lessons,journal/plans,journal/photos,output}
sed -e "s/@ID@/$ID/" -e "s/@SERIAL@/$SER/" -e "s/@DATE@/$(date +%F)/" "$KIT/templates/port.yaml" > "$P/port.yaml"
cp "$KIT/templates/port-gitignore" "$P/.gitignore"
cat > "$P/journal/sessions.md" <<EOT
# Session journal: $ID

## $(date +%F)
- Port created for device serial $SER.
- Next: M0 tasks (host check, learner profile, safety briefing).
EOT
cat > "$P/README.md" <<EOT
# Port: $ID

Created with the Nerves porting kit. State: \`port.yaml\`. Tasks: \`backlog board\` (run here).
Facts: \`dossier/\`. Lessons: \`journal/lessons/\`. Backups (not in git): \`backups/\`.
EOT

cd "$P"
git init -q
backlog init "$ID" --defaults --integration-mode none --task-prefix port >/dev/null
CFG=backlog/config.yml; [ -f "$CFG" ] || CFG=backlog.config.yml
sed -i 's/^statuses: .*/statuses: ["To Do", "In Progress", "Needs User", "Blocked", "Done"]/' "$CFG"
backlog config set remoteOperations false >/dev/null
backlog config set checkActiveBranches false >/dev/null
backlog config set autoOpenBrowser false >/dev/null
python3 -I "$KIT/tools/lib/seed_backlog.py" "$P" "$KIT/templates/backlog-seed.json"

echo "$ID" > "$KIT/ports/.active"
git add -A && git commit -q -m "Create port workspace for $ID" && echo "committed initial workspace"
echo "port ready: ports/$ID (active)"
