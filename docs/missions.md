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

## The six commands

| Command | What it does |
|---|---|
| `/mission <goal>` | Start a new mission. Orchestrator scopes goal, writes contract for your approval, hands off to `/loop`. |
| `/mission-status [id]` | Show current state of a mission (read-only). Defaults to the most recent. |
| `/mission-resume <id>` | Resume a paused or blocked mission in a fresh session. |
| `/mission-abort <id>` | Terminate a mission. Preserves the directory for audit. Does not roll back code changes. |
| `/mission-tick <id>` | Internal — fired by `/loop` on schedule. Do not invoke directly. |
| `/docs-gate [scope]` | Run the docs-auditor over framework documentation to catch drift (broken file refs, dead `/command` refs, unused `project.example.*.json` keys, CHANGELOG-vs-diff). Auto-dispatched at mission completion; also runnable standalone. |

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

## Running missions hands-free

Mission mode's "kick off after dinner, review at breakfast" promise is about **decision autonomy** — the orchestrator never asks you whether to retry a worker, advance to scrutiny, or accept a verdict. **Claude Code's permission system is orthogonal.** Every `Bash`, `Edit`, `Write`, `Task` dispatch, and MCP call still passes through the harness's permission gate. Without a baseline allow-list, an overnight mission stalls behind permission prompts and you wake up to a session frozen on turn three.

### What `install-v1.sh` now wires for you

The v1 installer adds a conservative starter `permissions.allow` to your project's `.claude/settings.json`:

- `Task` — for the orchestrator's sub-agent dispatches.
- `Bash(npm test*)`, `Bash(npm run *)`, `Bash(npx *)`, `Bash(pnpm *)`, `Bash(yarn *)` — JS/TS tool surface.
- `Bash(pytest*)`, `Bash(ruff *)`, `Bash(python3 *)` — Python tool surface.
- `Bash(git status*)`, `git diff*`, `git log*`, `git add *`, `git commit *`, `git push *`, `git branch*`, `git checkout*`, `git worktree *`, `git rev-parse*` — version control. The broad `git push *` allow is necessary because the orchestrator pushes the mission branch on completion; **the deny block below stops it from being used to push main or to force-push.**
- `Bash(gh pr create*)`, `gh pr view*`, `gh issue view*` — for `--from-issue` / `--auto-pr`.
- `mcp__playwright__*` — for `user-flow-tester`.
- `Bash(timeout *)`, `Bash(gtimeout *)` — both shell-out forms used by hooks.

### The paired deny block (gate-enforced)

Claude Code evaluates permission rules in order **deny → ask → allow**. A matching deny always wins, so the installer also wires a `permissions.deny` block that narrows the allow-list above:

- `Bash(git push * main)`, `Bash(git push * main:*)`, `Bash(git push *:main)`, `Bash(git push *:main *)` — and the same four shapes for `master`. Blocks any push that targets the primary branch, in any of the refspec forms a worker or procedure might accidentally produce.
- `Bash(git push --force*)`, `Bash(git push -f *)`, `Bash(git push --force-with-lease*)` — blocks force-push regardless of target branch.
- `Bash(git push --delete*)`, `Bash(git push -d *)` — blocks remote branch deletion via push.
- `Bash(git reset --hard*)`, `Bash(git clean -fd*)`, `Bash(git clean -fdx*)` — blocks destructive local-state resets that throw away uncommitted work.

The orchestrator's procedural rule (push only the mission branch, see `mission-tick.md:206`) is now enforced at the gate, not just by prompt. A worker drift or a future procedural bug can't accidentally land on main — the deny rule fires first.

**Override path:** if you legitimately need a force-push or a direct main push during recovery, temporarily remove the matching entry from `permissions.deny` and run the command manually. Don't add a competing allow rule — deny always wins, and it's a confusing failure mode to debug. Restore the entry when done.

The wiring (both allow and deny) is idempotent and additive. Any entries you already had are preserved; re-running `install-v1.sh` (or `scripts/wire-mission-permissions.py` directly) deduplicates by exact-string match.

Review the merged lists in `.claude/settings.json` after install and tighten or extend for your stack — particularly if you have unusual deploy commands, custom CLI tools, or MCP servers the worker will hit.

### If you need broader autonomy than the allow-list provides

Two harness-level escape hatches, in increasing order of "trust the contract":

1. **`claude --permission-mode acceptEdits`** — Claude Code auto-accepts file edits and standard tools but still confirms novel Bash patterns. Reasonable middle ground when you're refining your allow-list across a few runs.

2. **`claude --dangerously-skip-permissions`** — auto-allow everything. Only safe inside the mission's git worktree at `missions/<id>/worktree/` (which the framework already isolates filesystem changes to), and only when you trust the contract scope. This is the literal "walk away" setting.

The cron-paced flow (`--pace cron`, see below) starts each tick as a fresh remote session, which respects the project's `.claude/settings.json` exactly the same way — the wired allow-list applies. Use `--dangerously-skip-permissions` there only via the harness flag, never bake it into a routine.

### Why the allow-list is not just `["*"]`

A small audit trail matters. Six weeks from now, when a mission did something unexpected, the `permissions.allow` list is the first thing to read: "did I knowingly grant this surface, or did the orchestrator find a way past?" An explicit list answers that. `["*"]` doesn't.

### Hardening warn-only hooks during a mission tick

`main-push-guard.sh` is warn-only by default — it prints a message and exits 0 if you try to push to main/master without a `/deploy-gate` marker. The intent is to nudge an interactive user, not to block their muscle memory. In autonomous mission mode that's backwards: the orchestrator never "sees" a warning, it just keeps going.

The orchestrator's `mission-tick` procedure writes `.claude/.mission-tick-active-<MISSION_ID>` at the start of each tick and removes it at the end. When the marker is present and a push-to-main-without-deploy-gate triggers `main-push-guard.sh`, the hook exits 2 (blocking) instead of 0 (warning). Outside mission ticks (interactive sessions, gaps between ticks), the original warn behavior is unchanged.

Stale-marker recovery: if a tick crashes before cleanup, the marker persists until the next tick rewrites it OR until you `rm -f .claude/.mission-tick-active-*`. `/mission-abort` also removes the marker for the aborted mission.

Why `migration-guard.sh` did not get the same hardening: workers legitimately write migration files as part of normal flow, with `/schema-gate` (and the deterministic `schema-static-scan.sh`) running later in the tick. Blocking the file edit would kill the worker before scrutiny could fire. The schema-gate marker remains the harder block for that path.

## Secret hygiene and operational safety

The framework's safety net is built for *code correctness*: worktree isolation, contract approval, schema gate, dispatch caps, PR-not-merge. It is **not** built for secret hygiene. The list below names the leak vectors a non-tech founder is most likely to create and the configuration steps that close them.

### Keep secrets out of files every worker reads

Every dispatched agent receives `CLAUDE.md` and `.claude/project.json` in its context. If you paste an API key, DB password, or token into either, every feature-worker, scrutiny-validator, and `memory-broker` sees it — and `memory-broker` may then mirror it into local memory files or, if Mem0 is enabled, send a summary to `api.mem0.ai`.

Concrete rules:

- **API keys, tokens, DB passwords, signing secrets** → `.env` (gitignored) only. Reference by env-var name in CLAUDE.md if you must (`STRIPE_KEY is in .env, see .env.example for the var name`), never the value.
- **`.env.example`** — commit only the *names* of variables, never sample values that look real. A 40-character placeholder is enough for someone to grep "looks like an OpenAI key" and false-positive on every dependency scan.
- **`project.json`** — `supabase_project_ref` is the project ID, not a secret; that's fine. Anon/service keys go in `.env`.
- **CLAUDE.md "Red lines" section** — the template now flags this explicitly. If you bootstrapped before this rule landed, audit your CLAUDE.md manually.
- **gitleaks pre-commit hook** — `pre-git-check.sh` now scans staged changes via gitleaks (when installed) and blocks the commit on findings. This is your enforced backstop: if a worker accidentally hardcodes a key into source, the commit fails. Install with `brew install gitleaks` (or apt-equivalent). Without it, the hook prints a one-time notice and skips scanning — strongly recommended once you have real credentials anywhere in the project.

### Mission handoffs and logs capture worker stdout verbatim

`missions/<id>/handoffs/<feature>.md` and `missions/<id>/log.md` preserve every command the worker ran and its output. If the worker debugged with `env`, `printenv`, `cat .env`, `npm config list` (registry tokens), or `git config --list` (signing keys), those values land on disk in plain text. The mission directory is gitignored, but it persists indefinitely and is read by future missions via `memory-broker`.

Hygiene:

- **Do not paste mission handoff files publicly** — including in support channels, GitHub issues, or screenshots — without scanning for env-shaped strings first.
- **Periodically clean stale mission dirs**: `rm -rf missions/<old-id>/` once the corresponding PR has merged. The audit trail value tapers fast.
- **If a worker run touches secret-handling code**, treat the resulting `handoffs/` and `log.md` as secret-grade and shred them after the PR lands.

### Enable GitHub branch protection on `main`

This is outside the framework's control — but it is the **only** mechanical guard against a misbehaving push pattern landing on main. The framework's mission orchestrator pushes only the mission branch and the worker is system-prompted not to push at all, but the `permissions.allow` rule (`Bash(git push *)`) is broader than the procedural intent. Branch protection is your defense-in-depth.

Steps:

1. github.com → your repo → Settings → Branches → Add rule for `main` (or your primary branch).
2. Require pull request reviews before merging.
3. Require status checks (your CI) to pass.
4. Restrict who can push to matching branches (or check "Restrict force pushes").

Without this, `--auto-pr` is still safe (the orchestrator opens a PR, never merges). *With* this, even a misconfigured `permissions.allow` can't land bad code without a human approving the PR.

### Audit every MCP server you enable

Every MCP server expands the worker's reach beyond the framework's static checks. The starter `permissions.allow` permits `mcp__playwright__*` (for `user-flow-tester`); anything else you add (Supabase, Notion, Linear, Gmail) bypasses `/schema-gate` and other framework gates for its own surface.

- **Supabase MCP with destructive scope** — if the worker can call `mcp__claude_ai_Supabase__execute_sql`, it can `DELETE FROM users` regardless of `/schema-gate`. Constrain MCP scopes to read-only when missions don't need writes.
- **MCP servers with broad tool surfaces** (Gmail send, Slack post) — never wire these into the mission allow-list unless the contract explicitly requires the action.

### Dev servers spawned by `mission_user_test` are your responsibility to stop

v1.0 has no `preview_server_stop_command`. If your `preview_url_command` backgrounds a dev server, you'll accumulate stale servers across runs. See the configuration example below for the recommended pid-file pattern.

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
// Have the mission start its own dev server. Writes a pid file so you can
// kill the server cleanly between runs — see cleanup snippet below.
"mission_user_test": {
  "mcp": "playwright",
  "preview_url_command": "cd $CLAUDE_PROJECT_DIR/missions/$MISSION_ID/worktree && nohup npm run dev > /tmp/dev-$MISSION_ID.log 2>&1 & echo $! > /tmp/dev-$MISSION_ID.pid && sleep 8 && echo http://localhost:5173"
}
```

v1.0 does **not** auto-stop dev servers the command starts — you're responsible for cleanup. After a mission finishes (or aborts), kill the dev server:

```bash
# Single mission
[ -f /tmp/dev-<mission-id>.pid ] && kill "$(cat /tmp/dev-<mission-id>.pid)" && rm /tmp/dev-<mission-id>.pid

# All accumulated dev servers
for pid_file in /tmp/dev-*.pid; do
  [ -f "$pid_file" ] && kill "$(cat "$pid_file")" 2>/dev/null
  rm -f "$pid_file"
done
```

A `preview_server_stop_command` is on the roadmap so the orchestrator handles this itself.

When `preview_url_command` is null, the orchestrator writes `verdicts.<fid>.user_test = "skipped"` and proceeds straight from scrutiny to handoff. This is the right setting for backend-only features or when you want a faster verification loop before wiring browser tests in.

## GitHub: issue → PR in one command

`/mission --from-issue <url>` seeds the contract from a GitHub issue's title and body. You still review and approve the contract before any code is written — the issue is context, not contract.

`/mission "<goal>" --auto-pr` makes the orchestrator push the mission branch and `gh pr create` at completion (with an assembled body including PASS checkmarks and a `Closes <issue-url>` line if you also started from an issue). Set `github.auto_pr_on_completion: true` in `project.json` to make this the default.

Combined: `/mission --from-issue https://github.com/<org>/<repo>/issues/42 --auto-pr` is a fully autonomous issue→PR run. The orchestrator never merges — that's always human.

**Strongly recommended before relying on `--auto-pr`:** enable branch protection on your primary branch (require PR review, require status checks). The orchestrator opens a PR but never merges; branch protection is the mechanical guarantee that this stays true if the permission allow-list drifts. See "Secret hygiene and operational safety" above.

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
