#!/usr/bin/env bats
#
# Tests for scripts/lib/output.sh
#

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

setup() {
    source "$BATS_TEST_DIRNAME/../../scripts/lib/output.sh"
}

# ============================================================================
# Output mode tests
# ============================================================================

@test "parse_output_flags sets quiet mode" {
    parse_output_flags --quiet
    assert_equal "$GC_QUIET" "true"
}

@test "parse_output_flags sets json mode" {
    parse_output_flags --json
    assert_equal "$GC_JSON" "true"
}

@test "parse_output_flags sets verbose mode" {
    parse_output_flags --verbose
    assert_equal "$GC_VERBOSE" "true"
}

@test "parse_output_flags handles multiple flags" {
    parse_output_flags --verbose --json
    assert_equal "$GC_VERBOSE" "true"
    assert_equal "$GC_JSON" "true"
}

# ============================================================================
# Output function tests
# ============================================================================

@test "out prints message in normal mode" {
    GC_QUIET=false
    run out "test message"
    assert_output "test message"
}

@test "out suppresses output in quiet mode" {
    GC_QUIET=true
    run out "test message"
    assert_output ""
}

@test "verbose prints in verbose mode" {
    GC_VERBOSE=true
    run verbose "debug info"
    assert_output --partial "debug info"
}

@test "verbose suppresses in normal mode" {
    GC_VERBOSE=false
    run verbose "debug info"
    assert_output ""
}

# ============================================================================
# JSON output tests
# ============================================================================

@test "json_field creates valid field" {
    result=$(json_field "name" "value")
    assert_equal "$result" '"name": "value"'
}

@test "json_field escapes quotes" {
    result=$(json_field "name" 'value with "quotes"')
    [[ "$result" == *'\"'* ]]
}

@test "json_output creates valid JSON" {
    result=$(json_output "name" "test" "version" "1.0")
    # Should start with { and end with }
    [[ "$result" == "{"* ]]
    [[ "$result" == *"}" ]]
}
