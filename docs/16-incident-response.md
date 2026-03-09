# Incident Response

When you suspect a sandbox has been compromised (audit gate triggered, unexpected network traffic, unfamiliar files in workspace):

## 1. Contain

Stop the sandbox immediately:

```bash
docker sandbox stop <name>
```

Do not reconnect or run commands inside it. This preserves the VM state for forensic review.

## 2. Assess

On the host, review the synced workspace *without executing anything*. Do not run `make`, `npm install`, `git checkout`, or open the directory in VS Code (which may auto-execute tasks).

```bash
git log --oneline                              # Review commits
git diff HEAD~10                               # Check recent changes
find . -newer .git/index -type f               # Find recently modified files
ls -la .audit-logs/                            # Check blocked scan results
docker sandbox network log <name>              # Check network activity
```

## 3. Quarantine Host-Executable Files

Before interacting with the workspace on the host, inspect all files the write guard would have blocked:

- `.git/hooks/`
- `.vscode/`
- `.github/workflows/`
- `Makefile`, `Justfile`
- `.husky/`
- `.npmrc`
- `.claude/settings.json`

If any were modified (which would indicate the write guard was bypassed), treat the workspace as untrusted.

## 4. Rotate Credentials

If the sandbox had access to MCP server credentials, GitHub tokens, or any secrets in `.env` files, rotate them immediately. The Anthropic API key is safe (credential proxy, never entered the sandbox) unless you manually placed it inside.

## 5. Destroy and Rebuild

```bash
docker sandbox rm <name>                       # Destroy the VM
docker sandbox run -t <template> claude ~/project  # Fresh start
```

The workspace on the host is preserved (it was never inside the VM), so rebuilding is fast.

## 6. Review and Report

If the compromise was caused by a malicious skill or plugin, report it to the registry. Save `.audit-logs/` and network logs before destroying the sandbox.

## Ongoing Monitoring Checklist

- Review `docker sandbox network log` for traffic to unexpected domains
- Run `uvx mcp-scan@latest --pin --fail-on-change` weekly (or on every sandbox start)
- Review `.audit-logs/` for scan results
- Check `git log` for commits you don't recognize

## Audit Log Locations

- **Inline guards:** `.audit-logs/security-guard.jsonl` (in workspace)
- **Sidecar:** `/var/log/guardrails/` (volume-mounted in docker compose)
- **MCP scan:** `.audit-logs/mcp-scan-*.log`
- **Git history:** `git log --oneline` (auto-commit daemon)
