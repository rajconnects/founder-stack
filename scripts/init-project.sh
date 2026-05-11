#!/usr/bin/env bash
set -euo pipefail

# Founder Stack — interactive project setup.
# Asks 8 questions, writes .claude/project.json + a starter CLAUDE.md.
# Emits the project.json schema that the framework's agents and hooks actually
# read (see workflow/project.example.json for the full reference). Values you
# don't answer here are left at safe defaults; you can edit project.json after
# setup to wire in design tokens, deploy URLs, real_corpora, etc.
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

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 not found. init-project.sh needs python3 to emit project.json."
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
echo "I'll ask 8 questions. Press Enter to accept the default."
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

PROJECT_JSON_PATH="$TARGET_DIR/.claude/project.json"
WRITE_PROJECT_JSON=1

if [ -e "$PROJECT_JSON_PATH" ]; then
  read -rp "  .claude/project.json already exists. Overwrite? (y/N): " confirm
  case "$confirm" in
    [Yy]*) echo "  Overwriting existing project.json." ;;
    *)     echo "  Keeping existing project.json. (Edit it directly to update.)"
           WRITE_PROJECT_JSON=0 ;;
  esac
fi

if [ "$WRITE_PROJECT_JSON" = "1" ]; then
echo "Writing .claude/project.json ..."

# Build project.json with the schema agents/hooks read. The python heredoc
# below keeps null/empty handling and quoting honest. See
# workflow/project.example.json for documented defaults you can fill in later.
python3 - "$PROJECT_JSON_PATH" \
  "$PROJECT_NAME" "$DESCRIPTION" "$STACK" "$DEPLOY" "$DB" \
  "$PRIMARY_BRANCH" "$TEST_CMD" "$LINT_CMD" <<'PYEOF'
import json, sys

(out_path, name, desc, stack, deploy, db,
 branch, test_cmd, lint_cmd) = sys.argv[1:]

# Map the single-word stack answer onto {frontend, frontend_root, backend, backend_root}.
# Defaults assume a single-package layout at the project root; edit project.json
# if you have a monorepo (e.g. set frontend_root to "apps/web").
stack_map = {
    "next":   ("next",            ".",  None,              None),
    "python": (None,               None, "fastapi-python",  "."),
    "node":   (None,               None, "express-node",    "."),
    "rails":  (None,               None, "rails",           "."),
}
frontend, frontend_root, backend, backend_root = stack_map.get(stack, (None, None, None, None))
has_frontend = frontend is not None
has_backend = backend is not None

# Treat "none" as null for db/deploy.
db_val = None if db in ("none", "") else db
deploy_val = None if deploy in ("none", "") else deploy

config = {
    "project_name": name,
    "description": desc,
    "primary_branch": branch,

    "spec_roots": {
        "system": "specs/",
        "frontend": "specs/",
        "build_plans": "build-plans/",
    },

    "design_system": {
        "tokens": None,
        "components_spec": None,
        "flow_spec": None,
        "copy_guide": None,
        "principles": None,
        "mockups_dir": None,
        "artifacts_dir": None,
        "figma": {"file_key": None, "node_id": None, "screens": {}},
    },

    "migrations": None,

    "deploy_targets": {
        "staging": {"type": deploy_val, "url": None, "health_path": "/health"},
        "prod":    {"type": deploy_val, "url": None, "health_path": "/"},
    },

    "stack": {
        "frontend": frontend,
        "frontend_root": frontend_root,
        "backend": backend,
        "backend_root": backend_root,
        "db": db_val,
        "supabase_project_ref": None,
    },

    "test_commands": {
        "frontend":     test_cmd if has_frontend else None,
        "frontend_cwd": frontend_root if has_frontend else None,
        "backend":      test_cmd if (has_backend and not has_frontend) else None,
        "backend_cwd":  backend_root if (has_backend and not has_frontend) else None,
    },

    "test_roots": {
        "frontend": "src/**/__tests__/" if has_frontend else None,
        "backend":  "tests/" if has_backend else None,
    },

    "lint_commands": {
        "frontend": lint_cmd if has_frontend else None,
        "backend":  lint_cmd if (has_backend and not has_frontend) else None,
    },

    "decision_traces": "decisions/",
    "handoff_template": None,
    "handoff_output_dir": "implementation-notes/",
    "build_status_file": "build-plans/build-status.md",

    "context_doc": "CLAUDE.md",
    "glossary_doc": "CLAUDE.md",
    "glossary_anchor": "Glossary",

    "decision_records": {"format": "json-traces", "path": "decisions/"},

    "architecture_notes": None,
    "release_artifacts": [],
    "real_corpora": [],
    "schemas_of_record": [],
}

with open(out_path, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
PYEOF
fi  # WRITE_PROJECT_JSON

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
if [ "$WRITE_PROJECT_JSON" = "1" ]; then
  echo "  .claude/project.json"
else
  echo "  .claude/project.json  (kept existing — not overwritten)"
fi
[ -e "$TARGET_DIR/CLAUDE.md" ] && echo "  CLAUDE.md"
echo "  specs/ build-plans/ decisions/ implementation-notes/  (empty)"
echo ""
echo "Edit .claude/project.json to wire in design tokens, deploy URLs,"
echo "and migrations paths as your project grows. See"
echo "$FRAMEWORK_DIR/workflow/project.example.json for the full reference."
echo ""
echo "Next: open Claude Code here and try /spec-intake."
