---
description: Generate a phase handoff doc from the template, update build-status, and prompt decision-trace capture for open items.
argument-hint: <phase name or identifier, e.g., 6a>
---

You are running the end-of-phase handoff.

**Arguments:** `$ARGUMENTS`

## Steps

1. If `$ARGUMENTS` is empty, fail fast: "handoff requires a phase identifier. Example: `/handoff 6a`."

2. Read `.claude/project.json`. Extract `handoff_template`, `handoff_output_dir`, `build_status_file`, `decision_traces`.

3. **Pre-flight gate check.** Look for session markers:
   - `.claude/.design-gate-passed` (optional but expected)
   - `.claude/.schema-gate-passed` (only if this phase touched migrations)
   - `.claude/.deploy-gate-passed-staging` (required if phase is shipping a hosted service)
   - `.claude/.publish-gate-passed-<artifact>` (required if phase is shipping a packaged artifact, one per entry in `release_artifacts`)
   
   If any required marker is missing, warn the user and ask whether to proceed anyway. Do NOT silently generate a handoff doc for an unverified phase.

3b. **Design-bypass scan.** Glob `.claude/.design-bypass-*`. For each marker found, extract the scope slug from the filename. Print loudly:
   *"⚠ Design approval bypassed for: <scope-list>. The operator invoked `/frontend-build --bypass` for these scopes. Confirm justification before completing handoff."*
   Ask the user for a one-line justification per bypass; record under "Known risks / deferred items" in the generated handoff doc (step 5). After the handoff doc is written successfully (step 5), delete the bypass markers — they should not carry into the next phase.

3a. **Schema-of-record drift check (if `schemas_of_record` is configured).** Protocol/schema bugs are easy to miss because the truth lives in multiple places that drift independently. For each entry in `schemas_of_record`:
   - Run `git diff --name-only <phase-start-ref> HEAD` to see what changed in this phase.
   - If `canonical` is in the diff, ALL `shadowed_by` paths SHOULD also be in the diff. Surface mismatches: *"You changed `<canonical>` but not `<shadowed_by[i]>`. Producer/consumer drift risk — confirm intentional."*
   - If only some `shadowed_by` paths changed but not the canonical, surface the inverse: *"You changed `<shadowed_by[i]>` but not the canonical `<canonical>`. The schema spec may now be out of sync with implementation."*
   This is a soft check — the user confirms intent. Some changes legitimately affect only one site (e.g., a runtime validator becoming more lenient than the spec on purpose). Surface the discrepancy; let the user decide.

4. **Read the template** at `handoff_template`. Read the current `build_status_file` to understand what's been shipped.

5. **Generate handoff doc.** Output path: `<handoff_output_dir>/phase-<ARGS>-handoff.md`. Fill in the template with:
   - Phase name, start date (ask user if unknown), end date (today per CLAUDE.md currentDate).
   - What shipped (grep `git log --oneline --since=<phase start>` for commits in phase).
   - Gate results (from session markers + user recall).
   - Known risks / deferred items (ask user; do not fabricate).
   - Open decisions surfaced during the phase (see step 6).
   - Next-phase entry criteria.

6. **Open decisions scan.** Ask the user: "Did this phase surface any decisions that need capturing? (yes/no/list)". If yes or a list is given, capture each one as a trace file in `decision_traces` (path from `project.json`) using the schema documented in `docs/decision-traces.md` — `id`, `date`, `title`, `status`, `decided_by`, `decision`, `alternatives_rejected[]`, `rationale`, `revisit_triggers[]`. If the project has a `decision-trace-capture` skill installed, delegate to it instead. One file per decision.

7. **Update build-status.** Append or update the section for this phase in `build_status_file`: items shipped, items deferred, known risks. Preserve existing structure.

8. **Close the session claim.** Read `.claude/coordination.json`:
   - Find the row where `phase` matches `$ARGUMENTS` and `status: active`. If multiple match (rare), prefer the one whose `worktree` path equals `$PWD` or is the current worktree per `git rev-parse --show-toplevel`.
   - If found: set `status: completed`, set `completed` to now (ISO-8601), preserve all other fields.
   - If the row's `worktree` path is set and exists, ask the user: *"Remove worktree at `<path>`? (yes/no)"*. On yes, run `git worktree remove '<path>'` from the main repo root. Do **not** force-remove if uncommitted changes exist — surface and stop.
   - If no matching row: warn but continue (this handoff may pre-date the start-build flow).

9. **Print summary.** Filename of generated handoff, count of decisions captured, session row status (closed / not found), worktree status (removed / kept / not applicable), next phase name (if listed in build-status).

## Notes

- Handoff is the ritual that makes phases mechanical. Do not skip steps even if the user asks to hurry — that's how risks get buried.
- The handoff template is the source of truth for structure. If the template file is missing, fail — don't improvise.
- Handoff writes are append-style on `build_status_file`. Never replace existing phase sections; append or update-in-place by heading.
- Session markers are lightweight — a missing marker is a warning, not a hard block. The user may have run the gate in a prior session.
