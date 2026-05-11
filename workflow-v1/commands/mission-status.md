---
description: Show the current state of a mission — status, current step, verdicts so far, recent log entries. Read-only.
argument-hint: [mission-id, default: latest]
---

You are rendering a status summary for an in-flight or completed mission.

**Arguments:** `$ARGUMENTS`

## Steps

1. Read `.claude/project.json` → `mission_root` (default `missions/`).

2. Resolve mission id:
   - If `$ARGUMENTS` is non-empty: use it.
   - Else: `bash -c 'ls -1t <mission_root> 2>/dev/null | head -1'` to find the latest mission directory. If empty: print `No missions found in <mission_root>.` and stop.

3. Read `<mission_root>/<id>/state.json`. If absent or invalid: print `ERROR: state.json missing or invalid at <path>.` and stop.

4. Read `<mission_root>/<id>/log.md`. Extract the last 20 lines (or fewer if shorter).

5. Render to the user:

   ```
   Mission: <id>
   Goal:    <goal>
   Status:  <status>           (pace: <pace>)
   Step:    feature <fid> | <current_step>
   Caps:    <retry_counts[<fid>:worker]>/<caps.max_dispatches_per_feature> worker retries, <dispatches_total>/<caps.max_total_dispatches> total dispatches
   Worktree: <state.worktree.path> (branch <state.worktree.branch>, base <state.worktree.base_ref>)
              — or "none (host mode)" if state.worktree is null/absent

   Features:
     <fid> <name>  status=<status>  scrutiny=<verdict>  user_test=<verdict>
     ...

   Recent log:
   <last 20 lines of log.md>
   ```

6. If `status == blocked`: end with `Next action: review <mission_root>/<id>/log.md and the latest handoff, then /mission-resume <id> (after fixing root cause) or /mission-abort <id>.`

7. If `status == completed`: end with `Mission complete. Suggested next: review <mission_root>/<id>/contract.md and consider gh pr create.`

## Notes

- Read-only. Never modify state.json from this command.
- If multiple missions are in flight, the user is expected to pass the id. The "latest" default is a convenience for single-mission workflows.
