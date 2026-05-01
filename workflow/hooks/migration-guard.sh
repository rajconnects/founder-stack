#!/bin/bash
# Claude Code PreToolUse hook: warn when editing a migration file without having run /schema-gate this session.
# Non-blocking — prints a soft warning, always exits 0.
# Reads .claude/project.json for migrations path.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || echo "")
PROJECT_DIR=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ]; then exit 0; fi

# Resolve migrations path from project.json
CONFIG="$PROJECT_DIR/.claude/project.json"
if [ ! -f "$CONFIG" ]; then exit 0; fi

MIGRATIONS=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('migrations',''))" 2>/dev/null || echo "")
if [ -z "$MIGRATIONS" ]; then exit 0; fi

MIGRATIONS_DIR="$PROJECT_DIR/$MIGRATIONS"

# Only fire if the file is under migrations dir
case "$FILE_PATH" in
    "$MIGRATIONS_DIR"*|"$MIGRATIONS"*) ;;
    *) exit 0 ;;
esac

# Check for the session marker indicating /schema-gate has passed
MARKER="$PROJECT_DIR/.claude/.schema-gate-passed"
if [ -f "$MARKER" ]; then
    exit 0
fi

echo "[migration-guard] You're editing a migration file but /schema-gate has not passed this session."
echo "[migration-guard]   Run: /schema-gate <this migration> before applying it."
exit 0
