#!/bin/bash
# Claude Code PreToolUse hook: quality gate before git commit/push
# Receives tool input as JSON on stdin.
# Blocks the command (exit 2) if quality checks fail.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
PROJECT_DIR=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")

ALIGNMINK_DIR="$PROJECT_DIR/apps/Alignmink"
ERRORS=0

# Determine ruff command
RUFF_CMD=""
if [ -x "$ALIGNMINK_DIR/.venv/bin/ruff" ]; then
    RUFF_CMD="$ALIGNMINK_DIR/.venv/bin/ruff"
elif command -v ruff >/dev/null 2>&1; then
    RUFF_CMD="ruff"
fi

# --- git commit: lint + format check ---
if echo "$COMMAND" | grep -qE '^git commit'; then
    echo "[quality-gate] Running pre-commit checks..."

    if [ -n "$RUFF_CMD" ]; then
        # Run from within the directory so per-file-ignores match correctly
        if ! (cd "$ALIGNMINK_DIR" && "$RUFF_CMD" check . 2>/dev/null); then
            echo "[quality-gate] FAIL: Python lint errors. Run: cd apps/Alignmink && ruff check --fix ."
            ERRORS=1
        fi
        if ! (cd "$ALIGNMINK_DIR" && "$RUFF_CMD" format --check . 2>/dev/null); then
            echo "[quality-gate] FAIL: Python format issues. Run: cd apps/Alignmink && ruff format ."
            ERRORS=1
        fi
    fi

    if [ "$ERRORS" -ne 0 ]; then
        echo "[quality-gate] Commit blocked. Fix the issues above first."
        exit 2
    fi

    echo "[quality-gate] Pre-commit checks passed."
    exit 0
fi

# --- git push: lint + format + tests ---
if echo "$COMMAND" | grep -qE '^git push'; then
    echo "[quality-gate] Running pre-push checks (lint + tests)..."

    if [ -n "$RUFF_CMD" ]; then
        if ! (cd "$ALIGNMINK_DIR" && "$RUFF_CMD" check . 2>/dev/null); then
            echo "[quality-gate] FAIL: Python lint errors."
            ERRORS=1
        fi
    fi

    # Run tests (use .venv/bin/python relative to ALIGNMINK_DIR to avoid path-with-spaces issues)
    if [ -x "$ALIGNMINK_DIR/.venv/bin/python" ]; then
        if ! (cd "$ALIGNMINK_DIR" && .venv/bin/python -m pytest tests/ -q --tb=line 2>&1); then
            echo "[quality-gate] FAIL: Tests failing. Run: cd apps/Alignmink && .venv/bin/python -m pytest tests/ -v"
            ERRORS=1
        fi
    elif command -v python3 >/dev/null 2>&1; then
        if ! (cd "$ALIGNMINK_DIR" && python3 -m pytest tests/ -q --tb=line 2>&1); then
            echo "[quality-gate] FAIL: Tests failing."
            ERRORS=1
        fi
    fi

    if [ "$ERRORS" -ne 0 ]; then
        echo "[quality-gate] Push blocked. Fix the issues above first."
        exit 2
    fi

    echo "[quality-gate] Pre-push checks passed. All clear."
    exit 0
fi

# Not a commit or push — allow through
exit 0
