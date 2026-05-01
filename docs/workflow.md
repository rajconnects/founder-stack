# The Workflow — Five-Layer Build Cycle

Each phase of work passes through five layers. Skipping a layer is how codebases rot.

## Layer 1 — Intake

`/spec-intake <spec-file>`

A spec is a plain-English description of what you want built. The intake command (powered by the `spec-translator` subagent) parses it into a structured execution plan: file paths, dependency order, gate checkpoints.

**Output:** a plan object in your conversation, ready to approve or push back on.

## Layer 2 — Plan

Built-in plan mode in Claude Code.

You read the plan. Push back on what's wrong. Approve when right.

**Rule:** never let implementation start before you've actually read the plan. The 30 seconds of friction here saves hours of unwinding later.

## Layer 3 — Execute

Implementation, with three shell hooks running automatically:

- `auto-lint.sh` — on every file save
- `tsc-check.sh` — on every TypeScript change
- `pre-git-check.sh` — before every commit

Hooks are how the framework makes implementation safe without requiring you to read the diff. They block bad code from making it to git.

## Layer 4 — Verify

The gates. Three of them, run in order as relevant:

- `/test-gate <feature>` — were the tests written *first*? Do they actually establish the contract?
- `/design-gate <scope>` — does the implemented UI match the design tokens, spec, and (if Figma is connected) the design file?
- `/schema-gate <migration>` — is the migration additive-only, RLS-covered, reversible? Read-only DB checks confirm assumptions.

A failing gate blocks the next layer. The agent can't talk past them — they're shell scripts.

## Layer 5 — Ship

`/deploy-gate <env>` — post-deploy smoke check (health endpoint, Playwright critical path, log scan).

`/handoff <phase>` — generates a handoff doc, prompts decision-trace capture, closes the phase.

The handoff is what the *next* phase reads first. It's how single-track days stay single-track.

## Reuse, not rebuild

Don't reinvent the cycle for each phase. The same five layers carry every feature, every bug fix, every migration. The discipline is the discipline.
