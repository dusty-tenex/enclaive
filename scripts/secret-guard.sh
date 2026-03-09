#!/bin/bash
# PreToolUse: blocks writes that embed credentials or PII in source files.
set -euo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
case "$TOOL" in Write|Edit|MultiEdit) ;; *) exit 0 ;; esac
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SIDECAR="${GUARDRAILS_SIDECAR_URL:-http://localhost:8000}"

if RESP=$(curl -sf --max-time 5 -X POST "${SIDECAR}/guards/write_guard/validate" \
    -H "Content-Type: application/json" \
    -d "{\"llmOutput\": $(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty' | jq -Rs .)}" \
    2>/dev/null); then
    PASSED=$(echo "$RESP" | jq -r '.validation_passed // false' 2>/dev/null)
    if [ "$PASSED" = "false" ]; then
        echo "[GUARD] SECRET GUARD (sidecar): Blocked" >&2
        echo "  $(echo "$RESP" | jq -r '.validation_outcome // "validation failed"' 2>/dev/null)" >&2
        exit 2
    fi
    exit 0
fi

echo "$INPUT" | python3 "${SCRIPT_DIR}/security_guard.py" --mode write
exit $?
