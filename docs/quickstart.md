# Quickstart

Five minutes from clone to first spec. This page covers the **fresh repo** path. For existing repos or repos with another harness installed, read [`install.md`](install.md) first.

## 1. Install the framework

```bash
git clone https://github.com/rajconnects/founder-stack ~/founder-stack
```

That's it for the framework. You can install it into as many projects as you want from this one location.

## 2. Set up your project

```bash
mkdir my-product && cd my-product
git init
~/founder-stack/scripts/install.sh
~/founder-stack/scripts/init-project.sh
```

`install.sh` symlinks the workflow's commands, agents, hooks, and playbook into `.claude/`, then wires the hooks into `.claude/settings.json` so they actually fire.
`init-project.sh` asks 8 questions and writes a `project.json` and a starter `CLAUDE.md`.

## 3. Write your first spec

Spec files describe what you want built, in plain English. They live in `specs/`. Example:

```markdown
# Spec: Waitlist landing page

## Goal
A single-page site where visitors can submit their email to a waitlist.

## Constraints
- Static HTML, no build step
- Submissions go to Supabase
- Auto-reply email via Resend

## Acceptance
- 5+ submissions land in the waitlist table during a smoke test
- Auto-reply arrives within 60s
```

## 4. Run the workflow

In Claude Code, in your project directory:

```
/spec-intake specs/waitlist.md
```

The agent reads the spec and produces a structured plan. You approve the plan (or push back).

Then for the build:

```
/test-gate waitlist          # writes failing tests first
# implement until tests pass
/design-gate waitlist        # checks design compliance
/deploy-gate staging         # smoke verification on the deploy
/handoff phase-1             # closes the phase, captures decisions
```

## 5. Capture decisions

When the agent makes a non-obvious choice (architecture, scope cut, third-party tool pick), capture it as a trace:

```
/handoff phase-1
```

The handoff command prompts you to log open decisions. They land in `decisions/` as JSON files you can grep, link to, and revisit.

## 6. Try autonomous mode (v1 preview, optional)

Once you've shipped one or two phases by hand and you're comfortable with what the gates check, you can opt in to autonomous missions — an orchestrator drives the gates for you while you sleep.

```bash
~/founder-stack/scripts/install-v1.sh        # additive to v0.1; no v0.1 files touched
```

Then in Claude Code:

```
/mission "build a Counter component with persisted state, key must be 'counter:v1'"
# answer the orchestrator's scope questions, approve the contract, then:
/loop /mission-tick <id>                      # the orchestrator prints <id> on approval
```

Each mission runs in its own `git worktree` at `missions/<id>/worktree/`, so source-file edits stay isolated from your main checkout. Full reference: [`missions.md`](missions.md).

## What's next

- Read [`workflow.md`](workflow.md) for the full 5-layer model and the workflow diagram.
- Read [`gates.md`](gates.md) for what each gate actually checks.
- Read [`install.md`](install.md) for installing into an existing repo or alongside another harness.
- Read [`missions.md`](missions.md) for autonomous mode (v1 preview).
- Read [`session-hygiene.md`](session-hygiene.md) for when to `/clear` vs `/compact` between layers.
- Read [`decision-traces.md`](decision-traces.md) for trace philosophy.
