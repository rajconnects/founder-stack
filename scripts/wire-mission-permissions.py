#!/usr/bin/env python3
"""
Idempotently merge a mission-starter permissions.allow list into a project's
.claude/settings.json.

Usage:
    python3 wire-mission-permissions.py <path/to/.claude/settings.json>

Why this exists:
    Mission mode's "kick off after dinner, review at breakfast" promise is about
    *decision* autonomy — the orchestrator never asks you to approve a worker
    retry or a contract advance. But every Bash, Edit, Write, Task dispatch and
    MCP call still passes through Claude Code's permission gate. Without a
    baseline allow-list, an overnight mission stalls behind permission prompts.

    This wirer adds a conservative starter set covering the tool surface a
    typical mission worker will hit (npm/pnpm/yarn, python tooling, git, gh,
    Playwright MCP). It's additive: any allow entries already in the file are
    preserved, and matches are deduped by exact-string comparison so re-running
    is safe.

    Users should review .claude/settings.json after install and tighten or
    extend the list for their stack.
"""

import json
import sys
from pathlib import Path

# Conservative starter set. Patterns follow Claude Code's permission syntax:
#   "ToolName"               — exact match on a tool name (e.g. "Task")
#   "Bash(<glob>)"           — Bash command shape match
#   "mcp__<server>__*"       — MCP tool prefix match
#
# Read/Edit/Write/Glob/Grep are intentionally omitted — Claude Code's default
# mode auto-allows them, and listing them explicitly would change behavior in
# unexpected ways for users who deliberately constrain those at the org level.
MISSION_ALLOW = [
    # Sub-agent dispatch (orchestrator → worker/validator/auditor).
    "Task",

    # Package managers and JS test/lint runners.
    "Bash(npm test*)",
    "Bash(npm run *)",
    "Bash(npx *)",
    "Bash(npx --no-install *)",
    "Bash(pnpm *)",
    "Bash(yarn *)",

    # Python tooling.
    "Bash(pytest*)",
    "Bash(ruff *)",
    "Bash(python *)",
    "Bash(python3 *)",

    # Git read operations.
    "Bash(git status*)",
    "Bash(git diff*)",
    "Bash(git log*)",
    "Bash(git branch*)",
    "Bash(git rev-parse*)",
    "Bash(git worktree *)",

    # Git write operations the worker performs inside the mission worktree.
    "Bash(git add *)",
    "Bash(git commit *)",
    "Bash(git checkout*)",

    # Git push and PR creation only land changes from the mission branch; the
    # branch is scoped to the mission worktree, never main.
    "Bash(git push *)",
    "Bash(gh pr create*)",
    "Bash(gh pr view*)",
    "Bash(gh issue view*)",

    # User-flow-tester drives a real browser via Playwright MCP.
    "mcp__playwright__*",

    # macOS uses gtimeout when coreutils is installed; Linux ships timeout.
    # Hooks shell out to one or the other.
    "Bash(timeout *)",
    "Bash(gtimeout *)",
]


def main(settings_path: Path) -> int:
    if settings_path.exists():
        try:
            settings = json.loads(settings_path.read_text())
        except json.JSONDecodeError as exc:
            print(f"error: {settings_path} is not valid JSON: {exc}", file=sys.stderr)
            return 1
    else:
        settings_path.parent.mkdir(parents=True, exist_ok=True)
        settings = {}

    permissions = settings.get("permissions")
    if permissions is None:
        settings["permissions"] = {}
        permissions = settings["permissions"]
    elif not isinstance(permissions, dict):
        kind = type(permissions).__name__
        print(
            f"error: {settings_path} 'permissions' field is {kind}, expected object. "
            "Edit manually and re-run.",
            file=sys.stderr,
        )
        return 1

    allow = permissions.get("allow")
    if allow is None:
        permissions["allow"] = []
        allow = permissions["allow"]
    elif not isinstance(allow, list):
        kind = type(allow).__name__
        print(
            f"error: {settings_path} 'permissions.allow' is {kind}, expected list. "
            "Edit manually and re-run.",
            file=sys.stderr,
        )
        return 1

    existing = {entry for entry in allow if isinstance(entry, str)}
    added = 0
    for pattern in MISSION_ALLOW:
        if pattern in existing:
            continue
        allow.append(pattern)
        existing.add(pattern)
        added += 1

    tmp = settings_path.with_suffix(settings_path.suffix + ".tmp")
    tmp.write_text(json.dumps(settings, indent=2) + "\n")
    tmp.replace(settings_path)

    kept = len(MISSION_ALLOW) - added
    print(f"  mission permissions: {added} added, {kept} already present")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: wire-mission-permissions.py <path/to/settings.json>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(Path(sys.argv[1])))
