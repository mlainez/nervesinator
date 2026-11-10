#!/usr/bin/env bash
# Commit the active port's workspace when it changed (what the Stop hook does where one is wired).
# Usage: tools/checkpoint.sh
exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/hooks/checkpoint.py"
