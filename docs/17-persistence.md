# Persistence & Task Queues

Docker Sandboxes persist until you explicitly remove them:

- **Installed packages** survive reboots (inside the VM image)
- **Workspace changes** are on your host filesystem (always survive)
- **Claude Code config** inside the sandbox persists
- **Custom templates** are cached locally

## Task Queue

For long-running autonomous work that should survive interruptions:

```bash
./scripts/task-queue.sh add "Implement user authentication"
./scripts/task-queue.sh add "Write integration tests"
./scripts/task-queue.sh list
./scripts/task-queue.sh next   # Moves next task to active
./scripts/task-queue.sh done <task-id>
```

## Auto-Commit Daemon

Never lose work — run in the background:

```bash
./scripts/auto-commit.sh 60 &   # Commit every 60 seconds if changes detected
```

## Log Rotation

Audit logs accumulate over time. Run periodically:

```bash
./scripts/rotate-logs.sh
```

Or add to your `SessionStart` hook for automatic rotation.

## Pre-commit Secret Scanner

Install the secret scanner to block credential leaks:

```bash
./scripts/install-hooks.sh
```

> **Note:** The write guard blocks writes to `.git/hooks/`. Run `install-hooks.sh` during initial setup (before hooks are active), on the host, or use `make bypass-guards` temporarily.
