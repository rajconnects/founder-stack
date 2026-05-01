#!/usr/bin/env bash
set -euo pipefail

# Founder Stack — install workflow into a target project's .claude/ directory.
# Usage:
#   ~/founder-stack/scripts/install.sh           # install into current dir
#   ~/founder-stack/scripts/install.sh /path/to  # install into specified dir

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

mkdir -p "$TARGET_DIR/.claude"

echo "Installing Founder Stack into $TARGET_DIR/.claude/"
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

for subdir in commands agents hooks; do
  mkdir -p "$TARGET_DIR/.claude/$subdir"
  for file in "$FRAMEWORK_DIR/workflow/$subdir"/*; do
    [ -e "$file" ] || continue
    link_file "$file" "$TARGET_DIR/.claude/$subdir/$(basename "$file")"
  done
done

link_file "$FRAMEWORK_DIR/workflow/Engineering-Playbook.md" "$TARGET_DIR/.claude/Engineering-Playbook.md"
link_file "$FRAMEWORK_DIR/workflow/project.example.json" "$TARGET_DIR/.claude/project.example.json"

echo ""
echo "Done. Linked: $linked. Skipped: $skipped."
echo ""
echo "Next steps:"
echo "  1. Run: $FRAMEWORK_DIR/scripts/init-project.sh"
echo "     (generates .claude/project.json and a starter CLAUDE.md)"
echo "  2. Open Claude Code in this directory and try: /spec-intake"
