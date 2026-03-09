# enclAIve — Documentation

Defense-in-depth security layers for running Claude Code inside a Docker sandbox. Alpha -- pattern matching catches common payloads but can be bypassed.

## Quick Navigation

| Section | Topic |
|---------|-------|
| [Quick Start](01-quick-start.md) | `docker compose up` and you're running |
| [Architecture](02-architecture.md) | microVM isolation, network deny, credential proxy |
| [Authentication](03-authentication.md) | API key injection via proxy |
| [First Sandbox](04-first-sandbox.md) | Creating and configuring sandboxes |
| [Network Hardening](05-network-hardening.md) | Allowlist management |
| [Custom Templates](06-custom-templates.md) | Dockerfile templates |
| [Rules & Skills](07-rules-skills.md) | CLAUDE.md, AI instruction files |
| [Plugin Audit Gate](08-plugin-audit-gate.md) | Supply chain scanning |
| [Hook Scripts](09-hook-scripts.md) | Complete hook reference |
| [Worktrees](10-worktrees.md) | Git worktree-based parallelism |
| [Autonomous Loop Security](11-autonomous-loop-security.md) | Inter-iteration poisoning threat model |
| [Sub-Agents](12-sub-agents.md) | Task tool, Agent Teams |
| [MCP Gateway](13-mcp-gateway.md) | Credential isolation for MCP |
| [VS Code](14-vscode.md) | Live editing integration |
| [Security](15-security.md) | Defense layers and threat model |
| [Incident Response](16-incident-response.md) | When things go wrong |
| [Persistence](17-persistence.md) | Across reboots |
| [Platform Notes](18-platform-notes.md) | macOS, Linux, Windows |
| [Daily Workflow](19-daily-workflow.md) | Day-to-day usage |
| [Guardrails](20-guardrails.md) | Injection & exfiltration detection |
| **[Sidecar Architecture](21-sidecar-architecture.md)** | **Tamper-resistant validation server** |
| [Appendix A](appendix-a-devcontainer.md) | Devcontainer fallback |
| [Appendix B](appendix-b-donts.md) | Common mistakes |
| [Appendix C](appendix-c-allowlist.md) | Network allowlist reference |

## Architecture at a Glance

```
docker compose up
├── guardrails-sidecar (read-only, non-root, warm validators)
│   ├── Hub: SecretsPresent, GuardrailsPII
│   └── Custom: ExfilDetector, EncodingDetector, ForeignScript, Acrostic
└── sandbox (Claude Code + hooks)
    ├── PreToolUse: write-guard → memory-guard → exfil-guard → secret-guard
    ├── PostToolUse: skill-file-watcher
    └── SessionStart: bootstrap-plugins, memory-integrity (AI instruction files)
```
