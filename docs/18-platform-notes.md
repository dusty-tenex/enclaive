# Platform Notes

The `setup.sh` installer handles both macOS and Linux. It detects your shell, applies the correct paths, and works identically on both platforms.

## macOS

No additional configuration needed. The installer detects `~/.zshrc` vs `~/.bashrc` automatically. Ensure Docker Desktop is running before launching.

## Windows (WSL2)

Run `setup.sh` from inside a WSL2 terminal, not PowerShell. Docker Desktop must have the WSL2 backend enabled.

```bash
# In WSL2 (Ubuntu):
export ANTHROPIC_API_KEY="sk-ant-..."  # Add to ~/.bashrc for persistence
./setup.sh ~/my-project
```

**Performance note:** Keep your project directory inside the WSL2 filesystem (e.g., `~/my-project`), not on the Windows mount (`/mnt/c/...`). Cross-filesystem I/O is significantly slower.

## Linux

As of Docker Desktop 4.62, experimental Linux support for microVM sandboxes is available (single user only, UID 1000). Linux users with Docker Desktop should try microVM sandboxes first. For headless Linux servers, multi-user environments, or CI/CD, see [Appendix A: Devcontainer Fallback](appendix-a-devcontainer.md).
