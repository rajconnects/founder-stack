# Session Hygiene

The framework's other token-cost docs (see `CHANGELOG.md` 2026-05-05) are about *per-call* cost — picking the right model tier, trimming tool surface, scoping queries. This doc is about the cross-call version of the same lesson:

> **The cheapest token is the one you didn't carry forward.**

A single Opus orchestrator session that runs all day will, by default, drag every prior exchange into every new prompt. That's fine for ten minutes. By hour three it's the reason a simple gate run costs more than the work it's gating.

This doc is harness-agnostic. Mappings to specific tools (Claude Code's `/clear` and `/compact`) are at the bottom.

## The two operations

**Reset** — drop the entire conversation. Start fresh. New context window, no memory of what came before except what's on disk (CLAUDE.md, project.json, your code).

**Compact** — keep the same session but summarize earlier turns. The agent retains the gist of what happened but stops paying token cost for the verbatim transcript.

Reset is a hard cut. Compact is a smooth one.

## When to reset

- **Between unrelated tasks.** You finished `/schema-gate` on a migration; the next thing is a UX wireframe for an unrelated feature. Reset. There is no upside to dragging the migration's parsed columns into a design conversation.
- **After a long debugging tangent.** You spent 40 turns chasing a flaky test, found the root cause, fixed it, committed. Reset before the next feature. The chase is on disk in the commit message; you don't need it in context.
- **Before any gate run, when the gate is the *only* thing you're about to do.** Gates are designed to be self-contained — `/schema-gate` reads `project.json` and the migration file; `/design-gate` reads the spec and the changed files. They do not benefit from conversational history. Reset, run the gate, decide.
- **When you notice the agent referring to stale state.** Mentioning a file you already deleted, a function you renamed, a decision you reversed. That's a signal the cheap fix is a reset, not a longer correction.

## When to compact

- **Mid-task, when the same task continues but early exploration is no longer load-bearing.** You spent 20 turns figuring out *which* file owned the bug. You've found it; now you're implementing the fix. Compact — the search trail is overhead now, the fix work is what matters.
- **Before a long subagent delegation.** Subagents inherit context. If you're about to hand a 100k-token session to `frontend-engineer`, compact first so the subagent gets the gist instead of the full transcript.
- **When you're about to switch from "understanding the problem" to "executing the plan."** The exploration phase produces a lot of speculative thinking that the execution phase doesn't need. Compact at the seam.

## When to do neither

- **Mid-implementation with red tests on disk.** The conversation is the only place that knows *why* those specific tests are red and *what* the fix is supposed to look like. Don't reset. Don't compact yet.
- **Mid-`/spec-intake`.** The whole point is to converge on a spec interactively. Resetting throws away the convergence; compacting lossy-summarizes the very thing you're trying to nail down.
- **When the user just gave you nuanced feedback that hasn't been captured anywhere durable.** "Don't use that pattern, we tried it last quarter and it broke." Save it as memory or write it into CLAUDE.md *first*. Then you can reset safely.
- **When a gate just FAILED.** The failure context is what you need to fix it. Reset *after* the fix lands and the gate re-runs green, not before.

## How this fits the workflow

The five-layer model in `workflow.md` describes *what* runs at each stage. Session hygiene is orthogonal: it's a habit you apply *between* layer transitions. A natural rhythm:

1. `/spec-intake` → plan approved → **compact** (the back-and-forth on the spec is now load-bearing only as a summary).
2. Implementation → tests green → **keep going** (you're still in the same task).
3. `/design-gate` PASS → **reset before the next feature**.
4. `/handoff` → **reset after** (the PR is the durable artifact).

The gate commands themselves now suggest a reset on PASS for unrelated next-work — that's the hint, not a mandate.

## Claude Code mapping

In Claude Code:

- **Reset** = `/clear`. Drops the conversation. New session, same project.
- **Compact** = `/compact`. Summarizes earlier turns in place.

Both are user-invoked. The framework will *suggest* but never auto-trigger either — destructive context operations are the user's call.

## What this is not

- **An auto-clear hook.** Hooks that silently destroy conversation state would surprise users and break mental models. Not in scope.
- **A new slash command.** `/clear` and `/compact` are harness built-ins; aliasing them would fragment the contract.
- **A productivity rule.** The goal isn't fewer tokens for its own sake — it's that an Opus orchestrator dragging hours of stale context is *worse* at the next task, not just more expensive. Hygiene is about quality of reasoning as much as cost.

## The lesson worth carrying

Per-call cost is what model tiers and tool-surface trimming address. Session-level cost is what hygiene addresses. Both matter. If a session feels expensive *and* the agent feels distracted, the answer is usually `/clear`, not a smarter prompt.
