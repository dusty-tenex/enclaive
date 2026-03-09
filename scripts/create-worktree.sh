#!/bin/bash
set -euo pipefail
BRANCH=${1:?Usage: create-worktree.sh <branch-name> [base-branch]}
BASE=${2:-main}
WORKTREE_DIR=".worktrees/${BRANCH}"

mkdir -p .worktrees
echo ".worktrees/" >> .gitignore 2>/dev/null || true

git worktree add -b "$BRANCH" "$WORKTREE_DIR" "$BASE" 2>/dev/null \
    || git worktree add "$WORKTREE_DIR" "$BRANCH"

echo "[OK] Worktree: $WORKTREE_DIR (branch: $BRANCH)"
echo "   cd $WORKTREE_DIR && claude --dangerously-skip-permissions"
