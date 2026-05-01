---
description: Write failing tests FIRST that establish the feature contract from the spec. Tests go red; implementation makes them go green.
argument-hint: <feature name | component name | spec section reference>
---

You are running the test gate. This gate runs BEFORE implementation — tests establish the contract.

**Arguments:** `$ARGUMENTS`

## Steps

1. If `$ARGUMENTS` is empty, fail fast: "test-gate requires a scope (feature/component name or spec section). Example: `/test-gate ThemeToggle`." Do not guess.

2. **Classify the scope.** Read the cited brief/spec section. Pick one:
   - **Bounded** — acceptance criteria explicitly enumerate ≤5 test cases AND the contract fits in one paragraph. → main agent writes tests inline (step 3).
   - **Open** — criteria are prose, list >5 cases, or the contract is ambiguous. → delegate to subagent (step 4).

3. **(Bounded path.)** Read the cited spec section. Write 3–5 behavior/structure tests in the adjacent `*.test.tsx` / `tests/` location. Skip styling assertions — those are `/design-gate`'s job. Run `test_commands.*` from `test_commands.*_cwd`. Confirm failures are contract failures. If the test runner itself is broken (JSX runtime, polyfill gap, stale deps), fix it inline — config rot is a tax of doing business, not a workflow step. Report tests + paths. Skip to step 5.

4. **(Open path.)** Launch the `test-author` subagent with a self-contained prompt:
   - The scope argument.
   - Instruct it to read `.claude/project.json` for `test_commands`, `test_roots`, `design_system.*_spec`.
   - Ask it to write failing tests, run them to confirm the failure mode is a contract failure, and return the standard output.
   Print the subagent output verbatim.

5. If verdict is CONTRACT_ESTABLISHED (bounded or open), remind: "Tests red by design. Implement against the test file(s). When green, run `/design-gate <scope>`."

6. If verdict is ERROR (spec has no acceptance criteria), surface it — the user's next step is to tighten the spec, not to write code.

7. **Real-corpus gate (if `real_corpora` is configured in project.json).** Synthetic fixtures don't catch the gap between "code accepts the shape we wrote" and "code accepts the shape on disk." For each entry in `real_corpora`:
   - Resolve `validator` (file path + named export). Load the validator at test time, not at this gate's runtime.
   - List every artifact under `path`. For each, run it through the validator.
   - On any failure: surface the file path + the specific validator error. Do NOT auto-fix; the spec or the validator (depending on which is correct) needs to change. This is a contract conversation, not a code task.
   - On pass: log `[real-corpus] <name>: <count> validated` so the result is visible in handoff output.
   This step is the difference between "tests passed against my fixtures" and "the system handles real data." If the project doesn't ship a corpus on disk, omit `real_corpora` and skip this step.

## Notes

- Main agent writes tests when the contract already fits in your head; subagent writes when scope is open-ended. Delegation has overhead (prompt, context handoff, review) — pay it only when task size warrants.
- Neither path writes implementation. Tests must fail on the current repo state before implementation starts.
- If tests already exist and cover the spec, report that — don't duplicate.
- Re-running is idempotent: if contract tests exist, report "already established."
