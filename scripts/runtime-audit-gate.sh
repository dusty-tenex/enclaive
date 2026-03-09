#!/bin/bash
# PreToolUse hook: intercept runtime skill/plugin installs
set -euo pipefail
# Bypass only via host-controlled read-only mount (agent cannot write to this path)
[ -f /etc/sandbox-guards/bypass-audit-gate ] && exit 0

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')

if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if ! echo "$CMD" | grep -qiE '(plugin install|add-skill|skill.*install|git clone.*skill|npx.*skill|pnpm.*skill)'; then
    exit 0
fi

echo "[SCAN] Runtime audit gate triggered" >&2
echo "  Command: $CMD" >&2

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
export AUDIT_LOG_DIR="${PROJECT_DIR}/.audit-logs"
source "${PROJECT_DIR}/scripts/skill-audit.sh"

if [ -f "${PROJECT_DIR}/plugins.json" ]; then
    API=$(jq -r '.audit.api // empty' "${PROJECT_DIR}/plugins.json")
    [ -n "$API" ] && export SKILLAUDIT_API="$API"
fi

URL=$(echo "$CMD" | grep -oE 'https?://[^ "'\'']+' | head -1)
LOCAL_PATH=$(echo "$CMD" | grep -oE '(\./|/tmp/|/)[^ "'\'']+' | head -1)

PASSED=false

if [ -n "$URL" ]; then
    audit_url "$URL" && PASSED=true
elif [ -n "$LOCAL_PATH" ] && [ -d "$LOCAL_PATH" ]; then
    audit_path "$LOCAL_PATH" && PASSED=true
else
    PLUGIN_NAME=$(echo "$CMD" | sed -E 's/.*plugin install[[:space:]]+//' | awk '{print $1}')
    if [ -n "$PLUGIN_NAME" ] && [[ "$PLUGIN_NAME" != http* ]] && [[ "$PLUGIN_NAME" != /* ]]; then
        echo "  Marketplace plugin: $PLUGIN_NAME" >&2
        audit_url "marketplace://$PLUGIN_NAME" "$PLUGIN_NAME" && PASSED=true
    else
        echo "  [FAIL] Could not extract install target — blocking (fail-closed)" >&2
        PASSED=false
    fi
fi

if [ "$PASSED" = true ]; then
    echo "  [OK] Audit passed — allowing install" >&2
    exit 0
else
    echo "[FAIL] Plugin/skill blocked by security audit. Review .audit-logs/ for findings." >&2
    exit 2
fi
