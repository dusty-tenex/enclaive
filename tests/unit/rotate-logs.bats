#!/usr/bin/env bats
# Tests for scripts/rotate-logs.sh — audit/agent log rotation.

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/rotate-logs.sh"

setup() {
    export ORIG_DIR="$PWD"
    export TMPDIR_BATS="$(mktemp -d)"
    cd "$TMPDIR_BATS"
}

teardown() {
    cd "$ORIG_DIR"
    rm -rf "$TMPDIR_BATS"
}

@test "no-op when audit dir does not exist" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    # Should not mention pruning
    [[ "$output" != *"Pruned"* ]]
}

@test "no pruning when under max files" {
    mkdir -p .audit-logs
    for i in $(seq 1 5); do
        echo "{}" > ".audit-logs/log-${i}.json"
    done
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Pruned"* ]]
    [ "$(ls .audit-logs/*.json | wc -l)" -eq 5 ]
}

@test "prunes oldest files when over 200" {
    # This test requires GNU find (-printf) — skip on macOS
    if [[ "$(uname)" == "Darwin" ]]; then
        skip "GNU find required (runs in CI on Linux)"
    fi
    mkdir -p .audit-logs
    # Create 205 files with incrementing timestamps
    for i in $(seq 1 205); do
        touch -t "202401$(printf '%02d' $((i % 28 + 1)))0000" ".audit-logs/log-${i}.json"
    done
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pruned"* ]]
    remaining=$(find .audit-logs -name "*.json" -type f | wc -l)
    [ "$remaining" -eq 200 ]
}

@test "compresses old agent logs" {
    mkdir -p agent_logs
    echo "old log" > agent_logs/old.log
    # Make the file appear old (use touch with past date)
    touch -t 202301010000 agent_logs/old.log
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Compressed"* ]]
    # Original .log should be replaced by .log.gz
    [ ! -f agent_logs/old.log ] || [ -f agent_logs/old.log.gz ]
}

@test "skips agent log compression when dir missing" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "does not compress recent agent logs" {
    mkdir -p agent_logs
    echo "recent" > agent_logs/fresh.log
    run bash "$SCRIPT"
    # fresh.log should still exist as .log (not compressed)
    [ -f agent_logs/fresh.log ]
}
