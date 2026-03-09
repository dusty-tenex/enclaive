#!/bin/bash
# PreToolUse: blocks writes to memory/instruction files.
# Calls the guardrails sidecar (tamper-resistant, warm models) if available.
# Falls back to inline security_guard.py if sidecar is down.
set -euo pipefail
# Bypass only via host-controlled read-only mount (agent cannot write to this path)
[ -f /etc/sandbox-guards/bypass-memory-guard ] && exit 0
INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Only check memory-relevant files (structured tools provide reliable paths)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
case "$TOOL" in
    Write|Edit|MultiEdit)
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')
        if [ -n "$FILE_PATH" ]; then
            BASENAME=$(basename "$FILE_PATH")
            case "$BASENAME" in
                CLAUDE.md|RALPH.md|progress.md|MEMORY.md|SOUL.md) ;;  # memory file — check it
                *)
                    # Check for .claude/agents/*/memory/ or .claude/skills/*.md
                    case "$FILE_PATH" in
                        *.claude/agents/*/memory/*|*.claude/skills/*.md) ;;  # memory file — check it
                        *) exit 0 ;;  # not a memory file — skip
                    esac
                    ;;
            esac
        fi
        ;;
    Bash)
        # For Bash, the Python fallback handles path detection
        # Let it through to the sidecar/fallback for full analysis
        ;;
    *) exit 0 ;;
esac

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
if [ -f /etc/sandbox-guards/enclaive.conf ] && grep -q '^require_sidecar=0$' /etc/sandbox-guards/enclaive.conf 2>/dev/null; then
    : # Config file explicitly disables — allow fallback
elif [ "${GUARDRAILS_REQUIRE_SIDECAR:-1}" = "1" ]; then
    echo "[GUARD] MEMORY GUARD: Sidecar unreachable and GUARDRAILS_REQUIRE_SIDECAR=1 — blocking" >&2
    exit 2
fi

# Fallback: inline analysis (slower, but works without sidecar)
echo "$INPUT" | python3 "${SCRIPT_DIR}/security_guard.py" --mode memory
exit $?
