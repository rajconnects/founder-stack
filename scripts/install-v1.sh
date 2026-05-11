#!/usr/bin/env bash
set -euo pipefail

# Founder Stack v1 (autonomous missions) — install into a target project.
# This is ADDITIVE to scripts/install.sh — v0.1 commands/agents/hooks stay
# wired exactly as before, and v1 commands/agents are added alongside them.
#
# Usage:
#   ~/founder-stack/scripts/install-v1.sh           # install into current dir
#   ~/founder-stack/scripts/install-v1.sh /path/to  # install into specified dir
#
# Prerequisite: run scripts/install.sh first (v1 builds on v0.1's tree).

FRAMEWORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${1:-$(pwd)}"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

if [ ! -d "$TARGET_DIR/.git" ]; then
  echo "Error: $TARGET_DIR is not a git repository."
  echo "Run 'git init' first, or pass a different target directory."
  exit 1
fi

if [ "$TARGET_DIR" = "$FRAMEWORK_DIR" ]; then
  echo "Error: cannot install the framework into itself."
  exit 1
fi

if [ ! -d "$TARGET_DIR/.claude" ]; then
  echo "Error: $TARGET_DIR/.claude does not exist."
  echo "Run scripts/install.sh first to install v0.1, then re-run this script."
  exit 1
fi

echo "Installing Founder Stack v1 (missions) into $TARGET_DIR/.claude/"
echo "(additive to v0.1 — no v0.1 files are touched)"
echo ""

linked=0
skipped=0

link_file() {
  local src="$1"
  local dst="$2"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    echo "  skip (exists): ${dst#$TARGET_DIR/}"
    skipped=$((skipped + 1))
  else
    ln -s "$src" "$dst"
    echo "  linked:        ${dst#$TARGET_DIR/}"
    linked=$((linked + 1))
  fi
}

# v1 commands and agents land in the SAME .claude/commands and .claude/agents
# directories as v0.1 — Claude Code namespaces by filename, and v1 filenames
# are distinct (mission*.md, feature-worker.md, scrutiny-validator.md,
# memory-broker.md). No collisions.
for subdir in commands agents; do
  for file in "$FRAMEWORK_DIR/workflow-v1/$subdir"/*; do
    [ -e "$file" ] || continue
    link_file "$file" "$TARGET_DIR/.claude/$subdir/$(basename "$file")"
  done
done

# Clean up the retired mission-orchestrator agent symlink for users who
# installed v1.0/v1.1 before the nested-subagent-spawning refactor. Claude
# Code blocks sub-agents from spawning further sub-agents, so the orchestrator
# was moved into slash-command-driven procedures (see .claude/procedures/v1/).
# Leaving the symlink in place would surface a broken agent in agent listings.
STALE_ORCH="$TARGET_DIR/.claude/agents/mission-orchestrator.md"
if [ -L "$STALE_ORCH" ] || [ -e "$STALE_ORCH" ]; then
  rm -f "$STALE_ORCH"
  echo "  removed:       .claude/agents/mission-orchestrator.md (retired in this version)"
fi

# Templates live under .claude/templates/v1/ — procedures reference them
# by absolute path resolved from FRAMEWORK_DIR via the symlink.
mkdir -p "$TARGET_DIR/.claude/templates/v1"
for file in "$FRAMEWORK_DIR/workflow-v1/templates"/*; do
  [ -e "$file" ] || continue
  link_file "$file" "$TARGET_DIR/.claude/templates/v1/$(basename "$file")"
done

# Procedures live under .claude/procedures/v1/ — slash commands (/mission,
# /mission-tick, /mission-resume, /mission-abort) read these at runtime
# and execute the steps in the main agent thread. They must NOT be under
# .claude/agents/ — that directory is for callable sub-agents only.
mkdir -p "$TARGET_DIR/.claude/procedures/v1"
for file in "$FRAMEWORK_DIR/workflow-v1/procedures"/*; do
  [ -e "$file" ] || continue
  link_file "$file" "$TARGET_DIR/.claude/procedures/v1/$(basename "$file")"
done

# v1 playbook and example config sit alongside the v0.1 ones in .claude/.
link_file "$FRAMEWORK_DIR/workflow-v1/Engineering-Playbook-v1-deltas.md" \
          "$TARGET_DIR/.claude/Engineering-Playbook-v1-deltas.md"
link_file "$FRAMEWORK_DIR/workflow-v1/project.example.v1.json" \
          "$TARGET_DIR/.claude/project.example.v1.json"

# Hooks: v1 introduces no new hooks in MVP. v1.1 may add mission-heartbeat.sh.
# Hook wiring stays exactly as v0.1's install.sh left it.

# Per-mission worktrees + memory directories pollute git status if not ignored.
# When the worker opens a PR from missions/<id>/worktree, the mission's own
# state.json / log.md / handoffs would otherwise get included in the PR diff.
# Idempotently append the standard ignore lines to .gitignore.
echo ""
echo "Wiring .gitignore (idempotent) ..."
GITIGNORE="$TARGET_DIR/.gitignore"
touch "$GITIGNORE"
gi_added=0
for line in "missions/" "memory/" ".claude/settings.local.json"; do
  if ! grep -qxF "$line" "$GITIGNORE"; then
    printf '%s\n' "$line" >> "$GITIGNORE"
    echo "  added:     $line"
    gi_added=$((gi_added + 1))
  else
    echo "  present:   $line"
  fi
done
if [ "$gi_added" -gt 0 ]; then
  echo "  ($gi_added lines added to .gitignore)"
fi

echo ""
echo "Done. Linked: $linked. Skipped: $skipped."
echo ""
echo "Next steps:"
echo "  1. Merge keys from .claude/project.example.v1.json into your"
echo "     existing .claude/project.json. All v1 keys are optional —"
echo "     orchestrator falls back to defaults if absent."
echo "  2. Open Claude Code in this directory and try:"
echo "       /mission \"build a simple counter component\""
echo "  3. Reference: .claude/Engineering-Playbook-v1-deltas.md"
