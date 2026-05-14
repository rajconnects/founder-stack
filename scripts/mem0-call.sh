#!/bin/bash
# scripts/mem0-call.sh — Mem0 HTTP helper for the memory-broker agent.
#
# Why this exists:
#   The earlier pattern had memory-broker resolve $MEM0_API_KEY via
#   `bash -c 'echo "$MEM0_API_KEY"'`, which returns the key as a tool
#   result. The value entered the agent's reasoning context before being
#   spliced into an Authorization header. This script moves the entire
#   request construction into shell — the agent invokes the helper with
#   a payload and reads only the response body. The API key never enters
#   the model's context window.
#
# Usage:
#   scripts/mem0-call.sh write   '<json payload with user_id, messages, metadata>'
#   scripts/mem0-call.sh read    <memory-id>
#   scripts/mem0-call.sh search  '<json payload with user_id, query, limit, filters>'
#
# Environment:
#   MEM0_API_KEY        required for any op
#   MEM0_API_BASE       optional; defaults to https://api.mem0.ai/v1/memories
#                       (override for self-hosted or staging endpoints)
#
# Exit codes:
#   0   success — response body printed to stdout
#   2   bad usage (missing op, missing payload)
#   3   MEM0_API_KEY not set
#   4   curl non-zero (network error, 4xx/5xx) — body printed to stdout when
#       available, error summary to stderr

set -uo pipefail

OP="${1:-}"
PAYLOAD="${2:-}"

if [ -z "$OP" ]; then
    echo "usage: mem0-call.sh <write|read|search> <payload-or-id>" >&2
    exit 2
fi

if [ -z "${MEM0_API_KEY:-}" ]; then
    echo "ERROR: MEM0_API_KEY not set in environment" >&2
    exit 3
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl not found on PATH — required for Mem0 HTTP calls" >&2
    exit 4
fi

BASE="${MEM0_API_BASE:-https://api.mem0.ai/v1/memories}"
# Auth header is built and passed via stdin so it never appears in argv
# (process listings) or in shell history.
AUTH_HEADER="Authorization: Token ${MEM0_API_KEY}"

case "$OP" in
    write)
        if [ -z "$PAYLOAD" ]; then
            echo "ERROR: write requires a JSON payload as the second argument" >&2
            exit 2
        fi
        curl --silent --show-error --fail-with-body \
            --request POST "${BASE}/" \
            --header "@-" \
            --header "Content-Type: application/json" \
            --data "$PAYLOAD" <<< "$AUTH_HEADER"
        ;;
    read)
        if [ -z "$PAYLOAD" ]; then
            echo "ERROR: read requires a memory id as the second argument" >&2
            exit 2
        fi
        curl --silent --show-error --fail-with-body \
            --request GET "${BASE}/${PAYLOAD}/" \
            --header "@-" <<< "$AUTH_HEADER"
        ;;
    search)
        if [ -z "$PAYLOAD" ]; then
            echo "ERROR: search requires a JSON payload as the second argument" >&2
            exit 2
        fi
        curl --silent --show-error --fail-with-body \
            --request POST "${BASE}/search/" \
            --header "@-" \
            --header "Content-Type: application/json" \
            --data "$PAYLOAD" <<< "$AUTH_HEADER"
        ;;
    *)
        echo "ERROR: unknown op '$OP' — use write, read, or search" >&2
        exit 2
        ;;
esac

CURL_EXIT=$?
if [ "$CURL_EXIT" -ne 0 ]; then
    echo "ERROR: mem0 request failed (curl exit $CURL_EXIT)" >&2
    exit 4
fi
