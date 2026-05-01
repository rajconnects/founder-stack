---
description: Start a phase build with verifiable session state and an isolated git worktree. Wraps /spec-intake, claims files/branches/remote-ops in coordination.json, and spawns a worktree.
argument-hint: <phase id> [--severity major|minor] [--spec <path>]
---

You are starting a phase build. This command makes parallel-session coordination mechanical.

**Arguments:** `$ARGUMENTS`

## Steps

1. **Parse arguments.** First positional = phase id (e.g., `7a`, `docs-cleanup`). Optional flags:
   - `--severity major|minor` (default: ask the user — major = siblings pause; minor = siblings proceed with caution)
   - `--spec <path>` (optional — if given, run `/spec-intake <path>` first; otherwise ask the user for plan summary)

   If phase id missing, fail fast: `/start-build requires a phase id. Example: /start-build 7a --severity major`.

2. **Pre-sweep stale rows.** Read `.claude/coordination.json`. For each row with `status: active`:
   - Compute heartbeat age. If older than `_doc.staleness_threshold_minutes` (default 10), flip to `completed_unclean`, set `completed` timestamp, and note `worktree` path for cleanup.
   - For each `completed_unclean` row whose `worktree` path still exists on disk: run `git worktree remove --force <path>`. If removal fails, log the path so the user can investigate.

3. **Conflict check.** Among remaining `status: active` rows:
   - If any row has `severity: major` → **surface to the user** with the row's `plan_summary`, `branch`, and `claims`. Ask: *"Session `<id>` is running a major build on `<branch>`. Pause this build or proceed with caution?"* — let the user decide.
   - If any row has `severity: minor` and its `claims.files` glob-overlap your intended claims → **surface** the overlap and ask the user how to proceed.
   - If no overlap and no major sibling → proceed silently.

4. **Run intake (if not done).**
   - If `--spec` provided: invoke `/spec-intake <spec>` and use its plan as the basis.
   - Otherwise: ask the user for a one-line `plan_summary`, plus rough `claims` (files as globs, branches that will be pushed, remote ops like `migration` or `deploy:staging`).

5. **Capture session id.**
   - Read `$CLAUDE_SESSION_ID` from environment. If unset, ask the user to paste the resume id from the most recent `/resume` output (they can run `/resume` and copy the uuid).
   - Generate a new short id for `id` (e.g., `sess-` + first 8 chars of a uuid).

6. **Create the worktree.**
   - Branch name: phase id (e.g., `phase-7a-app-shell`) or as user specifies.
   - Worktree path: sibling to the repo root, named `../<repo-basename>-<branch-slug>`.
   - Run: `git worktree add <worktree-path> -b <branch-name>` (or without `-b` if branch already exists).
   - If `git worktree add` fails (branch exists in another worktree, dirty state, etc.), surface the error and stop — do not write the session row until the worktree exists.

7. **Write the session row** to `.claude/coordination.json`:
   ```json
   {
     "id": "sess-<id>",
     "resume_id": "<CLAUDE_SESSION_ID>",
     "status": "active",
     "severity": "<major|minor>",
     "phase": "<phase-id>",
     "branch": "<branch-name>",
     "worktree": "<absolute-worktree-path>",
     "plan_summary": "<one-line>",
     "claims": { "files": [...], "branches": [...], "remote_ops": [...] },
     "started": "<ISO-8601 now>",
     "heartbeat": "<ISO-8601 now>"
   }
   ```
   Append to `sessions` array. Preserve all other rows untouched.

8. **Print handoff to the user:**
   ```
   ✅ Build claim recorded: sess-<id> (severity: <major|minor>)
   Worktree: <absolute path>
   Branch:   <branch>
   Plan:     <summary>

   Next: cd '<worktree path>' and continue work there.
   To close this build: /handoff <phase-id>
   ```

## Notes

- **Heartbeat.** This command writes the initial heartbeat. Refresh during execution is convention-based until a hook is added — Claude should re-write `heartbeat` to the current ISO-8601 time when reading the file at turn start, if its own row is `active`.
- **Severity guidance.** Major = multi-day, multi-file, on a feature branch (e.g., a phase). Minor = single-file edits, doc updates, quick fixes. When in doubt, mark major — siblings can always choose to proceed.
- **Why pre-sweep before claim.** A leaked active row would block a legitimate new build. Sweeping first means a crashed previous session never permanently locks the workflow.
- **No overwrite.** Never replace the `sessions` array; append. Never edit other sessions' rows except to flip stale ones to `completed_unclean`.
- **Failure mode.** If anything between step 6 and step 8 fails after the worktree is created, surface the worktree path so the user can clean it up manually with `git worktree remove`.
