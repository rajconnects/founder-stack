# Multi-Session Coordination

When you have two or more Claude Code terminals open on the same project — or running with worktrees in parallel — they need to know about each other. Otherwise both will edit the same file at the same time and one wins silently.

## The protocol

Two files in `.claude/`:

- `coordination.json` — machine-readable session table
- `coordination.md` — human-readable log

Each session, when it starts, writes a row to `coordination.json` with:

- `session_id`
- `phase` — what they're working on
- `severity` — `major` or `minor`
- `claims` — files, branches, remote ops they're holding
- `status` — `active`, `completed`, `completed_unclean`
- `heartbeat` — last update timestamp

## Severity definitions

- **Major** — multi-day or multi-file build, owns a feature branch. Sibling sessions should pause.
- **Minor** — bounded scope: single-file edit, doc update, quick fix. Sibling sessions can proceed if claims don't overlap.

## Decision rules at every turn start

1. Read `coordination.json`. If your own row is `active`, refresh `heartbeat` to now.
2. Check siblings:
   - Sibling `severity: major` and `status: active` → **pause** until it completes (or user explicitly approves proceeding).
   - Sibling `severity: minor` and `status: active` → **proceed with caution**. Surface overlaps before editing.
   - All siblings completed → proceed normally.
3. Append a log line to `coordination.md` before any `git push`, force-push, rebase, branch deletion, migration, or deploy.

## Stale-row hygiene

Rows with `status: active` and a `heartbeat` older than 10 minutes are treated as crashed sessions. `/start-build` and `/sessions clean` sweep them.

## Inspecting state

- `/sessions list` — current table
- `/sessions show <id>` — single row
- `/sessions clean` — manual sweep

## When to use this

- Solo founder, one terminal — you don't need it. Skip.
- Solo founder, two terminals (e.g. one for fundraise prep, one for code) — you need it.
- More than one human on the project — you definitely need it.
