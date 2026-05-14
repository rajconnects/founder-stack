#!/bin/bash
# Claude Code PreToolUse hook: quality gate before git commit/push.
# Reads .claude/project.json for backend root and test commands.
# Blocks (exit 2) if checks fail. Skips silently if config or tools are missing.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
PROJECT_DIR=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")

CONFIG="$PROJECT_DIR/.claude/project.json"
[ -f "$CONFIG" ] || exit 0

BACKEND_ROOT=$(python3 -c "import json; v=json.load(open('$CONFIG')).get('stack',{}).get('backend_root'); print(v or '')" 2>/dev/null || echo "")
TEST_BACKEND=$(python3 -c "import json; v=json.load(open('$CONFIG')).get('test_commands',{}).get('backend'); print(v or '')" 2>/dev/null || echo "")

ERRORS=0

# Resolve ruff if backend root exists
RUFF_CMD=""
BACKEND_DIR=""
if [ -n "$BACKEND_ROOT" ]; then
    BACKEND_DIR="$PROJECT_DIR/$BACKEND_ROOT"
    if [ -x "$BACKEND_DIR/.venv/bin/ruff" ]; then
        RUFF_CMD="$BACKEND_DIR/.venv/bin/ruff"
    elif command -v ruff >/dev/null 2>&1; then
        RUFF_CMD="ruff"
    fi
fi

# --- git commit: secret scan + lint + format check ---
if echo "$COMMAND" | grep -qE '^git commit'; then
    echo "[quality-gate] Running pre-commit checks..."

    # Secret scan via gitleaks (optional dependency). If installed, run it
    # against staged changes and block (exit 2) on findings. If not
    # installed, print a one-time notice and continue — soft-optional so
    # users who haven't installed gitleaks aren't surprised by a block.
    if command -v gitleaks >/dev/null 2>&1; then
        if ! (cd "$PROJECT_DIR" && gitleaks protect --staged --redact --no-banner 2>&1); then
            echo "[gitleaks] Staged changes contain potential secrets. Commit blocked."
            echo "[gitleaks]   Inspect unredacted: cd '$PROJECT_DIR' && gitleaks protect --staged --verbose"
            echo "[gitleaks]   False positive? Add to .gitleaks.toml allowlist (see gitleaks docs)."
            exit 2
        fi
    else
        NOTICE_MARKER="$PROJECT_DIR/.claude/.gitleaks-notice-shown"
        if [ ! -f "$NOTICE_MARKER" ]; then
            echo "[pre-git-check] gitleaks not installed — secret scanning skipped."
            echo "  Install: brew install gitleaks   (or apt: gitleaks)"
            echo "  See:     https://github.com/gitleaks/gitleaks"
            echo "  (This notice will not repeat — touch \$NOTICE_MARKER if you want to re-show it.)"
            mkdir -p "$(dirname "$NOTICE_MARKER")" 2>/dev/null
            : > "$NOTICE_MARKER" 2>/dev/null || true
        fi
    fi

    if [ -n "$RUFF_CMD" ] && [ -n "$BACKEND_DIR" ]; then
        if ! (cd "$BACKEND_DIR" && "$RUFF_CMD" check . 2>/dev/null); then
            echo "[quality-gate] FAIL: Python lint errors. Run: cd $BACKEND_ROOT && ruff check --fix ."
            ERRORS=1
        fi
        if ! (cd "$BACKEND_DIR" && "$RUFF_CMD" format --check . 2>/dev/null); then
            echo "[quality-gate] FAIL: Python format issues. Run: cd $BACKEND_ROOT && ruff format ."
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

# --- git push: lint + tests ---
if echo "$COMMAND" | grep -qE '^git push'; then
    echo "[quality-gate] Running pre-push checks (lint + tests)..."

    if [ -n "$RUFF_CMD" ] && [ -n "$BACKEND_DIR" ]; then
        if ! (cd "$BACKEND_DIR" && "$RUFF_CMD" check . 2>/dev/null); then
            echo "[quality-gate] FAIL: Python lint errors."
            ERRORS=1
        fi
    fi

    # Backend tests, if a command is configured
    if [ -n "$TEST_BACKEND" ] && [ -n "$BACKEND_DIR" ]; then
        # Prefer .venv/bin/python for pytest commands (path-with-spaces safety)
        if [ -x "$BACKEND_DIR/.venv/bin/python" ] && [[ "$TEST_BACKEND" == pytest* ]]; then
            TEST_CMD=".venv/bin/python -m ${TEST_BACKEND}"
        else
            TEST_CMD="$TEST_BACKEND"
        fi
        if ! (cd "$BACKEND_DIR" && eval "$TEST_CMD -q --tb=line" 2>&1); then
            echo "[quality-gate] FAIL: Tests failing. Run: cd $BACKEND_ROOT && $TEST_BACKEND -v"
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
