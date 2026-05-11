---
description: One iteration of the autonomous mission loop. Invoked as `/loop /mission-tick <id>` to start, then re-fired by /loop dynamic mode on each ScheduleWakeup (local pace), or fired by /schedule (cron pace).
argument-hint: <mission-id>
---

You are firing one tick of an in-flight mission's autonomous loop. **This command runs the tick procedure directly in the main agent thread** — the procedure dispatches `feature-worker`, `scrutiny-validator`, `design-auditor`, `schema-analyst`, `user-flow-tester`, `docs-auditor`, and `memory-broker` via the Task tool. Claude Code blocks sub-agents from spawning further sub-agents, so the tick procedure must run as the main thread, not a sub-agent.

**Entry expectation:** this command should be invoked via `/loop /mission-tick <id>` — that puts the session into `/loop` dynamic mode, which is what makes the tick procedure's `ScheduleWakeup` calls actually fire. If you were invoked as a bare `/mission-tick <id>` (no `/loop` prefix), wakeups will be no-ops and the mission will stall after one tick.

**Arguments:** `$ARGUMENTS`

## Steps

1. If `$ARGUMENTS` is empty: print `ERROR: /mission-tick requires a mission id` and stop.

2. Read `.claude/project.json` → `mission_root`. Confirm `<mission_root>/<id>/state.json` exists. If not: print `ERROR: no mission state found at <path>. Aborting tick.` and stop.

3. **Read `.claude/procedures/v1/mission-tick.md` and execute it in this main agent thread.** Pass:
   - `MISSION_ID`: `<id>` from `$ARGUMENTS`

   The procedure handles cap checks, dispatches the next step (worker → scrutiny+design+schema in parallel → user-test → handoff), saves state, and either calls `ScheduleWakeup` (local pace) or returns silently (cron pace). On the last feature's handoff, it runs the Completion section (docs-audit, memory write, PR handoff).

4. After the procedure returns, capture its return line. Shape: `<id> | step <step> | <verdict-summary> | pace <pace> | status <status>`. Print it verbatim.

5. **Cron pace cleanup.** If the return shows `pace cron` AND `status` is one of `completed`, `aborted`, or `blocked`: invoke the `/schedule` skill via the Skill tool to **delete** the routine named `mission-<id>`. The mission's cron schedule should not keep firing after a terminal state. If routine deletion fails (already gone, schedule skill unreachable), log a warning but don't fail the tick — the next cron fire will just see terminal status and exit cleanly without doing work.

## Notes

- This command exists so `/loop` (local pace) and `/schedule` (cron pace) have a stable target to fire. It does no work of its own — the procedure dispatches the actual subagents.
- If the procedure returned with `resume_requested: true`, the next wakeup re-enters via this same command and starts a fresh session (the loop runtime / cron handles that).
- **Model expectation:** Opus is recommended for the tick loop (planning, retry decisions, audit aggregation). Sonnet works but is weaker at multi-dispatch reasoning.
