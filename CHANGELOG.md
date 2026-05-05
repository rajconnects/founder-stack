# Changelog

All notable changes to Founder Stack are recorded here. The framework is small enough that the *why* matters as much as the *what* — entries are written for the founder reading them six months later, not the bot diffing them next week.

## 2026-05-06 — Hooks now actually fire after install

### The realization

While sketching the npm packaging tradeoffs against three install scenarios (fresh repo, existing repo with no harness, existing repo with another harness) we found a real bug, not a packaging question. `install.sh` symlinked `workflow/hooks/*.sh` into `.claude/hooks/` and stopped there. Claude Code does not fire hooks just because the files exist — it fires them because entries in `.claude/settings.json` register them under specific events and matchers. The framework was shipping the *scripts* without the *registration*, which meant every install required the user to hand-edit JSON to make `auto-lint`, `tsc-check`, `pre-git-check`, `main-push-guard`, and `migration-guard` actually run.

Hand-editing JSON is exactly the friction the framework's audience can't absorb.

### The fix, in one sentence

**Make `install.sh` idempotently merge hook entries into `.claude/settings.json`, preserving any pre-existing user configuration.**

### Specifics shipped this release

- `scripts/wire-hooks.py` — new file. Stdlib-only (no jq dependency). Reads the existing `settings.json` (or creates it), registers each framework hook under the correct event (`PreToolUse` / `PostToolUse`) and matcher (`Bash` / `Edit|Write`), and dedupes by script filename so re-running install adds zero duplicates. User-authored entries — other hooks, permissions blocks, `Stop` event handlers — are left untouched.
- `scripts/install.sh` — invokes `wire-hooks.py` after the symlink loop. If `python3` is missing or the merger fails, install continues with a clear warning rather than aborting. The skip path tells the user exactly which command to run by hand.
- Hook → event mapping is now canonical: `auto-lint.sh` and `tsc-check.sh` on `PostToolUse Edit|Write`; `pre-git-check.sh` and `main-push-guard.sh` on `PreToolUse Bash`; `migration-guard.sh` on `PreToolUse Edit|Write`. `schema-static-scan.sh` deliberately stays out — it is invoked from inside `/schema-gate`, not registered as a Claude Code hook.

### What we deliberately didn't do

- We did not add jq, npm, or any new tooling dependency. The merger uses python3, which the hook scripts already require.
- We did not auto-`chmod +x` symlinked hook scripts. The source files in `workflow/hooks/` are already executable; the symlinks inherit that.
- We did not touch `init-project.sh`. Hook wiring is a property of the install, not project setup; conflating the two would re-wire on every project init and surprise users.
- We did not ship any of the other npm-packaging scope (CLI wrapper, namespace flag, `doctor` subcommand). Those are scenario-3 features and remain open work; this fix lives entirely in the existing bash install path.

### The lesson worth carrying

Yesterday's two entries were about token cost — per-call (model tier, tool surface) and cross-call (session hygiene). Today's is about a different kind of cost: the hand-editing tax the install was silently charging every user. Same shape of question, different axis: *what work are we asking the user to do because we never wrote the cheap version?*

The framework's whole pitch is that the discipline shouldn't depend on the user's tooling fluency. An install that works only after the user has opened JSON in a text editor was a quiet contradiction of that pitch. It is no longer.

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
