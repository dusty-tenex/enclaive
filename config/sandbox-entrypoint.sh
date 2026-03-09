#!/bin/bash
# Sandbox entrypoint: configure Claude Code hooks, lock down critical paths,
# then drop to sandbox user.
# Idempotent — safe to restart the container.
set -euo pipefail

WORKSPACE="${CLAUDE_PROJECT_DIR:-/workspace}"
SCRIPTS_SRC="/home/sandbox/.sandbox-scripts"
CONFIG_SRC="/home/sandbox/.sandbox-config"
SIDECAR="${GUARDRAILS_SIDECAR_URL:-http://guardrails-sidecar:8000}"

echo "━━━ enclAIve ━━━"

# ── Load API key from Docker secret if available ─────────────────────
if [ -f /run/secrets/anthropic_api_key ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    export ANTHROPIC_API_KEY="$(cat /run/secrets/anthropic_api_key)"
    echo "  [OK] ANTHROPIC_API_KEY loaded from Docker secret"
fi

# ── Plant canary tokens ──────────────────────────────────────────────
# Every common credential env var and config file is populated with a
# unique tripwire value. Real credentials flow through the Docker
# credential proxy (network layer) or MCP Gateway (isolated containers).
# Source (not exec) so env vars are exported into this shell.
# Try multiple locations: image build path, repo checkout, workspace
for CANARY_CANDIDATE in \
    "/home/sandbox/.sandbox-canary/setup-canaries.sh" \
    "${WORKSPACE}/config/canary/setup-canaries.sh" \
    "$(dirname "$0")/canary/setup-canaries.sh"; do
    if [ -f "$CANARY_CANDIDATE" ]; then
        # shellcheck source=config/canary/setup-canaries.sh
        source "$CANARY_CANDIDATE"
        break
    fi
done

# ── Wait for sidecar if URL is set ─────────────────────────────────
if [ -n "$SIDECAR" ]; then
    echo "  Waiting for guardrails sidecar at ${SIDECAR}..."
    for i in $(seq 1 30); do
        if curl -sf "${SIDECAR}/health" >/dev/null 2>&1; then
            echo "  [OK] Sidecar healthy"
            break
        fi
        [ "$i" -eq 30 ] && echo "  [WARN] Sidecar not reachable — using inline fallback"
        sleep 1
    done
fi

# ── Initialize workspace (idempotent) ─────────────────────────────
cd "$WORKSPACE"

# Git init if needed
if [ ! -d .git ]; then
    git init -q
    echo "  [OK] git init"
fi

# Copy scripts (as root, then fix ownership)
mkdir -p scripts
cp -n "${SCRIPTS_SRC}"/*.sh scripts/ 2>/dev/null || true
cp -n "${SCRIPTS_SRC}"/*.py scripts/ 2>/dev/null || true
chmod +x scripts/*.sh 2>/dev/null || true
chown -R sandbox:sandbox scripts/
echo "  [OK] Hook scripts installed ($(ls scripts/*.sh 2>/dev/null | wc -l) scripts)"

# Copy CLAUDE.md and RALPH.md templates (don't overwrite existing)
[ ! -f CLAUDE.md ] && cp "${CONFIG_SRC}/CLAUDE.md" . 2>/dev/null && chown sandbox:sandbox CLAUDE.md && echo "  [OK] CLAUDE.md template"
[ ! -f RALPH.md ] && cp "${CONFIG_SRC}/RALPH.md" . 2>/dev/null && chown sandbox:sandbox RALPH.md && echo "  [OK] RALPH.md template"

# Configure .claude/settings.json
mkdir -p .claude
if [ ! -f .claude/settings.json ]; then
    cat "${CONFIG_SRC}/settings.json" | \
        jq --arg url "$SIDECAR" '.env.GUARDRAILS_SIDECAR_URL = $url' \
        > .claude/settings.json
    echo "  [OK] .claude/settings.json configured"
else
    TMP=$(mktemp)
    jq --arg url "$SIDECAR" '.env.GUARDRAILS_SIDECAR_URL = $url' .claude/settings.json > "$TMP" && mv "$TMP" .claude/settings.json
    echo "  [OK] .claude/settings.json updated (sidecar URL)"
fi

# Audit log directory (prefer mounted volume, fallback to workspace)
if [ -d /var/log/enclaive ]; then
    chown sandbox:sandbox /var/log/enclaive
else
    mkdir -p .audit-logs
fi
chown -R sandbox:sandbox .claude

# ── Git pre-commit hook (secret scanner) ───────────────────────────
# Inline hook installation (previously in install-hooks.sh, now deprecated)
HOOK_DIR=".git/hooks"
mkdir -p "$HOOK_DIR"
if [ ! -f "$HOOK_DIR/pre-commit" ]; then
    cat > "$HOOK_DIR/pre-commit" << 'PREHOOK'
#!/bin/bash
PATTERNS=(
    'sk-ant-'
    'AKIA[0-9A-Z]{16}'
    'ghp_[a-zA-Z0-9]{36}'
    '-----BEGIN.*PRIVATE KEY'
    'xoxb-[0-9a-zA-Z]+'
    'glpat-[a-zA-Z0-9\-_]+'
    'npm_[a-zA-Z0-9]{30}'
    'sk_test_[a-zA-Z0-9_]+'
    'sk_live_[a-zA-Z0-9_]+'
    'SG\.[a-zA-Z0-9_]+'
    'sk-canary-openai-'
    'AIzaSy[a-zA-Z0-9_-]+'
    'gsk_[a-zA-Z0-9_]+'
    'xai-[a-zA-Z0-9_-]+'
    'mist-[a-zA-Z0-9_-]+'
)
for p in "${PATTERNS[@]}"; do
    if git diff --cached --diff-filter=ACM | grep -qE "$p"; then
        echo "BLOCKED: Potential secret matching: $p"
        exit 1
    fi
done
PREHOOK
    chmod +x "$HOOK_DIR/pre-commit"
    echo "  [OK] Pre-commit secret scanner installed"
fi

# ═══════════════════════════════════════════════════════════════════
# TIER 1: Filesystem-level protection for host-executable paths
# These paths are made immutable by the kernel — no regex parsing,
# no race conditions, no bypasses via variable indirection or symlinks.
# Only root can undo these protections, and the agent runs as sandbox.
# ═══════════════════════════════════════════════════════════════════
echo "  Locking down host-executable paths..."

# .git/hooks/ — owned by root, read+execute only for others
# Pre-commit hooks were already installed above
if [ -d .git/hooks ]; then
    chown -R root:root .git/hooks
    chmod 755 .git/hooks
    chmod 644 .git/hooks/* 2>/dev/null || true
    # Make executable hooks actually executable (read-only to sandbox user)
    for hook in .git/hooks/*; do
        [ -f "$hook" ] && [ ! -L "$hook" ] && head -1 "$hook" | grep -q '^#!' && chmod 755 "$hook"
    done
fi

# .git/config — root-owned, world-readable but not writable
if [ -f .git/config ]; then
    chown root:root .git/config
    chmod 644 .git/config
fi

# .claude/settings.json — root-owned after configuration
chown root:root .claude/settings.json
chmod 644 .claude/settings.json

# .claude/mcp.json — root-owned if it exists
if [ -f .claude/mcp.json ]; then
    chown root:root .claude/mcp.json
    chmod 644 .claude/mcp.json
fi

# .mcp.json at workspace root — root-owned if it exists
if [ -f .mcp.json ]; then
    chown root:root .mcp.json
    chmod 644 .mcp.json
fi

# .memory-integrity/ — snapshot files are root-owned to prevent tampering.
# Directory is sandbox-writable so the hook can create new snapshots,
# but existing snapshots (from prior sessions) are locked.
mkdir -p .memory-integrity
chown sandbox:sandbox .memory-integrity
chmod 755 .memory-integrity
# Lock existing snapshot files — new ones stay sandbox-owned until next restart
chown root:root .memory-integrity/*.sha256 2>/dev/null || true
chmod 444 .memory-integrity/*.sha256 2>/dev/null || true

# Count protected paths
PROTECTED=0
for p in .git/hooks .git/config .claude/settings.json .memory-integrity; do
    [ -e "$p" ] && ((PROTECTED++))
done
echo "  [OK] ${PROTECTED} paths locked (root-owned, agent cannot modify)"

# Ensure sandbox user owns everything else in the workspace
chown sandbox:sandbox .
find . -maxdepth 1 -not -name '.git' -not -name '.claude' -not -name '.mcp.json' -not -name '.memory-integrity' -not -name '.' \
    -exec chown -R sandbox:sandbox {} + 2>/dev/null || true
# Fix .claude subdirectories (agents, skills, etc.) to be sandbox-writable
find .claude -maxdepth 1 -not -name 'settings.json' -not -name 'mcp.json' -not -name '.claude' \
    -exec chown -R sandbox:sandbox {} + 2>/dev/null || true

echo ""
echo "━━━ Ready ━━━"
echo "  Workspace: ${WORKSPACE}"
echo "  Sidecar:   ${SIDECAR}"
echo "  Run:       claude"
echo ""

# ── Drop to sandbox user and exec CMD ────────────────────────────
exec gosu sandbox "$@"
