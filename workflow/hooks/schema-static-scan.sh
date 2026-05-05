#!/bin/bash
# Deterministic pre-pass for /schema-gate.
# Greps a migration file for unambiguously dangerous patterns before the agent runs.
# Output: prints findings to stdout; exit 0 = clean, exit 1 = FAIL with findings.
# Usage: schema-static-scan.sh <migration-file> [<migration-file> ...]

set -uo pipefail

if [ $# -eq 0 ]; then
    echo "schema-static-scan: no files provided" >&2
    exit 2
fi

FAIL=0
for FILE in "$@"; do
    if [ ! -f "$FILE" ]; then
        echo "schema-static-scan: $FILE not found" >&2
        FAIL=1
        continue
    fi

    # Strip SQL comments before scanning so commented-out examples don't trip the gate.
    STRIPPED=$(sed -E 's|--.*$||; s|/\*.*\*/||g' "$FILE")

    check() {
        local pattern="$1"
        local label="$2"
        local matches
        matches=$(echo "$STRIPPED" | grep -inE "$pattern" || true)
        if [ -n "$matches" ]; then
            echo "[FAIL] $FILE :: $label"
            echo "$matches" | sed 's/^/        /'
            FAIL=1
        fi
    }

    check '\bDROP[[:space:]]+TABLE\b'         'DROP TABLE — destructive, requires explicit deprecation plan'
    check '\bDROP[[:space:]]+COLUMN\b'        'DROP COLUMN — destructive'
    check '\bTRUNCATE\b'                      'TRUNCATE — wipes table'
    check '\bDELETE[[:space:]]+FROM\b'        'DELETE FROM — data loss; use a script, not a migration'
    check '\bALTER[[:space:]]+COLUMN\b.*\bTYPE\b' 'ALTER COLUMN ... TYPE — precision/type narrowing risk'
    # DROP INDEX without CONCURRENTLY — match DROP INDEX lines, then exclude ones with CONCURRENTLY.
    drop_idx=$(echo "$STRIPPED" | grep -inE '\bDROP[[:space:]]+INDEX\b' | grep -ivE '\bCONCURRENTLY\b' || true)
    if [ -n "$drop_idx" ]; then
        echo "[FAIL] $FILE :: DROP INDEX without CONCURRENTLY"
        echo "$drop_idx" | sed 's/^/        /'
        FAIL=1
    fi
    check '\bRENAME[[:space:]]+(TO|COLUMN)\b' 'RENAME — breaks reads from old name; needs deprecation window'
done

if [ $FAIL -eq 0 ]; then
    echo "schema-static-scan: clean"
fi
exit $FAIL
