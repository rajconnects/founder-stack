# Changelog

All notable changes to Founder Stack are recorded here. The framework is small enough that the *why* matters as much as the *what* — entries are written for the founder reading them six months later, not the bot diffing them next week.

## 2026-05-11 — v1 preview: autonomous missions (orchestrator + worker + scrutiny)

### The realization

The v0.1 workflow is gate-driven but session-oriented: every phase needs a human at both ends. You write the spec, run `/spec-intake`, approve the plan, drive implementation, run `/test-gate` and `/design-gate`, write the handoff. The discipline works — but the founder is the bottleneck. Even when the spec is crisp and the gates would clearly pass, the framework can't run from spec to verified outcome without a person at the keyboard between every step.

Three things made it clear v0.1 was leaving capability on the floor: the Factory Missions architecture (Luke at Factory's three-role talk on missions running 16 days unattended), Boris and Jarred's advanced Claude Code workflow demo on issue → PR autonomy in Bun, and the founder's own request to move up from per-step supervision to vision-and-architecture supervision.

### The fix, in one sentence

**Add an orchestrator that scopes the goal, writes a validation contract for human approval, then dispatches workers and validators on a `/loop` tick until the contract is satisfied — designed for overnight runs.**

### Specifics shipped this release

- `workflow-v1/agents/mission-orchestrator.md` — opus-tier orchestrator. Reads `state.json` as durable memory, dispatches workers and validators via Task tool, decides retry/advance/block at each step, self-paces via `ScheduleWakeup` inside `/loop` dynamic mode.
- `workflow-v1/agents/feature-worker.md` — sonnet-tier. Implements one feature against its contract slice, runs local lint/tsc/tests, emits a structured handoff with `commands_run`, `files_touched`, `contract_coverage`, `issues_discovered` sections (front-matter machine-parsed by orchestrator).
- `workflow-v1/agents/scrutiny-validator.md` — sonnet-tier. Adversarial fresh-context check: re-runs the worker's commands, dispatches v0.1 auditors (`design-auditor`, `schema-analyst`) directly via Task tool when scope warrants, judges contract coverage independently, flags honesty discrepancies (worker claimed exit 0 / file shows exit 1).
- `workflow-v1/agents/memory-broker.md` — haiku-tier. Single seam for cross-mission memory. Local files default; Mem0 over HTTP behind a config flag. Other agents call the broker via Task tool — they never read `memory/` directly. Flipping the Mem0 flag changes nothing in upstream agents.
- `workflow-v1/commands/{mission,mission-tick,mission-status,mission-resume,mission-abort}.md` — five new slash commands. `/mission` runs the synchronous scoping + contract-approval phase, then instructs the user to type `/loop /mission-tick <id>` to enter `/loop` dynamic mode for autonomous execution. Only `/loop` mode lets `ScheduleWakeup` actually fire — the two-step entry is deliberate (contract approval is a checkpoint the user must own) and load-bearing (without it, the loop never starts).
- `workflow-v1/templates/state.schema.json` — JSON Schema for the mission state file. `state.json` is the durable source of truth; the conversation is ephemeral.
- `workflow-v1/templates/mission-contract.template.md` — the contract is written **before** any worker dispatch and locked at user approval. Scrutiny failure triggers a worker retry with the prior handoff and verdict included, not a contract relaxation.
- `workflow-v1/templates/mission-handoff.template.md` — required front-matter and required section order, so scrutiny can parse deterministically.
- `workflow-v1/project.example.v1.json` — additive config schema with documented defaults. All v1 keys optional.
- `workflow-v1/Engineering-Playbook-v1-deltas.md` — thin deltas doc, references v0.1's playbook for shared concepts.
- `scripts/install-v1.sh` — additive installer. Symlinks `workflow-v1/` content into the target repo's `.claude/` alongside v0.1; no v0.1 file is overwritten. Filenames are distinct, so commands and agents coexist in the same directories.
- `docs/missions.md` — user-facing intro with the throwaway-repo verification path.
- `README.md` — adds a one-line v1 preview pointer to `docs/missions.md`.

### What we deliberately didn't do

- We did **not** rewrite v0.1. `workflow/` stays frozen; v1 is `workflow-v1/`. Existing installs that never run `/mission` see zero behavioral change.
- We did **not** ship a `cost_cap_usd` field. The orchestrator cannot introspect its own session spend from inside Claude Code, so a dollar cap with no enforcement path would be theater. `max_dispatches_per_feature` and `max_total_dispatches` are the cost proxies — observable and deterministic.
- We did **not** centralize gate logic. The scrutiny validator dispatches the *same* v0.1 subagent files (`design-auditor`, `schema-analyst`) via Task tool, so there is one source of truth per gate. Slash commands remain unchanged for direct human use.
- We did **not** wire user-flow testing in MVP. The orchestrator auto-skips the `user-test` step when `mission_user_test.preview_url_command` is null. v1.1 adds the Playwright-driven `user-flow-tester` subagent.
- We did **not** integrate GitHub. v1.0 prints a suggested `gh pr create` invocation at completion; v1.1 will accept `--from-issue <url>` and auto-create the PR.
- We did **not** ship cron pacing. `--pace cron` (via `/schedule`) is v1.1 — v1.0 is local-pace only (`ScheduleWakeup` inside `/loop`). MVP requires Claude Code to stay open overnight.

### The autonomy delta, made testable

The MVP's headline behavior is the **retry loop**: worker fails scrutiny → orchestrator re-dispatches with the failed handoff and scrutiny verdict in context, up to `max_dispatches_per_feature`. The verification path in `docs/missions.md` deliberately exercises this with a localStorage-key trap: the contract specifies a specific key (`counter:v1`), the worker is likely to initially pick a generic one, scrutiny fails on AC-3, the worker corrects on dispatch 2. If the orchestrator silently rewrites the contract instead of forcing a retry, the test fails — that's the wrong behavior.

Without that demonstrable delta, v1 would just be a wrapper around v0.1 gates. With it, missions are genuinely autonomous.

### The lesson worth carrying

`state.json` is the load-bearing decision. Treating the conversation as ephemeral and the state file as durable is what lets a single-Opus session run for hours without the orchestrator's context bloating, and what lets `/mission-resume` bootstrap a fresh session cleanly when context does overflow. Every architectural choice flows from that: structured handoffs, machine-parsed verdicts, atomic state writes, retry counts in state rather than conversation. The orchestrator's prompt is a state machine; the conversation is just the engine that drives it.

## 2026-05-06 — Install guide for the messy scenarios + refreshed workflow diagram

### The realization

The README had one install snippet and a stale PNG that predated the design ladder and `/frontend-build`. That's enough for a fresh repo and nothing else. The two scenarios that actually trip people — installing into a codebase that already exists, and installing alongside another harness or user-global commands — were undocumented. We were quietly assuming every user starts from `mkdir my-product`.

The diagram had its own version of the same problem: it showed five stages but said nothing about which commands and agents live in each. A founder reading the README couldn't answer "what runs when I'm in BUILD?" without spelunking through `workflow/commands/`.

### The fix, in one sentence

**Document the three real install scenarios end-to-end, and rebuild the workflow diagram so each stage names the commands and agents that run inside it.**

### Specifics shipped this release

- `docs/install.md` — new. Covers (1) fresh repo, (2) existing repo with no harness, (3) existing harness or user-global commands. Each scenario gets the actual command sequence, things to watch for, and a copy-pasteable verification block. Plus update path, uninstall steps, and a gotchas section (missing python3, moved framework dir, hooks not firing, slash commands not appearing).
- `assets/Workflow-Diagram-2.png` — new. Same five-stage style as the predecessor but each stage now has a translucent tools panel directly beneath it listing the commands, agents, and (for BUILD) auto-firing hooks. INTAKE → PLAN → BUILD → VERIFY → SHIP, with output labels and three starred footnotes carrying over the original tone ("VERIFY earns the right to ship," "hooks fire automatically — no model cost," "reset session between phases").
- `assets/Workflow-Summary.png` — removed. The replacement supersedes it; keeping a stale diagram around is worse than having one.
- `README.md` — embeds the new diagram, removes the prior Mermaid placeholder, and points existing-repo readers at `docs/install.md` from the Quickstart.
- `docs/workflow.md` — adds an "At a glance" Mermaid block before Layer 1 with the design ladder and gate-failure loops drawn explicitly.
- `docs/quickstart.md` — routes existing-repo readers to `install.md` first; expands the "what's next" links to include install + session-hygiene.

### What we deliberately didn't do

- We did not write a Cursor- or Cline-specific install path. The framework is Claude Code-first; the install guide says so explicitly and stops there.
- We did not ship a `--namespace founder` flag or a `doctor` subcommand for scenario 3 — those are real gaps that the doc names as future work, but they're CLI features, not documentation. Filing them as scope for the npm-wrapper conversation, not this release.
- We did not delete `assets/` content blindly. The old PNG was removed because the new one supersedes it; nothing else was touched.
- We did not change install scripts in this release — the `settings.json` wiring fix earlier today was the install change. This release is documentation catching up to reality.

### The lesson worth carrying

The earlier two entries today (model-tier work, then session hygiene) were about cost. This one is about *trust*: when a non-technical founder runs `install.sh` and sees `skip (exists): commands/spec-intake.md` they don't know what to do with that. The framework's whole pitch is that the discipline shouldn't depend on the user's tooling fluency — but the discipline *also* shouldn't depend on the user being lucky enough to start from a clean repo.

Documentation is part of the contract, not a gloss on it. If the install can hit five different states and only one of them is in the README, the framework is harder to adopt than it claims to be.

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
