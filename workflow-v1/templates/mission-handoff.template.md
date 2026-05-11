---
feature_id: {{feature_id}}
worker_dispatch: {{n}}
status: COMPLETE | PARTIAL | BLOCKED
finished_at: {{iso8601}}
---

> Workers fill this in at the end of every dispatch. Front-matter is required and machine-read by the orchestrator. Section order below is also required — scrutiny-validator parses by heading.

## commands_run

List every command the worker ran during this dispatch, in order, with its exit code. Even if a command was retried, list both runs.

- `<command>` → exit 0
- `<command>` → exit 1
- `<command>` → exit 0

## files_touched

Every file created, edited, or deleted by this dispatch. Use `(created)`, `(edited)`, `(deleted)` suffixes. Paths relative to repo root.

- `apps/web/src/components/Counter.tsx` (created)
- `apps/web/src/components/Counter.test.tsx` (created)

## contract_coverage

For each acceptance criterion in the feature's contract, declare `met` or `unmet`. If `unmet`, give a one-line reason. The orchestrator uses this to decide retry vs. advance.

- AC-1: met
- AC-2: met
- AC-3: unmet — localStorage key chosen ("counter") does not match contract spec ("counter:v1")

## issues_discovered

Anything the worker noticed that wasn't in the contract — adjacent bugs, unclear specs, blocked dependencies. Surface, don't fix unilaterally. The orchestrator decides whether to spawn a follow-up feature.

- None
- OR: `<one-line description>` — type: spec-gap | adjacent-bug | dep-blocked

## notes

Brief judgment calls the worker made that future readers might second-guess. Keep tight.

- Chose localStorage key `counter:v1` — see AC-3.
- Used `useSyncExternalStore` instead of `useState` + `useEffect` to handle SSR hydration.
