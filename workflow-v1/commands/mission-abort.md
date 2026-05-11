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

6. Launch the orchestrator:

   ```
   subagent_type: mission-orchestrator
   prompt: |
     MODE: abort
     MISSION_ID: <id>
     REASON: <the parsed reason or "user-initiated abort">
     INVOKED_BY: /mission-abort
   ```

7. Print the orchestrator's one-line confirmation. Suggest:
   ```
   Review code changes with:  git diff
   Review mission with:       cat <mission_root>/<id>/log.md
   ```

## Notes

- Abort is durable: once status is `aborted`, `/mission-resume` will refuse to continue. To restart, the user must `/mission` from scratch (which generates a new id).
- This command does not delete files. Audit trails are sacred.
- If a /loop is currently mid-tick on this mission, the in-flight tick will complete naturally; the next scheduled wake will see `status: aborted` and exit cleanly.
