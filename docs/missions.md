# Missions (v1 preview)

> Status: v1.0 MVP. Single-feature missions with the autonomous retry loop. Multi-feature decomposition, user-flow testing, GitHub PR integration, and Mem0 semantic recall are scheduled for v1.1 and v1.2.

## What missions are

A **mission** is an autonomous run from a high-level goal to a verified outcome. You describe what you want, approve the validation contract the orchestrator writes, and walk away. The orchestrator dispatches a feature-worker to implement, a scrutiny-validator to adversarially check the work against the contract, and retries on failure until the contract is satisfied or a cap is reached.

Missions are designed for **overnight runs**: kick off after dinner, review at breakfast.

This is additive to the v0.1 workflow. `/spec-intake`, `/test-gate`, `/design-gate`, etc. all still work standalone. v1 adds an orchestrator that drives them for you.

## When to use missions vs. v0.1

| Situation | Use |
|---|---|
| You know what you want and want to walk away | `/mission` |
| You want to drive the implementation yourself with safety gates | `/spec-intake`, then `/test-gate`/`/design-gate` etc. |
| Goal is exploratory or you don't have crisp acceptance criteria yet | `/spec-intake` first, then optionally `/mission` |
| Production deploy is in scope | v0.1 only. v1.0 explicitly excludes prod from the orchestrator's surface. |

## The roles

| Role | Where it lives | What it does |
|---|---|---|
| Orchestrator | `procedures/v1/mission-new.md` + `procedures/v1/mission-tick.md`, executed in your main agent thread by the `/mission*` slash commands. Inherits your session model — **Opus recommended**. | Scopes the goal, writes the validation contract, dispatches workers and validators, decides retry/advance/block. Maintains `state.json` as the durable source of truth. Runs in the main thread because Claude Code blocks sub-agents from spawning further sub-agents. |
| Worker | `feature-worker` agent (sonnet) | Implements one feature against its contract, runs local checks, emits a structured handoff. One feature per dispatch, clean context each time. |
| Scrutiny validator | `scrutiny-validator` agent (sonnet) | Adversarially re-checks the worker's static-correctness claims with fresh context — tests, types, contract-coverage, honesty flags. Emits PASS/FAIL. Does **not** dispatch other auditors. |
| Design auditor | `design-auditor` agent (haiku, v0.1) | Dispatched **in parallel with scrutiny** when the feature has a `Design contract` and the worker touched frontend files. Verifies tokens, component spec, Figma alignment. |
| Schema analyst | `schema-analyst` agent (haiku, v0.1) | Dispatched **in parallel with scrutiny** when the feature has a `Schema contract` and the worker touched migration files. Verifies RLS, indexes, forward-compat. |
| User-flow tester | `user-flow-tester` agent (sonnet) | Drives a real browser via Playwright MCP against your preview URL. Executes the contract's user-flow assertions, captures screenshots and console errors. Auto-skipped when `mission_user_test.preview_url_command` is null. |
| Docs auditor | `docs-auditor` agent (haiku) | Catches docs drift — broken file refs, dead `/command` refs, unused `project.example.*.json` keys, advisory CHANGELOG-vs-diff. Dispatched automatically at mission completion, or manually via `/docs-gate`. |
| Memory broker | `memory-broker` agent (haiku) | Reads and writes cross-mission memory. Local files by default; Mem0 over HTTP if configured. |

## The five commands

| Command | What it does |
|---|---|
| `/mission <goal>` | Start a new mission. Orchestrator scopes goal, writes contract for your approval, hands off to `/loop`. |
| `/mission-status [id]` | Show current state of a mission (read-only). Defaults to the most recent. |
| `/mission-resume <id>` | Resume a paused or blocked mission in a fresh session. |
| `/mission-abort <id>` | Terminate a mission. Preserves the directory for audit. Does not roll back code changes. |
| `/mission-tick <id>` | Internal — fired by `/loop` on schedule. Do not invoke directly. |

## What happens when you run `/mission`

1. You type `/mission "build a counter component with persisted state, key must be 'counter:v1'"`. This is the **synchronous** entry — the `mission-new` procedure runs in your foreground until the contract is approved.
2. The procedure reads `.claude/project.json`, generates a mission id, checks prior missions for relevant context via the memory-broker.
3. It asks 1–3 sharp scoping questions if anything is ambiguous, then writes `missions/<id>/contract.md` with explicit acceptance criteria, file scope, and test contract.
4. It presents the contract for your approval. You can say `yes`, `edit`, or `abort`.
5. On approval, it writes `missions/<id>/state.json` and prints:
   ```
   Mission <id> approved. To start the autonomous loop, type:
     /loop /mission-tick <id>
   ```
6. **You type `/loop /mission-tick <id>`.** This puts your session into `/loop` dynamic mode — the **only** mode in which `ScheduleWakeup` actually fires. From here you can leave the terminal.
7. Each `/loop` tick: orchestrator reads `state.json`, dispatches the next step (worker → scrutiny → user-test → handoff), updates `state.json`, calls `ScheduleWakeup` to cue the next tick.
8. On scrutiny FAIL: orchestrator includes the failed handoff and scrutiny verdict in a retry prompt to the worker. Up to `max_dispatches_per_feature` (3 by default) retries before transitioning to `status: blocked`.
9. On all features `status: completed` with PASS verdicts: orchestrator writes a summary via memory-broker (so the next mission can learn from this one), skips the next `ScheduleWakeup` (terminal state), and prints a completion message with a suggested `gh pr create` invocation.

The two-step entry (synchronous scope, then explicit `/loop` start) is deliberate. Contract approval is a checkpoint you must own — sliding straight into autonomous execution without that confirmation would be the wrong default.

## Configuration

All v1-specific settings live in `.claude/project.json` under new top-level keys. Every key is optional with documented defaults — you can opt in to missions without editing your existing project.json.

```json
{
  "mission_root": "missions/",
  "mission_model_seats": { "orchestrator": "opus", "worker": "sonnet", "scrutiny": "sonnet", "user_test": "sonnet", "memory_broker": "haiku" },
  "mission_caps": {
    "max_dispatches_per_feature": 3,
    "max_total_dispatches": 50,
    "default_wake_active_secs": 270,
    "default_wake_idle_secs": 1500
  },
  "memory": {
    "local_root": "memory/",
    "mem0": { "enabled": false, "api_key_env": "MEM0_API_KEY", "user_id_env": "MEM0_USER_ID" }
  },
  "mission_user_test": { "mcp": "playwright", "preview_url_command": null }
}
```

Full reference: `.claude/project.example.v1.json` (installed by `scripts/install-v1.sh`).

## Why dispatches, not dollar caps

The orchestrator cannot introspect its own session cost from inside Claude Code — there's no exposed primitive. So `mission_caps` cap **dispatch counts**, which are deterministic and observable, as the cost proxy. The default `max_total_dispatches: 50` is a reasonable ceiling for an overnight single-feature mission. Adjust based on your stack's test-suite cost and your tolerance.

## Memory and learning

After every completed mission, the orchestrator writes a 1–3 paragraph summary to `<memory.local_root>/missions/<id>.md` and indexes it. At the start of every new mission, the orchestrator searches the index by keyword overlap with the goal and reads the top 3 most-similar prior missions into the contract authoring prompt.

This is the "learn" loop: missions on similar problems get progressively better contracts. The orchestrator notices patterns ("last time I built a localStorage component, the key collision bug bit us — let me name the key explicitly in the contract").

Mem0 (semantic recall) is opt-in for v1.0 — set `memory.mem0.enabled: true` and `MEM0_API_KEY`. The memory-broker is the only file that reads these settings; other agents are unaware.

## Install

```bash
# After scripts/install.sh (the v0.1 installer)
~/founder-stack/scripts/install-v1.sh
```

Then merge `.claude/project.example.v1.json` keys into your existing `.claude/project.json` (optional — defaults are baked into the agents).

## Trying it out

Throwaway-repo verification path:

```bash
mkdir /tmp/fs-v1-test && cd $_
git init
npm create vite@latest web -- --template react-ts
~/founder-stack/scripts/install.sh
~/founder-stack/scripts/install-v1.sh
~/founder-stack/scripts/init-project.sh   # generates .claude/project.json
claude                                     # opens Claude Code
# At the prompt:
/mission "build a Counter component in apps/web/src/components/Counter.tsx with localStorage key 'counter:v1' and a test file at apps/web/src/components/Counter.test.tsx"
# Answer the orchestrator's scope questions, approve the contract, then type:
/loop /mission-tick <id>                   # id is printed by /mission on approval
```

Expected: the orchestrator asks a clarifying question or two, writes a contract, asks for approval, then runs autonomously. Within 10–20 minutes you should see `missions/<id>/state.json` with `status: completed` and a Counter component **inside the per-mission worktree** at `missions/<id>/worktree/apps/web/src/components/Counter.tsx`.

If the worker initially picks a wrong key (e.g., `"counter"` instead of `"counter:v1"`), scrutiny will FAIL on AC-3, and the orchestrator will re-dispatch the worker with the failed handoff. This is the autonomy delta — and the headline thing v1 does that v0.1 doesn't.

Confirm isolation worked:

```bash
git -C missions/<id>/worktree status     # shows Counter.tsx added on branch mission/<id>
git status                                # main checkout is clean
git branch --list "mission/*"             # shows mission/<id>
```

When you're happy, merge:

```bash
cd missions/<id>/worktree
git push -u origin mission/<id>
gh pr create                              # use the body the orchestrator suggested
# after merge:
git worktree remove missions/<id>/worktree
git branch -D mission/<id>
```

Or, to throw the mission away without merging:

```bash
git worktree remove --force missions/<id>/worktree
git branch -D mission/<id>
```

The `missions/<id>/state.json`, `contract.md`, `log.md`, and `handoffs/` stay on disk after either path — they're audit trail, not source.

## Enabling user-flow testing

When `mission_user_test.preview_url_command` is set in `project.json`, the orchestrator dispatches `user-flow-tester` after scrutiny PASSes. The tester drives a real browser via Playwright MCP, executes the contract's user-flow verbs, and emits PASS/FAIL with screenshots and console capture. On FAIL, the orchestrator re-dispatches the worker — same retry semantics as scrutiny — with the user-test verdict in the retry prompt.

Two minimal configurations:

```jsonc
// Dev server already running (you started it before the mission)
"mission_user_test": {
  "mcp": "playwright",
  "preview_url_command": "echo http://localhost:5173"
}
```

```jsonc
// Have the mission start its own dev server (simple background-and-wait pattern)
"mission_user_test": {
  "mcp": "playwright",
  "preview_url_command": "cd $CLAUDE_PROJECT_DIR/missions/$MISSION_ID/worktree && nohup npm run dev > /tmp/dev-$MISSION_ID.log 2>&1 & sleep 8 && echo http://localhost:5173"
}
```

v1.0 does **not** auto-stop dev servers the command starts — you're responsible for cleanup. A `preview_server_stop_command` is on the roadmap if this becomes painful.

When `preview_url_command` is null, the orchestrator writes `verdicts.<fid>.user_test = "skipped"` and proceeds straight from scrutiny to handoff. This is the right setting for backend-only features or when you want a faster verification loop before wiring browser tests in.

## GitHub: issue → PR in one command

`/mission --from-issue <url>` seeds the contract from a GitHub issue's title and body. You still review and approve the contract before any code is written — the issue is context, not contract.

`/mission "<goal>" --auto-pr` makes the orchestrator push the mission branch and `gh pr create` at completion (with an assembled body including PASS checkmarks and a `Closes <issue-url>` line if you also started from an issue). Set `github.auto_pr_on_completion: true` in `project.json` to make this the default.

Combined: `/mission --from-issue https://github.com/<org>/<repo>/issues/42 --auto-pr` is a fully autonomous issue→PR run. The orchestrator never merges — that's always human.

Requires `gh` CLI installed and authenticated.

## Laptop-asleep overnight runs (`--pace cron`)

Local pace requires Claude Code to stay open. If you want true hands-off — kick off, close the laptop, review in the morning — use cron pace:

```
/mission "<goal>" --pace cron
```

After contract approval, `/mission` invokes the `/schedule` skill to create a recurring routine named `mission-<id>` that fires `/mission-tick <id>` every `mission_caps.cron_interval_minutes` minutes (default 10). Each tick is a fresh session bootstrapped from `state.json` — the conversation is fully disposable. The routine auto-deletes when the mission reaches a terminal status.

Cron pace makes every tick a cache miss, so cost-per-equivalent-throughput is higher than local pace. Tune `cron_interval_minutes` to balance — 5 minutes for active runs, 30 for trickle work.

## What v1.0 doesn't do yet

- Multi-feature decomposition with dependency graphs
- Container isolation for destructive-command blast radius
- Mem0 semantic search (broker has the seam; the search call is local-only in v1.0)

Roadmap in `workflow-v1/Engineering-Playbook-v1-deltas.md`.
