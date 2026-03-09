# enclAIve

Defense-in-depth security for AI coding assistants.

---

> [WARN] ALPHA SOFTWARE
>
> enclAIve is in alpha. Its pattern-matching guards catch obvious payloads and
> LLMs gone off the rails, but they are naive and can be bypassed by a
> determined adversary. The sandbox (microVM) is the real security boundary;
> everything else is defense in depth that reduces risk but does not eliminate
> it. This is not a substitute for human code review.

---

## What it does

enclAIve wraps Claude Code in multiple security layers so you can grant it
autonomy with less risk. It combines Docker Sandbox microVM isolation with a
9-layer hook chain, a guardrails sidecar, canary token tripwires, and an
inline fallback detection engine.

No single layer is relied upon alone. If a guard is bypassed, the next layer
catches it -- or at minimum, the sandbox contains the blast radius.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  Layer 1: microVM Isolation                                         │
│    Own kernel. Workspace-only sync to host. Not a container.        │
├─────────────────────────────────────────────────────────────────────┤
│  Layer 2: Network Deny-by-Default                                   │
│    HTTP proxy, allowlisted domains only, raw TCP/UDP blocked.       │
├─────────────────────────────────────────────────────────────────────┤
│  Layer 3: Credential Proxy                                          │
│    API keys injected at the network layer, never enter the VM.      │
│    MCP Gateway isolates per-server credentials.                     │
├─────────────────────────────────────────────────────────────────────┤
│  Layer 4: Write Guard                                               │
│    Blocks writes to host-executable paths (.git/hooks, Makefile...) │
├─────────────────────────────────────────────────────────────────────┤
│  Layer 5: Guardrails Sidecar (tamper-resistant)                     │
│    Separate container, read-only filesystem. Runs Hub + custom      │
│    validators: secrets, PII, exfil, encoding, steganography.        │
├─────────────────────────────────────────────────────────────────────┤
│  Layer 6: Skill/Plugin Audit Gate                                   │
│    Scans plugins at session start. Blocks P0 violations at runtime. │
├─────────────────────────────────────────────────────────────────────┤
│  Layer 7: AI Memory Integrity                                       │
│    Checksums AI instruction files (CLAUDE.md, etc.) between sessions│
├─────────────────────────────────────────────────────────────────────┤
│  Layer 8: Canary Tokens                                             │
│    Tripwire credentials that alert on exfiltration attempts.        │
├─────────────────────────────────────────────────────────────────────┤
│  Layer 9: Pre-commit Secret Scanner                                 │
│    Last defense before secrets enter git history.                   │
└─────────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

- Docker Desktop 4.62+ with `docker sandbox` support
- Node.js 20+ (for CLI and VS Code extension)
- Git 2.40+
- Anthropic API key or Claude Max OAuth token
- macOS 13+ or Windows 11 with WSL2

### Setup

```bash
# Clone
git clone https://github.com/dusty-tenex/enclAIve.git
cd enclAIve

# Configure
cp .env.example .env
# Edit .env -- add your ANTHROPIC_API_KEY

# Install CLI
cd cli && npm install && npm link && cd ..

# Start everything (sidecar + sandbox microVM)
enclaive up
```

<details>
<summary>Alternative: standalone (no sidecar)</summary>

```bash
./setup.sh ~/my-project
cd ~/my-project
claude
```

This installs hooks and scripts directly. Guards run inline without the
sidecar. Less tamper-resistant (the agent has Bash access to guard scripts),
but works anywhere Python 3 and jq are available.
</details>

## How it works

**Inbound screening** (content entering Claude):
- SessionStart: memory-integrity.sh checksums AI instruction files (CLAUDE.md, progress.md, etc.)
- PostToolUse: skill-file-watcher.sh scans new SKILL.md files
- Opt-in: haiku-injection-screen.sh sends content to Haiku for classification

**Outbound screening** (Claude acting on the world):
- PreToolUse: write-guard.sh blocks host-executable path writes
- PreToolUse: memory-guard.sh screens writes to AI instruction files (CLAUDE.md, progress.md, etc.)
- PreToolUse: exfil-guard.sh screens Bash commands for data exfiltration
- PreToolUse: secret-guard.sh screens code writes for credentials/PII

Each guard calls the sidecar first (~50ms, tamper-resistant). If the sidecar
is unreachable, guards fall back to inline analysis (~300-500ms). Set
`GUARDRAILS_REQUIRE_SIDECAR=1` to disable inline fallback (fail-closed).

## Known Limitations

1. **Regex bypass** -- pattern matching is fast but brittle. Adversarial
   encoding, synonym substitution, or multi-turn manipulation can evade
   guards. The Haiku classifier (opt-in) adds a semantic layer but is not
   a complete solution either.

2. **No semantic understanding without LLM layer** -- the default guards
   use regex, entropy analysis, and statistical detection. They catch
   common attack patterns but lack the ability to understand intent.

3. **Exfiltration via allowlisted channels** -- if github.com is on the
   allowlist, data can be pushed to public repos. Network deny reduces
   but does not eliminate exfil risk.

4. **Steganography** -- Tier 4 attacks (synonym selection, timing channels,
   variable name encoding) are fundamentally undetectable by pattern analysis.

5. **Skills execute by being read** -- once a SKILL.md exists, it is active.
   The watcher detects but does not prevent execution.

6. **detect-secrets gaps** -- Yelp's detect-secrets library misses some
   credential formats. Custom patterns in validators.py cover common gaps
   but the coverage is not exhaustive.

See [docs/15-security.md](docs/15-security.md) for the full threat model.

## Developer Tools

### CLI

```bash
cd cli && npm install && npm link
enclaive up          # Build sidecar + launch sandbox microVM
enclaive status      # Check health + block stats
enclaive logs        # Tail security log
enclaive doctor      # Diagnose issues
enclaive down        # Stop everything
```

### VS Code Extension

```bash
cd vscode-extension && npm install && npm run build
```

Adds a status bar item showing sandbox state, block notifications when guards
fire, and a Security Guard output channel for viewing the audit log.

## For Security Researchers

If you can bypass a guard, exfiltrate a canary token, or inject instructions
that survive screening, we want to hear about it. Bypass reports become test
cases so the same class of issue is caught going forward.

See [SECURITY.md](SECURITY.md) for responsible disclosure and what counts
as a valid report.

## Documentation

Full documentation is in `docs/` and is [GitBook](https://www.gitbook.com/)-compatible.

| Topic | Page |
|-------|------|
| Architecture | [docs/02-architecture.md](docs/02-architecture.md) |
| Network Hardening | [docs/05-network-hardening.md](docs/05-network-hardening.md) |
| Hook Scripts Reference | [docs/09-hook-scripts.md](docs/09-hook-scripts.md) |
| Plugin Audit Gate | [docs/08-plugin-audit-gate.md](docs/08-plugin-audit-gate.md) |
| MCP Gateway | [docs/13-mcp-gateway.md](docs/13-mcp-gateway.md) |
| Threat Model | [docs/15-security.md](docs/15-security.md) |
| Guardrails | [docs/20-guardrails.md](docs/20-guardrails.md) |
| Sidecar Architecture | [docs/21-sidecar-architecture.md](docs/21-sidecar-architecture.md) |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[AGPL-3.0](LICENSE)
