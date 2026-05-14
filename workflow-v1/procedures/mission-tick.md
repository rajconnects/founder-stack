# Procedure: mission tick

You are running this procedure in the main agent thread, dispatched from `/mission-tick` (or `/loop /mission-tick`). The slash command has already verified `<mission_root>/<id>/state.json` exists and passes you the `MISSION_ID`.

This is the autonomous body. It runs one dispatch step per invocation, then either `ScheduleWakeup`s the next tick (local pace) or returns and waits for the next cron fire (cron pace).

**Why this lives in the main thread:** the procedure dispatches `feature-worker`, `scrutiny-validator`, `design-auditor`, `schema-analyst`, `user-flow-tester`, `docs-auditor`, and `memory-broker` via the Task tool. Claude Code blocks sub-agents from spawning further sub-agents, so the orchestration logic must run in the main agent's session — not as a sub-agent itself.

## Steps

1. **Resolve config and state.** Read `.claude/project.json` and `<mission_root>/<MISSION_ID>/state.json`. If state.json is missing or invalid: write a one-line error to `log.md`, set status to `blocked`, return.

1a. **Write the mission-mode marker.** Touch `$CLAUDE_PROJECT_DIR/.claude/.mission-tick-active-<MISSION_ID>`. This signals to `main-push-guard.sh` (and future warn-only hooks) that the strict path applies — blocking instead of warning on a push to main/master. The marker is removed at the end of this tick (step "Wrap up the tick") or via the cleanup step in any terminal-status branch below. If a tick crashes before cleanup, the marker is stale; the next tick rewrites it, and `/mission-abort` cleans up all matching markers.

2. **Reset resume flag.** If `resume_requested: true`, set it to `false` (we're resuming now).

3. **Check caps before dispatching anything.**
   - If `dispatches_total >= caps.max_total_dispatches`: set `status: blocked`, append to `error_log` (`"max_total_dispatches reached"`), append to `log.md`, return. Do **not** ScheduleWakeup.
   - For the current feature: if `retry_counts.<fid>:<step> >= caps.max_dispatches_per_feature`: same — set `status: blocked`, append error, return.

4. **Check context budget.** Rough heuristic: if **40 turns have elapsed since this `/mission-tick` invocation** OR you've consumed more than ~150KB of tool-result bytes during this tick, set `resume_requested: true`, write a one-line `log.md` entry (`"context budget exceeded, requesting resume"`), and exit. The next wake (from /loop or /schedule) re-enters in a fresh session. Count turns from the start of this tick, not from session start — pre-tick user activity doesn't trip the budget.

5. **Update heartbeat.** Set `last_heartbeat: now` in state.json.

6. **Dispatch by `current_step`:**

### current_step: worker

Dispatch the worker via the Task tool. **All paths in the dispatch prompt must be absolute** so the worker can resolve them after `cd $WORKTREE_PATH`:

```
subagent_type: feature-worker
prompt: |
  MISSION_ID: <id>
  FEATURE_ID: <fid>
  WORKTREE_PATH: <state.worktree.path, or "none" if worktree disabled>
  CONTRACT_PATH: <abs path to contract.md>#feature-<fid>
  HANDOFF_OUTPUT_PATH: <abs path to <mission_root>/<id>/handoffs/<fid>.md>
  DISPATCH_NUMBER: <retry_counts[<fid>:worker] + 1>
  PRIOR_HANDOFF: <inline contents of <fid>.md if this is a retry, else "none">
  PRIOR_SCRUTINY_VERDICT: <inline contents of <fid>.scrutiny.md if scrutiny FAILed previously, else "none">
  PRIOR_USER_TEST_VERDICT: <inline contents of <fid>.user-test.md if user-test FAILed previously, else "none">
  PROJECT_JSON_INLINE: <relevant fields: stack, test_commands, test_roots>
  MAX_DISPATCH_BUDGET_MIN: 30
```

On retry dispatch (`retry_counts[<fid>:worker] > 0`), **also** include `PRIOR_SCRUTINY_VERDICT` from `<fid>.scrutiny.md` — the worker's job on retry is to fix what scrutiny flagged.

When the worker returns:
- Read `<fid>.md` (the handoff).
- Parse the front-matter `status` field.
- Increment `retry_counts[<fid>:worker]` and `dispatches_total`.
- Append a one-line entry to `log.md`: `<timestamp> | feature <fid> | worker dispatch #<n> → <status>`.
- If worker `status: COMPLETE`: set `current_step: scrutiny`. Save state.
- If `PARTIAL` or `BLOCKED`: set `status: blocked` on the mission (human needs to look). Save state. Return.

### current_step: scrutiny

This step dispatches up to **three independent validators in parallel**, then aggregates. Issue the applicable Task calls in a single message so they run concurrently:

- **Always:** dispatch `scrutiny-validator` (static correctness — tests, types, contract-coverage, honesty).
- **If the contract's `Design contract` section for this feature is non-empty AND the worker touched files under `stack.frontend_root`:** also dispatch `design-auditor`.
- **If the contract's `Schema contract` section for this feature is non-empty AND the worker touched migration files:** also dispatch `schema-analyst`.

Dispatch prompts (all paths absolute):

```
subagent_type: scrutiny-validator
prompt: |
  MISSION_ID: <id>
  FEATURE_ID: <fid>
  WORKTREE_PATH: <state.worktree.path, or "none">
  CONTRACT_PATH: <abs path to contract.md>#feature-<fid>
  WORKER_HANDOFF_PATH: <abs path to <fid>.md>
  VERDICT_OUTPUT_PATH: <abs path to <fid>.scrutiny.md>
  PROJECT_JSON_INLINE: <stack, test_commands, test_roots>
```

```
subagent_type: design-auditor
prompt: |
  changed_files: <space-separated ABSOLUTE paths inside WORKTREE_PATH from the worker's files_touched that match stack.frontend_root>
  Return your standard PASS/FAIL with gaps. Do not write code.
```

```
subagent_type: schema-analyst
prompt: |
  Scope: <ABSOLUTE paths inside WORKTREE_PATH for migration files from worker's files_touched>
  PROJECT_JSON_INLINE: <migrations, stack.supabase_project_ref>
  Return your standard pass/fail with gaps.
```

**Aggregate the verdicts.** When all dispatched auditors have returned:

- Read `<fid>.scrutiny.md`. Parse the `Verdict:` line.
- Capture the `design-auditor` and `schema-analyst` verdicts inline (those agents return their verdict in the tool result; you do not need a verdict file for them in this flow — append them as appended sections to `<fid>.scrutiny.md` for the audit trail).
- Compute the overall verdict:
  - **PASS** only if `scrutiny-validator` is PASS AND (design-auditor not dispatched OR design-auditor PASS) AND (schema-analyst not dispatched OR schema-analyst PASS).
  - **FAIL** otherwise. The combined gap list is the union of all FAILing auditors' gaps.
- Increment `retry_counts[<fid>:scrutiny]` and `dispatches_total`. Append a one-line entry to `log.md`.
- If overall verdict is `PASS`: write `verdicts.<fid>.scrutiny = "PASS"` in state.json. Set `current_step: user-test` if `mission_user_test.preview_url_command` is set and the contract feature section has `User flows`, else `current_step: handoff`.
- If overall verdict is `FAIL`:
  - If `retry_counts[<fid>:worker] + 1 < caps.max_dispatches_per_feature`: set `current_step: worker`. The next tick will re-dispatch with the prior handoff + the combined FAIL gaps. Save state.
  - Else: cap hit. Set mission `status: blocked`. Save state. Return.

**Why three separate sub-agents instead of one validator?** Each has a fresh, adversarial context for its specialty. `scrutiny-validator` re-checks tests/types/AC coverage with skepticism. `design-auditor` re-checks tokens/components/Figma alignment. `schema-analyst` re-checks RLS/indexes/migration safety. They cannot delegate to each other (Claude Code blocks nested sub-agent spawning), so the main thread dispatches each one directly and aggregates.

### current_step: user-test

If `mission_user_test.preview_url_command` is null OR the contract feature section has no `User flows` block: **skip** this step. Write `verdicts.<fid>.user_test = "skipped"`, set `current_step: handoff`, save state, proceed.

Otherwise:

1. **Capture the preview URL.** Run `bash -c '<mission_user_test.preview_url_command>'`. Capture stdout (trim whitespace), capture stderr, capture exit code.
   - If exit != 0: append the stderr to `error_log` and `log.md`, set mission `status: blocked` with reason `"preview_url_command exited <code>"`. Save state. Return.
   - If stdout is empty: same — `status: blocked` with reason `"preview_url_command returned empty stdout"`.
   - Otherwise: stdout is the `PREVIEW_URL`.

2. **Dispatch user-flow-tester** via Task:

   ```
   subagent_type: user-flow-tester
   prompt: |
     MISSION_ID: <id>
     FEATURE_ID: <fid>
     WORKTREE_PATH: <state.worktree.path, or "none">
     CONTRACT_PATH: <abs path to contract.md>#feature-<fid>
     VERDICT_OUTPUT_PATH: <abs path to <fid>.user-test.md>
     PREVIEW_URL: <captured URL>
     ARTIFACTS_DIR: <abs path to <mission_root>/<id>/artifacts/>
     PROJECT_JSON_INLINE: <relevant fields>
     MAX_DISPATCH_BUDGET_MIN: 15
   ```

3. **Process the verdict.** Read `<fid>.user-test.md`. Parse the `Verdict:` line.
   - Increment `retry_counts[<fid>:user-test]` and `dispatches_total`.
   - Append to `log.md`.
   - If `Verdict: PASS`: write `verdicts.<fid>.user_test = "PASS"`. Set `current_step: handoff`.
   - If `Verdict: skipped`: write `verdicts.<fid>.user_test = "skipped"`. Set `current_step: handoff`.
   - If `Verdict: FAIL`:
     - If `retry_counts[<fid>:worker] + 1 < caps.max_dispatches_per_feature`: set `current_step: worker`. The next tick re-dispatches the worker with the user-test verdict as the retry context.
     - Else: cap hit. Set mission `status: blocked`.

### current_step: handoff

- Mark this feature `status: completed` in state.json `features` array.
- Set `verdicts.<fid>.completed_at = now`.
- If there are more features: `current_feature_idx += 1`, `current_step: worker`.
- If this was the last feature: go to **Completion** below.

7. **Save state, log, schedule next tick.** After every dispatch, before returning:
   - Save `state.json` (atomic write — use `Write` to a `.tmp` then `Bash mv`).
   - Append to `log.md` (one line per dispatch).
   - **Remove the mission-mode marker:** `rm -f "$CLAUDE_PROJECT_DIR/.claude/.mission-tick-active-<MISSION_ID>"`. This MUST happen before the return — otherwise interactive sessions in the gap between ticks would falsely trip the marker-based hardening in `main-push-guard.sh`.
   - **Local pace only:** call `ScheduleWakeup` with `delaySeconds: <mission_caps.default_wake_active_secs or 270>`, `prompt: "/mission-tick <id>"`, reason `"mission <id> next dispatch: <step>"`. In **cron pace**, do NOT call `ScheduleWakeup` — the next tick is cron-driven, not session-driven.
   - Return briefly to the dispatching slash command with: `<id> | step <step> | <verdict-summary> | pace <pace> | status <status>`. The slash command (`/mission-tick`) uses `status` to decide whether to delete the cron routine when terminal.
   - **Skip the `ScheduleWakeup` call** if `status` transitioned to `completed`, `aborted`, or `blocked` this tick — the loop should not re-fire on terminal states.

## Completion (formerly Procedure D)

Reached only when the last feature's `current_step: handoff` runs.

1. Set `state.json` `status: completed`.

2. **Run docs-auditor on mission-completion scope.** Dispatch via Task:

   ```
   subagent_type: docs-auditor
   prompt: |
     SCOPE: mission-completion
     MISSION_ID: <id>
     VERDICT_OUTPUT_PATH: <abs path to <mission_root>/<id>/handoffs/docs-audit.md>
   ```

   Read the returned verdict. If `Verdict: FAIL`: append the gaps to `log.md`, include a `"docs-audit FAILed — fix before merge"` line in the completion summary printed in step 6. Do **not** block mission completion on docs drift — code correctness is the gate, docs drift is a separate human concern. The advisory CHANGELOG-vs-diff section is purely informational.

3. Compose a 1–3 paragraph summary of the mission: what shipped, what surprised, what's deferred. If docs-auditor flagged real gaps in step 2, mention `"docs-audit gaps remaining"` with a pointer to `handoffs/docs-audit.md`.

4. **Write to memory.** Dispatch `memory-broker` via Task:

   ```
   subagent_type: memory-broker
   prompt: |
     OP: write
     KIND: mission_outcome
     PAYLOAD: {
       "mission_id": "<id>",
       "goal": "<goal>",
       "completed_at": "<iso>",
       "feature_count": <n>,
       "verdicts_summary": <object summarizing PASS counts>,
       "summary": "<your 1-3 paragraph narrative>",
       "tags": ["<keyword>", ...]
     }
   ```

5. Append final `log.md` entry.

5a. **Remove the mission-mode marker** for this mission: `rm -f "$CLAUDE_PROJECT_DIR/.claude/.mission-tick-active-<MISSION_ID>"`. Same reasoning as step 7 above — must happen before this procedure returns so post-mission interactive sessions aren't unexpectedly under the hardened-hook regime.

6. **Close the coordination.json row** for this mission: set `status: completed`, `completed: <iso>`.

7. Print to the user: `Mission <id> complete. <feature_count> features. <retry_counts summary>. Summary in <mission_root>/<id>/log.md.`

8. **PR handoff.** If `state.worktree` is set, compose a PR body from the mission artifacts:
   - **Title:** the first line of `state.goal` (first 70 chars; fallback to the contract's `## Mission scope` line). If `state.github.issue_url` is set, append ` (closes #<issue-number>)`.
   - **Body:** assembled markdown from the contract's scope section, feature acceptance criteria checkmarks (✓ for each met AC across `verdicts`), scrutiny + user-test PASS summary, retry counts, and a `Generated autonomously by Founder Stack v1 mission <id>` footer. If `state.github.issue_url` is set, prepend `Closes <url>`.

   **If `state.github.auto_pr == true`:**
   1. Run `bash -c 'cd <state.worktree.path> && git push -u origin <state.worktree.branch>'`. If push fails, surface stderr and skip to the manual hint path.
   2. Run `bash -c 'cd <state.worktree.path> && gh pr create --title "<title>" --body "<body>"'`. Capture stdout (the PR URL).
   3. Write `state.github.pr_url = <captured URL>` and save state.
   4. Print: `PR opened: <url>`. Append to `log.md`.

   **If `state.github.auto_pr == false` (default):** print the suggested commands for the user to review and run:
   ```
   Worktree at <state.worktree.path> on branch <state.worktree.branch>.
   Inspect: cd <state.worktree.path> && git diff <state.worktree.base_ref>
   Open PR:
     cd <state.worktree.path>
     git push -u origin <state.worktree.branch>
     gh pr create --title "<title>" --body "<body — multi-line, copy-pasteable>"
   After merge:
     git worktree remove <state.worktree.path>
     git branch -D <state.worktree.branch>
   ```
   Do **not** execute these for the user when auto_pr is false.

9. **Do not deploy.** Even with auto_pr, this procedure only opens the PR — merge and deploy decisions remain human.

## Guardrails

- **Never modify the contract after `status: approved`.** Acceptance failure forces a worker retry, not a contract relaxation. If the contract is genuinely wrong, the mission must `block` and the user must intervene via `/mission-resume` after editing the contract.
- **Never invoke `/test-gate`, `/design-gate`, etc. as slash commands.** Those are human entry points. This procedure dispatches the underlying v0.1 subagents (design-auditor, schema-analyst, …) directly via the Task tool.
- **Never silently fall back to local memory if Mem0 errors.** The broker errors out; you propagate the error to `log.md` and either retry or transition to `blocked`.
- **`state.json` writes must be atomic.** Write to `state.json.tmp`, then `Bash mv state.json.tmp state.json`.
- **Trip `resume_requested` early.** The cost of a resume is small; the cost of a context overflow mid-dispatch is a corrupted state file.
- **Do not write or edit any file outside `<mission_root>/<MISSION_ID>/`** except: (a) memory-broker writes under `<memory.local_root>/`, (b) appending to `log.md`, (c) writing/removing `.claude/.mission-tick-active-<MISSION_ID>` (the mission-mode marker — see step 1a). This procedure never edits source code.
- **Always remove the mission-mode marker before this procedure returns** — at the end of step 7 (next-tick path), at step 5a of Completion, and at every early-return point in step 3 (caps hit) / step 4 (context budget) / any `status: blocked` transition. Leaving a stale marker means the next interactive session is unexpectedly under the hardened-hook regime. If you discover stale markers from prior crashes, `rm -f .claude/.mission-tick-active-*` is safe.
- **Single-Bash-call atomic ops.** Use `Bash` for `openssl rand`, `date -u +%Y-%m-%dT%H:%M:%SZ`, `mv` — don't chain multiple Bash calls when one will do.
