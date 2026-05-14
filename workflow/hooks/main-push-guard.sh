#!/bin/bash
# Claude Code PreToolUse hook: warn on `git push` to main/master without a passing /deploy-gate marker.
# - Interactive sessions: prints a soft warning, exits 0.
# - Autonomous mission ticks (marker file present): blocks, exits 2.
# The mission-mode check looks for .claude/.mission-tick-active-* markers
# the mission-tick procedure writes; G8 in the safety advisory.

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

# Mission-mode hardening (G8). If any mission tick marker is present, an
# autonomous tick is in progress — block (exit 2) instead of warn (exit 0)
# so an autonomous misfire can't push to main while you're asleep.
# Markers are written by mission-tick.md at tick start and removed at tick end.
if ls "$PROJECT_DIR/.claude/".mission-tick-active-* >/dev/null 2>&1; then
    echo "[main-push-guard] Mission mode is active — blocking push to main/master."
    echo "[main-push-guard]   This block is gate-enforced when a mission tick is running."
    echo "[main-push-guard]   For legitimate manual recovery: /mission-abort the active mission first."
    exit 2
fi
exit 0
