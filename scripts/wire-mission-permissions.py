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

    # Mem0 helper — memory-broker invokes this; the helper keeps the API
    # key out of agent context. Absolute-path-prefix match.
    "Bash(*/.claude/scripts/mem0-call.sh *)",
    "Bash(.claude/scripts/mem0-call.sh *)",
]


# Deny list — patterns that override the allow list. Claude Code evaluates
# rules in order: deny → ask → allow, so a matching deny always wins.
#
# Why this exists alongside MISSION_ALLOW: the allow entry "Bash(git push *)"
# is broader than the procedural intent. Claude Code's `*` matches the rest
# of the command line (not "next single argument"), so without an explicit
# deny, "git push origin main" or "git push --force origin main" would be
# allowed. The orchestrator's tick procedure only ever pushes the mission
# branch via `git push -u origin <state.worktree.branch>`, and the worker
# is system-prompted not to push at all. This deny block enforces the
# procedural rule at the gate.
#
# Override path: if you genuinely need a force-push or a direct push to
# main during recovery, temporarily remove the matching entry from
# permissions.deny. Don't add a competing allow rule — deny always wins.
MISSION_DENY = [
    # Block pushes that target main/master, in any of the forms a worker
    # or procedure might accidentally produce.
    "Bash(git push * main)",
    "Bash(git push * main:*)",
    "Bash(git push *:main)",
    "Bash(git push *:main *)",
    "Bash(git push * master)",
    "Bash(git push * master:*)",
    "Bash(git push *:master)",
    "Bash(git push *:master *)",

    # Block any form of force-push regardless of branch.
    "Bash(git push --force*)",
    "Bash(git push -f *)",
    "Bash(git push --force-with-lease*)",

    # Block remote branch deletion via push.
    "Bash(git push --delete*)",
    "Bash(git push -d *)",

    # Block destructive local-state resets that throw away uncommitted work.
    "Bash(git reset --hard*)",
    "Bash(git clean -fd*)",
    "Bash(git clean -fdx*)",
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

    def merge_list(key: str, patterns: list[str]) -> tuple[int, int] | None:
        """Idempotently merge `patterns` into permissions[key]. Returns
        (added, kept) on success or None on a fatal typing error (already
        reported to stderr)."""
        current = permissions.get(key)
        if current is None:
            permissions[key] = []
            current = permissions[key]
        elif not isinstance(current, list):
            kind = type(current).__name__
            print(
                f"error: {settings_path} 'permissions.{key}' is {kind}, expected list. "
                "Edit manually and re-run.",
                file=sys.stderr,
            )
            return None

        existing = {entry for entry in current if isinstance(entry, str)}
        added = 0
        for pattern in patterns:
            if pattern in existing:
                continue
            current.append(pattern)
            existing.add(pattern)
            added += 1
        return added, len(patterns) - added

    allow_result = merge_list("allow", MISSION_ALLOW)
    if allow_result is None:
        return 1
    deny_result = merge_list("deny", MISSION_DENY)
    if deny_result is None:
        return 1

    tmp = settings_path.with_suffix(settings_path.suffix + ".tmp")
    tmp.write_text(json.dumps(settings, indent=2) + "\n")
    tmp.replace(settings_path)

    a_added, a_kept = allow_result
    d_added, d_kept = deny_result
    print(f"  mission permissions: allow {a_added} added, {a_kept} already present; "
          f"deny {d_added} added, {d_kept} already present")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: wire-mission-permissions.py <path/to/settings.json>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(Path(sys.argv[1])))
