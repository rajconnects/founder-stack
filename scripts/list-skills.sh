#!/usr/bin/env bash
set -euo pipefail

# Founder Stack — list available commands, agents, hooks, and skill packs.

FRAMEWORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo ""
echo "Founder Stack contents"
echo "======================"
echo ""
echo "Slash commands:"
for f in "$FRAMEWORK_DIR/workflow/commands"/*.md; do
  [ -e "$f" ] || continue
  name=$(basename "$f" .md)
  echo "  /$name"
done

echo ""
echo "Subagents:"
for f in "$FRAMEWORK_DIR/workflow/agents"/*.md; do
  [ -e "$f" ] || continue
  name=$(basename "$f" .md)
  echo "  $name"
done

echo ""
echo "Hooks:"
for f in "$FRAMEWORK_DIR/workflow/hooks"/*.sh; do
  [ -e "$f" ] || continue
  name=$(basename "$f")
  echo "  $name"
done

echo ""
echo "Skill packs:"
for d in "$FRAMEWORK_DIR/skills"/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  count=$(find "$d" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  echo "  $name ($count skills)"
done
echo ""
