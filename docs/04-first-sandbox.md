# Your First Sandbox

```bash
docker sandbox run claude ~/my-project
```

That's it. This:

1. Creates a microVM with its own kernel and Docker daemon
2. Syncs `~/my-project` bidirectionally to the same absolute path inside the VM
3. Launches Claude Code with `--dangerously-skip-permissions` enabled by default
4. Routes all network traffic through the credential-injecting proxy

The sandbox persists until you remove it. Installed packages, configuration, and state survive across sessions.

> **Resource limit:** Docker Sandbox microVMs default to 4GB RAM. If your workload requires more (TypeScript compilation, Python ML libraries, Docker builds inside the sandbox), increase the allocation in Docker Desktop settings → Resources. Insufficient RAM causes OOM kills that may tempt developers to bypass the sandbox.

## Essential Commands

```bash
# List all sandboxes
docker sandbox ls

# Reconnect to an existing sandbox
docker sandbox run claude-my-project

# Open a shell inside the sandbox (for debugging/setup)
docker sandbox exec -it claude-my-project bash

# Stop a sandbox (preserves state)
docker sandbox stop claude-my-project

# Destroy a sandbox (deletes everything inside)
docker sandbox rm claude-my-project

# Mount multiple workspaces (docs as read-only)
docker sandbox run claude ~/my-project ~/shared-docs:ro
```

> **Note:** When using docker compose, this configuration is handled automatically by the sandbox entrypoint. See [Quick Start](01-quick-start.md).
