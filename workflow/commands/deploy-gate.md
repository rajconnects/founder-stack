---
description: Post-deploy smoke verification — health check, Playwright smoke, log scan. Does not deploy or roll back.
argument-hint: staging | prod
---

You are running the deploy gate AFTER a deploy has completed.

**Arguments:** `$ARGUMENTS`

## Steps

1. If `$ARGUMENTS` is empty, default to `staging`. If the argument is `prod`, confirm with the user: "Run deploy-gate against prod? Smoke tests are read-only but add load. (yes/no)" — do NOT proceed without explicit yes.

2. Launch the `deploy-verifier` subagent with a self-contained prompt:
   - The environment name.
   - Instruct it to read `.claude/project.json` for `deploy_targets[<env>]` and `stack.supabase_project_ref`.
   - Ask for the standard verdict output.

3. Print the output verbatim.

4. Record the gate pass/fail for this session (lightweight marker: `touch .claude/.deploy-gate-passed-<env>` on PASS).

5. If verdict is FAIL, do NOT suggest code changes — the user's next step is diagnosis and rollback decision. Surface the failure details and stop.

6. **Session hygiene hint (PASS only).** Append one line: `Deploy verified. If you're moving to a different feature next, consider a session reset (in Claude Code: /clear). See docs/session-hygiene.md.` Skip on FAIL.

## Notes

- This is a READ-ONLY gate. The verifier cannot deploy, restart, or roll back. If the user wants those, they invoke their deploy tooling separately.
- Prod gate runs only with explicit confirmation — that's a safety rail, not an annoyance.
- Health check + smoke + logs is the full scope. Do not extend into load tests or long-running assertions; those belong in CI.
