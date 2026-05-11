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
     INVOKED_BY: /loop /mission-tick
   ```

4. Print the orchestrator's one-line return verbatim. The orchestrator will have already called `ScheduleWakeup` for the next tick if the mission is still running.

## Notes

- This command exists so `/loop` has a stable target to fire. It does no work of its own.
- If the orchestrator returned with `resume_requested: true`, the next wakeup re-enters via this same command, but starts a fresh session (the loop runtime handles that).
