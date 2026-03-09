#!/bin/bash
# Post-create script for Dev Containers.
# Runs after container build -- verifies sidecar and prints status.
set -euo pipefail

SIDECAR="${GUARDRAILS_SIDECAR_URL:-http://guardrails-sidecar:8000}"

echo "--- enclAIve ---"
echo ""

# Check sidecar health
if curl -sf "${SIDECAR}/health" >/dev/null 2>&1; then
    echo "[OK] Sidecar healthy at ${SIDECAR}"
else
    echo "[WARN] Sidecar not reachable at ${SIDECAR} -- using inline fallback"
fi

# Count active hooks
if [ -f .claude/settings.json ]; then
    HOOK_COUNT=$(python3 -c "
import json
s = json.load(open('.claude/settings.json'))
hooks = s.get('hooks', {})
count = sum(len(h.get('hooks', [])) for matchers in hooks.values() for h in matchers)
print(count)
" 2>/dev/null || echo "?")
    echo "[OK] ${HOOK_COUNT} security hooks active"
else
    echo "[WARN] .claude/settings.json not found"
fi

# Count scripts
SCRIPT_COUNT=$(ls scripts/*.sh 2>/dev/null | wc -l | tr -d ' ')
echo "[OK] ${SCRIPT_COUNT} guard scripts installed"

echo ""
echo "Run: claude"
echo ""
