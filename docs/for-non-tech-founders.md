# For Non-Technical Founders

You're a domain expert who decided to build software because nobody else will build it the way you see it. You have Claude Code, and you can ship faster than your engineer friends warned you about.

The thing nobody tells you: shipping fast is not the hard part. Reviewing what you shipped is the hard part — and you can't, because you don't read code.

## What goes wrong without process

By week 3 of pure vibe coding:

- Three modules implement the same logic three different ways. Nobody noticed.
- A migration shipped that you can't roll back. You can't tell.
- The agent confidently rewrote auth on Tuesday and you forgot why on Friday.
- Your tests pass but the feature doesn't actually work in production.

You can't fix this with smarter prompts or a stronger model. You fix it with structure.

## What the framework gives you

### Gates between phases

A failing `/test-gate` blocks implementation. A failing `/design-gate` blocks shipping. A failing `/schema-gate` blocks the migration. The agent can't talk its way past them — they're shell scripts. They run on actual evidence (test output, lint results, DB queries).

### Decision traces

Every choice that matters (architecture, pricing, scope cut) gets a trace: what you decided, what you rejected, what would make you revisit. Six weeks later when an agent suggests the rejected alternative, you grep `decisions/` and know in 10 seconds.

### Single-track days

One phase per day. Phase ends with a handoff doc. The next day reads the handoff before opening a file. Your context window stays clean; the agent's context window stays clean. You don't conflate yesterday's auth refactor with today's billing migration.

### Multi-session coordination

Two terminals open? `coordination.json` keeps them from stepping on each other. One session claims a feature branch; the other knows to wait or work elsewhere.

### Hooks as guardrails

`auto-lint.sh` runs on every save. `pre-git-check.sh` blocks commits that don't lint cleanly. `main-push-guard.sh` makes you confirm before pushing to your primary branch. Most of what an experienced engineer does mentally happens in a shell script you don't have to think about.

## What you still have to do

The framework reduces *engineering* judgment to process. **Domain judgment stays yours.**

- Read every handoff doc.
- Approve every plan before implementation starts.
- Decide what gets traced as a decision (anything you'd struggle to explain in 6 weeks).
- Notice when the agent is wrong about your domain (it always is, eventually, and you're the only one who knows).

## What this is not

- **Not a tutorial.** It assumes you've shipped *something* with Claude Code already.
- **Not BMAD or Spec-Kit.** Those own the process; you lose control. This is composable. Use what helps, ignore what doesn't.
- **Not a guarantee.** A framework can't make a confused product clear. It can keep a clear product from rotting.

## A note on tools

The framework is Claude Code-first. The slash commands, subagents, and hooks are Claude Code-native. Cursor, Copilot, and Pi don't have first-class equivalents — porting loses the enforcement layer.

Pick one tool. Go deep. The framework is the discipline; the tool is the host.
