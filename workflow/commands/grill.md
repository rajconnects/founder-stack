---
description: Stress-test a plan or proposal against the project context doc, glossary, and prior decision records. Surfaces contradictions, sharpens fuzzy language, and walks the decision tree one branch at a time. Adapted from mattpocock/skills/grill-with-docs.
argument-hint: <plan name or "current"> | the plan-mode plan if none given
---

You are running a grilling session: stress-testing a plan against the project's documented thinking before it advances to implementation.

**Arguments:** `$ARGUMENTS`

## Steps

1. **Resolve the plan to grill.**
   - If `$ARGUMENTS` is a file path, read it.
   - If `$ARGUMENTS` is `current` or empty, use the active plan-mode plan from this conversation.
   - If neither, ask the user: "Which plan should I grill? Paste it, give me a path, or say `current` to use the in-conversation plan."

2. **Resolve project context.** Read `.claude/project.json`. Extract:
   - `context_doc` — the project's primary thesis/context document (e.g. `CLAUDE.md`, `CONTEXT.md`).
   - `glossary_doc` + `glossary_anchor` — where the project's domain vocabulary lives.
   - `decision_records.path` and `decision_records.format` — where prior resolved decisions are stored.
   - `architecture_notes` — where long-form architecture memos live (optional).

3. **Load the project's thinking.** Read in this order:
   - The `context_doc` in full.
   - The glossary section (anchor) inside `glossary_doc`.
   - Index decision records:
     - If `format` is `json-traces`: glob `<path>/*.json`, read each, build a list of `(topic, status, resolution_summary, revisit_trigger)` tuples. Filter to `status: resolved` for the challenge phase.
     - If `format` is `markdown-adr`: glob `<path>/*.md`, parse the title and "Decision" / "Consequences" sections.
     - If `format` is `mixed`: do both.
   - Skim `architecture_notes` filenames for any obviously relevant memos. Read full content only if a name matches the plan's scope.

4. **Run the grilling loop.** Walk down each branch of the plan's decision tree, one question at a time. For each question, also propose your recommended answer based on what you've read. Wait for the user's response before continuing to the next question. Stop only when every branch is resolved or explicitly deferred.

   Cover at minimum:
   - **Glossary conflicts.** Does the plan use a term that conflicts with the glossary's definition? Surface it: "The glossary says X means A, but you seem to mean B — which is it?"
   - **Fuzzy terms.** Does the plan use vague or overloaded words? Propose a precise canonical term from the glossary.
   - **Prior decision conflicts.** Does the plan contradict any resolved decision record? Surface the trace ID and the original resolution. Ask: "This conflicts with [trace topic, resolved on date]. The original resolution was: [summary]. Reopen, or revise the plan?"
   - **Concrete scenarios.** When the plan asserts how something works, invent a concrete edge-case scenario and ask the user to confirm. ("If a user does X mid-flow, what does the plan say happens?")
   - **Untested assumptions.** When the plan asserts a fact, ask: "How do we know this? Is there a measurement, a prior decision, or is this assumption?" Tag assumptions for later validation.
   - **Code agreement.** When the plan describes how the system behaves, spot-check the code if a path is implied. Surface any divergence between plan and code.

5. **Update the project's thinking inline.** As terms are resolved or decisions crystallize, do not batch them.
   - **Glossary update needed.** If the user clarifies or introduces a term that should live in the glossary, propose the exact diff and ask permission before writing.
   - **Decision needs capturing.** If the grilling produces a new decision (or revises a prior one), say: "This is decision-worthy — want me to capture it via the existing decision-trace flow?" Hand off to whatever the project's decision-capture skill is (do not fabricate one). If the project ships with a `decision-trace-capture` skill, that's typically what `/handoff` invokes.

6. **Print a session summary.** When the user signals "done":
   - Number of branches grilled.
   - Number of glossary updates proposed (and accepted).
   - Number of decision-record conflicts surfaced.
   - Number of new decisions worth capturing.
   - Plan status: ready to advance to plan-mode approval / needs revision / blocked.

## Notes

- This command is the layer between `/spec-intake` and plan-mode approval. The plan came in via `/spec-intake`; `/grill` makes it survive contact with the project's accumulated thinking.
- Do not re-translate the plan. Do not rewrite it. Only surface contradictions and propose precise language.
- One question at a time. Resist the urge to dump a list. Walking the tree branch-by-branch is the point — it forces the user to commit to each branch before the next.
- If the user says "skip this branch," accept and log it as deferred. Don't grind.
- If the project has no `context_doc` or no decision records yet, fall back to grilling against the plan's internal consistency only, and offer at the end: "This project doesn't have a context doc yet. Want me to scaffold one from this plan?"
