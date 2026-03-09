# Git Worktrees

Git worktrees let you run multiple Claude instances on separate branches simultaneously within the same sandbox.

## Create Worktrees

```bash
./scripts/create-worktree.sh feature-auth
./scripts/create-worktree.sh feature-api
./scripts/create-worktree.sh feature-tests
```

## Run Parallel Agents with tmux

```bash
tmux new-session -d -s agents
tmux send-keys "cd .worktrees/feature-auth && claude --dangerously-skip-permissions" Enter
tmux split-window -h
tmux send-keys "cd .worktrees/feature-api && claude --dangerously-skip-permissions" Enter
tmux attach -t agents
```

## Security: Worktree Hook Inheritance

All git worktrees share the parent repo's `.git/hooks/` directory. If a compromised agent writes a malicious hook in one worktree, it affects all worktrees (including the main checkout). The write guard blocks all `.git/hooks/` writes regardless of worktree. Each worktree runs inside the same sandbox, so the blast radius is already contained to the VM.
