# Decision Traces

A decision trace is a structured record of a choice you made: what you decided, what you rejected, and what would make you revisit. Traces live as files in `decisions/`, one per decision.

## Why

Six weeks from now, an agent will suggest the option you already rejected. Without a trace, you have to re-derive your reasoning from scratch. With a trace, you grep `decisions/` and answer in 10 seconds.

The cost of writing a trace is 60 seconds. The cost of *not* having one when you need it is 30 minutes plus the risk of contradicting yourself.

## What deserves a trace

- Architecture choices (why this DB, why this hosting model)
- Scope cuts (what's in V1, what's deferred to V1.1)
- Pricing decisions
- Tool/library picks where you considered alternatives
- Anything you'd struggle to explain in 6 weeks

What does NOT deserve a trace:
- "I named the variable `userCount`"
- "I used the existing util function"
- Anything that's obvious from reading the code

## The schema

```json
{
  "id": "2026-04-15-cascading-spines-v1-option-c",
  "date": "2026-04-15",
  "title": "Cascading spines architecture — V1 commits to Option C",
  "status": "resolved",
  "decided_by": "Arun",
  "decision": "...",
  "alternatives_rejected": [
    { "option": "Option A — flat tables", "reason_rejected": "..." },
    { "option": "Option B — pure graph", "reason_rejected": "..." }
  ],
  "rationale": "...",
  "revisit_triggers": [
    "When team/individual/agent spines ship",
    "If pilots surface need for cross-spine permissions before V1.5"
  ],
  "supersedes": [],
  "superseded_by": null,
  "links": {
    "spec": "specs/...",
    "notes": "implementation-notes/..."
  }
}
```

## Status values

- `open` — decision pending
- `contested` — disagreement in flight, war-cabinet may help
- `resolved` — decided
- `superseded` — a later trace replaced this one (link in `superseded_by`)

## Lifecycle

**At session start:**
> "Are there open decisions from previous sessions I should check?"

The agent searches `decisions/` for `status: open` or `status: contested`.

**At session end:**
> "I detected N decisions in this session. Want me to capture them as traces?"

The `/handoff` command prompts this automatically.

## Anti-patterns

- **Trace inflation.** Don't trace every decision; trace the consequential ones. A trace for "I chose `npm` over `yarn`" is noise.
- **After-the-fact rationalization.** Write the trace at the moment of decision, with the alternatives you actually considered. Reconstructing months later loses the genuine reasoning.
- **No revisit trigger.** Every trace needs a "when would I revisit this?" line. Without it the trace is a tombstone, not a tool.
