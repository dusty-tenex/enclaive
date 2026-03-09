# Plugin Audit Gate

Skills and plugins are both the biggest productivity lever and the biggest supply chain attack vector for AI agents. A SKILL.md file is natural language that Claude follows as instructions — there's no syntax boundary between "data" and "code." Audits of public registries have found credential theft, data exfiltration, prompt injection, reverse shells, and MCP tool chain abuse in over 12% of published skills.

This system gives you a **single config file** as the source of truth for desired plugins, a **shared audit function** that both boot-time and runtime installs must pass, and **two entry points** — a `SessionStart` bootstrap and a `PreToolUse` gate — that both call the same scanner.

## How It Works

```
┌─ Session Start ─────────────────────────────────────┐
│  bootstrap-plugins.sh reads plugins.json            │
│  → For each plugin: clone → audit → install/block   │
│  → MCP scan (if uvx available)                      │
└─────────────────────────────────────────────────────┘

┌─ Runtime (every tool use) ──────────────────────────┐
│  PreToolUse: runtime-audit-gate.sh                  │
│    → Catches "plugin install" / "add-skill" commands│
│    → Same audit logic as bootstrap                  │
│  PreToolUse: write-guard.sh                         │
│    → Blocks writes to host-executable paths         │
│  PostToolUse: skill-file-watcher.sh                 │
│    → Catches SKILL.md creation by any method        │
└─────────────────────────────────────────────────────┘
```

## Setup

The `setup.sh` installer handles all of this automatically. For manual setup, copy the files:

```bash
# Copy all scripts
cp -r scripts/ ~/my-project/scripts/

# Copy plugin manifest
cp config/plugins.json ~/my-project/plugins.json

# Copy settings with hooks wired
mkdir -p ~/my-project/.claude
cp config/settings.json ~/my-project/.claude/settings.json
```

## The Plugin Manifest (`plugins.json`)

Declare everything you want installed in one file ([`config/plugins.json`](../config/plugins.json)):

```json
{
  "plugins": [
    {
      "name": "plugin-dev",
      "source": "marketplace",
      "description": "Anthropic's official plugin development tools"
    },
    {
      "name": "team-standards",
      "source": "https://github.com/your-org/team-standards",
      "pin": "v2.1.0"
    }
  ],
  "audit": {
    "api": "local",
    "policy": "fail-closed",
    "block_on": ["critical", "high"]
  }
}
```

The `pin` field locks a git-sourced plugin to a tag, branch, or commit SHA. Without it, the bootstrap clones `HEAD`. Pin to tags or SHAs for production.

## Scan Levels

| Level | What It Catches | Action |
|-------|----------------|--------|
| **P0** | Hidden Unicode, base64 payloads, credential access, reverse shells | **Block immediately** |
| **P1** | eval/exec, code execution patterns | **Warn, allow** (common in legit projects) |
| **P2** | Large encoded blobs, obfuscated control flow | **Note for awareness** |

## Runtime Flow Example

```
Claude: "I'll install a formatting plugin from this GitHub URL"
  → Bash(claude plugin install https://github.com/some/plugin)

  [PreToolUse: runtime-audit-gate.sh]
  [SCAN] Scanning URL: https://github.com/some/plugin
    → Clones, scans SKILL.md files, checks patterns
    [OK] Audit passed → install proceeds

  [PostToolUse: skill-file-watcher.sh]
  [SCAN] Scans any new SKILL.md files that appeared
```

If audit fails:

```
  [PreToolUse: runtime-audit-gate.sh]
  [ALERT] P0: Reverse shell pattern in evil-plugin:SKILL.md
  [FAIL] exit 2 → install denied. Claude sees the reason.
```

## Overriding the Gate

When the audit gate blocks a legitimate install you've manually reviewed:

```bash
# From the HOST (not inside the sandbox):
make bypass-guards                              # Creates bypass files on host
docker compose exec sandbox claude plugin install /path/to/reviewed-plugin
make reset-guards                               # Re-enables all guards
```

> **Security note:** Guard bypass is controlled via a read-only mount at `/etc/sandbox-guards/`. The agent cannot create, modify, or delete bypass files — only the host operator can. This is a significant improvement over the previous env-var approach, which a prompt-injected agent could exploit.

## Network Allowlist for Remote Scanning

The audit gate defaults to **local scanning** with no network dependency. If you opt into remote API scanning by setting `"api": "https://audit-api.example.com"` in `plugins.json`, add it to your network policy:

```bash
docker sandbox network proxy <n> --allow-host "audit-api.example.com"
```

> **Trust consideration:** The external audit API URL is a placeholder — replace it with your organization's scanning endpoint. For production, keep the local scanner as default. Pattern-matching scanners cannot detect novel attacks; the sandbox is your hard boundary.

## Hook Failure Behavior

If a `command`-type hook exits with a non-zero code, Claude Code treats it as a **blocking failure** — for `PreToolUse`, the tool call is denied; for `SessionStart`, the session may fail to start. This is correct fail-closed behavior, but it means a broken script (missing `jq`, syntax error, network timeout) will block all work.

To prevent this:

1. Test hook scripts manually before committing: `echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | ./scripts/runtime-audit-gate.sh`
2. The `set -euo pipefail` in each script ensures early failure with a clear error
3. Consider adding a health check to `SessionStart` that verifies all hook dependencies (`jq`, `git`, `curl`)

## File Layout After Setup

```
my-project/
├── plugins.json                          # Source of truth — what to install
├── .claude/
│   ├── settings.json                     # Hooks wiring
│   └── skills/
│       └── skill-audit/
│           └── SKILL.md                  # Air-gapped fallback auditor
├── scripts/
│   ├── skill-audit.sh                    # Shared audit library
│   ├── bootstrap-plugins.sh              # SessionStart: reads plugins.json, scans, installs
│   ├── memory-integrity.sh              # SessionStart: detects inter-session memory poisoning
│   ├── runtime-audit-gate.sh             # PreToolUse: catches runtime installs
│   ├── write-guard.sh                    # PreToolUse: blocks host-executable file writes
│   ├── skill-file-watcher.sh             # PostToolUse: scans new SKILL.md regardless of method
│   └── override-audit.sh                 # Documented bypass for reviewed installs
├── .audit-logs/                          # Scan results (auto-created, gitignored)
└── ...
```

## Guardrails AI Integration

The bootstrap script (`bootstrap-plugins.sh`) also installs guardrails-ai and Hub validators at session start. When using docker compose, these are pre-installed in the sidecar container.
