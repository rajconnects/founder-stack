---
description: Start a new autonomous mission. Orchestrator scopes the goal, writes a validation contract for your approval, then dispatches workers and validators on a /loop tick until the mission completes or blocks. Designed for overnight runs.
argument-hint: <goal> [--pace local|cron]
---

You are kicking off a new Founder Stack v1 autonomous mission.

**Arguments:** `$ARGUMENTS`

## Steps

1. If `$ARGUMENTS` is empty or lacks a goal: print:
   ```
   /mission requires a goal. Example: /mission "build a counter component with persisted state"
   Optional: --pace local (default) or --pace cron (v1.1, /schedule-driven).
   ```
   Stop.

2. Parse `--pace` flag if present. Strip it from the goal string. Default: `local`.

3. Read `.claude/project.json`. Confirm `mission_root` is set (default `missions/`). If the project hasn't been configured for v1 yet, print one line directing the user to copy `.claude/project.example.v1.json` keys into their `project.json`, then proceed with defaults.

4. Launch the `mission-orchestrator` subagent via Task tool:

   ```
   subagent_type: mission-orchestrator
   prompt: |
     MODE: new
     GOAL: <the parsed goal>
     PACE: <local|cron>
     INVOKED_BY: /mission
   ```

5. When the orchestrator returns, print its summary verbatim. The summary will include the mission id and instructions for the user to type `/loop /mission-tick <id>` to enter autonomous loop mode. Do not synthesize on top of it.

## Notes

- `/mission` runs the **synchronous** part of the mission: scoping conversation, contract authoring, contract approval, `state.json` initialization. After this, the user must type `/loop /mission-tick <id>` to enter `/loop` dynamic mode. **Only `/loop` dynamic mode lets `ScheduleWakeup` actually fire** — without it, the autonomous loop never advances.
- This two-step entry (synchronous scope, then explicit `/loop` start) is intentional. Contract approval is a checkpoint the user must own; sliding straight into autonomous execution without that confirmation would be the wrong default.
- Do not invoke `mission-orchestrator` outside of this command. Other entry points (`/mission-resume`, `/mission-abort`) have their own dispatching prompts.
- `--pace cron` is v1.1. In v1.0, only `--pace local` is fully wired; the orchestrator will fall back to local with a warning if cron is requested.
