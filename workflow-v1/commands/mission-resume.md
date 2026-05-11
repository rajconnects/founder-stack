---
description: Resume a paused or blocked mission. Bootstraps a fresh orchestrator session from state.json — used after context-overflow auto-exit, after a session crash, or after a human cleared a blocking issue.
argument-hint: <mission-id>
---

You are resuming an in-flight mission in a fresh session. The orchestrator's prior conversation is gone; everything it needs is in `state.json`.

**Arguments:** `$ARGUMENTS`

## Steps

1. If `$ARGUMENTS` is empty: print `ERROR: /mission-resume requires a mission id. Run /mission-status to see active missions.` and stop.

2. Read `.claude/project.json` → `mission_root`. Confirm `<mission_root>/<id>/state.json` exists.

3. Read the state. Validate:
   - `status` is one of `running`, `paused`, `blocked`. If `completed` or `aborted`: refuse with `Cannot resume <id> — status is <status>.`
   - If `status: blocked`: print the last 5 lines of `log.md` and the most recent handoff/scrutiny verdict, then ask: `Resume anyway? (yes/no)`. On `no`: stop.

4. Launch the orchestrator:

   ```
   subagent_type: mission-orchestrator
   prompt: |
     MODE: resume
     MISSION_ID: <id>
     INVOKED_BY: /mission-resume
   ```

5. The orchestrator will:
   - Reset `resume_requested: false` if set.
   - Update `last_heartbeat`.
   - Pick up from `current_step` and continue.
   - Print instructions for the user to enter `/loop` dynamic mode for autonomous execution.

6. Print the orchestrator's return verbatim. The user will see something like:
   ```
   Mission <id> resumed at step <step>. To continue autonomously, type:
     /loop /mission-tick <id>
   ```

   `/mission-resume` itself runs synchronously (no `ScheduleWakeup`), the same way `/mission` does. Only `/loop /mission-tick` enables the autonomous tick cadence.

## Notes

- Resume does **not** retry caps. If `retry_counts` for the current feature is already at `caps.max_dispatches_per_feature`, the orchestrator will immediately re-block. To force progress past a cap, the user must either edit `state.json` directly or `/mission-abort` and start a new mission.
- Resume assumes the underlying repo is in a sane state — if the user manually edited code between sessions, that's their judgment. The orchestrator does not roll back or compare.
