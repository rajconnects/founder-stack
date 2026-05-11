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

# Normalize the join so "." / "./apps/web" / "apps/web/" all resolve to a
# canonical absolute path. Empty stays empty (branch skipped below).
norm_path() {
    local root="$1"
    [ -z "$root" ] && return 0
    python3 -c "import os,sys; print(os.path.normpath(os.path.join(sys.argv[1], sys.argv[2])))" "$PROJECT_DIR" "$root" 2>/dev/null || echo "$PROJECT_DIR/$root"
}
FRONTEND_DIR=$(norm_path "$FRONTEND_ROOT")
BACKEND_DIR=$(norm_path "$BACKEND_ROOT")

# --- Python files (under backend_root) ---
# Prefix match against normalized BACKEND_DIR — substring match was too loose
# (a "." root matched every path; an "apps/api" root matched any path
# containing that string).
if [[ "$FILE_PATH" == *.py ]] && [ -n "$BACKEND_DIR" ] && [[ "$FILE_PATH" == "$BACKEND_DIR"/* ]]; then
    RUFF_CMD=""
    if [ -x "$BACKEND_DIR/.venv/bin/ruff" ]; then
        RUFF_CMD="$BACKEND_DIR/.venv/bin/ruff"
    elif command -v ruff >/dev/null 2>&1; then
        RUFF_CMD="ruff"
    fi

    if [ -n "$RUFF_CMD" ]; then
        CONFIG_ARGS=()
        [ -f "$BACKEND_DIR/pyproject.toml" ] && CONFIG_ARGS=(--config "$BACKEND_DIR/pyproject.toml")
        # ${ARR[@]+"${ARR[@]}"} expands to nothing when the array is empty,
        # avoiding "unbound variable" under set -u with empty arrays.
        FIXED=$("$RUFF_CMD" check --fix ${CONFIG_ARGS[@]+"${CONFIG_ARGS[@]}"} "$FILE_PATH" 2>&1 || true)
        "$RUFF_CMD" format ${CONFIG_ARGS[@]+"${CONFIG_ARGS[@]}"} "$FILE_PATH" 2>/dev/null || true
        if echo "$FIXED" | grep -q "Fixed"; then
            echo "[auto-lint] Fixed issues in $(basename "$FILE_PATH")"
        fi
    fi
fi

# --- TS/TSX files (under frontend_root) ---
if [[ "$FILE_PATH" == *.ts || "$FILE_PATH" == *.tsx ]] && [ -n "$FRONTEND_DIR" ] && [[ "$FILE_PATH" == "$FRONTEND_DIR"/* ]]; then
    if [ -d "$FRONTEND_DIR/node_modules" ]; then
        if (cd "$FRONTEND_DIR" && npx --no-install prettier --write "$FILE_PATH" 2>/dev/null); then
            echo "[auto-lint] Formatted $(basename "$FILE_PATH")"
        fi
    fi
fi

exit 0
