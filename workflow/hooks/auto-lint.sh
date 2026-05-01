#!/bin/bash
# Claude Code PostToolUse hook: auto-lint files after Edit/Write
# Receives tool input as JSON on stdin.
# Runs ruff (Python) or eslint+prettier (TS) on the edited file.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

PROJECT_DIR=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")
ALIGNMINK_DIR="$PROJECT_DIR/apps/Alignmink"

# --- Python files ---
if [[ "$FILE_PATH" == *.py ]] && [[ "$FILE_PATH" == *apps/Alignmink* ]]; then
    RUFF_CMD=""
    if [ -x "$ALIGNMINK_DIR/.venv/bin/ruff" ]; then
        RUFF_CMD="$ALIGNMINK_DIR/.venv/bin/ruff"
    elif command -v ruff >/dev/null 2>&1; then
        RUFF_CMD="ruff"
    fi

    if [ -n "$RUFF_CMD" ]; then
        FIXED=$("$RUFF_CMD" check --fix --config "$ALIGNMINK_DIR/pyproject.toml" "$FILE_PATH" 2>&1 || true)
        "$RUFF_CMD" format --config "$ALIGNMINK_DIR/pyproject.toml" "$FILE_PATH" 2>/dev/null || true

        if echo "$FIXED" | grep -q "Fixed"; then
            BASENAME=$(basename "$FILE_PATH")
            echo "[auto-lint] Fixed issues in $BASENAME"
        fi
    fi
fi

# --- TypeScript/React files ---
if [[ "$FILE_PATH" == *.ts || "$FILE_PATH" == *.tsx ]] && [[ "$FILE_PATH" == *apps/Alignmink/web* ]]; then
    WEB_DIR="$ALIGNMINK_DIR/web"
    if [ -d "$WEB_DIR/node_modules" ]; then
        (cd "$WEB_DIR" && npx prettier --write "$FILE_PATH" 2>/dev/null || true)
        BASENAME=$(basename "$FILE_PATH")
        echo "[auto-lint] Formatted $BASENAME"
    fi
fi

exit 0
