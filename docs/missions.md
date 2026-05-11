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

## The three roles

| Role | Agent | What it does |
|---|---|---|
| Orchestrator | `mission-orchestrator` (opus) | Scopes the goal, writes the validation contract, dispatches workers and validators, decides retry/advance/block. Maintains `state.json` as the durable source of truth. |
| Worker | `feature-worker` (sonnet) | Implements one feature against its contract, runs local checks, emits a structured handoff. One feature per dispatch, clean context each time. |
| Scrutiny validator | `scrutiny-validator` (sonnet) | Adversarially re-checks the worker's claims with fresh context, dispatches v0.1 auditors as needed, emits a PASS/FAIL verdict. |
| Memory broker | `memory-broker` (haiku) | Reads and writes cross-mission memory. Local files by default; Mem0 over HTTP if configured. |

## The five commands

| Command | What it does |
|---|---|
| `/mission <goal>` | Start a new mission. Orchestrator scopes goal, writes contract for your approval, hands off to `/loop`. |
| `/mission-status [id]` | Show current state of a mission (read-only). Defaults to the most recent. |
| `/mission-resume <id>` | Resume a paused or blocked mission in a fresh session. |
| `/mission-abort <id>` | Terminate a mission. Preserves the directory for audit. Does not roll back code changes. |
| `/mission-tick <id>` | Internal — fired by `/loop` on schedule. Do not invoke directly. |

## What happens when you run `/mission`

1. You type `/mission "build a counter component with persisted state, key must be 'counter:v1'"`. This is the **synchronous** entry — the orchestrator runs in your foreground until the contract is approved.
2. The orchestrator reads `.claude/project.json`, generates a mission id, checks prior missions for relevant context via the memory-broker.
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

## What v1.0 doesn't do yet

- Multi-feature decomposition with dependency graphs
- User-flow testing via Playwright (currently auto-skipped if `mission_user_test.preview_url_command` is null)
- `--pace cron` (laptop-asleep missions via `/schedule`)
- `/mission --from-issue <github-url>`
- `gh pr create` automation at mission completion
- Mem0 semantic search (broker has the seam; the search call is local-only in v1.0)

Roadmap in `workflow-v1/Engineering-Playbook-v1-deltas.md`.
