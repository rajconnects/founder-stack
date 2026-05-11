# Procedure: new mission

You are running this procedure in the main agent thread, dispatched from `/mission`. The slash command has already parsed `$ARGUMENTS` and confirmed `.claude/project.json` exists. The dispatching slash command passes the parsed `GOAL`, `ISSUE_URL`, `PACE`, and `AUTO_PR` values in its body.

You will scope the goal, author the validation contract, get human approval, and initialize `state.json`. You do **not** dispatch any worker in this procedure — that happens later inside the tick loop. You **may** dispatch the `memory-broker` subagent via the Task tool to read prior-mission context (you are in the main thread, so nested sub-agent spawning is fine).

## Steps

1. **Resolve project config.** Read `.claude/project.json`. Extract `mission_root` (default `missions/`), `mission_model_seats`, `mission_caps`, `memory.*`, `mission_user_test.*`, `test_commands`, `stack`, `github.auto_pr_on_completion` (default `false`). If any field is missing, use the documented defaults from `workflow-v1/project.example.v1.json`. Do **not** fail just because a field is missing — log the default fallback in `log.md` when you create it in step 7.

2. **Fetch the issue if invoked via `--from-issue`.** If `ISSUE_URL != "none"`:
   - Validate the URL matches `https://github.com/<owner>/<repo>/issues/<number>`. If not, print `ERROR: --from-issue requires a GitHub issue URL` and stop.
   - Run `bash -c 'gh issue view <ISSUE_URL> --json title,body,state,labels'`.
   - If the command fails (gh not installed, no auth, issue not found): print the stderr verbatim and stop.
   - If `state == "closed"`: warn the user and ask whether to proceed. If yes, continue; if no, stop.
   - Compose the goal string for downstream steps: `"<title>\n\n<body>"`. The contract is still authored from scratch in step 5 — issue context is the seed, not the contract.
   - Stash the URL for `state.json.github.issue_url` (written at step 7).

3. **Generate mission id.** `YYYY-MM-DD-<slug>-<4-char-hash>`:
   - `<slug>`: lowercase, dash-separated, max 5 words drawn from the goal.
   - `<4-char-hash>`: `bash -c 'openssl rand -hex 2'`.
   - Create `<mission_root>/<mission_id>/`, `<mission_root>/<mission_id>/handoffs/`, and `<mission_root>/<mission_id>/artifacts/`.

4. **Create the per-mission worktree** (filesystem isolation for worker edits). Read `mission_runtime.worktree.enabled` from project.json (default `true`). If `true`:
   - Compute `WORKTREE_PATH = <abs-main-repo>/<mission_root>/<mission_id>/worktree`.
   - Compute `BRANCH = mission/<mission_id>`.
   - Compute `BASE_REF = <--base arg if provided, else current HEAD of main repo>`. Capture the SHA with `bash -c 'git rev-parse <ref>'` so the recorded `base_ref` is stable.
   - Run `bash -c 'git worktree add -b <BRANCH> <WORKTREE_PATH> <BASE_REF>'` from the main repo root.
   - If the command fails (branch exists, dirty tree, etc.): surface the stderr verbatim, delete the partially-created `<mission_root>/<mission_id>/` directory, and stop. **Do not** write `state.json` for a mission whose worktree creation failed.
   - **Symlink `.claude/` into the worktree** so slash commands resolve from either CWD: `bash -c 'ln -s <abs-main-repo>/.claude <WORKTREE_PATH>/.claude'`. If the worktree already has a `.claude` (rare — base ref had one tracked), skip the symlink and set `claude_dir_symlink: false` later.
   - **Record in coordination.json** (reuses v0.1's stale-cleanup): append a row with `id: mission-<mission_id>`, `phase: mission`, `status: active`, `severity: major` (missions own a branch and run for hours — always major; sibling sessions pause), `worktree: <WORKTREE_PATH>`, `branch: <BRANCH>`, `started: <iso>`, `heartbeat: <iso>`. Best-effort — if `coordination.json` is missing or malformed, log to `log.md` and continue.

   If `mission_runtime.worktree.enabled` is `false` (host mode): skip step 4 entirely. `worktree` stays `null` in `state.json`; worker and scrutiny operate in the main repo CWD.

5. **Read prior-mission context.** Dispatch the `memory-broker` subagent via the Task tool:

   ```
   subagent_type: memory-broker
   prompt: |
     OP: search
     KIND: mission_outcome
     PAYLOAD: { "query": "<goal>", "limit": 3 }
   ```

   Capture the returned items. If non-empty, paste each item's `goal` + `snippet` into the contract authoring prompt and into `log.md` under "Prior-mission references".

6. **Scope the goal with the user.** This is the only mandatory human checkpoint in a new mission. Ask 1–3 sharp questions to disambiguate scope, success criteria, and any hard constraints (specific library, specific file path, specific behavior). Keep it tight — 3 questions max. If the goal is already crisp, skip and proceed.

7. **Author the contract.** Read `$CLAUDE_PROJECT_DIR/.claude/templates/v1/mission-contract.template.md`. Fill in:
   - One feature per logical unit of work (MVP: aim for 1 feature; v1.1 multi-feature decomposition).
   - For each feature: file scope (explicit list), acceptance criteria, test contract (which test files cover which ACs), design/schema/user-flow contracts as applicable.
   - Insert the prior-mission references section (from step 5).
   - Output: `<mission_root>/<mission_id>/contract.md`.

8. **Present the contract for approval.** Print the contract to the user. Ask: `Approve and lock the contract? (yes/edit/abort)`. On `yes`, set `status: approved` in the contract front-matter and proceed to step 9. On `edit`, take the user's revision verbatim and re-prompt. On `abort`, delete the mission directory and return.

9. **Initialize state.json** per `$CLAUDE_PROJECT_DIR/.claude/templates/v1/state.schema.json`:
   - `mission_id`, `goal`, `pace` (from the `PACE` arg, default `local`), `status: running`.
   - `features`: array from the contract, all `status: pending`.
   - `current_feature_idx: 0`, `current_step: worker`.
   - `caps`: from project.json or defaults.
   - `dispatches_total: 0`, `error_log: []`, `last_heartbeat: now`, `resume_requested: false`.
   - `worktree`: from step 4 — `{ path, branch, base_ref, claude_dir_symlink }` if worktree mode is on, else omit the field entirely.
   - `github`: `{ issue_url: <ISSUE_URL from step 2, or null>, pr_url: null, auto_pr: <AUTO_PR, OR github.auto_pr_on_completion from project.json, default false> }`. `pr_url` gets populated in the completion procedure when the PR is created.

10. **Hand off based on pace.** Two paths:

   **If `PACE == "local"` (default):** print to the user, verbatim:

   ```
   Mission <id> approved and ready to run autonomously (pace: local).

   To start the autonomous loop, type:
     /loop /mission-tick <id>

   The orchestrator will tick on its own cadence (default 270s active, 1500s idle).
   Check progress any time with:  /mission-status <id>
   ```

   **If `PACE == "cron"`:** print, verbatim:

   ```
   Mission <id> approved and ready to run autonomously (pace: cron).
   /mission will create a /schedule routine to fire ticks every <cron_interval_minutes> minutes.
   Check progress any time with:  /mission-status <id>
   Cancel anytime with:           /mission-abort <id>
   ```

   In both cases, do **not** call `ScheduleWakeup` here. In local mode, the user enters `/loop /mission-tick <id>` to start; the first tick runs the tick procedure (which calls `ScheduleWakeup` for subsequent ticks). In cron mode, `/mission` (the dispatching slash command) creates the `/schedule` routine after this procedure returns.

11. **Return a one-line summary to the dispatching slash command** that includes `mission_id` and `pace`, so `/mission` knows whether to create the cron routine.

## Guardrails

- **Never modify the contract after `status: approved`.** Acceptance failure forces a worker retry, not a contract relaxation. If the contract is genuinely wrong, the user must `/mission-abort` and start over with a corrected scope.
- **Never silently fall back to local memory if Mem0 errors.** The broker errors out; you propagate the error to `log.md` and either retry or stop — your call based on `mission_caps`.
- **`state.json` writes must be atomic.** Write to `state.json.tmp`, then `Bash mv state.json.tmp state.json`. Avoid partial writes that would corrupt a resume.
- **Do not write or edit any file outside `<mission_root>/<mission_id>/`** except: (a) the memory-broker writes under `<memory.local_root>/`, (b) appending to `log.md`. This procedure never edits source code.
- **Single-Bash-call atomic ops.** Use `Bash` for `openssl rand`, `date -u +%Y-%m-%dT%H:%M:%SZ`, `mv` — don't chain multiple Bash calls when one will do.
