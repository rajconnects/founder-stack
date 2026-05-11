# Mission contract: {{mission_id}}

**Goal:** {{goal}}

**Authored:** {{date}}
**Author:** mission-orchestrator
**Status:** draft | approved | locked

> The contract is written **before** any worker dispatch. Workers and validators read their feature's section as the spec of done. The orchestrator does not rewrite contract sections after lock — failed acceptance triggers a worker re-dispatch with the prior handoff, not a contract relaxation.

## Mission scope

**In scope:** <one-line summary of what this mission delivers end-to-end>

**Out of scope:** <bullet list of things deliberately deferred — be explicit, prevents scope drift mid-mission>

## Prior-mission references

<inserted by memory-broker at contract-authoring time; up to 3 nearest prior missions by keyword match (local) or semantic search (Mem0). Orchestrator paraphrases relevance in one line each. Delete this section if no prior missions are relevant.>

- mission `<id>` ({{goal}}) — relevance: <why it informs this contract>

---

## Feature f01: <feature-name>

**Files in scope:** <list of file paths the worker is permitted to create or edit. Anything outside this list requires orchestrator approval via a new contract revision.>

**Depends on:** none | f00, f02

**Acceptance criteria** (each becomes a contract-coverage line in the worker's handoff):

- AC-1: <verifiable claim about behavior or shape>
- AC-2: <…>
- AC-3: <…>

**Test contract** (red tests required before worker dispatch begins production code):

- <test file path>:<describe-block name> covers AC-1, AC-2
- <test file path>:<describe-block name> covers AC-3

**Design contract** (skip if no UI):

- Tokens: every color must come from `{{design_system.tokens}}`; no hex literals.
- Component spec section: <link or anchor>
- Figma node: <node_id or "none">

**Schema contract** (skip if no DB):

- Migration files: <path or "none">
- RLS expectations: <one line>
- Index expectations: <one line>

**User flows** (consumed by `user-flow-tester` when `mission_user_test.preview_url_command` is set in project.json; auto-skipped otherwise):

- UF-1: <natural-language scenario, e.g. "Navigate to /, click increment 3 times, reload page, assert count text shows '3'">

Author flows in plain English using verbs the tester parses: *Navigate to*, *Click <label>*, *Type X into <field>*, *Reload*, *Wait for X*, *Assert <claim>*. Be specific enough that there's exactly one element matching each `<label>` — ambiguity causes FAIL.

**Out of scope for this feature:** <bullet list>

---

## Feature f02: <feature-name>

<…repeat structure…>

---

## Definition of mission complete

The mission is `completed` when:

- Every feature has `status: completed` in `state.json`.
- Every feature's `verdicts.<id>.scrutiny == "PASS"`.
- Every feature's `verdicts.<id>.user_test == "PASS"` (or `"skipped"` if no `user_flows` declared and `mission_user_test.preview_url_command` is null).
- No `error_log` entries with severity `blocking`.

If any of these fails after caps are exhausted, the mission transitions to `status: blocked` and waits for human `/mission-resume` or `/mission-abort`.
