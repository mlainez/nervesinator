#!/usr/bin/env bash
# Bring an existing port's workspace up to the kit's current templates, without touching its work.
# Usage: tools/update-port.sh --port <id>
#
# Today: appends the lines of templates/port-gitignore that ports/<id>/.gitignore lacks, then stops
# tracking files the updated rules ignore (git rm --cached: the files stay on disk). New port.yaml
# fields and backlog tasks are not added: compare with templates/ and add what the port needs.
set -uo pipefail
KIT=$(cd "$(dirname "$0")/.." && pwd)
[ "${1:-}" = --port ] && [ -n "${2:-}" ] || { sed -n '2,7p' "$0"; exit 2; }
P="$KIT/ports/$2"
[ -d "$P" ] || { echo "no such port: $P"; exit 2; }

added=0
touch "$P/.gitignore"
while IFS= read -r line; do
  [ -z "$line" ] && continue
  grep -qxF -- "$line" "$P/.gitignore" && continue
  echo "$line" >> "$P/.gitignore"
  case "$line" in \#*) ;; *) echo "  + $line"; added=$((added + 1)) ;; esac
done < "$KIT/templates/port-gitignore"
echo "$added ignore rule(s) added to ports/$2/.gitignore"

if git -C "$P" rev-parse --git-dir >/dev/null 2>&1; then
  tracked=$(git -C "$P" ls-files -ci --exclude-standard)
  if [ -n "$tracked" ]; then
    echo "$tracked" | while IFS= read -r f; do git -C "$P" rm -q --cached -- "$f" && echo "  untracked (kept on disk): $f"; done
    echo "commit in ports/$2 to record it"
  fi
fi
