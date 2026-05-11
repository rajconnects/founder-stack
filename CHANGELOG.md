# Changelog

All notable changes to Founder Stack are recorded here. The framework is small enough that the *why* matters as much as the *what* — entries are written for the founder reading them six months later, not the bot diffing them next week.

## 2026-05-11 — v1 missions: docs-auditor catches drift between docs and the actual repo

### The realization

The framework's CLAUDE.md is explicit: this is a published framework, every file in `workflow/` and `workflow-v1/` ends up symlinked into someone else's project, every command and agent is a public interface. So when a README mentions `/spec-intake` that's been renamed, or a CHANGELOG bullet claims a file that was never committed, or `project.example.v1.json` has a key no agent reads — that drift lands directly in user installs as silently-broken behavior. The risk is highest at exactly the surfaces non-technical founders read first: README, CHANGELOG, the playbook, the install guide.

Every other gate the framework ships is for *code* drift. The framework's own *documentation* has been hand-maintained — which works until it doesn't. The three earlier v1.1 commits today landed before this one and each surfaced a small docs cleanup as part of the work; with `docs-auditor` running, that catching happens deterministically instead of by my noticing.

### The fix, in one sentence

**Ship `docs-auditor` (haiku) that runs four passes over framework documentation — broken file refs, dead slash-command refs, unused `project.example.*.json` keys, advisory CHANGELOG-vs-diff — exposed as `/docs-gate` for humans and auto-dispatched by `mission-orchestrator` in Procedure D before the memory write.**

### Specifics shipped this release

- `workflow-v1/agents/docs-auditor.md` — new agent. Read-only tool surface (Read, Grep, Glob, Bash for `git diff`). Four passes:
  - **(a) Broken file references.** Inline code spans containing `/` or known extensions, and markdown links to relative paths — verifies each exists on disk. Skips fenced-block examples and template placeholders.
  - **(b) Dead slash-command references.** Greps for `/<name>` patterns; checks each against `workflow*/commands/<name>.md`. Allowlists built-in Claude Code commands (`/clear`, `/loop`, `/schedule`, etc.) so they don't flag.
  - **(c) Unused config keys.** For each top-level key in `workflow/project.example.json` and `workflow-v1/project.example.v1.json`, greps across `workflow*/agents/`, `workflow*/commands/`, `workflow*/hooks/`, playbooks, and docs. Zero matches → flag. Skips `_comment` keys.
  - **(d) CHANGELOG-vs-diff (advisory only).** Compares the top CHANGELOG entry's "Specifics shipped" bullets against `git diff --name-only` over the relevant range. Surfaces overclaim (entry names a file not in the diff) and underclaim (substantive file change with no bullet mention). Uses haiku-tier judgment to ignore trivial diffs (whitespace, comment tweaks).

  Verdict structure: PASS if passes a–c return zero flags; pass d is informational. FAIL otherwise.
- `workflow-v1/commands/docs-gate.md` — new slash command. Args: scope (`changelog | readme | playbook | docs | full`, default `full`) and optional `--range <git-range>` for pass d. Dispatches `docs-auditor`, prints verdict verbatim, does not auto-fix. The user owns drift resolution (sometimes a "broken" link is a real removal).
- `workflow-v1/agents/mission-orchestrator.md` — Procedure D step 2 now auto-dispatches `docs-auditor` with `SCOPE: mission-completion` before composing the summary or writing memory. A FAIL doesn't block mission completion (code correctness is the gate; docs drift is a separate human concern) — the completion summary surfaces the gap and points to `handoffs/docs-audit.md`. Remaining Procedure D steps renumbered 3–9.
- `workflow-v1/Engineering-Playbook-v1-deltas.md` — new "Docs drift detection" section before the two-validators section. Adds a `docs-auditor` row to the roles table. Removes the corresponding v1.1 roadmap line.
- `docs/missions.md` — roles table now lists `docs-auditor`. "What v1.0 doesn't do yet" loses the docs-auditor line.
- `scripts/install-v1.sh` — no change needed; the install loop already iterates over every file in `workflow-v1/agents/` and `workflow-v1/commands/`, so the new files ship automatically. (Validated by re-reading the install script.)

### What we deliberately didn't do

- We did **not** make the docs-auditor write or rewrite docs. It only reports. A "broken file ref" might be a real removal the user wants to keep — the human resolves. Auto-fixing risks confidently silencing real signals.
- We did **not** gate mission completion on docs PASS. Code correctness gates the mission; docs drift is a separate concern surfaced for the human to fix before merging the PR. Making docs a hard gate would block missions that successfully shipped code over a typo in the CHANGELOG — the wrong trade.
- We did **not** ship a Markdown linter, link-checker, or grammar tool. Plenty exist (markdownlint, lychee, alex). The docs-auditor is scoped specifically to framework-as-public-interface drift — drift that's invisible to general-purpose linters because they don't know the framework's command inventory or config schema. The two aren't substitutes; users can run both.
- We did **not** scan v0.1's `workflow/` for unused config keys against v1's project.example.v1.json (or vice versa). Each file is checked against its own consumer set. Cross-version drift is a separate, harder problem — flagged for v1.2 if it bites.
- We did **not** flag every `/`-separated string as a path or every `/foo` as a slash-command. Pass (a) requires either a directory anchor (`./`, `workflow/`, `docs/`, etc.) or a known file extension; tool-list patterns like `Edit/Write/Read` are explicitly excluded. Pass (b) only matches commands inside backticks (the framework's docs convention) and skips lines containing `://`. Without these tighteners, the first `/docs-gate full` run on this very repo would flag dozens of false positives and train the user to ignore the gate — exactly the failure mode "deterministic where possible" discipline exists to prevent.
- The auditor's framework-mode passes (b) and (c) **degrade to no-ops in user product installs** where the framework source tree isn't at the root — `.claude/` is symlinks, not source. Pass (a) and the advisory (d) still catch broken refs and CHANGELOG drift in the user's own docs. v1.2 adds an explicit mode flag for more aggressive user-product scanning.

### The lesson worth carrying

The framework's discipline has been: deterministic where possible, agent for genuine judgment. Docs drift fits that template precisely — broken refs and dead commands are bash-checkable; CHANGELOG-vs-diff is judgment. By making the deterministic passes hard-gate the verdict and the judgment pass advisory-only, the agent contributes value where it's irreplaceable (recognizing meaningful vs. trivial diffs) without false-positiving on the parts where bash already knows the answer. Most of the docs-auditor's runtime is grep and stat — and that's the right shape. The agent is the inspector of last resort, not the primary worker.

## 2026-05-11 — v1 missions: `--pace cron` for laptop-asleep overnight runs

### The realization

Local pace was always a half-step toward true autonomy. It lets you walk away from the terminal, but Claude Code has to stay open — meaning your laptop has to stay awake, on AC, with the network up. The "overnight" promise of v1 leaks at exactly the moment most founders actually leave: lid closes, machine sleeps, mission stalls until morning when you wake the laptop and the `/loop` resumes from wherever `ScheduleWakeup` last fired.

The `/schedule` skill exists for exactly this case — cron-managed remote agents that run independently of your local session. The wiring was straightforward once we recognized that the orchestrator's "ephemeral conversation, durable `state.json`" pattern was already what cron mode requires: every cron fire is a fresh session that bootstraps from state.json, runs one tick, exits. The conversation has no reason to persist between ticks — the loop pattern in local mode already simulates this; cron just makes it real.

### The fix, in one sentence

**Add `--pace cron` to `/mission`: after contract approval, `/mission` invokes the `/schedule` skill via the Skill tool to create a routine named `mission-<id>` that fires `/mission-tick <id>` every `mission_caps.cron_interval_minutes` minutes; the routine auto-deletes when the mission reaches a terminal status.**

### Specifics shipped this release

- `workflow-v1/commands/mission.md` — step 5 adds the cron-pace branch: after the orchestrator returns successfully with `pace cron`, invoke the `/schedule` skill via the Skill tool to create the routine. If creation fails, surface the error and tell the user they can fall back to `/loop /mission-tick <id>` (local). The contract and state are still valid — only the autonomous tick path is lost.
- `workflow-v1/commands/mission-tick.md` — step 5 adds the cron-pace cleanup: when the orchestrator's return shows `pace cron` AND status is terminal (`completed`, `aborted`, `blocked`), invoke `/schedule` to delete the routine. If deletion fails (already gone), log warning but don't fail — the next cron fire would see terminal status anyway and exit cleanly.
- `workflow-v1/commands/mission-abort.md` — new step 8: read state.json, and if `state.pace == "cron"`, invoke `/schedule` to delete the routine. Abort is intentional; we always clean up.
- `workflow-v1/commands/mission-resume.md` — if `state.pace == "cron"`, re-create the routine after the orchestrator resumes state (the routine may have been auto-deleted on a prior terminal transition, or manually removed).
- `workflow-v1/agents/mission-orchestrator.md` — Procedure A step 8 now branches on `pace`: local-mode prints the `/loop /mission-tick` instructions; cron-mode prints a different message explaining that `/mission` will create the routine. Procedure B (tick) skips the `ScheduleWakeup` call in cron mode — the next tick is cron-driven, not session-driven. The return line now includes `pace <pace>` so the dispatching slash command knows which lifecycle to follow.
- `workflow-v1/project.example.v1.json` — `mission_caps.cron_interval_minutes` added (default 10). Documented range 5-60; below 5 hits `/schedule` minimums.
- `workflow-v1/Engineering-Playbook-v1-deltas.md` — pacing section rewritten with both modes side by side: local for desk-machine overnight runs, cron for truly laptop-asleep runs. Removes `--pace cron` from the v1.1 deferred list.
- `docs/missions.md` — adds a "Laptop-asleep overnight runs (`--pace cron`)" section with the trade-off framing.

### What we deliberately didn't do

- We did **not** dynamically tune `cron_interval_minutes` based on mission step. The orchestrator can't reach into the cron schedule to change its own interval — cron is a fixed cadence. If a mission is idle (waiting on a deploy preview), it ticks at the same rate as when it's actively dispatching. Local pace handles this with `default_wake_idle_secs`; cron does not. The right next iteration if this matters is a `cron_idle_interval_minutes` that the orchestrator can request `/schedule` to update — but that's complexity for an edge case. v1.0 keeps it simple.
- We did **not** mix cron and local pacing within a mission. Once you pick at `/mission` time, the mission stays that pace until it terminates. You can `/mission-abort` and start fresh in the other mode, but mid-mission flips would require state.json migration logic for a small benefit.
- We did **not** use `CronCreate` / `CronDelete` directly from the slash command. Going through the `/schedule` skill keeps the abstraction at the skill level, where the user already manages other cron jobs. If `/schedule` evolves (e.g., adds tags, history, manual run), missions inherit those improvements automatically.
- We did **not** show cron run history in `/mission-status`. Out of scope for v1.1 — the orchestrator's `log.md` already captures every tick's verdict, which is the founder-readable view. `/schedule list` shows the routine state for debugging.

### The lesson worth carrying

Cron mode revealed how much architectural value sat in v1.0's "ephemeral conversation, durable state.json" decision. We made it for context-overflow resilience — to let `/mission-resume` bootstrap a fresh session — but the same property is what makes cron mode work without any state-machine refactor. The conversation was already disposable; cron just removed the requirement that consecutive ticks share a process. Whenever a framework's storage layer is honest about what's truly persistent vs. ephemeral, capabilities that look like new infrastructure often turn out to be a small wrapper. The work in this release was 90% documentation and 10% skill invocation — the substance had already been built.

## 2026-05-11 — v1 missions: GitHub integration (issue → mission → PR)

### The realization

Boris and Jarred's advanced Claude Code workflow video framed the natural unit of work as `issue → repro → fix → tests → PR`. v1.0 missions can do all the middle steps autonomously, but the endpoints — pulling context from an issue, and opening a PR from the result — were the human's job. That means the autonomy guarantee leaks at exactly the points where teams already have shared conventions: issue tracking and code review. A founder who wants the orchestrator to "work the issue queue overnight" can't ask it to start from `#42`, and at the end of a successful run, the founder still has to context-switch back into shell mode to push the branch and craft the PR body.

The mechanics are small (a `gh issue view` here, a `gh pr create` there), but the framing matters: missions should be a complete loop, not a middle slice that demands manual bookends.

### The fix, in one sentence

**Add `/mission --from-issue <url>` to seed the contract from a GitHub issue's title+body, and `--auto-pr` (per-mission flag, or `github.auto_pr_on_completion` in `project.json` for project-wide default) to make the orchestrator push the mission branch and run `gh pr create` automatically on completion — never merging, only opening.**

### Specifics shipped this release

- `workflow-v1/commands/mission.md` — accepts `--from-issue <url>`, `--auto-pr`. Argument parsing now distinguishes flags from positional goal text; the dispatching prompt to the orchestrator carries `ISSUE_URL` and `AUTO_PR` fields explicitly.
- `workflow-v1/agents/mission-orchestrator.md` — Procedure A step 1b: when `ISSUE_URL != "none"`, calls `gh issue view <url> --json title,body,state,labels`, validates the URL pattern, surfaces gh failures verbatim (missing auth, issue not found), warns and confirms on closed issues, and uses `title + body` as the goal seed for contract authoring. The contract is still authored from scratch and approved by the user — the issue is context, not contract. Procedure D step 7: when `state.github.auto_pr == true`, pushes the mission branch (`git push -u origin <branch>` from inside the worktree), composes a PR body from the contract scope + per-feature AC checkmarks + scrutiny/user-test PASS summary + retry counts + `Closes <issue-url>` if applicable, runs `gh pr create`, captures the URL into `state.github.pr_url`. On push or PR-create failure, falls back to the default-path manual command print — the run isn't a total loss.
- `workflow-v1/templates/state.schema.json` — `github` object gains `auto_pr` boolean (default false). `issue_url` and `pr_url` already existed; they're now actually populated.
- `workflow-v1/project.example.v1.json` — new top-level `github.auto_pr_on_completion` (default `false`) for projects that want auto-PR as the default for every mission. Per-mission `--auto-pr` flag overrides.
- `workflow-v1/Engineering-Playbook-v1-deltas.md` — new "GitHub integration" section between the roles table and pacing. Removes the two corresponding lines from the v1.1 roadmap.
- `docs/missions.md` — adds a "GitHub: issue → PR in one command" section showing the combined `--from-issue ... --auto-pr` invocation.

### What we deliberately didn't do

- We did **not** make the orchestrator merge PRs. Even with `--auto-pr`, only `gh pr create` runs; merge is always human. The whole point of v1's "founder operates at architecture and verification" framing is that someone competent must look at the diff before it lands. Auto-merge would defeat that with no upside — the time saved is trivial relative to the trust cost.
- We did **not** install or auth `gh` for the user. If the CLI is missing or unauthenticated, the orchestrator surfaces the error and stops the affected step (issue fetch fails the mission setup; PR create falls back to manual). Installation is a one-time setup the user owns.
- We did **not** parse the issue body as a contract. The orchestrator authors the contract from the issue context the same way it does from a typed goal — the human reviews and approves it. An issue body is a hint, not a spec, and treating it as a spec would skip the approval ritual that's the load-bearing checkpoint.
- We did **not** add `--from-pr` for review missions. A natural follow-on, but a different mission shape (worker reads a diff, not writes code) — deferring to v1.2 alongside `framework_self_evolution`.

### The lesson worth carrying

The endpoints of an autonomous workflow are where the framework either earns or loses adoption. The middle (worker → scrutiny → user-flow tester) is what's algorithmically interesting; the bookends (where work comes from, where it lands) are where the framework either fits into a team's existing rhythm or doesn't. Issue-to-PR is the universal rhythm for any team using GitHub — making missions speak that rhythm natively cost two `bash -c 'gh …'` calls and an assembled markdown body, and it's the cheapest interface affordance v1 will ever ship.

## 2026-05-11 — v1 missions: user-flow-tester closes the "code compiles" → "feature works" gap

### The realization

After yesterday's MVP, a passing mission meant: code compiles, lint passes, tests pass, design-auditor and schema-analyst found no gaps. That's the **scrutiny** validator's domain — static and local. What it doesn't catch: features that compile and pass unit tests but **don't actually work** when a user opens the browser. The Factory talk that framed v1's architecture was explicit about this: scrutiny + user-testing are deliberately separate roles, because they catch different failure classes.

In the MVP, the `current_step: user-test` branch was a stub that wrote `verdicts.<fid>.user_test = "skipped"` and proceeded. So a mission could `status: completed` with the feature visibly broken in a browser — exactly the kind of false PASS the framework is supposed to prevent.

### The fix, in one sentence

**Ship `user-flow-tester` (sonnet) that drives a real browser via Playwright MCP, executes the contract's `User flows` block, and emits PASS/FAIL with screenshots + console capture — and wire the orchestrator to dispatch it instead of skipping.**

### Specifics shipped this release

- `workflow-v1/agents/user-flow-tester.md` — new agent file. Tool surface scoped to `mcp__playwright__*` (browser_navigate, browser_snapshot, browser_click, browser_type, browser_press_key, browser_take_screenshot, browser_console_messages, browser_network_requests, browser_evaluate, browser_close, etc.) plus Read/Grep/Bash. Procedure: parse contract's `User flows` block; for each UF-N, snapshot the page, parse the natural-language verbs (Navigate to X, Click Y, Reload, Assert Z), execute against the preview URL, capture a screenshot to `<mission_root>/<id>/artifacts/<fid>-uf<N>.png`, capture console errors and failed network requests, judge PASS or FAIL with a specific reason citing the failing verb. Overall verdict is PASS iff every UF PASSes AND zero console errors AND zero failed network requests.
- `workflow-v1/agents/mission-orchestrator.md` — replaced the v1.0 `user-test` skip stub with a real dispatch. The orchestrator now: (a) reads `mission_user_test.preview_url_command`, (b) `bash -c`'s it to capture the URL, (c) dispatches `user-flow-tester` with `PREVIEW_URL` and `ARTIFACTS_DIR`, (d) processes the verdict with the same retry semantics as scrutiny — FAIL re-dispatches the worker with the user-test verdict in `PRIOR_USER_TEST_VERDICT`. A FAIL from `preview_url_command` itself (exit != 0 or empty stdout) transitions the mission to `status: blocked` with a clear error, rather than silently advancing.
- `workflow-v1/agents/feature-worker.md` — step 1 now requires `PRIOR_USER_TEST_VERDICT` alongside `PRIOR_SCRUTINY_VERDICT`. Step 3 explicitly branches on which one is populated: a scrutiny FAIL retry focuses on static fixes (compile, tests, lint, design tokens, contract coverage); a user-test FAIL retry focuses on runtime fixes (hydration, async, state-persistence, event handlers). Worker is instructed **not** to over-correct — fix the failed class only. Without this split, runtime-failure retries would inherit the static-failure mental model and the worker would rewrite working code.
- `workflow-v1/project.example.v1.json` — `mission_user_test.preview_url_command` comment refreshed with two concrete recipes: (a) dev server already running (`echo http://localhost:5173`), (b) start-on-demand (`cd $CLAUDE_PROJECT_DIR/missions/$MISSION_ID/worktree && nohup npm run dev … & sleep 8 && echo …`). Documents the v1.0 caveat that mission-started dev servers are not auto-stopped (roadmap: `preview_server_stop_command` in v1.2). Adds `fail_on_console_errors` and `fail_on_failed_requests` flags (both default `false`) — console errors and 4xx/5xx requests are recorded in every verdict but **advisory by default**, since real apps boot with third-party noise (React DevTools, deprecated-API warnings, HMR chatter) that would otherwise cause spurious retries exhausting caps without surfacing real bugs. Flip to `true` when the app's console is genuinely expected to be clean.
- `workflow-v1/templates/mission-contract.template.md` — refreshed the `User flows` section: removes the stale "skip in MVP" parenthetical (the tester ships in this commit) and adds the verb vocabulary the tester parses (*Navigate to*, *Click <label>*, *Type X into <field>*, *Reload*, *Wait for X*, *Assert <claim>*) so contract authors know exactly which English maps to executable actions.
- `workflow-v1/Engineering-Playbook-v1-deltas.md` — adds a `user-flow-tester` row to the roles table and a "Two validators, two failure classes" section explaining the scrutiny-vs-user-test failure-class split and why the retry context differs between them. Removes user-flow-tester from the v1.1 deferred list (it's now shipped).
- `docs/missions.md` — adds a roles-table entry for `user-flow-tester`, plus an "Enabling user-flow testing" section with both recipes inline. Updates the "What v1.0 doesn't do yet" list to remove the user-flow line and add the v1.1 items that are still ahead (docs-auditor, container isolation, cron pacing, GitHub integration, Mem0 semantic search).

### What we deliberately didn't do

- We did **not** ship dev-server lifecycle management. The orchestrator runs `preview_url_command` once at the start of `user-test`; it does not start, stop, or restart servers. If your command starts a background server, you own cleaning it up. Documented loudly in the project.example.v1.json comment, with a roadmap line for `preview_server_stop_command` when the friction warrants it.
- We did **not** parse the user-flow grammar formally. The verbs are natural-language and a sonnet-tier agent reads them as English. This deliberately keeps contracts human-authored — no DSL to learn — at the cost of occasional verb ambiguity that the tester surfaces as a FAIL with `"ambiguous element: N matches for '<label>'"`. The right next iteration if this becomes a recurring failure is a contract authoring helper, not a flow-grammar parser.
- We did **not** wire visual regression. Screenshots are captured for human review and audit, but the tester doesn't compare them to a baseline. `mcp__glance__visual_baseline` and `visual_compare` exist and would slot in cleanly later; deferred until contract patterns stabilize.
- We did **not** make the user-flow tester re-author the contract. If a flow is impossible to verify (no preview URL, missing component, ambiguous element reference), the tester FAILs and the orchestrator decides whether to retry the worker or block. The contract is locked at user approval; only the human can revise it.

### The lesson worth carrying

The Factory architecture's split — scrutiny vs. user-testing as separate roles — is the load-bearing one. v1.0 collapsed them ("skip user-test") and got away with it for static features. The moment a feature has runtime behavior the unit tests don't cover (localStorage, routing, hydration, animation timing, anything async), scrutiny PASS is no longer the same as "works." Shipping user-flow-tester now, rather than waiting for a user to hit the false-PASS class of bug, is the cheaper trade. The cost was one agent file plus one orchestrator branch change.

## 2026-05-11 — v1 missions: per-mission git worktree for filesystem isolation

### The realization

We shipped the v1 mission MVP earlier today with the worker editing source files in the main checkout. That works for one mission at a time on a human-supervised flow — but the whole pitch of v1 is overnight unsupervised runs. The first time the worker misreads a contract and writes to the wrong path, the main checkout is contaminated. Worse: parallel missions on the same repo would step on each other immediately, and any attempt at a multi-mission flow becomes a coordination nightmare from day one.

v0.1 solved an adjacent version of this for parallel human sessions: `/start-build` claims a git worktree, `coordination.json` tracks it, and `coord-cleanup.sh` sweeps stale rows. The pattern was right there — autonomous missions just needed to adopt it before the first overnight run, not after.

### The fix, in one sentence

**Each mission runs inside its own `git worktree` at `missions/<id>/worktree/` on branch `mission/<id>`; the orchestrator stays in the main repo and dispatches worker/scrutiny with an explicit `WORKTREE_PATH` they `cd` into before any Bash.**

### Specifics shipped this release

- `workflow-v1/templates/state.schema.json` — new `worktree` object with `path`, `branch`, `base_ref`, `claude_dir_symlink`. Absent or null in host mode.
- `workflow-v1/agents/mission-orchestrator.md` — Procedure A step 2b creates the worktree with `git worktree add -b mission/<id> <path> <base_ref>`, symlinks `.claude/` into it (so slash commands resolve from either CWD), and registers a row in v0.1's `coordination.json` to reuse the existing stale-cleanup script. The coordination row uses `severity: major` (missions own a branch and run for hours — sibling sessions pause). Dispatches in Procedure B now pass `WORKTREE_PATH` and use absolute paths everywhere so the worker/scrutiny can resolve them after `cd`. Procedures C (abort) and D (complete) close the coordination row with `status: completed` (NOT `completed_unclean`, which would trigger force-removal of the worktree) and surface explicit `git worktree remove` / `gh pr create` hints — they do not auto-execute either.
- `workflow-v1/agents/feature-worker.md` — required `WORKTREE_PATH` field in the dispatch prompt. New step 1b: every Bash command must be `cd "$WORKTREE_PATH" && ...`, and Edit/Write/Read tool calls target absolute paths inside the worktree. First-dispatch `npm install` (or pnpm/yarn/bun equivalent based on lockfile) when `node_modules/` is absent. New guardrail forbids reads or edits outside the worktree except for the explicit `HANDOFF_OUTPUT_PATH` and `CONTRACT_PATH` the dispatcher provided.
- `workflow-v1/agents/scrutiny-validator.md` — same `WORKTREE_PATH` requirement, same `cd` discipline. Crucially: when scrutiny dispatches v0.1 `design-auditor` or `schema-analyst` via Task tool, file paths in `changed_files` are now **absolute paths inside the worktree**, so the v0.1 auditors (which use Read tool with whatever path you hand them) resolve correctly regardless of where the subagent runs.
- `workflow-v1/commands/mission-status.md` — renders the worktree path, branch, and base ref in the status block.
- `workflow-v1/project.example.v1.json` — new `mission_runtime.worktree.{enabled, base_ref}` config. Default `enabled: true` and `base_ref: "HEAD"`. Disable for host mode if you want the worker to edit the main checkout (not recommended for unattended runs).
- `workflow-v1/Engineering-Playbook-v1-deltas.md` — new "Isolation" section describing the mechanism and the `.claude/` symlink trick.
- `docs/missions.md` — the verification block now includes `git -C missions/<id>/worktree status` and the merge/discard recipes so users see the audit trail vs. source distinction.
- `scripts/install-v1.sh` — idempotently appends `missions/`, `memory/`, and `.claude/settings.local.json` to the target repo's `.gitignore`. Without this, every mission's `gh pr create` from the worktree branch would pull in the mission's own state.json/log.md/handoffs alongside the source diff. The append is line-exact (`grep -qxF` then append), so re-running install adds nothing.

### What we deliberately didn't do

- We did **not** auto-merge the mission branch. v1.0 prints a pre-filled `gh pr create` invocation; the human owns the merge decision. Auto-merge is a v1.1 flag (`--auto-pr`).
- We did **not** auto-remove worktrees on `/mission-abort` or completion. The audit trail is sacred — if the worker did something interesting, you want to inspect the worktree, not have it vaporize. Cleanup is a documented shell command.
- We did **not** ship destructive-command sandboxing. Filesystem isolation only. A worker that runs `rm -rf ~/Documents` inside a worktree's Bash session still hits the host filesystem — the worktree gives you blast radius on *source files*, not on shell commands. Container isolation in v1.1 closes that gap; flagged in the playbook as the next escalation.
- We did **not** invent a new coordination layer. v0.1's `coordination.json` and `coord-cleanup.sh` already do exactly what missions need — the row schema accommodates a `phase: mission` value cleanly with `severity: major`, and stale-cleanup runs every existing user already has installed.

### The lesson worth carrying

The right primitive was already in the framework. The unlock was recognizing that v0.1's worktree pattern — designed for parallel human-driven phases — generalized to autonomous missions with zero new infrastructure. The temptation when shipping v1 was to build a new isolation layer to match the new abstraction; what actually shipped was a four-line addition to Procedure A and an explicit path field in two dispatch prompts. When a framework has a small, well-shaped primitive set, the right move is almost always to reach for one of those before inventing.

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
