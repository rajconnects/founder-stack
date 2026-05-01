# Quickstart

Five minutes from clone to first spec.

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

`install.sh` symlinks the workflow's commands, agents, hooks, and playbook into `.claude/`.
`init-project.sh` asks 7 questions and writes a `project.json` and a starter `CLAUDE.md`.

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

## What's next

- Read [`docs/workflow.md`](workflow.md) for the full 5-layer model.
- Read [`docs/gates.md`](gates.md) for what each gate actually checks.
- Read [`docs/decision-traces.md`](decision-traces.md) for trace philosophy.
