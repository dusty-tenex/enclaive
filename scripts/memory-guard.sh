#!/bin/bash
# PreToolUse: blocks writes to memory/instruction files.
# Calls the guardrails sidecar (tamper-resistant, warm models) if available.
# Falls back to inline security_guard.py if sidecar is down.
set -euo pipefail
# Bypass only via host-controlled read-only mount (agent cannot write to this path)
[ -f /etc/sandbox-guards/bypass-memory-guard ] && exit 0
INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SIDECAR="${GUARDRAILS_SIDECAR_URL:-http://localhost:8000}"

# Try sidecar first (fast path: ~50ms, tamper-resistant)
if RESP=$(curl -sf --max-time 5 -X POST "${SIDECAR}/guards/memory_guard/validate" \
    -H "Content-Type: application/json" \
    -d "{\"llmOutput\": $(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty' | jq -Rs .)}" \
    2>/dev/null); then
    PASSED=$(echo "$RESP" | jq -r '.validation_passed // false' 2>/dev/null)
    if [ "$PASSED" = "false" ]; then
        echo "[GUARD] MEMORY GUARD (sidecar): Blocked" >&2
        echo "  $(echo "$RESP" | jq -r '.validation_outcome // "validation failed"' 2>/dev/null)" >&2
        exit 2
    fi
    exit 0
fi

# If REQUIRE_SIDECAR is set, do not fall back to inline (A-SEC-3)
if [ "${GUARDRAILS_REQUIRE_SIDECAR:-}" = "1" ]; then
    echo "[GUARD] GUARD: Sidecar unreachable and GUARDRAILS_REQUIRE_SIDECAR=1 — blocking" >&2
    exit 2
fi

# Fallback: inline analysis (slower, but works without sidecar)
echo "$INPUT" | python3 "${SCRIPT_DIR}/security_guard.py" --mode memory
exit $?
