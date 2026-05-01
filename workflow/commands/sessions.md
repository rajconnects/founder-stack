---
description: List active and recent Claude Code session claims from coordination.json. Optionally clean stale rows + orphan worktrees.
argument-hint: [list|clean|show <id>]
---

You are inspecting parallel-session state.

**Arguments:** `$ARGUMENTS` (default: `list`)

## Subcommands

### `list` (default)

1. Read `.claude/coordination.json`.
2. Print a table:
   ```
   ID         STATUS              SEVERITY  PHASE       BRANCH                    HEARTBEAT (age)
   sess-abc   active              major     7a          phase-7a-app-shell        2m
   sess-def   completed           minor     docs        main                      —
   sess-ghi   completed_unclean   major     6d          phase-6d-domain-spines    18m (stale)
   ```
3. Below the table, list any rows where `status: active` and heartbeat age > staleness threshold — these are likely crashed sessions.

### `show <id>`

Print the full row for `<id>` as pretty JSON. Resolve `<id>` against either `id` or `resume_id` (substring match OK).

### `clean`

1. Read `.claude/coordination.json`.
2. For each row with `status: active` and heartbeat older than `_doc.staleness_threshold_minutes`:
   - Flip to `completed_unclean`, set `completed` to now.
3. For each `completed_unclean` row whose `worktree` path exists on disk and is registered in `git worktree list`:
   - Run `git worktree remove --force '<path>'`. Capture stderr.
4. Print a summary:
   ```
   Swept N stale rows. Removed M worktrees. K paths needed manual cleanup:
     - <path>: <reason>
   ```
5. Surface anything that needs the user's eyes — never silently delete uncommitted work in a worktree without warning. If `git worktree remove` complains about uncommitted changes, do **not** add `--force` automatically; report and ask.

## Notes

- This command is read-mostly. `clean` is the only writer beyond status flips. Never mutate the `claims` of another session — those are owned by their writer.
- Heartbeat ages are computed against the system clock at command run.
- For routine operation, the scheduled cleanup script (`.claude/scripts/coord-cleanup.sh`) handles `clean` non-interactively. `/sessions clean` is the manual lever.
