---
description: Resume a paused or blocked mission. Re-syncs state, updates the heartbeat, and tells you how to re-enter /loop. Used after context-overflow auto-exit, after a session crash, or after a human cleared a blocking issue.
argument-hint: <mission-id>
---

You are resuming an in-flight mission in a fresh session. The prior autonomous-loop conversation is gone; everything we need is in `state.json`.

**Arguments:** `$ARGUMENTS`

## Steps

1. If `$ARGUMENTS` is empty: print `ERROR: /mission-resume requires a mission id. Run /mission-status to see active missions.` and stop.

2. Read `.claude/project.json` → `mission_root`. Confirm `<mission_root>/<id>/state.json` exists. If not, print `ERROR: no mission state found at <path>.` and stop.

3. Read the state. Validate:
   - `status` is one of `running`, `paused`, `blocked`. If `completed` or `aborted`: refuse with `Cannot resume <id> — status is <status>.` and stop.
   - If `status: blocked`: print the last 5 lines of `log.md` and the most recent handoff/scrutiny verdict, then ask: `Resume anyway? (yes/no)`. On `no`: stop.

4. **Synchronously re-sync state** (this is small enough to inline — no separate procedure file):
   - Set `resume_requested: false` if it was true.
   - Update `last_heartbeat` to now.
   - Save state atomically (`Write` to `state.json.tmp`, then `Bash mv state.json.tmp state.json`).
   - Append to `log.md`: `<timestamp> | mission resumed by /mission-resume`.

5. Print:

   ```
   Mission <id> resumed.
     Status:  <status>
     Step:    feature <fid> | <current_step>
     Caps:    <retry_counts[<fid>:worker]>/<caps.max_dispatches_per_feature> retries used

   To continue autonomously, type:
     /loop /mission-tick <id>
   ```

6. **If `state.pace == "cron"`:** invoke the `/schedule` skill via the Skill tool to **re-create** the routine named `mission-<id>` (the original may or may not still exist — `/schedule create` should be idempotent or the skill should handle "already exists" gracefully; if it's strict, list routines first and skip creation if the name already matches). The cron will fire `/mission-tick <id>` every `mission_caps.cron_interval_minutes` minutes from now.

   **If `state.pace == "local"`:** the user will see the instructions from step 5 telling them to type `/loop /mission-tick <id>`. Nothing more for this command to do.

   `/mission-resume` itself runs synchronously (no `ScheduleWakeup`), the same way `/mission` does. Only `/loop /mission-tick` (local) or the cron schedule (cron) enables the autonomous tick cadence.

## Notes

- Resume does **not** reset retry caps. If `retry_counts` for the current feature is already at `caps.max_dispatches_per_feature`, the next tick will immediately re-block. To force progress past a cap, the user must either edit `state.json` directly or `/mission-abort` and start a new mission.
- Resume assumes the underlying repo is in a sane state — if the user manually edited code between sessions, that's their judgment. This command does not roll back or compare.
