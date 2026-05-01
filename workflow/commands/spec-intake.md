---
description: Read a spec file (or the latest in spec_roots) and produce a structured execution plan. Enters plan mode with the generated plan.
argument-hint: <spec file path> | auto
---

You are running the intake step of the engineering workflow.

**Arguments:** `$ARGUMENTS`

## Steps

1. Launch the `spec-translator` subagent with a self-contained prompt:
   - The spec argument (`$ARGUMENTS`), or `auto` to pick the latest.
   - Instruct it to read `.claude/project.json` first to resolve paths.
   - Ask for the standard plan output format.

2. When the subagent returns, do NOT synthesize — print the plan verbatim for the user.

3. Ask the user: "Enter plan mode with this plan? (yes/no)" — if yes, use the standard plan workflow (the plan content becomes the basis for a plan file). If no, stop here.

## Notes

- Never translate specs yourself; always delegate to `spec-translator`. It has the right tool scope (Read/Grep/Glob only) and the right system prompt.
- If the subagent returns an ERROR (missing `.claude/project.json` or invalid spec), surface it verbatim and stop.
- The generated plan is intentionally terse — don't expand it, don't add implementation details. Implementation happens after plan approval.
