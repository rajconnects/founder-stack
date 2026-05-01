---
description: Pull broader architectural context for a code area, file, or concept — adjacent modules, callers, related decision records, glossary terms in play. Adapted from mattpocock/skills/zoom-out.
argument-hint: <file path | module name | concept> | nothing for the current focus
---

You are running a context-broadening pass. The user is unfamiliar with this area and needs a map before editing.

**Arguments:** `$ARGUMENTS`

## Steps

1. **Resolve the focus.**
   - If `$ARGUMENTS` is a file path, that's the focus.
   - If `$ARGUMENTS` is a module/concept name, find the file(s) that own it.
   - If `$ARGUMENTS` is empty, infer focus from the conversation's most recently-read file.
   - If you can't infer, ask.

2. **Read project conventions.** Read `.claude/project.json`. Extract:
   - `glossary_doc` + `glossary_anchor` — to use the project's vocabulary, not generic terms.
   - `decision_records.path` and `decision_records.format` — to surface relevant prior decisions.
   - `stack` and `frontend_root` / `backend_root` — to scope the search appropriately.

3. **Build the map.** Use the `Explore` subagent (if available) or direct Read/Grep/Glob:
   - **Module under focus.** Confirm what it is in glossary terms, not framework terms. (Not "the FooHandler" — "the [Glossary Term] intake module.")
   - **Direct callers.** Grep for imports/calls. Cap at top 10 by call frequency.
   - **Direct dependencies.** What this module reads from, writes to, or depends on.
   - **Sibling modules.** Other modules in the same conceptual scope.
   - **Tests.** Existing test files exercising this module.
   - **Relevant decision records.** Search `decision_records.path` for any record whose topic mentions the focus area or glossary terms in play. List the topic + status + 1-line resolution summary.
   - **Architecture notes.** If `architecture_notes` is configured, list filenames whose names mention the focus area.

4. **Print the map.** Use this structure:

   ```
   ## Focus
   [glossary-aware one-liner of what this is]

   ## Callers (top N by frequency)
   - <caller> — <what it asks of this module>

   ## Dependencies
   - <dep> — <what we ask of it>

   ## Siblings (same scope)
   - <sibling> — <what it owns>

   ## Tests
   - <path> — <what it covers>

   ## Relevant decisions
   - [trace-id] <topic> — <resolution> (status: <resolved/open>)

   ## Architecture notes
   - <filename> — <relevance>

   ## Glossary terms in play
   - <term>: <definition from glossary>
   ```

5. **End with one open question.** Based on what you mapped, propose one question you'd ask before editing this area — the question whose answer would most reduce risk. Do not propose a plan; that's what `/spec-intake` is for. The output of `/zoom-out` is a map, not a plan.

## Notes

- Use the project's glossary vocabulary throughout. If the glossary defines a domain term (e.g. "Order," "Strategy Spine," "Booking"), use it — do not drift into generic words like "the table," "the handler," "the file." Consistency in language is the work.
- Do not propose changes. Do not propose refactors. Do not flag tech debt. This command is read-only orientation. (For refactor surfacing, use `/architecture-review`.)
- If the project has no glossary yet, fall back to plain English and note it once: "No glossary detected at <glossary_doc>. Using plain English."
- Cap output at ~50 lines. If the map is genuinely larger, summarize and offer "say expand for the full map."
