# Changelog

All notable changes to Founder Stack are recorded here. The framework is small enough that the *why* matters as much as the *what* — entries are written for the founder reading them six months later, not the bot diffing them next week.

## 2026-05-06 — Session hygiene: the cross-call counterpart

### The realization

Yesterday's entry was about *per-call* cost — picking the right model tier per agent, trimming tool surface, scoping queries. That fix matters, but it has a sibling we hadn't documented: a single Opus orchestrator session that runs all day silently drags every prior turn into every new prompt. By hour three, a `/schema-gate` run that should be cheap is being asked to share context with an unrelated UX wireframe from earlier in the day.

The cheapest token is the one you didn't carry forward.

### The fix, in one sentence

**Make session reset and session compaction first-class workflow operations — documented, suggested at the natural seams, never silently auto-triggered.**

### Specifics shipped this release

- `docs/session-hygiene.md` — new doc. Defines reset vs compact, when to do each, when to do neither (mid-implementation with red tests, mid-`/spec-intake`, after the user gives non-durable feedback, on a gate FAIL). Harness-agnostic; Claude Code's `/clear` and `/compact` are the appendix mapping.
- `workflow/commands/schema-gate.md`, `design-gate.md`, `deploy-gate.md`, `publish-gate.md` — PASS path now prints a one-line session-reset suggestion pointing at the doc. FAIL paths untouched: failure context is what the user needs to diagnose.
- `workflow/commands/test-gate.md` — deliberately *not* changed. Test-gate PASS means tests are red and implementation is next; that's the canonical "stay in the session" case.
- `docs/workflow.md` — added a cross-cutting "Session hygiene" section before "Reuse, not rebuild." Frames hygiene as orthogonal to the five layers, not a sixth layer.

### What we deliberately didn't do

- We didn't add an auto-clear hook. Hooks that silently destroy conversation state would surprise users and break their mental model. The framework suggests; the user clears.
- We didn't add a new `/reset` slash command. `/clear` and `/compact` are harness built-ins; aliasing them would fragment the contract, and per the framework rule, command shapes are public interfaces.
- We didn't write Pi-specific guidance. Pi has its own context model — covered if a user asks. The default doc stays harness-agnostic.

### The lesson worth carrying

Per-call cost is what model tiers and tool-surface trimming address. Session-level cost is what hygiene addresses. The two together cover the cost surface; in isolation, either one leaves the other unbounded.

If a session feels expensive *and* the agent feels distracted, the answer is usually a reset, not a smarter prompt.

## 2026-05-05 — Gates that don't pay model tax for free work

### The realization

`/schema-gate` was burning ~25% of session tokens on a single user's project. We pulled the agent apart and found the cost was structural, not accidental: a Sonnet-class model was being asked to do regex pattern-matching, then run live SQL queries it scoped too widely, then produce a verbose audit that mostly restated the migration file the user already had on disk.

That's not a bug in the agent — it's a category error in the gate's design. We were paying *reasoning prices* for *deterministic checks*. Hex-literal scanning, "does this migration contain a DROP TABLE", and "is the migration timestamp greater than the latest applied" are all answerable by a regex or a one-row SQL query. They never needed a model.

### The fix, in one sentence

**Push every check that can be deterministic into a shell script or a scoped SQL query, and reserve the agent for the parts that genuinely need judgement.**

### Specifics shipped this release

- `workflow/hooks/schema-static-scan.sh` — a free, deterministic pre-pass that catches `DROP TABLE`, `DROP COLUMN`, `TRUNCATE`, `DELETE FROM`, `ALTER COLUMN ... TYPE`, unsafe `DROP INDEX`, and `RENAME` before the agent ever loads. These are unambiguous fails; an LLM was the wrong oracle.
- `workflow/agents/schema-analyst.md` — rewritten. Model dropped from `sonnet` to `haiku`. Tool surface trimmed from 6 Supabase MCP tools to 1 (`execute_sql`). Live-DB queries are scoped per-table/column instead of dumping `information_schema.columns` and `pg_policies` wholesale. Forward-compat check now requires an explicit `--notes <path>` instead of grepping the architecture-notes directory. Output template halved; no more echoing migration SQL back at the user.
- `workflow/commands/schema-gate.md` — slash command now resolves config and parses migration shape *once*, then passes the parsed `new_tables` / `new_columns` / `new_indexes` into the agent prompt. The agent stops re-reading `project.json`. Verdicts are cached by file hash; re-running the gate on an unchanged migration is now free. `get_advisors` is opt-in via `--with-advisors` rather than running on every gate.
- `workflow/agents/design-auditor.md`, `deploy-verifier.md`, `spec-translator.md` — model pinned to `haiku` instead of `inherit`. Inheriting from an Opus parent session was silently turning structured-audit work into Opus-priced work.
- `workflow/agents/test-author.md` — pinned to `sonnet`. Tests are the one place the agent actually writes code, so this stays above haiku, but no longer inherits Opus.
- `workflow/commands/design-gate.md` — passes `changed_files` into the auditor so it doesn't rediscover scope by grepping `frontend_root`. Token-sync and Figma variable diffs are opt-in via `--full`.

### What we deliberately didn't do

- We didn't soften any gate's verdict. PASS/FAIL semantics are unchanged. The cheap path catches the same destructive patterns it always did — earlier and for free.
- We didn't break command argument shapes (`/schema-gate <file>`, `/design-gate <scope>`). Per the framework rule, installs are symlinks; argument shape is a public interface.
- We didn't touch hooks that already ran shell-fast (`migration-guard.sh`, `pre-git-check.sh`). They were already on the right side of the model/no-model line.

### The lesson worth carrying

Gates exist to refuse to let founders skip the parts that matter. But "matters" doesn't mean "needs an LLM." A gate's job is to *be confidently wrong on the unsafe path*, and a regex is more confidently wrong about `DROP TABLE` than any model will be. The model earns its keep on the questions a regex can't answer — *is this 100k-row index going to lock for ten minutes*, *does this new column inherit the right RLS policy*, *does this migration walk away from the documented evolution direction*. Everything else should be a shell script.

If you find yourself paying a 25% session tax on any single command in the framework, ask: how much of that work is the model doing because the work is hard, versus because we never wrote the cheap version?
