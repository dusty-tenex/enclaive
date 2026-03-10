# Part 1: Quick Start

## Docker Compose (Recommended)

```bash
git clone https://github.com/dusty-tenex/enclaive.git
cd enclaive
cp .env.example .env
# Edit .env: add ANTHROPIC_API_KEY (required) and GUARDRAILS_TOKEN (recommended)

docker compose up -d
docker compose exec sandbox claude
```

This starts two containers:
1. **guardrails-sidecar** — validation server (tamper-resistant, warm models)
2. **sandbox** — your workspace with Claude Code and all hooks pre-configured

## Standalone (No Docker Compose)

```bash
git clone https://github.com/dusty-tenex/enclaive.git
cd enclaive
./setup.sh ~/my-project
cd ~/my-project
claude
```

This installs hooks and scripts directly into your project. Guards run inline (no sidecar). Less secure (agent can tamper with guard scripts), but works anywhere Python 3 and jq are available.

## Verify Guards Are Active

```bash
# Check hook chain
cat .claude/settings.json | jq '.hooks'

# Check sidecar health (compose only)
curl http://localhost:8000/health

# Test a detection (should be blocked)
echo '{"tool_name":"Write","tool_input":{"file_path":"test.py","content":"sk-ant-api03-TESTKEY1234567890abcdefghijklmnop"}}' \
  | python3 scripts/security_guard.py --mode write
# Should output: [GUARD] SECURITY GUARD [WRITE]: Blocked
```
