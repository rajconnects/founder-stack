---
description: Review a pending DB migration for additive-only, RLS coverage, data-loss risk, index impact, and forward-compat. Queries live DB read-only.
argument-hint: <migration file path | glob> | auto
---

You are running the schema gate.

**Arguments:** `$ARGUMENTS`

## Steps

1. If `$ARGUMENTS` is empty or `auto`, find migration files modified in the last hour under the `migrations` path from `.claude/project.json`. If none, fail: "schema-gate found no recent migrations. Pass a file path or edit a migration first."

2. Launch the `schema-analyst` subagent with a self-contained prompt:
   - The resolved migration file(s).
   - Instruct it to read `.claude/project.json` for `migrations` path, `stack.db`, `stack.supabase_project_ref`.
   - Ask for the standard five-risk audit output.

3. Print the audit verbatim.

4. Record the gate pass/fail for this session (so `/deploy-gate` and migration-guard hooks can check). A lightweight marker file is fine: `touch .claude/.schema-gate-passed` on PASS, remove on FAIL.

5. If verdict is FAIL or PASS_WITH_WARNINGS, list the exact line-level fixes from the analyst output. Do not apply — this is a gate, not an executor.

## Notes

- The schema-analyst only reads the DB. It never applies migrations. Even if it returns an "Apply command," the user executes it.
- If `stack.db` is not Supabase, the analyst errors out — that's expected; adapt project.json or extend the agent.
- `get_advisors` results are pre-existing issues, not caused by this migration. Surface them but don't count them against the verdict unless the migration worsens them.
