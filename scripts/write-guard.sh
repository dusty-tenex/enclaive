#!/bin/bash
# PreToolUse hook: blocks writes to host-executable and security-critical paths.
#
# ENFORCEMENT MODEL (three tiers):
#
#   Tier 1 — Kernel-enforced (entrypoint.sh):
#     .git/hooks/, .git/config, .claude/settings.json, .mcp.json
#     Root-owned, sandbox user cannot write. No hook needed — kernel blocks it.
#     This hook serves as a defense-in-depth early warning for Tier 1 paths.
#
#   Tier 2 — Hook-enforced for Write/Edit (this script):
#     .vscode/*, .idea/, .husky/, .npmrc, .yarnrc, etc.
#     Reliable because Write/Edit paths come from structured JSON.
#     NOT enforced for Bash — regex parsing is unreliable (see Tier 3 note).
#
#   Tier 3 — Agent-writable (no restriction):
#     Makefile, .github/workflows/, .gitlab-ci.yml, Justfile, .python-version
#     Autonomous agents legitimately create these. Sandbox boundary contains risk.
#
# WHY NO BASH PATH EXTRACTION:
#   Extracting file paths from arbitrary bash commands via regex is fundamentally
#   unreliable. Variable indirection, subshells, symlinks, Python one-liners,
#   dd, install, process substitution — all bypass regex extraction trivially.
#   Tier 1 paths are protected by the kernel (root ownership). Tier 2 paths
#   are protected for the structured Write/Edit tools that Claude Code uses
#   for ~95% of file operations. The sandbox boundary handles the rest.

set -euo pipefail
# Bypass only via host-controlled read-only mount (agent cannot write to this path)
[ -f /etc/sandbox-guards/bypass-write-guard ] && exit 0
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')

# Only enforce for structured file-writing tools (reliable path extraction)
case "$TOOL" in
    Write|Edit|MultiEdit) ;;
    *) exit 0 ;;
esac

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')
[ -z "$FILE_PATH" ] && exit 0

# Canonicalize: resolve ../ and ./ to prevent traversal bypasses
# e.g., ./.git/../.git/hooks/pre-commit → .git/hooks/pre-commit
if command -v realpath >/dev/null 2>&1; then
    # Use --relative-to to keep it workspace-relative, --no-symlinks to
    # resolve path components without requiring the file to exist
    CANONICAL=$(realpath -m --relative-to="$(pwd)" "$FILE_PATH" 2>/dev/null) || CANONICAL="$FILE_PATH"
else
    # Fallback: strip ./ prefixes and collapse ../ sequences (loop to handle multiple levels)
    CANONICAL="$FILE_PATH"
    PREV=""
    while [ "$CANONICAL" != "$PREV" ]; do
        PREV="$CANONICAL"
        CANONICAL=$(echo "$CANONICAL" | sed -e 's|/\./|/|g' -e 's|/[^/]*/\.\./|/|g' -e 's|^\./||')
    done
fi

# ── Tier 1: Kernel-enforced paths (defense-in-depth warning) ──────
# These are root-owned — the write will fail at the kernel level anyway.
# This hook provides a clear error message instead of a cryptic "Permission denied".
TIER1_PATTERNS=(
    '(^|/)\.git/hooks(/|$)'
    '(^|/)\.git/config$'
    '(^|/)\.gitconfig$'
    '(^|/)\.claude/settings\.json$'
    '(^|/)\.mcp\.json$'
    '(^|/)\.claude/mcp\.json$'
)

for pattern in "${TIER1_PATTERNS[@]}"; do
    if echo "$CANONICAL" | grep -qE "$pattern"; then
        echo "[GUARD] WRITE GUARD [Tier 1]: Blocked write to kernel-protected path: $FILE_PATH" >&2
        echo "  This path is root-owned inside the sandbox. The kernel will block this write." >&2
        echo "  This path is enforced by the kernel inside the sandbox." >&2
        exit 2
    fi
done

# ── Tier 2: Hook-enforced paths (IDE, package manager config) ─────
# These are writable on disk but should not be modified by the agent.
# Enforced reliably because Write/Edit paths come from structured JSON.
TIER2_PATTERNS=(
    '(^|/)\.vscode/settings\.json$'
    '(^|/)\.vscode/tasks\.json$'
    '(^|/)\.vscode/launch\.json$'
    '(^|/)\.vscode/extensions\.json$'
    '\.code-workspace$'
    '(^|/)\.idea/'
    '(^|/)\.husky/'
    '(^|/)\.npmrc$'
    '(^|/)\.yarnrc'
    '(^|/)lefthook\.yml$'
    '(^|/)\.pre-commit-config\.yaml$'
    '(^|/)/etc/sandbox-guards/'
    '(^|/)/run/secrets/'
    '(^|/)\.env(\.|$)'
    '(^|/)Makefile$'
    '(^|/)Justfile$'
    '(^|/)\.github/workflows/'
    '(^|/)\.gitlab-ci\.yml$'
    '(^|/)\.circleci/'
    '(^|/)Jenkinsfile$'
    '(^|/)\.profile$'
    '(^|/)\.bashrc$'
    '(^|/)\.zshrc$'
)

for pattern in "${TIER2_PATTERNS[@]}"; do
    if echo "$CANONICAL" | grep -qE "$pattern"; then
        echo "[GUARD] WRITE GUARD [Tier 2]: Blocked write to host-config path: $FILE_PATH" >&2
        echo "  These files sync to the host and may affect IDE or toolchain behavior." >&2
        echo "  To override (host-side only): touch /path/to/guard-bypass/bypass-write-guard" >&2
        exit 2
    fi
done

exit 0
