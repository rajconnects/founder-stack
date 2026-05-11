---
description: Start a new autonomous mission. Scopes the goal, writes a validation contract for your approval, then (after explicit /loop or cron start) dispatches workers and validators on a tick loop until the mission completes or blocks. Designed for overnight runs.
argument-hint: <goal> | --from-issue <url> [--pace local|cron] [--auto-pr]
---

You are kicking off a new Founder Stack v1 autonomous mission. **This command runs orchestration logic directly in the main agent thread** (not via a sub-agent), so that downstream Task tool dispatches to `feature-worker`, `scrutiny-validator`, `design-auditor`, `schema-analyst`, `user-flow-tester`, `docs-auditor`, and `memory-broker` actually work — Claude Code blocks sub-agents from spawning further sub-agents.

**Arguments:** `$ARGUMENTS`

## Steps

1. **Parse arguments.** Recognized:
   - `--from-issue <url>` — fetch a GitHub issue's title+body and use it as the goal seed (the procedure authors the contract from it).
   - `--pace local|cron` — local (default; ScheduleWakeup inside /loop, requires Claude Code stay open) or cron (routes ticks through `/schedule` so missions survive laptop sleep).
   - `--auto-pr` — when the mission completes, automatically push the branch and `gh pr create` with an assembled body. Default off; the procedure prints the suggested command for the user to run.
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

3. **Read `.claude/procedures/v1/mission-new.md` and execute it in this main agent thread.** That procedure scopes the goal with the user, authors the contract, gets approval, creates the worktree, and initializes `state.json`. It prints its own user-facing output directly (scoping questions, contract preview, approval prompt, pace-specific final instructions) — do not re-print. Pass it the parsed values:
   - `GOAL`: the parsed goal string (or `"from-issue"` if `--from-issue` was used)
   - `ISSUE_URL`: the URL if `--from-issue`, else `"none"`
   - `PACE`: `local` or `cron`
   - `AUTO_PR`: `true` or `false`

   When the procedure finishes, capture the returned `mission_id` and `pace` (the procedure's step 11 returns a one-line summary containing both).

4. **If `pace == "cron"`:** invoke the `/schedule` skill via the Skill tool to create a recurring routine that fires `/mission-tick <mission_id>` every `mission_caps.cron_interval_minutes` (default 10) minutes. The routine name should be `mission-<mission_id>` so subsequent commands (`/mission-tick`, `/mission-abort`, `/mission-resume`) can find and delete it by name. If routine creation fails, surface the error and tell the user they can fall back to `/loop /mission-tick <id>` for local pacing. Do not delete the mission directory on cron failure — the contract is still valid; the user just loses the cron-driven path.

   **If `pace == "local"`:** the procedure's printed instructions already told the user to type `/loop /mission-tick <id>`. Do nothing further.

## Notes

- `/mission` runs the **synchronous** part of the mission: scoping conversation, contract authoring, contract approval, `state.json` initialization, and (in cron pace) routine creation. After this, the autonomous loop runs.
- In **local pace**, the user must explicitly type `/loop /mission-tick <id>` to enter `/loop` dynamic mode. Only `/loop` dynamic mode lets `ScheduleWakeup` actually fire — without it, the autonomous loop never advances.
- In **cron pace**, the `/schedule` routine fires ticks on the cron schedule regardless of whether the user's terminal is open. Each tick is a fresh session bootstrapped from `state.json`. Better for laptop-asleep overnight runs; more cache misses (one per tick).
- The two-step entry (synchronous scope, then explicit autonomous start) is intentional. Contract approval is a checkpoint the user must own; sliding straight into autonomous execution without that confirmation would be the wrong default.
- **Model expectation:** orchestration logic now runs in your session's main agent (not a pinned-Opus sub-agent). Opus is recommended for the scoping conversation, contract authoring, and the autonomous tick loop. Sonnet works but is noticeably weaker at the planning passes.
