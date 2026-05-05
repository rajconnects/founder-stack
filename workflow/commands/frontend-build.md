---
description: Produce a design-context-aware frontend implementation brief and write a scaffold file. Hard gate on `.design-approved-<scope>` (set by /ux-mockup approval). Use --bypass for emergencies; bypasses are recorded and surfaced in /handoff.
argument-hint: <component name | scope> [--bypass]
---

You are running the frontend specialist build step.

**Arguments:** `$ARGUMENTS`

## Steps

1. **Resolve scope.** Parse `$ARGUMENTS`. Scope is required — there is no `auto`. If empty, fail loudly: `frontend-build requires an explicit scope. Example: /frontend-build OnboardingForm.`

2. **Compute the scope slug.** Lowercase, alphanumerics + dashes only. Same slugification as `/ux-wireframe` and `/ux-mockup`.

3. **Hard gate on design approval.** Check for `.claude/.design-approved-<scope-slug>`.
   - **If present:** continue with `approval_state = approved`.
   - **If missing AND `--bypass` is NOT set:** fail with verdict `BLOCKED_NO_DESIGN_APPROVAL`. Print the exact remediation: *"Run /ux-wireframe <scope> then /ux-mockup <scope> and approve. Or pass --bypass if this is an emergency (will be flagged in handoff)."* Stop. Do not launch the agent.
   - **If missing AND `--bypass` IS set:** `touch .claude/.design-bypass-<scope-slug>` (consumed by `/handoff` and `/design-gate`). Print: *"⚠ Design approval bypassed for <scope>. This will be surfaced in /handoff."* Continue with `approval_state = bypassed`.

4. **Resolve config and inline.** Read `.claude/project.json` once. Extract: `design_system.components_spec`, `design_system.flow_spec`, `design_system.tokens`, `design_system.figma.file_key`, `design_system.figma.screens`, `stack.frontend`, `stack.frontend_root`, `test_roots.frontend`, `test_commands.frontend`. If `stack.frontend` is null, fail: `frontend-build only runs for frontend stacks (stack.frontend is null).` If `frontend_root` is null, fail likewise.

5. **Launch `frontend-engineer`** with a self-contained prompt containing: scope label and slug, the inlined config fields above, and `approval_state`. Do NOT ask the agent to re-read `project.json`. Do NOT ask the agent to write files — that is your job.

6. **Print the agent output verbatim.** Including the brief sections (composition, optimization, scaffold body). Do not soften or reinterpret.

7. **Write the scaffold (or skip).** Parse the agent output:
   - Extract the **File path** from the agent header.
   - Extract the **scaffold body** from the `## (c) Scaffold body` code fence.
   - **If file at the resolved path exists:** print *"File exists at `<path>` — emitting brief only. No scaffold written."* Do not write. Do not ask. Continue cleanly.
   - **If file does not exist:** ask the operator: *"Write scaffold to `<path>`? (yes/no)"*. On `yes`, Write the scaffold body to that path. On `no`, skip.

8. **Closing line.** On success print: *"Brief delivered. Implement against `<test-path>` (red tests). Run `/design-gate <scope>` before `/handoff`."*

## Notes

- The hard gate exists because design drift into engineering is the most expensive bug class to catch later. `--bypass` is a real escape hatch, not a habit — every bypass surfaces in `/handoff` for the operator to justify.
- Per Branch 4 (write-authority discipline): the agent emits the scaffold body in Markdown; the command performs the file write. This keeps writes centralized in commands so audit trails stay in one place.
- The brief is the artifact even when the scaffold is skipped (file exists). The main agent reads the brief and implements against the existing file.
- Markers (`.design-approved-<scope>`, `.design-bypass-<scope>`) are gitignored and per-session.
- If `figma.file_key` is null, the agent skips the Figma reference step; the brief still ships with `components_spec` + `flow_spec` citations.
