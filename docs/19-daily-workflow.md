# Daily Workflow Cheat Sheet

```bash
# ── Start of day ──────────────────────────────────────────────
docker sandbox run claude ~/my-project      # Enter sandbox
# Claude Code starts with full autonomy
# SessionStart hook auto-installs plugins
# PreToolUse hook gates any new skill installs through audit

# ── Interactive work ──────────────────────────────────────────
# Just talk to Claude. Edit files in VS Code on the host.

# ── Autonomous work ──────────────────────────────────────────
# Use the native Agent tool with run_in_background: true
# and isolation: "worktree" for long-running autonomous tasks.
# See RALPH.md pattern for iterative loop tasks.

# ── Reconnect after disconnect ────────────────────────────────
docker sandbox run claude-my-project        # Re-enter sandbox

# ── Monitor ──────────────────────────────────────────────────
docker sandbox ls                            # See all sandboxes
docker sandbox network log claude-my-proj   # Network activity
git log --oneline                            # Review commits

# ── End of day ───────────────────────────────────────────────
# Just close the terminal. Sandbox persists.
# Or: docker sandbox stop claude-my-project

# ── Nuke and rebuild ─────────────────────────────────────────
docker sandbox rm claude-my-project          # Destroy VM
docker sandbox run claude ~/my-project       # Fresh start
```
