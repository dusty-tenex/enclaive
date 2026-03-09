#!/bin/bash
set -euo pipefail

# CLAUDE_PROJECT_DIR is set by Claude Code hooks; fall back to git root or cwd
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
MANIFEST="${PROJECT_DIR}/plugins.json"
STAGING="/tmp/plugin-staging"
AUDIT_LOG_DIR="${PROJECT_DIR}/.audit-logs"
export AUDIT_LOG_DIR

source "${PROJECT_DIR}/scripts/skill-audit.sh"

if [ ! -f "$MANIFEST" ]; then
    echo "[INFO] No plugins.json found — skipping plugin bootstrap"
    exit 0
fi

echo "━━━ Plugin Bootstrap ━━━"

AUDIT_POLICY=$(jq -r '.audit.policy // "fail-closed"' "$MANIFEST")
AUDIT_API_URL=$(jq -r '.audit.api // "local"' "$MANIFEST")
export SKILLAUDIT_API="$AUDIT_API_URL"

TOTAL=$(jq '.plugins | length' "$MANIFEST") || { echo "[FAIL] Could not parse plugins.json"; exit 1; }
if [ "$TOTAL" -eq 0 ]; then
    echo "[INFO] No plugins defined in plugins.json"
    exit 0
fi
INSTALLED=0
SKIPPED=0
BLOCKED=0

mkdir -p "$STAGING"

for i in $(seq 0 $((TOTAL - 1))); do
    NAME=$(jq -r ".plugins[$i].name" "$MANIFEST")
    SOURCE=$(jq -r ".plugins[$i].source" "$MANIFEST")
    PIN=$(jq -r ".plugins[$i].pin // empty" "$MANIFEST")

    echo ""
    echo "[$((i + 1))/$TOTAL] $NAME ($SOURCE)"

    if claude plugin list 2>/dev/null | grep -q "$NAME"; then
        echo "  ✓ Already installed"
        INSTALLED=$((INSTALLED + 1))
        continue
    fi

    if [ "$SOURCE" = "marketplace" ]; then
        if audit_url "marketplace://$NAME" "$NAME"; then
            claude plugin install "$NAME" 2>&1 | sed 's/^/  /' || {
                echo "  [WARN] Install failed — skipping"
                SKIPPED=$((SKIPPED + 1))
                continue
            }
            INSTALLED=$((INSTALLED + 1))
        else
            echo "  [FAIL] Audit failed — not installing $NAME"
            BLOCKED=$((BLOCKED + 1))
        fi
        continue
    fi

    CLONE_DIR="${STAGING}/${NAME}"
    rm -rf "$CLONE_DIR"
    CLONE_ARGS=(--depth 1)
    [ -n "$PIN" ] && CLONE_ARGS+=(--branch "$PIN")

    echo "  Cloning ${SOURCE}${PIN:+ @ $PIN}..."
    git clone "${CLONE_ARGS[@]}" "$SOURCE" "$CLONE_DIR" 2>&1 | sed 's/^/  /' || {
        echo "  [WARN] Clone failed — skipping"
        SKIPPED=$((SKIPPED + 1))
        continue
    }

    if [ ! -f "$CLONE_DIR/.claude-plugin/plugin.json" ]; then
        echo "  [WARN] No .claude-plugin/plugin.json — skipping (not a valid plugin)"
        SKIPPED=$((SKIPPED + 1))
        rm -rf "$CLONE_DIR"
        continue
    fi

    if audit_path "$CLONE_DIR" "$NAME"; then
        # Deep MCP server code audit (static + optional AI review)
        if "${PROJECT_DIR}/scripts/mcp-audit-gate.sh" "$CLONE_DIR" "$NAME"; then
            echo "  Installing..."
            claude plugin install "$CLONE_DIR" 2>&1 | sed 's/^/  /' || {
                echo "  [WARN] Install failed — skipping"
                SKIPPED=$((SKIPPED + 1))
                rm -rf "$CLONE_DIR"
                continue
            }
            INSTALLED=$((INSTALLED + 1))
        else
            echo "  [FAIL] MCP code audit FAILED — not installing $NAME"
            echo "  Review: ${AUDIT_LOG_DIR}/"
            BLOCKED=$((BLOCKED + 1))
        fi
    else
        echo "  [FAIL] Audit FAILED — not installing $NAME"
        echo "  Review: ${AUDIT_LOG_DIR}/"
        BLOCKED=$((BLOCKED + 1))
    fi
    rm -rf "$CLONE_DIR"
done

rm -rf "$STAGING"

echo ""
echo "━━━ Bootstrap Complete ━━━"
echo "  Installed: $INSTALLED  Skipped: $SKIPPED  Blocked: $BLOCKED"

if [ "$BLOCKED" -gt 0 ]; then
    echo ""
    echo "  [WARN] $BLOCKED plugin(s) blocked by audit. Review .audit-logs/ for details."
fi

# ── Guardrails AI ─────────────────────────────────────────────────
# guardrails-ai and detect-secrets are pre-installed in the Docker image
# (see sandbox.Dockerfile). Only install Hub validators if not already present.
if command -v guardrails &>/dev/null; then
    python3 -c "from guardrails.hub import SecretsPresent" 2>/dev/null || {
        echo "  Installing Hub validators..."
        guardrails hub install hub://guardrails/secrets_present --quiet 2>/dev/null || true
        guardrails hub install hub://guardrails/guardrails_pii --quiet 2>/dev/null || true
        guardrails hub install hub://guardrails/detect_prompt_injection --quiet 2>/dev/null || true
    }
fi

# ── MCP server integrity check ─────────────────────────────────────
if command -v uvx &>/dev/null; then
    echo ""
    echo "━━━ MCP Server Scan ━━━"
    uvx mcp-scan@latest --pin --fail-on-change 2>&1 \
        | tee "${AUDIT_LOG_DIR}/mcp-scan-$(date +%Y%m%d-%H%M%S).log" || {
        echo "  [WARN] MCP scan detected changes or failed. Review .audit-logs/mcp-scan-*.log"
    }
fi
