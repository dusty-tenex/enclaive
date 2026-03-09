# enclAIve - VS Code Extension

VS Code integration for enclAIve. Provides real-time
status monitoring, block notifications, and a security log viewer.

## Features

- **Status Bar** -- Shows sandbox state (Off, Starting, Active, Sidecar Down) with
  live block count.
- **Notifications** -- Desktop warnings when a tool call is blocked, with rate limiting.
- **Security Log Viewer** -- Output channel listing all blocked entries with live streaming.
- **Docker Commands** -- Start, stop, restart sidecar, open shell, and run diagnostics
  from the command palette.

## Commands

| Command | Description |
|---------|-------------|
| enclAIve: Start | Start sandbox containers via docker compose |
| enclAIve: Stop | Stop sandbox containers |
| enclAIve: Restart Sidecar | Restart the guardrails sidecar container |
| enclAIve: Show Security Log | Open the security log output channel |
| enclAIve: Run Doctor | Run diagnostic checks |
| enclAIve: Open Shell | Open a bash shell in the sandbox container |

## Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| enclaive.sidecarUrl | string | http://localhost:8000 | Sidecar API URL |
| enclaive.auditLogPath | string | .audit-logs/security-guard.jsonl | Audit log path (relative to workspace) |
| enclaive.notifications.enabled | boolean | true | Enable block notifications |
| enclaive.notifications.minInterval | number | 5000 | Min ms between notifications |
| enclaive.statusBar.showBlockCount | boolean | true | Show block count in status bar |
| enclaive.autoStart | boolean | false | Auto-start on workspace open |

## Building

```bash
npm install
npm run build
```

## Packaging

```bash
npx vsce package
```
