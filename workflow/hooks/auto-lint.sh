#!/bin/bash
# Claude Code PostToolUse hook: auto-lint files after Edit/Write.
# Reads .claude/project.json for stack roots; runs available linters.
# Soft: never blocks. Silently exits 0 if tools or config are missing.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || echo "")
PROJECT_DIR=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

CONFIG="$PROJECT_DIR/.claude/project.json"
[ -f "$CONFIG" ] || exit 0

# Resolve stack roots from project.json (null/missing → empty string)
FRONTEND_ROOT=$(python3 -c "import json; v=json.load(open('$CONFIG')).get('stack',{}).get('frontend_root'); print(v or '')" 2>/dev/null || echo "")
BACKEND_ROOT=$(python3 -c "import json; v=json.load(open('$CONFIG')).get('stack',{}).get('backend_root'); print(v or '')" 2>/dev/null || echo "")

# --- Python files (under backend_root) ---
if [[ "$FILE_PATH" == *.py ]] && [ -n "$BACKEND_ROOT" ] && [[ "$FILE_PATH" == *"$BACKEND_ROOT"* ]]; then
    BACKEND_DIR="$PROJECT_DIR/$BACKEND_ROOT"
    RUFF_CMD=""
    if [ -x "$BACKEND_DIR/.venv/bin/ruff" ]; then
        RUFF_CMD="$BACKEND_DIR/.venv/bin/ruff"
    elif command -v ruff >/dev/null 2>&1; then
        RUFF_CMD="ruff"
    fi

    if [ -n "$RUFF_CMD" ]; then
        CONFIG_ARGS=()
        [ -f "$BACKEND_DIR/pyproject.toml" ] && CONFIG_ARGS=(--config "$BACKEND_DIR/pyproject.toml")
        FIXED=$("$RUFF_CMD" check --fix "${CONFIG_ARGS[@]}" "$FILE_PATH" 2>&1 || true)
        "$RUFF_CMD" format "${CONFIG_ARGS[@]}" "$FILE_PATH" 2>/dev/null || true
        if echo "$FIXED" | grep -q "Fixed"; then
            echo "[auto-lint] Fixed issues in $(basename "$FILE_PATH")"
        fi
    fi
fi

# --- TS/TSX files (under frontend_root) ---
if [[ "$FILE_PATH" == *.ts || "$FILE_PATH" == *.tsx ]] && [ -n "$FRONTEND_ROOT" ] && [[ "$FILE_PATH" == *"$FRONTEND_ROOT"* ]]; then
    FRONTEND_DIR="$PROJECT_DIR/$FRONTEND_ROOT"
    if [ -d "$FRONTEND_DIR/node_modules" ]; then
        if (cd "$FRONTEND_DIR" && npx --no-install prettier --write "$FILE_PATH" 2>/dev/null); then
            echo "[auto-lint] Formatted $(basename "$FILE_PATH")"
        fi
    fi
fi

exit 0
