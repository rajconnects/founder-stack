---
description: Start a new autonomous mission. Orchestrator scopes the goal, writes a validation contract for your approval, then dispatches workers and validators on a /loop tick until the mission completes or blocks. Designed for overnight runs.
argument-hint: <goal> | --from-issue <url> [--pace local|cron] [--auto-pr]
---

You are kicking off a new Founder Stack v1 autonomous mission.

**Arguments:** `$ARGUMENTS`

## Steps

1. **Parse arguments.** Recognized:
   - `--from-issue <url>` — fetch a GitHub issue's title+body and use it as the goal seed (orchestrator authors the contract from it). The URL must be a GitHub issue URL — the orchestrator calls `gh issue view`.
   - `--pace local|cron` — local (default; ScheduleWakeup inside /loop, requires Claude Code stay open) or cron (v1.1; routes ticks through `/schedule` so missions survive laptop sleep).
   - `--auto-pr` — when the mission completes, the orchestrator runs `gh pr create` automatically with an assembled body. Default off; the orchestrator prints the suggested command for the user to run.
   - Remaining positional text is the goal string. Strip the flags first.

   If neither a goal string nor `--from-issue` is provided, print:
   ```
   /mission requires a goal. Examples:
     /mission "build a counter component with persisted state"
     /mission --from-issue https://github.com/<org>/<repo>/issues/42
   Optional: --pace local (default) | --pace cron, --auto-pr
   ```
   Stop.

2. Read `.claude/project.json`. Confirm `mission_root` is set (default `missions/`). If the project hasn't been configured for v1 yet, print one line directing the user to copy `.claude/project.example.v1.json` keys into their `project.json`, then proceed with defaults.

3. Launch the `mission-orchestrator` subagent via Task tool:

   ```
   subagent_type: mission-orchestrator
   prompt: |
     MODE: new
     GOAL: <the parsed goal, or "from-issue" if --from-issue was used>
     ISSUE_URL: <url if --from-issue, else "none">
     PACE: <local|cron>
     AUTO_PR: <true|false>
     INVOKED_BY: /mission
   ```

4. When the orchestrator returns, print its summary verbatim. Capture the `mission_id` and `pace` from its return line for the next step.

5. **If `pace == "cron"`:** invoke the `/schedule` skill via the Skill tool to create a recurring routine that fires `/mission-tick <mission_id>` every `mission_caps.cron_interval_minutes` (default 10) minutes. The routine name should be `mission-<mission_id>` so subsequent commands (`/mission-tick`, `/mission-abort`, `/mission-resume`) can find and delete it by name. If routine creation fails, surface the error and tell the user they can fall back to `/loop /mission-tick <id>` for local pacing. Do not delete the mission directory on cron failure — the contract is still valid; the user just loses the cron-driven path.

   **If `pace == "local"`:** the orchestrator's printed instructions already tell the user to type `/loop /mission-tick <id>`. Do nothing further.

## Notes

- `/mission` runs the **synchronous** part of the mission: scoping conversation, contract authoring, contract approval, `state.json` initialization, and (in cron pace) routine creation. After this, the autonomous loop runs.
- In **local pace**, the user must explicitly type `/loop /mission-tick <id>` to enter `/loop` dynamic mode. Only `/loop` dynamic mode lets `ScheduleWakeup` actually fire — without it, the autonomous loop never advances.
- In **cron pace**, the `/schedule` routine fires ticks on the cron schedule regardless of whether the user's terminal is open. Each tick is a fresh session bootstrapped from `state.json`. Better for laptop-asleep overnight runs; more cache misses (one per tick).
- The two-step entry (synchronous scope, then explicit autonomous start) is intentional. Contract approval is a checkpoint the user must own; sliding straight into autonomous execution without that confirmation would be the wrong default.
- Do not invoke `mission-orchestrator` outside of this command. Other entry points (`/mission-resume`, `/mission-abort`) have their own dispatching prompts.
