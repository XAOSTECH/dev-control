#!/usr/bin/env bats
#
# Integration tests for gc command
#

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

setup() {
    GC="$BATS_TEST_DIRNAME/../gc"
}

# ============================================================================
# Basic invocation tests
# ============================================================================

@test "gc --help shows usage" {
    run "$GC" --help
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "git-control"
}

@test "gc --version shows version" {
    run "$GC" --version
    assert_success
    assert_output --partial "git-control"
}

@test "gc with unknown command shows error" {
    run "$GC" nonexistent-command
    assert_failure
    assert_output --partial "Unknown command"
}

@test "gc without arguments shows help" {
    run "$GC"
    assert_success
    assert_output --partial "Usage:"
}

# ============================================================================
# Command discovery tests
# ============================================================================

@test "gc lists available commands" {
    run "$GC" --help
    assert_output --partial "Commands:"
}

@test "gc status works with --json" {
    run "$GC" status --json
    assert_success
    # Should output valid JSON
    assert_output --partial "{"
    assert_output --partial "}"
}

@test "gc config show works" {
    run "$GC" config show
    assert_success
}

# ============================================================================
# Plugin tests
# ============================================================================

@test "gc plugin list works" {
    run "$GC" plugin list
    assert_success
}

@test "gc plugin info shows plugin details" {
    run "$GC" plugin info example
    # May succeed or fail depending on plugin presence
    # Just verify it doesn't crash
    [[ $status -eq 0 || $status -eq 1 ]]
}
