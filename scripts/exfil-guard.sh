#!/bin/bash
# PreToolUse: blocks Bash commands that attempt data exfiltration.
set -euo pipefail
# Bypass only via host-controlled read-only mount (agent cannot write to this path)
[ -f /etc/sandbox-guards/bypass-exfil-guard ] && exit 0
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
[ "$TOOL" != "Bash" ] && exit 0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SIDECAR="${GUARDRAILS_SIDECAR_URL:-http://localhost:8000}"

if RESP=$(curl -sf --max-time 5 -X POST "${SIDECAR}/guards/exfil_guard/validate" \
    -H "Content-Type: application/json" \
    -d "{\"llmOutput\": $(echo "$INPUT" | jq -r '.tool_input.command // empty' | jq -Rs .)}" \
    2>/dev/null); then
    PASSED=$(echo "$RESP" | jq -r '.validation_passed // false' 2>/dev/null)
    if [ "$PASSED" = "false" ]; then
        echo "[GUARD] EXFIL GUARD (sidecar): Blocked" >&2
        echo "  $(echo "$RESP" | jq -r '.validation_outcome // "validation failed"' 2>/dev/null)" >&2
        exit 2
    fi
    exit 0
fi

# If REQUIRE_SIDECAR is set, do not fall back to inline
if [ "${GUARDRAILS_REQUIRE_SIDECAR:-1}" = "1" ]; then
    echo "[GUARD] EXFIL GUARD: Sidecar unreachable and GUARDRAILS_REQUIRE_SIDECAR=1 — blocking" >&2
    exit 2
fi

echo "$INPUT" | python3 "${SCRIPT_DIR}/security_guard.py" --mode exfil
exit $?
