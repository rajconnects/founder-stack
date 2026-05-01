#!/usr/bin/env bash
set -euo pipefail

# Founder Stack — interactive project setup.
# Asks ~6 questions, writes .claude/project.json + a starter CLAUDE.md.
# Usage:
#   ~/founder-stack/scripts/init-project.sh           # set up current dir
#   ~/founder-stack/scripts/init-project.sh /path/to  # set up specified dir

FRAMEWORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${1:-$(pwd)}"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

if [ ! -d "$TARGET_DIR/.claude" ]; then
  echo "Error: $TARGET_DIR/.claude/ doesn't exist."
  echo "Run install.sh first."
  exit 1
fi

ask() {
  local prompt="$1"
  local default="${2:-}"
  local answer
  if [ -n "$default" ]; then
    read -rp "  $prompt [$default]: " answer
    echo "${answer:-$default}"
  else
    read -rp "  $prompt: " answer
    echo "$answer"
  fi
}

echo ""
echo "Founder Stack — project setup"
echo "================================"
echo "I'll ask 7 questions. Press Enter to accept the default."
echo ""

PROJECT_NAME=$(ask "Project name" "$(basename "$TARGET_DIR")")
DESCRIPTION=$(ask "One-line description" "")
STACK=$(ask "Stack (next/python/node/rails/other)" "next")
DEPLOY=$(ask "Deploy target (vercel/fly/railway/render/none)" "vercel")
DB=$(ask "Database (supabase/postgres/sqlite/none)" "none")
PRIMARY_BRANCH=$(ask "Primary branch" "main")
TEST_CMD=$(ask "Test command" "npm test")
LINT_CMD=$(ask "Lint command" "npm run lint")

echo ""
echo "Writing .claude/project.json ..."

cat > "$TARGET_DIR/.claude/project.json" <<EOF
{
  "project_name": "$PROJECT_NAME",
  "description": "$DESCRIPTION",
  "stack": "$STACK",
  "deploy_target": "$DEPLOY",
  "database": "$DB",
  "primary_branch": "$PRIMARY_BRANCH",
  "commands": {
    "test": "$TEST_CMD",
    "lint": "$LINT_CMD"
  },
  "paths": {
    "specs": "specs/",
    "build_plans": "build-plans/",
    "decisions": "decisions/",
    "implementation_notes": "implementation-notes/"
  }
}
EOF

if [ ! -e "$TARGET_DIR/CLAUDE.md" ]; then
  echo "Writing starter CLAUDE.md ..."
  sed \
    -e "s|{{project_name}}|$PROJECT_NAME|g" \
    -e "s|{{description}}|$DESCRIPTION|g" \
    -e "s|{{stack}}|$STACK|g" \
    -e "s|{{primary_branch}}|$PRIMARY_BRANCH|g" \
    "$FRAMEWORK_DIR/templates/CLAUDE.md.template" > "$TARGET_DIR/CLAUDE.md"
else
  echo "CLAUDE.md exists — leaving it alone. (Reference templates/CLAUDE.md.template if you want a refresh.)"
fi

mkdir -p "$TARGET_DIR/specs" "$TARGET_DIR/build-plans" "$TARGET_DIR/decisions" "$TARGET_DIR/implementation-notes"

echo ""
echo "Setup complete."
echo ""
echo "Files written:"
echo "  .claude/project.json"
[ -e "$TARGET_DIR/CLAUDE.md" ] && echo "  CLAUDE.md"
echo "  specs/ build-plans/ decisions/ implementation-notes/  (empty)"
echo ""
echo "Next: open Claude Code here and try /spec-intake."
