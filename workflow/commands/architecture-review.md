---
description: Post-phase architectural review. Surfaces deepening opportunities (shallow modules, leaky seams, tightly-coupled clusters), informed by the project's glossary and prior decision records. Adapted from mattpocock/skills/improve-codebase-architecture.
argument-hint: <phase identifier or scope path, e.g. 7a or apps/web/src/components/dashboard>
---

You are running an architecture review. The aim is to surface refactoring opportunities that turn shallow modules into deep ones — improving testability, AI-navigability, and locality of change.

**Arguments:** `$ARGUMENTS`

## Vocabulary (use these terms exactly)

- **Module** — anything with an interface and an implementation.
- **Interface** — everything a caller must know: types, invariants, error modes, ordering, config. Not just signature.
- **Depth** — leverage at the interface. Deep = a lot of behaviour behind a small interface. Shallow = interface nearly as complex as the implementation.
- **Seam** — where an interface lives; a place behaviour can be altered without editing in place.
- **Locality** — change, bug, and knowledge concentrated in one place.
- **Deletion test** — imagine deleting the module. If complexity vanishes, it was a pass-through. If complexity reappears across N callers, it earned its keep.

## Steps

1. **Resolve scope.**
   - If `$ARGUMENTS` is a phase identifier (e.g. `7a`), use the corresponding handoff doc and recent commits to define scope.
   - If `$ARGUMENTS` is a path, scope to that subtree.
   - If `$ARGUMENTS` is empty, ask: "Review which scope? A phase identifier (e.g. `7a`) or a path."

2. **Read project conventions.** Read `.claude/project.json`. Extract:
   - `context_doc`, `glossary_doc`, `glossary_anchor` — vocabulary discipline.
   - `decision_records.path` and `decision_records.format` — to avoid re-litigating settled decisions.
   - `architecture_notes` — long-form memos to respect.
   - `handoff_output_dir` — for phase handoff lookup.
   - `test_roots` — to weigh test surface in the deepening analysis.

3. **Read the project's thinking.**
   - Glossary section.
   - Decision records relevant to the scope (filter by topic mention, status `resolved`).
   - Any architecture note whose filename mentions the scope.
   - The handoff doc for the scoped phase, if applicable.

4. **Explore the scope.** Use the `Explore` subagent or direct Read/Grep/Glob. Look for:
   - Modules whose interface is nearly as complex as their implementation (shallow).
   - Pure functions extracted only for testability where the real bugs hide in how they're called (no locality).
   - Tightly-coupled clusters that leak across seams.
   - Untested code paths or paths that are hard to test through their current interface.
   - Where understanding one concept requires bouncing across many small modules.

   For anything suspected shallow, apply the **deletion test**: would deletion concentrate complexity, or just move it?

5. **Present candidates.** Output a numbered list. For each candidate:

   ```
   ### N. <glossary-aware module name>

   **Files:** <paths>

   **Problem:** <why the current architecture causes friction — using glossary terms for the domain and the vocabulary above for architecture>

   **Solution:** <plain English description of what would change. No interface design yet.>

   **Benefits:** <in terms of locality, leverage, and how tests would improve>

   **ADR/decision impact:** <"none" | "contradicts [trace-id / ADR-id] — worth reopening because…" | "extends [trace-id / ADR-id]">
   ```

   Rules:
   - Use glossary terms for the domain and the architecture vocabulary above for architecture. Do not drift into "component," "service," "boundary."
   - If a candidate contradicts an existing decision record, only surface it when the friction is real enough to warrant revisiting. Mark it clearly.
   - Do NOT propose interfaces. Surface candidates only.

6. **Wait for selection.** Ask: "Which candidate would you like to explore?" Do not proceed past this point unsolicited.

7. **Grilling loop on the chosen candidate.** When the user selects:
   - Walk the design tree: constraints, dependencies, the shape of the deepened module, what sits behind the seam, what tests survive.
   - Use the `/grill` flow if it exists, or run the same one-question-at-a-time pattern inline.
   - Inline side effects:
     - **Naming a deepened module after a concept not in the glossary** — propose a glossary update inline.
     - **User rejects a candidate with a load-bearing reason** — offer to capture as a decision record. Frame it: "Want me to record this so future architecture reviews don't re-suggest it?" Skip ephemeral reasons (e.g. "not worth it right now") and self-evident ones.
   - Hand off decision capture to the project's existing decision-trace skill. Do not invent a new format.

## Notes

- This command runs **post-phase**, between `/handoff` and the next `/start-build`. Do not run mid-phase.
- The output of step 5 is the deliverable for the user to review independently. The grilling loop in step 7 is optional — the user may take the candidate list, sleep on it, and come back.
- Test surface matters. A shallow module with deep tests behind it has earned more than its depth suggests; weigh that before recommending deletion.
- If the project has no decision records yet, run anyway but flag at the start: "No decision records found at `<path>`. Surfacing candidates without prior-decision filter — expect some re-litigation."
