#!/bin/bash
# Claude Code PreToolUse hook: warn on `git push` to main/master without a passing /deploy-gate marker.
# Non-blocking — prints a soft warning, always exits 0.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
PROJECT_DIR=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")

# Only care about git push to main/master
if ! echo "$COMMAND" | grep -qE '^git push'; then exit 0; fi
if ! echo "$COMMAND" | grep -qE '\b(main|master)\b'; then
    # If no explicit branch, git push without args pushes current branch — check that
    CURRENT_BRANCH=$(cd "$PROJECT_DIR" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    case "$CURRENT_BRANCH" in
        main|master) ;;
        *) exit 0 ;;
    esac
fi

# Check for any deploy-gate marker
if ls "$PROJECT_DIR/.claude/".deploy-gate-passed-* >/dev/null 2>&1; then
    exit 0
fi

echo "[main-push-guard] Pushing to main/master but /deploy-gate has not passed this session."
echo "[main-push-guard]   Run: /deploy-gate staging first to smoke-verify before shipping."
exit 0
