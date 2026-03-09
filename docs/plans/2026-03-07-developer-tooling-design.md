# Developer Tooling Design

Date: 2026-03-07

## Problem

Developers using claude-sandbox need to memorize docker compose commands, manually check sidecar health, and parse raw JSONL audit logs. The sandbox is powerful but opaque.

## Solution

Three independently useful tools, shipped in order:

1. **Dev Container config** — VS Code "Reopen in Container" works out of the box
2. **CLI tool** — `claude-sandbox up/status/logs/doctor` wraps docker compose
3. **VS Code extension** — status bar, block notifications, log viewer

---

## Phase 1: Dev Container

### Files

- `.devcontainer/devcontainer.json` — points at existing `docker-compose.yml`, targets `sandbox` service
- `.devcontainer/postCreate.sh` — verifies sidecar health, prints guard status

### Key decisions

- `workspaceFolder: "/workspace"` matches existing compose volume mount
- `forwardPorts: [8000]` exposes sidecar to host for debugging
- `overrideCommand: true` prevents Dev Containers from overriding the `sleep infinity` CMD
- `shutdownAction: "stopCompose"` cleans up on close
- No docker-compose.yml modifications needed — existing file is already Dev Container compatible (`stdin_open: true`, `tty: true` already set)

---

## Phase 2: CLI Tool (`claude-sandbox`)

### Tech stack

- Node.js (already required for Claude Code)
- `commander` for arg parsing
- `chalk` for colored output
- `ora` for spinners
- `execa` for shell commands

### Structure (flat — 4 source files, not 11)

```
cli/
├── package.json                    # @tenexai/claude-sandbox
├── bin/claude-sandbox.js           # Entry point + simple command definitions
├── src/
│   ├── docker.js                   # Docker compose wrapper (shared)
│   ├── init.js                     # Project scaffolding
│   ├── status.js                   # status + doctor diagnostics
│   └── logs.js                     # Audit log tailing + pretty-printing
├── templates/                      # Files copied by `init`
│   ├── docker-compose.yml
│   ├── .env.example
│   └── devcontainer.json
└── README.md
```

### Commands

| Command | What it does | Complexity |
|---------|-------------|------------|
| `init [dir]` | Copy templates + scripts into project | Medium (file copying, .gitignore update) |
| `up` | `docker compose up -d` + health check + status | Low (calls docker.js) |
| `down [--clean]` | `docker compose down [--volumes]` | Trivial |
| `shell` | `docker compose exec sandbox bash` | Trivial |
| `run <cmd>` | `docker compose exec sandbox <cmd>` | Trivial |
| `status` | Container state + sidecar health + block stats | Medium (JSONL parsing) |
| `logs [--follow] [--mode X]` | Tail/filter audit JSONL | Medium (streaming + formatting) |
| `doctor` | 10 diagnostic checks | Medium (multiple checks) |

Simple commands (up, down, shell, run) are defined inline in `bin/claude-sandbox.js`. Complex commands get their own module.

### Output style

All output uses `[OK]`, `[FAIL]`, `[WARN]`, `[INFO]` labels. No emojis.

```
$ claude-sandbox up
[INFO] Building guardrails-sidecar...
[INFO] Building sandbox...
[OK]   Sidecar healthy (3 Hub validators, 4 custom validators)
[OK]   Sandbox ready

Guards active:
  memory_guard  -- SecretsPresent, GuardrailsPII, DetectJailbreak, EncodingDetector, AcrosticDetector
  exfil_guard   -- SecretsPresent, ExfilDetector, EncodingDetector, ForeignScriptDetector
  inbound_guard -- DetectJailbreak, UnusualPrompt, EncodingDetector, ForeignScriptDetector
  write_guard   -- SecretsPresent, GuardrailsPII, DetectPII, AcrosticDetector

Run: claude-sandbox shell
```

---

## Phase 3: VS Code Extension (Tier 1 only)

### Scope: Ship the high-value features, skip the dashboard

**Included (Tier 1):**
- Status bar item (sandbox state, block count, tooltip with details)
- Block notifications (non-modal, rate-limited)
- Security Guard output channel (tails JSONL, pretty-prints)
- Command palette commands (start, stop, restart sidecar, shell, doctor, show log)
- Extension settings (sidecar URL, log path, notification toggle)

**Deferred (Tier 2 — build later if needed):**
- Webview dashboard (stats cards, pipeline visualization, validator list)

### Structure

```
vscode-extension/
├── package.json                    # tenexai.claude-sandbox
├── src/
│   ├── extension.ts                # activate/deactivate
│   ├── sidecarClient.ts            # HTTP client for /health
│   ├── auditLogWatcher.ts          # FileSystemWatcher for JSONL
│   ├── statusBar.ts                # Status bar item
│   ├── commands.ts                 # Command implementations
│   ├── notifications.ts            # Block notification logic
│   └── config.ts                   # Extension settings
├── resources/
│   └── icons/
│       ├── shield-active.svg
│       └── shield-inactive.svg
├── tsconfig.json
├── esbuild.config.js
└── README.md
```

### Status bar states

- `Shield Sandbox: Off` — gray, click opens "Start" command
- `Shield Sandbox: Starting...` — yellow
- `Shield Sandbox: Active (7 blocks)` — green, click opens log
- `Shield Sandbox: Sidecar Down` — red, click runs doctor

### Activation triggers

- Workspace contains `docker-compose.yml` with `guardrails-sidecar` service
- Workspace contains `.claude/settings.json`
- User runs any `Claude Sandbox:` command

---

## What we're NOT building

- No new sidecar API endpoints (use existing `/health` only)
- No new container images (CLI and extension talk to existing compose setup)
- No modifications to existing scripts/, validators.py, or guard_definitions.py
- No webview dashboard (deferred to Tier 2)
- No Makefile aliases (CLI replaces that need)
