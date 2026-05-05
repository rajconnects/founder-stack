---
description: Review a pending DB migration. Static checks (drops/renames/truncates) run as a deterministic shell pre-pass; live-DB checks (RLS, index size, forward-compat) run via a Haiku subagent. Read-only.
argument-hint: <migration file path | glob> | auto [--with-advisors] [--notes <path>]
---

You are running the schema gate.

**Arguments:** `$ARGUMENTS`

## Steps

1. **Resolve files.** If `$ARGUMENTS` is empty or `auto`, read `migrations` from `.claude/project.json` and pick files in that dir modified within the last hour. Otherwise use the path/glob given. If none found: fail loudly.

2. **Cache check.** For each migration file, compute `sha256sum`. If `.claude/.schema-gate-cache/<sha>.md` exists, print it, refresh `.claude/.schema-gate-passed`, and stop. Re-running the gate on unchanged files must not invoke the agent.

3. **Static pre-pass (deterministic, free).** Run `workflow/hooks/schema-static-scan.sh <file>...`. If it exits non-zero, print its findings, remove `.claude/.schema-gate-passed`, and stop — these are unambiguous FAILs the agent cannot rescue.

4. **Resolve config and parse migration shape.** Read `.claude/project.json` once. Extract `stack.supabase_project_ref` and `migrations`. Then parse the migration SQL to extract:
   - `new_tables` — `CREATE TABLE [IF NOT EXISTS] <name>` matches.
   - `new_columns` — `ALTER TABLE <t> ADD COLUMN <c>` matches.
   - `new_indexes` — `CREATE [UNIQUE] INDEX [CONCURRENTLY] <n> ON <t>` matches; record whether `CONCURRENTLY` is present.
   If the migration has none of these (e.g. function-only DDL), skip step 5 and emit `verdict: PASS — no schema surface to audit`.

5. **Launch `schema-analyst`** with a self-contained prompt containing: the migration file paths, `supabase_project_ref`, the parsed `new_tables` / `new_columns` / `new_indexes`, and (if `--notes <path>` was passed) the evolution-notes path. Do NOT ask the agent to re-read `project.json`.

6. **Optional advisors pass.** If `--with-advisors` was passed AND the agent returned `verdict: PASS`, call `mcp__claude_ai_Supabase__get_advisors` once from this slash command and append a one-line summary. Do not run advisors by default — they are project-wide and noisy.

7. **Cache and mark.** Save the agent output to `.claude/.schema-gate-cache/<sha>.md`. On PASS, `touch .claude/.schema-gate-passed`. On FAIL, `rm -f .claude/.schema-gate-passed`.

8. **Print.** On PASS, print one line: `schema-gate: PASS — <N> tables, <M> columns, <K> indexes audited`. On FAIL or PASS_WITH_WARNINGS, print the agent's terse output verbatim.

## Notes

- The static scan catches the cheap fails for free. The agent only sees migrations that already passed it.
- The agent runs on Haiku — output is intentionally terse. Don't pad it.
- The gate is read-only. Even if the agent suggests an "Apply command", the user runs it.
- `--notes <path>` is the only way forward-compat is checked; there is no broad architecture-notes grep anymore.
