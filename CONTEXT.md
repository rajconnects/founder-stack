# Context — Why This Framework Exists

## The problem

Agentic coding tools turn a non-technical founder into a 1-person product team. They also let you ship architectural disasters at extraordinary speed. By week 3 of pure vibe coding:

- Three modules implement the same logic three different ways. Nobody noticed.
- A migration shipped that you can't roll back. You can't tell.
- The agent confidently rewrote auth on Tuesday and you forgot why on Friday.
- Tests pass but the feature doesn't work in production.

You can't fix this with smarter prompts. You fix it with structure.

## The thesis

If you can't review the diff, the *process* has to be your reviewer. Gates run between phases. Decision traces capture *why* you chose A over B. Single-track days prevent context contamination. The workflow refuses to let you skip the parts that matter.

## Three principles

1. **Gates over good intentions.** A failing `/test-gate` tells you something. Promising you'll add tests later doesn't.
2. **Traces over memory.** Every consequential decision gets logged with alternatives and revisit triggers. Six weeks later you can answer "why did I choose this?" without guessing.
3. **One thing at a time.** A phase finishes before the next starts. A handoff doc closes it. The next phase reads that handoff before opening a file.

## What this is not

- **Not a tutorial.** It assumes you've shipped *something* with Claude Code already.
- **Not BMAD or Spec-Kit.** Those own the process; you lose control. This is composable. Use what helps, ignore what doesn't.
- **Not editor-agnostic.** Claude Code is the host. Other editors don't have first-class subagents/hooks; porting loses 70% of the value.
