#!/usr/bin/env python3
"""
Idempotently wire Founder Stack hooks into a project's .claude/settings.json.

Usage:
    python3 wire-hooks.py <path/to/.claude/settings.json>

The merger reads the existing settings.json (creating it if absent), adds
entries for every framework hook under the matching event/matcher group,
and writes the result back atomically. Re-running is safe — entries are
deduped by script filename, so the user's hand-edits are preserved and
no duplicates are introduced.
"""

import json
import sys
from pathlib import Path

HOOKS = [
    ("PostToolUse", "Edit|Write", "auto-lint.sh"),
    ("PostToolUse", "Edit|Write", "tsc-check.sh"),
    ("PreToolUse",  "Bash",       "pre-git-check.sh"),
    ("PreToolUse",  "Bash",       "main-push-guard.sh"),
    ("PreToolUse",  "Edit|Write", "migration-guard.sh"),
]


def hook_command(script: str) -> str:
    return f"bash $CLAUDE_PROJECT_DIR/.claude/hooks/{script}"


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

    existing = settings.get("hooks")
    if existing is None:
        settings["hooks"] = {}
    elif not isinstance(existing, dict):
        kind = type(existing).__name__
        print(
            f"error: {settings_path} 'hooks' field is {kind}, expected object. "
            "Edit manually and re-run.",
            file=sys.stderr,
        )
        return 1

    added = kept = 0
    for event, matcher, script in HOOKS:
        groups = settings["hooks"].setdefault(event, [])
        if not isinstance(groups, list):
            print(
                f"error: settings.json hooks.{event} is not a list. Edit manually.",
                file=sys.stderr,
            )
            return 1

        group = next((g for g in groups if isinstance(g, dict) and g.get("matcher") == matcher), None)
        if group is None:
            group = {"matcher": matcher, "hooks": []}
            groups.append(group)

        entries = group.setdefault("hooks", [])
        if not isinstance(entries, list):
            print(
                f"error: settings.json hooks.{event}[matcher={matcher}].hooks is not a list.",
                file=sys.stderr,
            )
            return 1

        already_wired = any(
            script in (e.get("command") or "")
            for e in entries
            if isinstance(e, dict)
        )
        if already_wired:
            kept += 1
            continue

        entries.append({"type": "command", "command": hook_command(script)})
        added += 1

    tmp = settings_path.with_suffix(settings_path.suffix + ".tmp")
    tmp.write_text(json.dumps(settings, indent=2) + "\n")
    tmp.replace(settings_path)

    print(f"  hooks wired: {added} added, {kept} already present")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: wire-hooks.py <path/to/settings.json>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(Path(sys.argv[1])))
