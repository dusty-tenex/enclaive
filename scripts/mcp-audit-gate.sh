#!/bin/bash
# MCP Server Audit Gate — wraps mcp-audit.py for use in bootstrap-plugins.sh
# Usage: mcp-audit-gate.sh /path/to/server-dir [server-name]
# Exit codes: 0 = pass, 2 = blocked
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
AUDIT_LOG_DIR="${AUDIT_LOG_DIR:-${PROJECT_DIR}/.audit-logs}"
mkdir -p "$AUDIT_LOG_DIR"

TARGET="${1:?Usage: mcp-audit-gate.sh <server-dir> [name]}"
NAME="${2:-$(basename "$TARGET")}"

AI_FLAG=""
if [ "${MCP_AUDIT_AI_REVIEW:-0}" = "1" ]; then
    AI_FLAG="--ai-review"
fi

LOGFILE="${AUDIT_LOG_DIR}/mcp-audit-$(date +%Y%m%d-%H%M%S)-${NAME}.json"

echo "  [SCAN] MCP audit: $NAME"

python3 "${PROJECT_DIR}/scripts/mcp-audit.py" "$TARGET" $AI_FLAG --json > "$LOGFILE" 2>&1
EXIT_CODE=$?

VERDICT=$(python3 -c "import json,sys; print(json.load(open('$LOGFILE')).get('verdict','ERROR'))" 2>/dev/null || echo "ERROR")
P0=$(python3 -c "import json,sys; print(json.load(open('$LOGFILE')).get('summary',{}).get('P0',0))" 2>/dev/null || echo "?")
P1=$(python3 -c "import json,sys; print(json.load(open('$LOGFILE')).get('summary',{}).get('P1',0))" 2>/dev/null || echo "?")

echo "  [SCAN] Result: ${VERDICT} (P0=$P0, P1=$P1) -- log: $LOGFILE"

if [ "$VERDICT" = "BLOCK" ]; then
    echo "  [FAIL] MCP server $NAME BLOCKED by audit"
    # Print P0 findings for visibility
    python3 -c "
import json, sys
report = json.load(open('$LOGFILE'))
for f in report.get('findings', []):
    if f.get('severity') == 'P0':
        print(f\"  [P0] {f.get('detail', '?')}\")
        if f.get('snippet'):
            print(f\"       {f['snippet']}\")
" 2>/dev/null || true
    exit 2
fi

exit 0
