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

4. When the orchestrator returns, print its summary verbatim. The summary will include the mission id and instructions for the user to type `/loop /mission-tick <id>` to enter autonomous loop mode. Do not synthesize on top of it.

## Notes

- `/mission` runs the **synchronous** part of the mission: scoping conversation, contract authoring, contract approval, `state.json` initialization. After this, the user must type `/loop /mission-tick <id>` to enter `/loop` dynamic mode. **Only `/loop` dynamic mode lets `ScheduleWakeup` actually fire** — without it, the autonomous loop never advances.
- This two-step entry (synchronous scope, then explicit `/loop` start) is intentional. Contract approval is a checkpoint the user must own; sliding straight into autonomous execution without that confirmation would be the wrong default.
- Do not invoke `mission-orchestrator` outside of this command. Other entry points (`/mission-resume`, `/mission-abort`) have their own dispatching prompts.
- `--pace cron` is v1.1. In v1.0, only `--pace local` is fully wired; the orchestrator will fall back to local with a warning if cron is requested.
