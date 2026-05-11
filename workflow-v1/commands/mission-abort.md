---
description: Terminate a mission. Sets status to aborted, writes a final log entry, preserves the mission directory for audit. Does not roll back code changes.
argument-hint: <mission-id> [reason]
---

You are aborting an in-flight mission.

**Arguments:** `$ARGUMENTS`

## Steps

1. If `$ARGUMENTS` is empty: print `ERROR: /mission-abort requires a mission id. Run /mission-status to see active missions.` and stop.

2. Parse: first whitespace-separated token is the id; remainder is the abort reason (may be empty).

3. Read `.claude/project.json` → `mission_root`. Confirm `<mission_root>/<id>/state.json` exists.

4. Read the state. If `status` is already `completed` or `aborted`: print `Mission <id> already <status>. Nothing to do.` and stop.

5. **Confirm with the user.** Print:
   ```
   About to abort mission <id> (goal: <goal>).
   Status:    <status>
   Features:  <completed>/<total> completed
   Reason:    <reason or "not provided">

   This will:
     - Set status: aborted in state.json
     - Append a final log entry
     - Stop further /loop wakeups
     - Preserve the mission directory at <mission_root>/<id>/ for audit
     - NOT roll back any code changes the worker made — review with git diff

   Proceed? (yes/no)
   ```
   On `no`: stop.

6. **Perform the abort synchronously** (small enough to inline):
   - Set `state.json` `status: aborted`. Append `error_log` entry with timestamp + the parsed reason (or `"user-initiated abort"` if empty).
   - Save state atomically.
   - Append to `log.md`: `<timestamp> | mission aborted by user`.
   - **Close the coordination.json row** if it exists: set `status: completed`, `completed: <iso>`. **Do not** use `completed_unclean` — that status triggers v0.1's `coord-cleanup.sh` to force-remove the worktree, which would defeat the audit-trail guarantee. The mission-level "aborted" signal lives in `state.json.status`, not in the coordination row.
   - Do **not** delete files. Do **not** call memory-broker. The mission directory and the worktree are preserved for audit.

7. **Worktree cleanup hint.** If `state.worktree` is set, print:
   ```
   Worktree preserved at <state.worktree.path> on branch <state.worktree.branch>.
   To inspect: cd <state.worktree.path> && git status
   To discard: git worktree remove --force <state.worktree.path> && git branch -D <state.worktree.branch>
   ```

8. **Cron pace cleanup.** If `state.pace == "cron"`: invoke the `/schedule` skill via the Skill tool to delete the routine named `mission-<id>`. If deletion fails (already gone), log a warning but don't fail — the user invoked abort with clear intent. If state.pace is local, skip (nothing to clean up).

9. Suggest:
   ```
   Review code changes with:  cd <state.worktree.path> && git diff <state.worktree.base_ref>
                              (or `git diff` from the main repo if worktree is disabled)
   Review mission with:       cat <mission_root>/<id>/log.md
   ```

## Notes

- Abort is durable: once status is `aborted`, `/mission-resume` will refuse to continue. To restart, the user must `/mission` from scratch (which generates a new id).
- This command does not delete files. Audit trails are sacred.
- If a /loop is currently mid-tick on this mission, the in-flight tick will complete naturally; the next scheduled wake will see `status: aborted` and exit cleanly.
