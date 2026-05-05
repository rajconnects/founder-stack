---
description: Verify implemented frontend code against design spec, tokens, component contract, and Figma. Returns pass/fail with a gap list. Pass --strict to enforce the .design-approved-<scope> marker as a hard prerequisite (otherwise it's a soft warning).
argument-hint: <component name | file path | directory> [--strict] (comma-separated scope ok; omit scope for all recently-changed frontend files)
---

You are running the design gate.

**Arguments:** `$ARGUMENTS`

## Steps

1. If the scope portion of `$ARGUMENTS` is empty, determine scope by running `git diff --name-only HEAD~5 -- '*.tsx' '*.ts' '*.css'` and deduplicating to changed components/files. Otherwise use the provided scope. Detect `--strict` separately.

1b. **Approval-marker check.** For each component in scope, compute the scope slug (lowercase + alphanumerics + dashes) and check for `.claude/.design-approved-<scope-slug>` and `.claude/.design-bypass-<scope-slug>`.
   - **If `.design-bypass-<scope-slug>` exists:** prepend a loud warning regardless of `--strict`:
     ```
     > [bypass] This scope shipped via `/frontend-build --bypass`. Design approval was skipped — confirm with the operator that the bypass was justified.
     ```
     Continue to step 2 (audit still runs).
   - **If `.design-approved-<scope-slug>` is missing AND `--strict` is NOT set:** prepend a soft warning (verdict still computed by the audit):
     ```
     > [warn] No `.design-approved` marker for <component>. The components_spec and flow_spec entries may be hand-authored or pre-date the UX design layer. Audit will run; consider `/ux-wireframe <component>` then `/ux-mockup <component>` if results are unexpected. Use `/design-gate <scope> --strict` to enforce.
     ```
     Continue to step 2.
   - **If `.design-approved-<scope-slug>` is missing AND `--strict` IS set:** skip the audit and return verdict `FAIL` with reason `missing-design-approval`. List exactly which scopes lacked markers and the remediation: *"Run /ux-wireframe <scope> then /ux-mockup <scope>, or invoke /frontend-build with --bypass if you must ship without design sign-off."* Stop. Do not launch the auditor.

2. Launch the `design-auditor` subagent with a self-contained prompt:
   - The resolved scope (component names / file paths) as `changed_files` so the agent does not rediscover scope by grepping `frontend_root`.
   - Inline the relevant fields from `.claude/project.json` (tokens path, components_spec, flow_spec, figma config) — read it once here, don't make the agent re-read it.
   - Token-sync and Figma `get_variable_defs` are opt-in via `--full`; default is per-component audit only.
   - Ask for the standard audit output.

3. Print the audit result verbatim, with any approval-marker warnings (from step 1b) prepended. Do NOT soften FAILs, do NOT "interpret" gaps into your own words — the auditor's output is the gate.

4. If verdict is FAIL, list the specific next actions at the end: "Fix the N flagged items in design-auditor output, then re-run `/design-gate`." Do not auto-fix unless the user asks.

5. **Session hygiene hint (PASS only).** Append one line: `If the next task is unrelated to this scope, consider a session reset (in Claude Code: /clear). See docs/session-hygiene.md.` Do not print on FAIL or on bypass-marker warnings — the user is still in remediation mode.

## Notes

- This gate is required before `/handoff`. If the user tries to hand off without running it, remind them.
- Gap lists reference file:line. Make sure those refs are preserved when printing.
- If `design_system.figma.file_key` is null in project.json, the Figma audit is skipped automatically — that's by design for projects without a live Figma link.
- `--strict` is the "gate is a gate" stance: missing `.design-approved-<scope>` marker fails immediately, no audit. Default behavior leaves the gate soft so projects with hand-authored `components_spec` (pre-existing the UX layer) aren't punished. CI integrations should pass `--strict`.
- A `.design-bypass-<scope>` marker (set by `/frontend-build --bypass`) always triggers a loud warning, regardless of `--strict`. The audit still runs.
