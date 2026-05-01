# Founder Stack

**Engineering workflow for non-technical founders shipping real products with Claude Code.**

This is the workflow used to take a real SaaS from blank repo to deployed beta in 13 days, solo, without writing a line of code by hand. It's opinionated, gate-driven, and refuses to let you skip the parts that matter.

## What's in here

- **The Workflow** — `Engineering-Playbook.md` plus 12 slash commands, 5 subagents, and 5 shell hooks that enforce a 5-layer build cycle: intake → plan → execute → verify → ship.
- **Skills** — optional reasoning packs (decision traces, war cabinet, grill, zoom-out).
- **Templates** — parameterized `CLAUDE.md` and `project.json` for new projects.
- **Init script** — interactive setup that asks 6 questions and writes your project config.

## Quickstart (60 seconds)

```bash
git clone https://github.com/rajconnects/founder-stack ~/founder-stack
cd your-new-project
git init   # if not already a repo
~/founder-stack/scripts/install.sh
~/founder-stack/scripts/init-project.sh
```

`install.sh` symlinks the workflow into your project's `.claude/`. `init-project.sh` walks you through generating a `project.json` and a starter `CLAUDE.md`.

Open Claude Code in that directory and try `/spec-intake` to begin.

## Why "for non-technical founders"?

Most agentic-coding tutorials assume you can read the diff and tell when the agent is bullshitting. Non-technical founders can't — so they need *process* instead of *judgment* as the safety net. Gates, traces, and single-track days are how you ship without the codebase rotting.

[Read the framing essay →](docs/for-non-tech-founders.md)

## Editor support

V1 ships **Claude Code-first**. The primitives (slash commands, subagents, hooks) are Claude Code-native. Cursor/Copilot/Pi don't have first-class equivalents; ports lose the enforcement layer. A Cursor rules-only pack may follow if there's demand.

## Inspiration & credit

Heavily inspired by [mattpocock/skills](https://github.com/mattpocock/skills). Founder Stack adds the *workflow* layer (gates, coordination, traces, handoffs) on top of the skills idea, framed for non-technical founders.

## License

MIT
