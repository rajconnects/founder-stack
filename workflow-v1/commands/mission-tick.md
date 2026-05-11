---
description: One iteration of the orchestrator loop. Invoked as `/loop /mission-tick <id>` by the user after `/mission` approval to start autonomous execution, and re-fired by /loop dynamic mode on each ScheduleWakeup.
argument-hint: <mission-id>
---

You are firing one tick of an in-flight mission's orchestrator loop.

**Entry expectation:** this command should be invoked via `/loop /mission-tick <id>` — that puts the session into `/loop` dynamic mode, which is what makes the orchestrator's `ScheduleWakeup` calls actually fire. If you were invoked as a bare `/mission-tick <id>` (no `/loop` prefix), the orchestrator's wakeups will be no-ops and the mission will stall after one tick.

**Arguments:** `$ARGUMENTS`

## Steps

1. If `$ARGUMENTS` is empty: print `ERROR: /mission-tick requires a mission id` and stop.

2. Read `.claude/project.json` → `mission_root`. Confirm `<mission_root>/<id>/state.json` exists. If not: print `ERROR: no mission state found at <path>. Aborting tick.` and stop.

3. Launch the orchestrator:

   ```
   subagent_type: mission-orchestrator
   prompt: |
     MODE: tick
     MISSION_ID: <id>
     INVOKED_BY: /loop /mission-tick (or /schedule if cron pace)
   ```

4. Print the orchestrator's return line verbatim. The line has shape `<id> | step <step> | <verdict-summary> | pace <pace> | status <status>`.

5. **Cron pace cleanup.** If the orchestrator's return shows `pace cron` AND `status` is one of `completed`, `aborted`, or `blocked`: invoke the `/schedule` skill via the Skill tool to **delete** the routine named `mission-<id>`. The mission's cron schedule should not keep firing after a terminal state. If routine deletion fails (already gone, schedule skill unreachable), log a warning but don't fail the tick — the next cron fire will just see terminal status and exit cleanly without doing work.

## Notes

- This command exists so `/loop` (local pace) and `/schedule` (cron pace) have a stable target to fire. It does no work of its own — orchestrator dispatches the actual subagents.
- If the orchestrator returned with `resume_requested: true`, the next wakeup re-enters via this same command, but starts a fresh session (the loop runtime / cron handles that).
