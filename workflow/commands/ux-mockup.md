---
description: Refine wireframes into high-fidelity Figma mockups, then run the human approve/iterate/reject ritual. On approve, sets `.design-approved-<scope>` marker — the engineering hard gate consumed by /frontend-build. Layer 1.7 of the workflow; requires /ux-wireframe first.
argument-hint: <scope name> [--source <figma-url|node-id>] [--skip-when-trivial]
---

You are running the mockup step of the UX design layer. This step ends with a human approve/iterate/reject prompt — you do not approve on the operator's behalf.

**Arguments:** `$ARGUMENTS`

## Steps

1. **Resolve scope.** Parse `$ARGUMENTS`. The scope label is required — there is no `auto` for mockup work, since high-fidelity needs an explicit target. If empty: fail loudly: `ux-mockup requires an explicit scope. Example: /ux-mockup OnboardingForm.`

2. **Compute the scope slug.** Same slugification as `/ux-wireframe`.

3. **Verify wireframe prerequisite.** Check for `.claude/.ux-wireframe-passed-<scope-slug>`. If missing: fail: `No wireframe marker for <scope>. Run /ux-wireframe <scope> first.` Do not proceed.

4. **Resolve config and inline.** Read `.claude/project.json` once. Extract: `design_system.components_spec`, `design_system.flow_spec`, `design_system.tokens`, `design_system.figma.file_key`, `design_system.figma.screens`, `stack.frontend`. If `stack.frontend` is null, fail. If `figma.file_key` is null AND `--skip-when-trivial` is NOT set, fail: `ux-mockup requires figma.file_key to produce mockup frames. Pass --skip-when-trivial to skip Figma writes and proceed straight to approval.`

5. **Launch `ux-mockup-designer`** with a self-contained prompt containing: the scope label and slug, the inlined config fields above, the `--source` reference (if any), and the `--skip-when-trivial` flag (if any). Do NOT ask the agent to re-read `project.json`.

6. **Print the agent output verbatim.**

7. **Run the approve/iterate/reject ritual.** This step is owned by the command, not the agent — human-gate authority lives here.

   ```
   Mockups produced. Review them carefully (Figma frames listed above).
   Approve to push to engineering, iterate to refine, reject to abort.
   > approve / iterate / reject
   ```

   - On `approve`: `touch .claude/.design-approved-<scope-slug>`. Print: `Design approved for <scope>. Engineering may proceed via /frontend-build <scope>.`
   - On `iterate`: write nothing. Print: `Iterating. Make changes in Figma (or re-run /ux-wireframe <scope> for contract changes), then re-run /ux-mockup <scope>.`
   - On `reject`: write nothing. Ask the operator for a one-line reason. Print: `Mockup rejected: <reason>. No marker written. Re-run /ux-wireframe <scope> with the reason in mind.`

## Notes

- The `.design-approved-<scope-slug>` marker is the **hard gate** consumed by `/frontend-build`. Without it, engineering work is blocked unless the operator explicitly bypasses (recorded in the handoff doc).
- `--skip-when-trivial` skips Figma writes but still runs the approval ritual. Use for one-line scopes where the wireframe contract is enough.
- Markers are gitignored and per-session. Re-running `/ux-mockup` always re-runs the agent and re-prompts approval.
- If the operator approves without reviewing (very fast turnaround), trust them. Time-between-mockup-and-approval telemetry is a future polish, not a gate.
