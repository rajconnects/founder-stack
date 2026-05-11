# Engineering Playbook v1 — Deltas

**This is a deltas doc.** v1 ships *additive* to v0.1. Everything in v0.1's `workflow/Engineering-Playbook.md` still applies — same project.json contract, same gates, same subagents, same hooks. This file only documents what changes when you opt in to v1 missions by running `/mission` instead of `/spec-intake`.

For shared concepts (gate philosophy, session hygiene, model tiers, coordination.json, decision traces, install/symlink mechanics), read v0.1's playbook first.

## What v1 adds

A single new layer above v0.1's eight:

```
0.  MISSION    Autonomous orchestrator → workers → validators → handoff → memory
               drives layers 1–7 below for you. /mission, /mission-tick (via /loop),
               /mission-status, /mission-resume, /mission-abort.
```

The v0.1 layers (INTAKE → SHIP → REFLECT) still exist and still work standalone. v1 just gives you an autonomous driver for them.

## The three roles

| Role | Agent | Model | What it does |
|---|---|---|---|
| Orchestrator | `mission-orchestrator` | opus | Scopes goal, writes contract, dispatches workers/validators, decides retry/advance/block, maintains `state.json`, self-paces via ScheduleWakeup |
| Worker | `feature-worker` | sonnet | Implements one feature against its contract slice, runs local checks, emits structured handoff |
| Scrutiny validator | `scrutiny-validator` | sonnet | Adversarial fresh-context check of worker's claims; dispatches v0.1 auditors (`design-auditor`, `schema-analyst`) as needed; emits PASS/FAIL |
| User-flow tester | `user-flow-tester` | sonnet | Drives `mcp__playwright__*` against a reachable preview URL; executes the contract's `user_flows[]` verbs in a real browser; captures screenshots, console errors, failed network requests; emits PASS/FAIL. Auto-skipped when `mission_user_test.preview_url_command` is null. |
| Memory broker | `memory-broker` | haiku | Single seam for cross-mission memory; local files by default, Mem0 over HTTP if configured |

## Two validators, two failure classes

Scrutiny and user-flow tester are deliberately separate roles — they catch different failure classes and the retry context differs.

- **Scrutiny FAIL** means: code doesn't compile, tests fail, types fail, design tokens are violated, schema migration is unsafe. The retry prompt to the worker includes the scrutiny verdict so it knows which static check to fix.
- **User-flow test FAIL** means: code compiles and tests pass, but the feature *doesn't actually work in a browser*. The retry prompt includes the user-test verdict — different signal (which user flow failed at which verb), so the worker knows to fix the runtime behavior, not the static state.

Both verdicts can re-dispatch the worker, up to `caps.max_dispatches_per_feature`. The user-test verdict is what makes `PASS` mean "the feature works end-to-end," not just "it compiles."

## The validation contract

The contract is the load-bearing artifact. It's written **before** any worker dispatch and locked at user approval. The orchestrator does not rewrite contract sections after lock — failed acceptance triggers a worker retry with the prior handoff in context, not a contract relaxation.

Template: `workflow-v1/templates/mission-contract.template.md`.
Schema for `state.json`: `workflow-v1/templates/state.schema.json`.

## Mission directory layout

```
missions/<mission-id>/                    ← YYYY-MM-DD-<slug>-<4-char-hash>
  state.json                              ← orchestrator's durable source of truth
  contract.md                             ← locked validation contracts per feature
  log.md                                  ← append-only narrative
  handoffs/
    <feature-id>.md                       ← worker handoff (front-matter required)
    <feature-id>.scrutiny.md              ← scrutiny verdict
    <feature-id>.user-test.md             ← v1.1
  artifacts/                              ← traces, screenshots, deploy URLs
  worktree/                               ← isolated git worktree on branch mission/<id>
    .claude → ../../../.claude            ← symlink to main repo's .claude
    <project source files…>               ← worker edits land here
```

## Isolation (worktree mode)

Each mission's worker edits happen in a per-mission `git worktree` rooted at `<mission_root>/<mission_id>/worktree/` on branch `mission/<mission_id>`. The main checkout stays clean; other missions stay independent. This is filesystem isolation only — destructive Bash commands still run on the host (the v1.1 container path closes that gap).

Mechanism:

- **Orchestrator** runs in the main repo. It owns `state.json`, `contract.md`, `log.md`, and `handoffs/*` — all under `<mission_root>/<mission_id>/`, not in the worktree.
- **Worker** and **scrutiny-validator** receive `WORKTREE_PATH` in their dispatch prompts and prefix every Bash command with `cd "$WORKTREE_PATH"`. Edit/Write/Read tool calls target absolute paths inside the worktree. The handoff write goes to the absolute `HANDOFF_OUTPUT_PATH` in the main repo's mission directory — handoffs are metadata, not source.
- **`.claude/` is symlinked** into the worktree at creation time, so slash commands resolve from either CWD.
- **coordination.json** gets a row per mission (reusing v0.1's stale-cleanup script). On `/mission-abort` or mission completion, the row is closed; the worktree itself is preserved for human inspection.

Disable with `mission_runtime.worktree.enabled: false` for host mode (worker edits in the main checkout).

## Pacing for overnight runs

The orchestrator self-paces with `ScheduleWakeup`, which only fires inside `/loop` dynamic mode. The entry sequence is therefore two steps:

1. User types `/mission "<goal>"`. Orchestrator runs synchronously: scopes the goal, writes the contract, asks for approval, initializes `state.json`.
2. On approval, orchestrator prints `Type: /loop /mission-tick <id>`. User types it. Session enters `/loop` dynamic mode. Each subsequent orchestrator tick ends with another `ScheduleWakeup` whose `prompt` is the same `/mission-tick <id>` — `/loop` re-fires it.

- **Active dispatching:** wake at `mission_caps.default_wake_active_secs` (270s default). Under the 5-min prompt-cache TTL, so cache stays warm.
- **Idle (waiting on deploy or human review):** wake at `mission_caps.default_wake_idle_secs` (1500s default). One cache miss, amortized.

**Context overflow protection.** When the orchestrator detects ~40 conversation turns or ~150KB of tool-result bytes consumed in its session, it sets `resume_requested: true`, writes a one-line log entry, and exits. The next `/loop` wake re-enters via `/mission-resume <id>` in a fresh session, which boots only from `state.json` + the current feature's contract slice. The conversation is disposable; state is durable.

## Retry loop (the autonomy delta)

When scrutiny FAILs, the orchestrator does **not** simply re-dispatch the worker with the original prompt. It includes the prior handoff and the scrutiny verdict in the retry prompt, so the worker knows exactly which ACs are unmet and what scrutiny flagged. The worker focuses its second dispatch on the gaps, not on redoing the feature.

Caps prevent runaway loops:
- `mission_caps.max_dispatches_per_feature` (3 by default)
- `mission_caps.max_total_dispatches` (50 by default)

When a cap is reached, the mission transitions to `status: blocked` and waits for human `/mission-resume` (after the human investigates) or `/mission-abort`.

## Integration with v0.1 gates

The scrutiny validator invokes v0.1 subagents (`design-auditor`, `schema-analyst`) **directly via the Task tool, not via slash commands**. Slash commands are human entry points — they parse scope, manage session markers, prompt for input. The orchestrator already knows scope (from the contract), records verdicts in `state.json` (not session markers), and benefits from the agents' raw structured output. Slash commands remain unchanged for direct human use.

This means v0.1 gates have a single source of truth. The orchestrator does not duplicate logic — it dispatches the same auditor files you'd invoke as a human.

## Memory and learning

The memory-broker is a single seam. Other agents call it via Task tool; it routes to local files or Mem0.

**Local mode (default).** Mission outcomes write to `<memory.local_root>/missions/<id>.md` and append a row to `<memory.local_root>/index.json`. At mission start, the orchestrator searches by keyword match across `tags + goal` and reads the top 3 most-similar prior missions into the contract authoring prompt.

**Mem0 mode (opt-in).** Set `memory.mem0.enabled: true` and `memory.mem0.api_key_env` in `project.json`. The broker mirrors writes to Mem0 in addition to local files (Mem0 is augmentation, not replacement). Searches use Mem0's semantic recall.

The broker file is the **only** place Mem0 is referenced. Other agents don't know which backend is live.

## Configuration

All v1-specific keys live in `project.json` under new top-level fields. See `workflow-v1/project.example.v1.json` for the schema. Every key is optional with documented defaults — you can opt in to v1 missions without editing your existing `project.json`.

## What v1 explicitly does **not** do (yet)

- Multi-feature decomposition with dependency graphs — v1.1.
- `--pace cron` via `/schedule` for laptop-asleep missions — v1.1.
- `/mission --from-issue <github-url>` and `gh pr create` on completion — v1.1.
- `docs-auditor` subagent + `/docs-gate` (catches CHANGELOG/README/playbook drift against the actual diff; runs in orchestrator Procedure D before memory write) — v1.1.
- Container isolation for destructive-command blast radius (`rm -rf` etc. still hit host today) — v1.1.
- Mem0 semantic search wired through (broker has the seam; v1.0 is keyword-match local) — v1.2.
- Framework self-evolution (mission outcomes propose edits to `workflow-v1/`) — v1.2.

## Backwards compatibility

`scripts/install-v1.sh` symlinks `workflow-v1/` content into `.claude/` alongside v0.1 — same `.claude/commands/`, `.claude/agents/`, `.claude/hooks/` directories. No v0.1 file is overwritten. Users who never run `/mission` see no behavioral change. Users who do still have access to `/spec-intake`, `/test-gate`, etc. unchanged.
