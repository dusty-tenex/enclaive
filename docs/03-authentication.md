# Authentication

The sandbox uses two complementary mechanisms to inject real credentials without ever exposing them inside the VM.

## Docker Credential Proxy (Recommended)

Docker Desktop includes a built-in MITM proxy that intercepts outbound HTTPS requests to known API domains and injects credentials from the host environment. The sandbox never sees the real key — it only has a canary token in the env var.

**Supported providers:**

| Env Var | API Domain | Setup |
|---------|-----------|-------|
| `ANTHROPIC_API_KEY` | api.anthropic.com | `export ANTHROPIC_API_KEY="sk-ant-..."` in host shell |
| `OPENAI_API_KEY` | api.openai.com | `export OPENAI_API_KEY="sk-..."` in host shell |
| `AWS_ACCESS_KEY_ID` | AWS API endpoints | `export AWS_ACCESS_KEY_ID="AKIA..."` in host shell |
| `AWS_SECRET_ACCESS_KEY` | (same) | `export AWS_SECRET_ACCESS_KEY="..."` in host shell |
| `GH_TOKEN` | api.github.com | `export GH_TOKEN="ghp_..."` in host shell |
| `GOOGLE_API_KEY` | generativelanguage.googleapis.com | `export GOOGLE_API_KEY="AIza..."` in host shell |
| `XAI_API_KEY` | api.x.ai | `export XAI_API_KEY="xai-..."` in host shell |
| `MISTRAL_API_KEY` | api.mistral.ai | `export MISTRAL_API_KEY="..."` in host shell |
| `GROQ_API_KEY` | api.groq.com | `export GROQ_API_KEY="gsk_..."` in host shell |

**How it works:**

1. Set the real API key in your host shell config (`~/.zshrc`, `~/.bashrc`)
2. Restart Docker Desktop so the daemon picks up the new env var
3. Inside the sandbox, the env var contains a canary token (not the real key)
4. When the agent makes an HTTPS request to the API domain, the proxy intercepts it and swaps in the real credential
5. If the canary value appears in outbound traffic to any other destination, the exfiltration guard fires

This is the strongest security posture: even if an attacker gains full shell access inside the sandbox, `echo $ANTHROPIC_API_KEY` returns a canary — not your real key.

## MCP Gateway (For Unsupported Services)

For services not covered by Docker's credential proxy (Slack, Stripe, SendGrid, etc.), use the MCP Gateway:

```bash
# Store a secret on the host
docker mcp secret set SLACK_BOT_TOKEN

# The secret is injected into the MCP server container, not the sandbox
```

The MCP Gateway runs services in isolated containers with their own network namespace. The sandbox communicates with them via the MCP protocol — credentials never enter the sandbox process.

## Canary Token Architecture

Every credential env var inside the sandbox is pre-populated with a unique canary (tripwire) value. There are two tiers:

**Proxy-backed canaries** are always safe to set unconditionally. The Docker credential proxy overrides the canary at the network layer, so the real key is used for API calls while the env var remains a tripwire.

**Tripwire canaries** have no credential proxy. They use the `${VAR:-canary}` pattern so user-provided values (via `.env` or docker compose `environment`) take precedence. If no override is provided, the canary is active and any use triggers the exfiltration guard.

See [config/canary/registry.json](../config/canary/registry.json) for the full canary registry.

## Why This Matters

Anthropic's Workspace feature allows multiple API keys to share access to cloud-stored project files. If an API key were stolen, the attacker could read, modify, or delete all shared workspace files, upload malicious content, or generate costs against the organization's account. The credential proxy eliminates this entire risk class by ensuring the key never enters the sandbox.

> **Note:** When using docker compose, canary token setup is handled automatically by the sandbox entrypoint. See [Quick Start](01-quick-start.md).
