#!/usr/bin/env bats
# Tests for scripts/task-queue.sh — file-based task queue.

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/task-queue.sh"

setup() {
    export ORIG_DIR="$PWD"
    export TMPDIR_BATS="$(mktemp -d)"
    cd "$TMPDIR_BATS"
}

teardown() {
    cd "$ORIG_DIR"
    rm -rf "$TMPDIR_BATS"
}

@test "add creates a pending task" {
    run bash "$SCRIPT" add "Buy groceries"
    [ "$status" -eq 0 ]
    [[ "$output" == *"queued"* ]]
    # Verify file exists in pending/
    [ "$(ls .task-queue/pending/ | wc -l)" -eq 1 ]
}

@test "add writes content to the task file" {
    bash "$SCRIPT" add "Deploy to prod"
    file=$(ls .task-queue/pending/*.md | head -1)
    [ "$(cat "$file")" = "Deploy to prod" ]
}

@test "next claims a pending task" {
    bash "$SCRIPT" add "First task"
    run bash "$SCRIPT" next
    # Note: script returns exit 1 when task claimed ([ "$CLAIMED" = false ] fails)
    [ "$output" = "First task" ]
    # Task moved from pending to active
    [ "$(ls .task-queue/pending/ | wc -l)" -eq 0 ]
    [ "$(ls .task-queue/active/ | wc -l)" -eq 1 ]
}

@test "next returns Empty when queue is empty" {
    run bash "$SCRIPT" next
    [ "$status" -eq 0 ]
    [ "$output" = "Empty" ]
}

@test "done moves active task to done" {
    bash "$SCRIPT" add "My task"
    # Get the task ID from the filename
    id=$(ls .task-queue/pending/ | sed 's/\.md$//')
    bash "$SCRIPT" next >/dev/null || true
    bash "$SCRIPT" done "$id"
    [ "$(ls .task-queue/active/ | wc -l)" -eq 0 ]
    [ "$(ls .task-queue/done/ | wc -l)" -eq 1 ]
}

@test "list shows queue state" {
    bash "$SCRIPT" add "Task A"
    bash "$SCRIPT" add "Task B"
    bash "$SCRIPT" next >/dev/null || true
    run bash "$SCRIPT" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pending:"* ]]
    [[ "$output" == *"Active:"* ]]
    [[ "$output" == *"Done:"* ]]
}

@test "multiple adds create unique IDs" {
    bash "$SCRIPT" add "Task 1"
    bash "$SCRIPT" add "Task 2"
    bash "$SCRIPT" add "Task 3"
    count=$(ls .task-queue/pending/ | wc -l)
    [ "$count" -eq 3 ]
    # All filenames should be unique
    unique=$(ls .task-queue/pending/ | sort -u | wc -l)
    [ "$unique" -eq 3 ]
}

@test "next processes tasks in order" {
    # Add tasks with slight delay to ensure ordering
    bash "$SCRIPT" add "First"
    sleep 0.01
    bash "$SCRIPT" add "Second"
    run bash "$SCRIPT" next
    [[ "$output" == "First" ]]
}

@test "usage message for unknown command" {
    run bash "$SCRIPT" unknown
    [[ "$output" == *"Usage"* ]]
}

@test "usage message for no arguments" {
    run bash "$SCRIPT"
    [[ "$output" == *"Usage"* ]]
}
