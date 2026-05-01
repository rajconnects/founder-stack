---
description: Verify implemented frontend code against design spec, tokens, component contract, and Figma. Returns pass/fail with a gap list.
argument-hint: <component name | file path | directory> (comma-separated ok; omit for all recently-changed frontend files)
---

You are running the design gate.

**Arguments:** `$ARGUMENTS`

## Steps

1. If `$ARGUMENTS` is empty, determine scope by running `git diff --name-only HEAD~5 -- '*.tsx' '*.ts' '*.css'` and deduplicating to changed components/files. Otherwise use the provided scope.

2. Launch the `design-auditor` subagent with a self-contained prompt:
   - The resolved scope (component names / file paths).
   - Instruct it to read `.claude/project.json` for tokens path, components_spec, flow_spec, and figma config.
   - Ask for the standard audit output.

3. Print the audit result verbatim. Do NOT soften FAILs, do NOT "interpret" gaps into your own words — the auditor's output is the gate.

4. If verdict is FAIL, list the specific next actions at the end: "Fix the N flagged items in design-auditor output, then re-run `/design-gate`." Do not auto-fix unless the user asks.

## Notes

- This gate is required before `/handoff`. If the user tries to hand off without running it, remind them.
- Gap lists reference file:line. Make sure those refs are preserved when printing.
- If `design_system.figma.file_key` is null in project.json, the Figma audit is skipped automatically — that's by design for projects without a live Figma link.
