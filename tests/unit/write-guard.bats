#!/usr/bin/env bats
# Tests for scripts/write-guard.sh — PreToolUse hook that blocks writes to
# host-executable and security-critical paths.

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/write-guard.sh"

# Helper: build JSON hook input
hook_json() {
    local tool="$1" path="$2"
    printf '{"tool_name":"%s","tool_input":{"file_path":"%s","content":"hello"}}' "$tool" "$path"
}

# ── Tool filtering ─────────────────────────────────────────────────

@test "allows non-file tools (Bash)" {
    echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | bash "$SCRIPT"
}

@test "allows non-file tools (Read)" {
    echo '{"tool_name":"Read","tool_input":{"file_path":"foo.txt"}}' | bash "$SCRIPT"
}

@test "allows empty file_path" {
    echo '{"tool_name":"Write","tool_input":{"content":"hi"}}' | bash "$SCRIPT"
}

# ── Tier 1: kernel-protected paths ─────────────────────────────────

@test "blocks .git/hooks/pre-commit (Tier 1)" {
    run bash -c 'echo '"'"'{"tool_name":"Write","tool_input":{"file_path":".git/hooks/pre-commit","content":"#!/bin/sh"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Tier 1"* ]]
}

@test "blocks .git/config (Tier 1)" {
    run bash -c 'hook_json Write .git/config | bash '"$SCRIPT"
    # Use inline JSON since helper isn't exported
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":".git/config","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Tier 1"* ]]
}

@test "blocks .claude/settings.json (Tier 1)" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":".claude/settings.json","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Tier 1"* ]]
}

@test "blocks .mcp.json (Tier 1)" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":".mcp.json","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Tier 1"* ]]
}

@test "blocks .claude/mcp.json (Tier 1)" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":".claude/mcp.json","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Tier 1"* ]]
}

@test "blocks .gitconfig (Tier 1)" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":".gitconfig","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Tier 1"* ]]
}

# ── Tier 2: hook-enforced paths ────────────────────────────────────

@test "blocks .vscode/settings.json (Tier 2)" {
    run bash -c 'printf '"'"'{"tool_name":"Edit","tool_input":{"file_path":".vscode/settings.json","new_string":"x","old_string":"y"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Tier 2"* ]]
}

@test "blocks .idea/ paths (Tier 2)" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":".idea/workspace.xml","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Tier 2"* ]]
}

@test "blocks .npmrc (Tier 2)" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":".npmrc","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Tier 2"* ]]
}

@test "blocks .env (Tier 2)" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":".env","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Tier 2"* ]]
}

@test "blocks .env.local (Tier 2)" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":".env.local","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Tier 2"* ]]
}

@test "blocks .bashrc (Tier 2)" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":".bashrc","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Tier 2"* ]]
}

@test "blocks .zshrc (Tier 2)" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":".zshrc","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Tier 2"* ]]
}

@test "allows .github/workflows/ (Tier 3 -- agent-writable)" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":".github/workflows/ci.yml","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "allows Makefile (Tier 3 -- agent-writable)" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":"Makefile","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "allows Jenkinsfile (Tier 3 -- agent-writable)" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":"Jenkinsfile","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "blocks .husky/ (Tier 2)" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":".husky/pre-commit","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Tier 2"* ]]
}

@test "blocks /etc/sandbox-guards/ (Tier 2)" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":"/etc/sandbox-guards/bypass-write-guard","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Tier 2"* ]]
}

@test "blocks /run/secrets/ (Tier 2)" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":"/run/secrets/api_key","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Tier 2"* ]]
}

# ── Allowed paths ──────────────────────────────────────────────────

@test "allows normal source files" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":"src/main.py","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "allows README.md" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":"README.md","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "allows tests" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":"tests/test_foo.py","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 0 ]
}

# ── Traversal prevention ──────────────────────────────────────────

@test "blocks traversal to .git/hooks via ../" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":"src/../.git/hooks/pre-commit","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
}

@test "blocks traversal to .env via ./" {
    run bash -c 'printf '"'"'{"tool_name":"Write","tool_input":{"file_path":"./.env","content":"x"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
}

# ── MultiEdit tool ─────────────────────────────────────────────────

@test "blocks MultiEdit to protected path" {
    run bash -c 'printf '"'"'{"tool_name":"MultiEdit","tool_input":{"file_path":".git/hooks/post-commit","edits":[]}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
}
