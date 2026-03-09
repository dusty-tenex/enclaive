# VS Code Live Editing

Since Docker Sandboxes sync workspace files bidirectionally at the same absolute path, VS Code on your host sees changes in real-time.

## Setup

1. Open `~/my-project` in VS Code on your host (normal, not "Reopen in Container")
2. Run `docker sandbox run claude ~/my-project` in a terminal
3. As Claude edits files inside the sandbox, VS Code sees changes immediately
4. You can edit files in VS Code, and Claude sees your changes too

**Enable auto-save** for the smoothest experience: Settings → `files.autoSave` → `afterDelay`, `files.autoSaveDelay` → `1000`.

**Install GitLens** to watch Claude's commits in real-time.

No Dev Containers extension needed — this is just normal file editing on a synced directory.

## Security Warning: Bidirectional Sync

Bidirectional sync is also an attack surface. A prompt-injected agent inside the sandbox can write files that **execute on the host**:

- **`.git/hooks/`** — execute on `git pull`, `git checkout`, etc.
- **`.git/config`** — custom credential helpers can execute arbitrary commands
- **`.vscode/settings.json`** — VS Code reads when you open the folder

The write guard (see [Hook Scripts Reference](09-hook-scripts.md)) blocks all of these paths. If you see write guard blocks that you didn't expect, that's it doing its job.
