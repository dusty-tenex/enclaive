# Network Hardening

By default, sandboxes allow all outbound HTTP/HTTPS traffic (with private CIDRs blocked). For maximum security, switch to a **deny-by-default** policy:

```bash
docker sandbox network proxy claude-my-project \
    --policy deny \
    --allow-host "api.anthropic.com" \
    --allow-host "sentry.io" \
    --allow-host "statsig.anthropic.com" \
    --allow-host "events.statsig.com" \
    --allow-host "statsig.com" \
    --allow-host "registry.npmjs.org" \
    --allow-host "github.com" \
    --allow-host "api.github.com" \
    --allow-host "pypi.org" \
    --allow-host "files.pythonhosted.org"
```

> **Do NOT add `*.githubusercontent.com` unless required.** This domain serves raw content from every public GitHub repository. A prompt-injected agent could fetch and execute arbitrary code from any repo.

Changes take effect immediately and persist across sandbox restarts.

## HTTPS Proxy Behavior

The sandbox's HTTPS proxy terminates TLS connections using its own CA (MITM) to enforce domain-level filtering. It inspects the destination hostname but not request/response content. The sandbox container trusts the proxy's CA certificate automatically.

If a tool uses certificate pinning and fails with TLS errors:

```bash
docker sandbox network proxy claude-my-project \
    --bypass-host api.service-with-certificate-pinning.com
```

> **Note:** Bypassed hosts are not subject to allow/deny policy filtering. Only bypass hosts you trust.

## Inspect Network Activity

```bash
# View what the agent is actually trying to reach
docker sandbox network log claude-my-project

# Check current proxy config
cat ~/.docker/sandboxes/vm/claude-my-project/proxy-config.json
```

## Block Internal Networks (already default, but explicit)

```bash
docker sandbox network proxy claude-my-project \
    --block-cidr 10.0.0.0/8 \
    --block-cidr 172.16.0.0/12 \
    --block-cidr 192.168.0.0/16 \
    --block-cidr 169.254.169.254/32   # AWS metadata endpoint
```

See [Appendix C](appendix-c-allowlist.md) for the complete domain allowlist reference.

> **Note:** When using docker compose, this configuration is handled automatically by the sandbox entrypoint. See [Quick Start](01-quick-start.md).
