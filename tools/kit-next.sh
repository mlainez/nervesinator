#!/usr/bin/env bash
# Where the port stands and what comes next, derived from the evidence on disk (read-only).
# Usage: tools/kit-next.sh [--port <id>] [--json]
exec python3 -I "$(cd "$(dirname "$0")" && pwd)/lib/kit_next.py" "$@"
