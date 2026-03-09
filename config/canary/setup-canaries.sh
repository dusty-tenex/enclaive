#!/usr/bin/env bash
# setup-canaries.sh — Populate the sandbox credential surface with canary tokens.
#
# Two tiers of canary env vars:
#
#   proxy-backed: Docker Desktop's credential proxy intercepts HTTPS requests
#   to known API domains and injects real credentials at the network layer.
#   The canary env var is always safe to set — it's never actually sent.
#   Services: Anthropic, OpenAI, AWS, GitHub, Google, xAI, Mistral, Groq.
#
#   tripwire: No credential proxy for this service. Canary is set by default.
#   If the user needs direct CLI access, they override via .env or docker
#   compose environment block. MCP Gateway is the recommended path.
#
# If any canary value appears in outbound traffic, exfiltration is occurring.
#
# Run at container start (called from sandbox-entrypoint.sh).
# Values come from registry.json.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${SCRIPT_DIR}/registry.json"

if [ ! -f "$REGISTRY" ]; then
    echo "  [WARN] Canary registry not found at $REGISTRY"
    exit 0
fi

# ── PROXY-BACKED CANARIES ────────────────────────────────────────────
# Docker Desktop's credential proxy overrides these at the network layer.
# The canary env var is always safe — real credentials never touch the sandbox.
# Always set unconditionally (proxy handles real auth transparently).

# Anthropic — proxy intercepts api.anthropic.com
# (only set canary if not loaded from Docker secrets for backward compat)
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    export ANTHROPIC_API_KEY="sk-ant-api03-canary-bQ7xR9mK4pL2nW5jF8vH3cY6tA1dS0gE-xxxxxxxxxxxxxxxx"
fi

# OpenAI — proxy intercepts api.openai.com
export OPENAI_API_KEY="sk-canary-openai-8kL3mN7pQ2rS5tU9wX1yZ4bD6fH0jK3nP5qR7sT9u"

# AWS — proxy intercepts AWS API endpoints
export AWS_ACCESS_KEY_ID="AKIAJ3XNWVEOHPZL7QOQ"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYzEXAMPLEKEY"

# GitHub — proxy intercepts api.github.com
export GITHUB_TOKEN="ghp_a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
export GH_TOKEN="ghp_a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"

# Google AI — proxy intercepts generativelanguage.googleapis.com
export GOOGLE_API_KEY="AIzaSyC-canary-x7k9m2p4q6r8s0t1u3v5w7y9z1a3b5"

# xAI — proxy intercepts api.x.ai
export XAI_API_KEY="xai-canary-x7k9m2p4q6r8s0t1u3v5w7y9z1a3b5c7d9e1f3g5"

# Mistral — proxy intercepts api.mistral.ai
export MISTRAL_API_KEY="mist-canary-x7k9m2p4q6r8s0t1u3v5w7y9z1a3b5c7d9"

# Groq — proxy intercepts api.groq.com
export GROQ_API_KEY="gsk_canary_x7k9m2p4q6r8s0t1u3v5w7y9z1a3b5c7d9e1f3"

# ── TRIPWIRE CANARIES ────────────────────────────────────────────────
# No credential proxy for these services. Canary is the default.
# User can override via .env or docker compose environment block.
# MCP Gateway (docker mcp secret set) is the recommended path.

export SLACK_BOT_TOKEN="${SLACK_BOT_TOKEN:-xoxb-canary-948372615204-5839201746382-aB3cD5eF7gH9iJ1kL3mN5oP}"
export SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-https://hooks.slack.example.com/services/T00CANARY/B00CANARY/canary24chartoken00000}"
export DATABASE_URL="${DATABASE_URL:-postgres://canary_user:canary_password_x7k9m2@db.internal.example.com:5432/canary_db}"
export STRIPE_SECRET_KEY="${STRIPE_SECRET_KEY:-sk_test_canary_51Hx7Kp3mN9qR2sT4uW6yA8bC0dE1fG3hI5jK7lM}"
export SENDGRID_API_KEY="${SENDGRID_API_KEY:-SG.canary_token.x7k9m2p4q6r8s0t1u3v5w7y9z1a3b5c7d9e1f3g5h7}"
export GITLAB_TOKEN="${GITLAB_TOKEN:-glpat-canary-x7k9m2p4q6r8s0}"
export NPM_TOKEN="${NPM_TOKEN:-npm_canary9x7k2m4p6q8r0s1t3u5v7w9y1}"

# ── File canaries ────────────────────────────────────────────────────
# Honeypot credential files at standard locations.

# AWS credentials file
mkdir -p ~/.aws
cat > ~/.aws/credentials << 'EOF'
[default]
aws_access_key_id = AKIAJ3XNWVEOHPZL7QOQ
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYzEXAMPLEKEY
EOF
chmod 600 ~/.aws/credentials

# GitHub CLI hosts
mkdir -p ~/.config/gh
cat > ~/.config/gh/hosts.yml << 'EOF'
github.com:
    oauth_token: ghp_a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0
    user: deploy-bot
    git_protocol: https
EOF
chmod 600 ~/.config/gh/hosts.yml

# .netrc
cat > ~/.netrc << 'EOF'
machine api.internal.corp
login deploy
password s3cur3-canary-t0ken
EOF
chmod 600 ~/.netrc

echo "  [OK] Canary tokens planted ($(jq '.canaries | length' "$REGISTRY") tripwires)"
