# Engineering Playbook

The portable engineering workflow that travels with `.claude/`. Copy this tree to any new project, drop in a fresh `project.json`, and the workflow runs.

## The seven layers

```
1.  INTAKE     Spec → executable plan             → /spec-intake
1.5 CHALLENGE  Stress-test plan vs. project memory → /grill         ← optional, before plan approval
2.  PLAN       Plan mode + gated subtasks         → (built-in plan mode)
2.5 ORIENT     Map an unfamiliar code area        → /zoom-out       ← optional, before editing unfamiliar scope
3.  EXECUTE    Implementation with enforced rails → hooks (auto-lint, tsc-check)
4.  VERIFY     Design / test / schema gates ⭐    → /design-gate, /test-gate, /schema-gate
5.  SHIP       Pre-publish + post-deploy smoke    → /publish-gate, /deploy-gate, /handoff
6.  REFLECT    Post-phase architectural review    → /architecture-review  ← optional, between handoff and next start-build
```

Verify (layer 4) gets the sharpest tooling — that's where spec-to-code drift and unsafe migrations do the most damage. Layers 1.5, 2.5, and 6 are optional context-and-coherence layers — adapted from `mattpocock/skills` (`grill-with-docs`, `zoom-out`, `improve-codebase-architecture`) and adopted as portable contracts. Each reads `context_doc`, `glossary_doc`, and `decision_records` from `project.json`.

`/publish-gate` (layer 5, sibling of `/deploy-gate`) catches the "code worked locally but the published tarball is broken" bug class. Run `npm pack` → install in tmpdir → run a smoke command → assert expected output. The complementary inputs `real_corpora` (test-gate input) and `schemas_of_record` (handoff drift check) live in `project.json`. See "Reality-check inputs" below.

## Files in `.claude/`

| Path | Purpose |
|---|---|
| `project.json` | Project self-description. Paths to specs, tokens, migrations, deploy targets. Every agent and hook reads this first. |
| `project.example.json` | Template for new projects. Copy to `project.json` and fill in. |
| `agents/*.md` | Five subagents: `spec-translator`, `design-auditor`, `test-author`, `schema-analyst`, `deploy-verifier`. All read `project.json`. |
| `commands/*.md` | Slash commands: `/spec-intake`, `/grill`, `/zoom-out`, `/design-gate`, `/test-gate`, `/schema-gate`, `/publish-gate`, `/deploy-gate`, `/handoff`, `/architecture-review`, `/start-build`, `/sessions`. Thin wrappers that delegate to subagents. |
| `hooks/*.sh` | Shell scripts wired via `settings.json`: `auto-lint.sh`, `pre-git-check.sh`, `tsc-check.sh`, `migration-guard.sh`, `main-push-guard.sh`. |
| `settings.json` | Portable hook wiring. Committed. |
| `settings.local.json` | Machine-specific permissions. Gitignored. |
| `Engineering-Playbook.md` | This file. |

## Brief readiness (the real input)

A phase's quality ceiling is its brief's quality. Author briefs at the path your project sets in `project.json` (typical: `<build_plans>/component-briefs/AUTHORING.md`) — phase label cross-check, design-source authority, utility-class resolution are caught there, once. Don't build downstream checks for what the brief should catch itself.

## Multi-session coordination

Parallel Claude Code sessions are first-class in the workflow, not an exception. Every phase build runs through `/start-build` (claim + worktree) and `/handoff` (close + teardown). The state file is `.claude/coordination.json`; the human-readable companion is `.claude/coordination.md`.

### Mechanism

| Component | Role |
|---|---|
| `.claude/coordination.json` | Machine-readable session rows: `id`, `resume_id`, `status`, `severity`, `phase`, `branch`, `worktree`, `plan_summary`, `claims`, `started`, `heartbeat`, `completed`. |
| `/start-build <phase>` | Pre-sweep stale rows → conflict-check siblings → run intake (or capture plan summary) → spawn worktree → write claim row. |
| `/sessions [list\|show\|clean]` | Inspect or sweep state. |
| `/handoff <phase>` | Generate handoff doc + close session row + remove worktree (with user confirm). |
| `.claude/scripts/coord-cleanup.sh` | Background sweep for stale rows + orphan worktrees. Run via cron / `/schedule` routine. Never force-removes worktrees with uncommitted work — surfaces them instead. |

### Severity convention

- **Major:** multi-day, multi-file, owns a feature branch (e.g., a phase scope). Sibling sessions **pause** until complete.
- **Minor:** bounded edits — single file, doc tweak, quick fix. Sibling sessions **proceed with caution** if file claims don't overlap.

When in doubt, mark major. The cost of a sibling pausing is much lower than the cost of a stomp.

### At every turn (when sibling terminals may be active)

1. Read `.claude/coordination.json`. Refresh own row's `heartbeat` if `active`.
2. Apply the severity rules above.
3. Append to `.claude/coordination.md` before `git push`, force-push, rebase, branch deletion, migration, or deploy.
4. Surface conflicts to the user — never auto-resolve a claim collision.

### Why this slots in across all layers

The five-layer flow (Intake → Plan → Execute → Verify → Ship) describes *one session's* journey. Coordination describes *between-session* hygiene and applies the moment a second terminal exists. `/start-build` is the gateway; `/handoff` is the exit ramp; `coord-cleanup.sh` is the background safety net.

## The typical phase

A phase takes a spec and produces shippable code, a handoff doc, and decision traces. It runs in this order:

1. `/spec-intake <spec path>` — `spec-translator` reads the spec, emits a structured plan. Enter plan mode.
2. Approve plan. Claude implements per plan.
3. Before writing a new feature: `/test-gate <scope>` — `test-author` writes failing tests establishing the contract.
4. Implement against red tests. Hooks enforce lint (auto-lint.sh) and flag type errors (tsc-check.sh) on every Edit.
5. After a component/screen set is complete: `/design-gate <scope>` — `design-auditor` checks tokens, component contract, a11y, design-source alignment.
6. Before applying a migration: `/schema-gate <migration>` — `schema-analyst` checks additive-only, RLS, data loss, index impact, forward-compat. Queries live DB read-only.
7. After deploy: `/deploy-gate <env>` — `deploy-verifier` runs health checks, Playwright smoke, log scan.
8. End of phase: `/handoff <phase>` — generates handoff doc, updates build-status, prompts decision-trace capture for open items.

## How agents and commands compose with existing skills

| Existing skill | Role in the workflow |
|---|---|
| `dev-cycle` (if installed) | Orchestrator of layer 3→4 pre-ship (lint + test + type-check + security + code review). Called before `/deploy-gate`. |
| `lint`, `test`, `code-review`, `security-review` (if installed) | Components of `dev-cycle`. Keep. |
| `decision-trace-capture` (if installed) | Invoked by `/handoff` for any decisions surfaced during the phase. |
| `auto-lint.sh` hook | Layer 3 rail. |
| `pre-git-check.sh` hook | Layer 3 rail — pre-commit/push lint + test gate. |
| `tsc-check.sh` hook | Layer 3 — warns on TypeScript errors after Edit. Non-blocking. |
| `migration-guard.sh` hook | Layer 4 — soft-warns if editing a migration without `/schema-gate` marker. |
| `main-push-guard.sh` hook | Layer 5 — soft-warns on `git push <primary_branch>` without `/deploy-gate` marker. |

## Session markers

Gates write small marker files so hooks and downstream commands know what passed in the current session:

- `.claude/.schema-gate-passed` — `/schema-gate` returned PASS
- `.claude/.deploy-gate-passed-<env>` — `/deploy-gate <env>` returned PASS
- `.claude/.design-gate-passed` — `/design-gate` returned PASS (optional)
- `.claude/.publish-gate-passed-<artifact>` — `/publish-gate` returned PASS

These are session-scoped and gitignored. They're advisory — not a hard lock. A missing marker triggers a warning, not a block.

## Portability

Everything under `.claude/` is portable. To move the workflow to a new project:

1. Copy `.claude/` directory into the new repo.
2. Copy `.claude/project.example.json` → `.claude/project.json`; edit the paths.
3. Commit `.claude/` (including `project.json` and `settings.json`).
4. Gitignore `.claude/settings.local.json`, `.claude/.schema-gate-passed`, `.claude/.deploy-gate-passed-*`, `.claude/.design-gate-passed`, `.claude/.publish-gate-passed-*`.
5. Confirm `Read` / `Grep` / `Bash` permissions for the new repo's paths.

If `stack.db` does not match a supported provider, `schema-analyst` errors out — either adapt `project.json` or extend the agent with alternative DB tools.

If `design_system.figma.file_key` is null, the Figma step in `design-auditor` is skipped automatically.

## Gate assignment — which gate enforces which criterion

Acceptance criteria that require a running app, network, or DOM do NOT belong in `/design-gate` (which only reads files and design-source data). Assign as follows:

| Criterion type | Gate | Why |
|---|---|---|
| Token usage, hex literals, a11y attributes in source | `/design-gate` | Static code read is sufficient |
| Component contract (props, variants) from spec | `/design-gate` | Static code read is sufficient |
| Design-source alignment (variable match, visual) | `/design-gate` | Design MCP available; static comparison |
| Color contrast (axe-core), focus rings in running DOM | `/deploy-gate` | Needs a browser; Playwright smoke with axe-core |
| Performance (TTI <500ms, transition <200ms) | `/deploy-gate` | Needs Playwright timing API against deployed env |
| Keyboard-only full journey | `/deploy-gate` | Needs a browser with Playwright keyboard simulation |
| Unit / integration behavior | `/test-gate` | Test framework invokes |
| RLS, data-loss risk, schema safety | `/schema-gate` | Live DB query needed |
| Published artifact installs and runs | `/publish-gate` | Pack + install in tmpdir |

If `project.json` has `test_commands.frontend: null`, `/test-gate` for frontend scope errors out until a runner is installed. axe-core dependency alone is not sufficient — it needs a test runner.

## Bounded vs. open scope

Not every phase deserves the full flow. Match tooling to task size.

| Signal | Shape |
|---|---|
| Brief enumerates ≤5 tests, contract fits in one paragraph | **Bounded** — main agent writes tests inline in `/test-gate`; `/spec-intake` is optional if the brief already lists subtasks |
| Prose criteria, >5 test cases, ambiguous contract, or cross-cutting change | **Open** — full flow: `/spec-intake` → subagent test-author → `/design-gate` → `/schema-gate` |

Delegation has overhead (prompt, context handoff, review). For bounded work the overhead dominates; main agent does the work directly. The `test-gate` command classifies and branches automatically — see `commands/test-gate.md`.

**Still mandatory for bounded work:** `/design-gate` (static token + design-source audit) and, for UI work, `/deploy-gate` runtime checks. Gates are the whole point; delegation within a gate is the cost-control lever.

## Config rot as a tax of doing business

Test runners break (JSX runtime drift, polyfill gaps, stale deps). `npm install` hangs. Hooks rot. These are environment issues, not workflow issues — don't instrument against them. Budget ~15 min per phase to fix whatever rotted since last touch, fix it inline, and keep moving. A pre-flight guard for every gate would cost more than it saves.

## Reference assets vs. authoritative specs

Some projects keep static mockup files (e.g., HTML/PDF visual references) during design sprints. These are NOT authoritative — the `design-auditor` compares only against `design_system.components_spec`, `flow_spec`, `tokens`, `copy_guide`, and `figma` from `project.json`. Mockups are historical artifacts; drift between mockups and spec is expected.

## Subagent registration requires a session restart

Files added under `.claude/agents/` and `.claude/commands/` are picked up when Claude Code starts a new session. Adding an agent file mid-session does NOT make it callable via the Agent tool in that session — the tool returns `Agent type '<name>' not found`. Restart Claude Code after creating or editing agent/command files.

Slash commands invoked via `Skill` follow the same rule: the skill list is bound at session start.

## Anti-patterns

- **Don't invoke subagents directly from the main session.** Always go through the slash command — the command handles argument parsing, scope resolution, and session markers.
- **Don't translate specs yourself in the main session** for open-ended scope. Use `/spec-intake`. For bounded scope (brief already lists subtasks), skip intake — read the brief and go.
- **Don't edit agent or command files with project-specific paths.** Everything project-specific goes in `project.json`.
- **Don't skip `/test-gate` to "move fast."** Implementation without a contract is what causes spec drift. The gate is the whole point.
- **Don't run `/deploy-gate prod` without confirmation.** The command asks; don't bypass.
- **Don't commit session markers.** They're per-session state, gitignored.

## Fail modes and recovery

| Symptom | Likely cause | Recovery |
|---|---|---|
| `ERROR: .claude/project.json missing or invalid` from any agent | Config file deleted or malformed | Restore from `project.example.json`, fill in paths |
| `/design-gate` always returns FAIL on tokens | Hex literals in code, tokens.css not linked | Fix hex literals OR update `design_system.tokens` path in project.json |
| `/schema-gate` skips live-state checks | DB MCP not authenticated | Surface warning, don't block; authenticate and re-run |
| `/deploy-gate` times out | Deploy target URL wrong or app down | Fix `deploy_targets.<env>.url`; verify app health out-of-band |
| `tsc-check.sh` prints errors on every edit | Pre-existing type debt | Fix type debt or accept the noise; hook is non-blocking |
| Main-push-guard warns even after `/deploy-gate` | Marker cleared between sessions | Re-run `/deploy-gate` in the current session; markers are session-scoped |

## Extending the workflow

Add a new gate:
1. Write `.claude/agents/<gate>-auditor.md` with constrained tools and a clear output format.
2. Write `.claude/commands/<gate>-gate.md` that delegates to the agent.
3. If blocking, add a hook in `.claude/settings.json` that checks for the marker.
4. Update this Playbook's "The typical phase" section.

Keep gates narrow. Each one answers one question (design drift? schema risk? deploy health?). Don't combine.

## The three context-and-coherence commands

Three commands adapted from `mattpocock/skills` to fill genuine gaps in the workflow without duplicating existing gates. All three read `context_doc`, `glossary_doc`, `glossary_anchor`, and `decision_records` from `project.json` — zero project-specific names hardcoded.

| Command | Layer | When it fires | What it does |
|---|---|---|---|
| `/grill <plan>` | 1.5 | Between `/spec-intake` and plan-mode approval | Walks plan against project context doc + glossary + resolved decision records, one branch at a time. Surfaces glossary conflicts, fuzzy terms, prior-decision contradictions. Updates glossary inline. |
| `/zoom-out <area>` | 2.5 | Before editing unfamiliar code | Builds a glossary-aware map: callers, dependencies, siblings, tests, relevant decision records, architecture notes. Read-only. |
| `/architecture-review <scope>` | 6 | Between `/handoff` and next `/start-build` | Surfaces deepening opportunities (shallow modules, leaky seams). Uses domain glossary for naming, decision records to avoid re-litigation. Candidates only — no interface design. |

### Decision-records format support

`decision_records.format` in `project.json` selects the parser:
- `json-traces` — decision-trace JSON (with `topic`, `status`, `resolution_summary`, `revisit_trigger`).
- `markdown-adr` — standard ADR markdown (title + Decision + Consequences sections).
- `mixed` — both, in the same directory.

Adding a new format means extending the loader inside the three commands; the rest of the contract is format-agnostic.

### Why these are commands, not skills

They run in-conversation, are user-invoked, and produce outputs the user reviews directly. Skills are for delegated, prompt-loaded sub-tasks. The three live in `.claude/commands/` for the same reason `/spec-intake` does.

## Reality-check inputs

The context-and-coherence commands give the workflow a **before-acting** layer (do you understand the context?). The reality-check inputs give it an **after-acting** layer (does the artifact actually work?). Both share the same pattern: declare what matters in `project.json`, gates parameterize on it.

| `project.json` key | Read by | What it catches |
|---|---|---|
| `release_artifacts[]` | `/publish-gate` (layer 5) | Files referenced from `package.json` but missing from the `files` allowlist; postinstall hooks that crash on consumer install; stale `dist/` from a forgotten build. The "code worked locally, tarball is broken" bug class. |
| `real_corpora[]` | `/test-gate` (layer 4) | Tests pass against synthetic fixtures but reject real on-disk artifacts. Catches schema-too-strict, missing-field-in-fixture, vocabulary drift between code and reality. |
| `schemas_of_record[]` | `/handoff` (layer 5) | Protocol/spec drift across the canonical site (e.g. JSON Schema) and shadow sites (Zod validator, producer templates, prose docs). Soft check that surfaces touch-one-but-not-the-others mismatches. |

### Why these are config, not gates of their own

A gate has a single job (one question, one verdict). A config field tells an existing gate where to look. `release_artifacts` is "where my publishable thing is + how to smoke it." `real_corpora` is "where my real-world fixtures live + how to validate them." Adding new gates would inflate the workflow surface area; teaching existing gates new tricks via config does not.

### The bug class each one targets

- **`release_artifacts`** — a published package whose `postinstall` hook references a file missing from the `files` allowlist. `prepublishOnly` runs unit tests against the source tree, which has the file. Only a fresh-consumer install catches the breakage.
- **`real_corpora`** — a schema change makes a field required. The fixture has it. The real on-disk corpus does not. Tests pass; production rejects actual data.
- **`schemas_of_record`** — a producer template diverges from the canonical schema over multiple releases because nothing checked them against each other. Reader rejects valid producer output.

## Portability checklist (for porting `.claude/` to a new project)

1. Copy `.claude/` to the new repo.
2. `cp .claude/project.example.json .claude/project.json`. Edit paths.
3. **Required for the seven-layer flow:**
   - `spec_roots`, `test_commands`, `test_roots`, `migrations`, `deploy_targets`, `decision_traces`, `handoff_template`, `handoff_output_dir`, `build_status_file` — for layers 1, 3, 4, 5.
4. **Required additionally for layers 1.5, 2.5, and 6:**
   - `context_doc` — path to the project's primary thesis/context document (e.g. `CLAUDE.md`, `CONTEXT.md`, `README.md` if minimal).
   - `glossary_doc` + `glossary_anchor` — where the project's domain vocabulary lives (file path + heading anchor).
   - `decision_records.path` + `decision_records.format` — directory + parser format (`json-traces` | `markdown-adr` | `mixed`).
   - `architecture_notes` (optional) — directory of long-form architecture memos.
5. **Required additionally for the reality-check inputs:**
   - `release_artifacts[]` — for `/publish-gate`. Omit if the project doesn't ship a packaged artifact.
   - `real_corpora[]` — for `/test-gate`'s real-corpus step. Omit if no on-disk fixture set exists.
   - `schemas_of_record[]` — for `/handoff`'s drift check. Omit if the project doesn't maintain a shared schema across multiple sites.
6. Gitignore `settings.local.json`, `.schema-gate-passed`, `.deploy-gate-passed-*`, `.design-gate-passed`, `.publish-gate-passed-*`.
7. Confirm `Read` / `Grep` / `Bash` permissions for the new repo's paths.
8. Restart Claude Code so new commands and agents are picked up.

If `context_doc` or `decision_records` is null, `/grill`, `/zoom-out`, and `/architecture-review` degrade gracefully — they print a one-line "no context configured" warning and run with reduced fidelity. Same for the reality-check inputs: omit the array, the relevant gate-step is skipped. The seven-layer flow still runs unchanged.

If `stack.db` does not match a supported provider, `/schema-gate` errors out (unchanged behavior).

If `design_system.figma.file_key` is null, the design-source step is skipped (unchanged behavior).
