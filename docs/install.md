# Install Guide

Three scenarios, three install paths. Pick yours, follow the steps, run the verification block at the end.

The framework lives in one location on your machine and gets symlinked into each project. Editing the framework updates every project that links to it — that's the design.

## Prerequisites

- **git** — required. Installs are gated on the target being a git repo.
- **python3** — required for hooks to work and for the install's hook-wiring step.
- **Claude Code** — the workflow's commands, agents, and hooks are Claude Code-native.
- **bash** — macOS/Linux ship with this. On Windows, use WSL.

## One-time framework clone

Do this once, anywhere. Most people put it in their home directory.

```bash
git clone https://github.com/rajconnects/founder-stack ~/founder-stack
```

You can install it into as many projects as you want from this one clone.

---

## Scenario 1 — Fresh repo (no code yet)

You're starting a new product from scratch.

```bash
mkdir my-product && cd my-product
git init
~/founder-stack/scripts/install.sh
~/founder-stack/scripts/init-project.sh
```

**What gets created:**

- `.claude/commands/` — symlinks to all 15 slash commands
- `.claude/agents/` — symlinks to all 8 subagents
- `.claude/hooks/` — symlinks to all 6 hook scripts
- `.claude/settings.json` — created with the 5 framework hooks registered under the right Claude Code events
- `.claude/Engineering-Playbook.md`, `.claude/project.example.json` — symlinks
- `.claude/project.json` — written by `init-project.sh` from your answers
- `CLAUDE.md` — written from `templates/CLAUDE.md.template`
- `specs/`, `build-plans/`, `decisions/`, `implementation-notes/` — empty starter dirs

**Things to consider:** none specific to this scenario. The clean path is the easy path.

---

## Scenario 2 — Existing repo, no other AI harness

You have a codebase already. No `.claude/` directory yet, no Cursor rules, no Cline config.

```bash
cd existing-product
~/founder-stack/scripts/install.sh
~/founder-stack/scripts/init-project.sh
```

**Things to consider:**

- **Existing CLAUDE.md.** If you already have one, `init-project.sh` will not overwrite it. The framework's commands assume a CLAUDE.md exists; yours will work as long as it's readable as project guidance. If you want the framework's starter version, move yours aside first or merge by hand using `templates/CLAUDE.md.template` as reference.
- **Directory collisions.** `init-project.sh` creates `specs/`, `build-plans/`, `decisions/`, `implementation-notes/` if they don't exist. If your codebase already has `specs/` meaning something different (e.g., test specs, OpenAPI specs), edit `.claude/project.json` *after* setup to point `paths.specs` somewhere else like `framework-specs/`. The framework reads paths from this config, so the rename propagates.
- **Existing `.claude/settings.json`.** The install merges into it idempotently. Your existing `permissions`, `Stop` handlers, or unrelated hooks are preserved verbatim. Only the framework's 5 hook entries are added.
- **Hooks fire on Edit/Write/Bash globally.** Once installed, every Edit and Write to `.ts` / `.tsx` files runs `tsc-check.sh`; every `git commit`/`git push` runs `pre-git-check.sh`. None of these block by default — they print warnings. If you have a `.venv` or backend root, configure `stack.backend_root` in `project.json` so they know where to look.

**Verification block** (run after install):

```bash
# 1. Hooks are wired
python3 -c "
import json
s = json.load(open('.claude/settings.json'))
events = s.get('hooks', {})
expected = {'auto-lint.sh', 'tsc-check.sh', 'pre-git-check.sh', 'main-push-guard.sh', 'migration-guard.sh'}
seen = {entry['command'].rsplit('/', 1)[-1]
        for ev in events.values() for grp in ev for entry in grp.get('hooks', [])
        if 'command' in entry}
missing = expected - seen
print('OK — all 5 framework hooks wired' if not missing else f'MISSING: {missing}')
"

# 2. Symlinks resolve
ls -la .claude/commands/spec-intake.md
# Should show -> /Users/.../founder-stack/workflow/commands/spec-intake.md

# 3. Open Claude Code, type /spec-intake — the command should be available.
```

---

## Scenario 3 — Existing harness or global capabilities

This is the messy one. Sub-cases below; read the one that applies, then run the install.

### 3a. Another framework's commands already in `.claude/commands/`

You have a `.claude/commands/some-cmd.md` from a previous setup. The framework's install will print `skip (exists): commands/...` for any name collisions and silently leave the existing file in place. After install, your `/spec-intake` (or whichever) might still point at the old definition, not the framework's.

**What to do:**

1. **List the collisions** — `install.sh` prints them inline. Note which framework files were skipped.
2. **Decide per file**: keep theirs (do nothing — but the framework command won't work for that name), or remove theirs (`rm .claude/commands/<name>.md`) and re-run the install.
3. There is no namespace flag yet — installing as `/founder:spec-intake` is on the roadmap but not shipped. If you need to coexist with another framework long-term, that's the missing feature. File an issue if you hit this.

### 3b. User-global commands at `~/.claude/commands/`

If you have personal commands at the user level, Claude Code resolves slash commands from project first, then global. Project-level framework commands shadow your globals — usually what you want, but be aware:

- A `/spec-intake` you defined globally is no longer reachable in this project. To call yours, rename it (e.g. `/my-spec-intake`).
- The framework does not touch `~/.claude/`. Anything global stays global.

### 3c. Existing `.claude/settings.json` with hooks already configured

The install's merger is conservative: it adds entries by script name and preserves anything it doesn't recognize. Your hooks stay, our hooks join. No duplicates on re-run.

If you have a hook on the same event/matcher (e.g., your own `PostToolUse Edit|Write` handler), both will fire. Order is: yours first (because we append), ours after.

If a framework hook misbehaves on your codebase, you can:

- Comment it out in `.claude/settings.json` (don't delete the script — let it stay symlinked; just remove the registration entry).
- Re-run `scripts/wire-hooks.py` to re-add it later.

### 3d. CLAUDE.md with conflicting instructions

The framework expects a CLAUDE.md that doesn't actively contradict its conventions. Common conflicts:

- House style says "tests in `__tests__/`" but `project.json` has `test_roots: ["tests"]`.
- House style says "use Yarn" but framework hooks shell out to `npm`.

**What to do:** read `templates/CLAUDE.md.template` and decide what to merge. The framework's expectations live in `project.json` (paths, test commands, stack roots) — keep those aligned with whatever your CLAUDE.md says, or the agents will get confused.

---

## Updating the framework

```bash
cd ~/founder-stack
git pull
```

Symlinked projects pick up the change immediately — no reinstall needed. If a release adds new hooks (the install script registers them in settings.json), re-run the install in each project to wire the new ones:

```bash
~/founder-stack/scripts/install.sh /path/to/project
```

The merger is idempotent — re-running on an unchanged framework adds zero entries.

## Installing v1 autonomous missions (preview, additive)

After v0.1 is installed, v1 ships as an additive layer — no v0.1 files are touched, and you opt in by typing `/mission` instead of `/spec-intake`.

```bash
~/founder-stack/scripts/install-v1.sh                   # current dir
# or
~/founder-stack/scripts/install-v1.sh /path/to/project  # specific dir
```

**What gets added:**

- Five new slash commands: `/mission`, `/mission-tick`, `/mission-status`, `/mission-resume`, `/mission-abort`
- Four new agents: `mission-orchestrator` (opus), `feature-worker` (sonnet), `scrutiny-validator` (sonnet), `memory-broker` (haiku)
- Templates under `.claude/templates/v1/`: `state.schema.json`, `mission-contract.template.md`, `mission-handoff.template.md`
- `Engineering-Playbook-v1-deltas.md` and `project.example.v1.json`
- `.gitignore` entries (idempotent) for `missions/`, `memory/`, and `.claude/settings.local.json` — keeps mission metadata out of PRs the worker opens from the mission branch

**What does NOT change:** existing v0.1 commands, agents, hooks, or settings. Users who never type `/mission` see no behavioral difference.

**Optional config.** Merge keys from `.claude/project.example.v1.json` into your existing `.claude/project.json` to customize mission caps, model seats, or memory backend. Every v1 key has a documented default — you can skip this step entirely.

Reference: [`missions.md`](missions.md).

## Uninstalling

The framework is symlinks plus a settings.json registration. To remove:

```bash
cd /path/to/project
rm -rf .claude/commands .claude/agents .claude/hooks
rm -f .claude/Engineering-Playbook.md .claude/project.example.json
# Optionally remove project.json if you want a fully clean slate
# Edit .claude/settings.json by hand to remove the framework's hook entries
#   (they all reference .claude/hooks/<script>.sh)
```

Files outside `.claude/` (CLAUDE.md, specs/, decisions/, etc.) are yours to keep or delete.

There's no `uninstall.sh` script today. If multiple users hit this often enough, that's worth shipping — file an issue.

---

## Common gotchas

**`install.sh` says "not a git repository."** Run `git init` first. The framework refuses to install into a non-git target because half the hooks key off git operations.

**`python3 not found` warning during install.** The hook scripts won't fire without it, and the wiring step bails. Install python3 (macOS: `brew install python3`) and re-run.

**Symlinks point at the wrong place after moving the framework.** Symlinks are absolute. If you move `~/founder-stack` to a new location, every install's `.claude/` entries break. Fix: re-run `install.sh` in each project (existing symlinks are skipped — delete them first, or `rm -rf .claude/{commands,agents,hooks}` and re-install).

**Hooks not firing.** Three things to check, in order: (1) `.claude/settings.json` has entries for them — `cat` it; (2) python3 is available — `which python3`; (3) `.claude/project.json` exists and has the right `stack.frontend_root` / `stack.backend_root` — most hooks early-exit if these are missing.

**Slash commands not appearing in Claude Code.** Restart Claude Code after install. The command list is read at startup.
