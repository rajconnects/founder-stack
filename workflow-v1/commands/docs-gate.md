---
description: Audit framework docs for drift — broken file refs, dead command refs, unused project.json keys, and CHANGELOG-vs-diff overclaim/underclaim. Dispatches docs-auditor.
argument-hint: [scope: changelog | readme | playbook | docs | full] [--range <git-range>]
---

You are running a docs-drift check on the framework's published documentation.

**Arguments:** `$ARGUMENTS`

## Steps

1. **Parse the scope arg.** One of `changelog`, `readme`, `playbook`, `docs`, `full`. Default `full`. Anything else: print the recognized values and stop.

2. **Parse `--range`** if present (e.g., `--range main..HEAD`). Default `HEAD~5..HEAD`. Used only when the scope includes the CHANGELOG-vs-diff pass.

3. **Dispatch docs-auditor:**

   ```
   subagent_type: docs-auditor
   prompt: |
     SCOPE: <parsed scope>
     DIFF_RANGE: <parsed range>
     VERDICT_OUTPUT_PATH: <not set — print to stdout>
   ```

4. When the auditor returns, print its verdict verbatim. Do not synthesize on top of it.

5. If the verdict is FAIL, do not auto-fix. Surface to the user and stop — drift fixes are the user's call (sometimes a broken link is a real removal; sometimes it's a typo).

## Notes

- The auditor is **read-only**. It catches drift; it does not write docs.
- Scope `full` is the most thorough but the slowest — use `changelog` or `readme` for fast targeted runs while iterating on a release entry.
- The CHANGELOG-vs-diff pass uses judgment (not strict matching) — a single CHANGELOG bullet can describe a thematic change touching multiple files; the auditor only surfaces meaningful gaps. Treat its findings as advisory.
- Missions auto-dispatch this auditor in Procedure D (mission completion), with `SCOPE: mission-completion` and `MISSION_ID` scoped to the mission's commit range. Manual runs target the same auditor.
