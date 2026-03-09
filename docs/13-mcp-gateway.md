# MCP Gateway Integration

Docker's MCP Gateway lets you expose MCP tools to Claude Code through a centralized, containerized gateway — and critically, it **solves the MCP credential isolation problem** that the sandbox proxy alone cannot.

## The MCP Credential Problem (and How the Gateway Solves It)

The sandbox's credential proxy only injects `ANTHROPIC_API_KEY` and `GITHUB_TOKEN`. MCP servers that need their own credentials (Slack tokens, database URLs, third-party API keys) previously required those secrets to be inside the sandbox, where a prompt-injected agent could read and exfiltrate them.

The Docker MCP Gateway eliminates this by running each MCP server in its own isolated container with secrets injected at launch, never exposed as environment variables inside the sandbox:

```bash
# Store secrets in Docker Desktop's secure secret store (on the HOST)
docker mcp secret set GITHUB_PERSONAL_ACCESS_TOKEN=ghp_your-token
docker mcp secret set SLACK_BOT_TOKEN=xoxb-your-token
docker mcp secret set JIRA_API_TOKEN=your-jira-token

# Secrets are injected ONLY into the specific server container that needs them
# The sandbox VM never sees them
docker mcp secret ls   # Verify what's stored
```

The gateway spawns a fresh container for each tool call, injects the relevant secret, executes the request, and tears the container down. The secret exists only for the duration of that single call. Combined with `--block-secrets` (which scans tool responses for leaked credentials) and `--block-network` (zero-trust networking per server), this gives you least-privilege credential scoping that the sandbox proxy alone cannot provide.

### Architecture With Gateway

```
HOST
├── Docker Sandbox (microVM)
│   └── Claude Code ──► MCP Gateway (on host)
│                            ├── GitHub MCP Server container
│                            │   └── GITHUB_TOKEN injected at start
│                            ├── Slack MCP Server container
│                            │   └── SLACK_TOKEN injected at start
│                            └── Jira MCP Server container
│                                └── JIRA_TOKEN injected at start
│
│   Claude NEVER sees GitHub/Slack/Jira tokens.
│   Each server runs in its own container with resource limits.
│   Secrets are injected per-call and destroyed after.
└── Docker Desktop secret store (encrypted, host-only)
```

## Option A: Docker MCP Toolkit (Recommended)

```bash
# On the HOST — initialize the gateway
docker mcp catalog init
docker mcp server add github --profile claude-dev
docker mcp server add filesystem --profile claude-dev

# Store credentials securely
docker mcp secret set GITHUB_PERSONAL_ACCESS_TOKEN=ghp_your-token

# Connect Claude Code to the gateway
docker mcp client connect claude-code --profile claude-dev

# Enable runtime protections
docker mcp gateway run \
    --block-secrets \
    --block-network \
    --cpus 1 \
    --memory 512Mb

# Verify
docker mcp server ls --profile claude-dev
```

Each MCP server runs in its own container with `--security-opt no-new-privileges`, CPU/memory limits, and network isolation. The gateway handles OAuth flows automatically for services like GitHub, Notion, and Linear — no manual token creation needed.

## Option B: MCP Servers Inside the Sandbox

Since the sandbox has its own Docker daemon, you can also run MCP servers inside it. This is simpler but **does not isolate MCP credentials from the agent** — use only with non-sensitive tokens:

```bash
docker sandbox exec -it claude-my-project bash
claude mcp add github -- npx -y @modelcontextprotocol/server-github
claude mcp add filesystem -- npx -y @modelcontextprotocol/server-filesystem /workspace
```

## Option C: Remote MCP via supergateway

For MCP servers running on a remote host (VPS, cloud):

```bash
claude mcp add remote-tools -- npx supergateway \
    --streamableHttp "http://your-server:9876/mcp" \
    --outputTransport stdio \
    --header "Authorization: Bearer YOUR_TOKEN"
```

## Scanning MCP Servers for Tool Poisoning

MCP servers can contain hidden instructions in tool descriptions that steer agents to exfiltrate data:

```bash
uvx mcp-scan@latest            # Scan for poisoning
uvx mcp-scan@latest --pin      # Pin descriptions — detect changes on future runs
```

> **Data disclosure:** `mcp-scan` sends MCP tool names and descriptions to Invariant Labs' cloud API by default. Use `--local-only` (requires `OPENAI_API_KEY`) for fully offline scanning.

**Commit the `.mcp-scan` lockfile to version control.** The `--pin` flag creates a baseline; committing it means the entire team shares one baseline and any description change is detected on every machine.

## MCP Scan Lockfile

**Important:** Commit the `.mcp-scan` lockfile to your repository so all team members share the same pinned baselines. Without a shared lockfile, each developer creates their own baseline, and a rug-pull attack (MCP server changes descriptions after initial approval) would only be detected by the specific developer who pinned it.

```bash
# Pin and commit
npx mcp-scan --pin
git add .mcp-scan
git commit -m "Pin MCP tool descriptions"
```

Do NOT add `.mcp-scan` to `.gitignore`.
