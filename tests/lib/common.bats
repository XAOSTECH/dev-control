#!/usr/bin/env bats
#
# Tests for scripts/lib/common.sh
#

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

setup() {
    # Load the library
    source "$BATS_TEST_DIRNAME/../scripts/lib/common.sh"
}

# ============================================================================
# Text processing tests
# ============================================================================

@test "trim removes leading whitespace" {
    result=$(trim "  hello")
    assert_equal "$result" "hello"
}

@test "trim removes trailing whitespace" {
    result=$(trim "hello  ")
    assert_equal "$result" "hello"
}

@test "trim removes both leading and trailing whitespace" {
    result=$(trim "  hello world  ")
    assert_equal "$result" "hello world"
}

@test "to_lower converts uppercase to lowercase" {
    result=$(to_lower "HELLO WORLD")
    assert_equal "$result" "hello world"
}

@test "to_upper converts lowercase to uppercase" {
    result=$(to_upper "hello world")
    assert_equal "$result" "HELLO WORLD"
}

# ============================================================================
# Array tests
# ============================================================================

@test "in_array finds element in array" {
    local arr=("apple" "banana" "cherry")
    run in_array "banana" "${arr[@]}"
    assert_success
}

@test "in_array returns failure for missing element" {
    local arr=("apple" "banana" "cherry")
    run in_array "orange" "${arr[@]}"
    assert_failure
}

@test "in_array handles empty array" {
    local arr=()
    run in_array "apple" "${arr[@]}"
    assert_failure
}

# ============================================================================
# Validation tests
# ============================================================================

@test "is_git_repo returns success in git repo" {
    cd "$BATS_TEST_DIRNAME/.."
    run is_git_repo
    assert_success
}

@test "is_git_repo returns failure outside git repo" {
    cd /tmp
    run is_git_repo
    assert_failure
}

# ============================================================================
# Path tests
# ============================================================================

@test "get_script_dir returns correct directory" {
    local result
    result=$(get_script_dir)
    [[ -d "$result" ]]
}

# ============================================================================
# Version comparison tests
# ============================================================================

@test "version_gte returns true for equal versions" {
    run version_gte "1.0.0" "1.0.0"
    assert_success
}

@test "version_gte returns true for greater version" {
    run version_gte "2.0.0" "1.0.0"
    assert_success
}

@test "version_gte returns false for lesser version" {
    run version_gte "1.0.0" "2.0.0"
    assert_failure
}

@test "version_gte handles complex versions" {
    run version_gte "1.10.0" "1.9.0"
    assert_success
}
