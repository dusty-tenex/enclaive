# Part 2: Architecture

## Deployment Model

```
Host Machine
├── Docker Desktop 4.62+
│   ├── Guardrails Sidecar Container (read-only, non-root)
│   │   └── guardrails-api on :8000 (Hub + custom validators)
│   └── Sandbox Container (or microVM)
│       ├── Claude Code CLI
│       ├── Hook scripts → curl sidecar for validation
│       ├── Your project workspace (mounted volume)
│       └── Inline fallback (security_guard.py + validators.py)
└── docker-compose.yml (one-command startup)
```

## Security Boundaries

1. **microVM/container** — own kernel (microVM) or process isolation (container). Agent cannot access host.
2. **Network deny-by-default** — HTTP proxy allowlists specific domains. Raw TCP/UDP blocked.
3. **Credential proxy** — ANTHROPIC_API_KEY injected at proxy layer, never enters sandbox.
4. **Guardrails sidecar** — separate container, read-only filesystem. Agent cannot tamper with validation logic.
5. **Hook chain** — 9 hooks fire on every tool call. PreToolUse hooks can block before execution.

## Key Design Principle

The sandbox is the security boundary. Everything else — hook scripts, guardrails, audit logs — is defense-in-depth. If all guards fail, the sandbox still contains the blast radius.

## Two Deployment Paths

| | Docker Compose (recommended) | Standalone (setup.sh) |
|-|---|---|
| Sidecar | Yes, tamper-resistant, warm models | No, inline only |
| Startup | `docker compose up -d` | `./setup.sh ~/project` |
| Guard tamper resistance | High (separate container) | Low (agent has Bash) |
| Performance | ~50ms per validation | ~300-500ms per validation |
| Dependencies | Docker, docker compose | Python 3, jq, bash |
