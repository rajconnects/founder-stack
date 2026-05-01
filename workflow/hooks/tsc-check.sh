#!/bin/bash
# Claude Code PostToolUse hook: TypeScript type check after Edit/Write of .ts/.tsx
# Non-blocking — prints warnings, always exits 0.
# Reads .claude/project.json for stack.frontend_root.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || echo "")
PROJECT_DIR=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")

# Only .ts / .tsx files, and only if the file still exists
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then exit 0; fi
case "$FILE_PATH" in
    *.ts|*.tsx) ;;
    *) exit 0 ;;
esac

# Resolve frontend root from project.json
CONFIG="$PROJECT_DIR/.claude/project.json"
if [ ! -f "$CONFIG" ]; then exit 0; fi

FRONTEND_ROOT=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('stack',{}).get('frontend_root',''))" 2>/dev/null || echo "")
if [ -z "$FRONTEND_ROOT" ]; then exit 0; fi

FRONTEND_DIR="$PROJECT_DIR/$FRONTEND_ROOT"

# Only run if the edited file is under the frontend root
case "$FILE_PATH" in
    "$FRONTEND_DIR"/*) ;;
    *) exit 0 ;;
esac

# Only run if tsconfig and node_modules exist
if [ ! -f "$FRONTEND_DIR/tsconfig.json" ] || [ ! -d "$FRONTEND_DIR/node_modules" ]; then exit 0; fi

# Run type check with a short timeout — warn-only, never block
OUTPUT=$(cd "$FRONTEND_DIR" && timeout 10 npx --no-install tsc --noEmit --pretty false 2>&1 || true)
ERRORS=$(echo "$OUTPUT" | grep -E "^.*\.tsx?\([0-9]+,[0-9]+\): error" | head -5 || true)

if [ -n "$ERRORS" ]; then
    COUNT=$(echo "$OUTPUT" | grep -cE "^.*\.tsx?\([0-9]+,[0-9]+\): error" || echo 0)
    echo "[tsc-check] $COUNT type error(s). First 5:"
    echo "$ERRORS" | sed 's/^/  /'
fi

exit 0
