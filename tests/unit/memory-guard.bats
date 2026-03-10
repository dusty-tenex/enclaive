#!/usr/bin/env bats
# Tests for scripts/memory-guard.sh — PreToolUse hook for memory file protection.
# These tests focus on file detection logic (sidecar is mocked as unavailable).

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/memory-guard.sh"

setup() {
    # Disable sidecar requirement so we test the detection logic path
    export GUARDRAILS_REQUIRE_SIDECAR=0
    # Point sidecar to a port nothing listens on
    export GUARDRAILS_SIDECAR_URL="http://127.0.0.1:19999"
}

# ── Tool filtering ─────────────────────────────────────────────────

@test "allows Read tool" {
    run bash -c 'echo '"'"'{"tool_name":"Read","tool_input":{"file_path":"CLAUDE.md"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "allows Grep tool" {
    run bash -c 'echo '"'"'{"tool_name":"Grep","tool_input":{"pattern":"foo"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 0 ]
}

# ── Memory file detection ─────────────────────────────────────────

@test "checks CLAUDE.md" {
    # With sidecar down and require=0, falls back to Python security_guard.py
    # Safe content should pass
    run bash -c 'echo '"'"'{"tool_name":"Write","tool_input":{"file_path":"CLAUDE.md","content":"Remember to use bun"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "skips non-memory files" {
    run bash -c 'echo '"'"'{"tool_name":"Write","tool_input":{"file_path":"src/main.py","content":"import os"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "skips random .md files" {
    run bash -c 'echo '"'"'{"tool_name":"Write","tool_input":{"file_path":"docs/guide.md","content":"# Guide"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "checks RALPH.md" {
    run bash -c 'echo '"'"'{"tool_name":"Write","tool_input":{"file_path":"RALPH.md","content":"Safe content here"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "checks MEMORY.md" {
    run bash -c 'echo '"'"'{"tool_name":"Write","tool_input":{"file_path":"MEMORY.md","content":"Remember this"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "checks SOUL.md" {
    run bash -c 'echo '"'"'{"tool_name":"Edit","tool_input":{"file_path":"SOUL.md","new_string":"updated","old_string":"old"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "checks progress.md" {
    run bash -c 'echo '"'"'{"tool_name":"Write","tool_input":{"file_path":"progress.md","content":"Step 1 done"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "checks .claude/agents/*/memory/ paths" {
    run bash -c 'echo '"'"'{"tool_name":"Write","tool_input":{"file_path":".claude/agents/coder/memory/notes.md","content":"ok"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "checks .claude/skills/*.md paths" {
    run bash -c 'echo '"'"'{"tool_name":"Write","tool_input":{"file_path":".claude/skills/my-skill.md","content":"ok"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 0 ]
}

# ── Sidecar-required mode ─────────────────────────────────────────

@test "blocks when sidecar required and unreachable" {
    export GUARDRAILS_REQUIRE_SIDECAR=1
    run bash -c 'echo '"'"'{"tool_name":"Write","tool_input":{"file_path":"CLAUDE.md","content":"anything"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Sidecar unreachable"* ]]
}

@test "blocks Bash tool when sidecar required and unreachable" {
    export GUARDRAILS_REQUIRE_SIDECAR=1
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"echo hi > CLAUDE.md"}}'"'"' | bash '"$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Sidecar unreachable"* ]]
}
