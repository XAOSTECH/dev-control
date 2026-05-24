#!/usr/bin/env bats
#
# Tests for scripts/lib/cli.sh and scripts/lib/validation.sh
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

setup() {
    source "$BATS_TEST_DIRNAME/../../scripts/lib/cli.sh"
    source "$BATS_TEST_DIRNAME/../../scripts/lib/validation.sh"
}

# ============================================================================
# cli.sh — version_gte
# ============================================================================

@test "version_gte: equal versions return true" {
    run version_gte "1.0.0" "1.0.0"
    assert_success
}

@test "version_gte: greater version returns true" {
    run version_gte "2.0.0" "1.5.0"
    assert_success
}

@test "version_gte: lesser version returns false" {
    run version_gte "1.0.0" "1.5.0"
    assert_failure
}

@test "version_gte: handles patch-level comparisons" {
    run version_gte "1.0.10" "1.0.9"
    assert_success
}

# ============================================================================
# cli.sh — flag helpers
# ============================================================================

@test "is_flag: recognises a flag" {
    run is_flag "--verbose"
    assert_success
}

@test "is_flag: rejects a value" {
    run is_flag "value"
    assert_failure
}

@test "flag_has_value: accepts a plain value" {
    run flag_has_value "myvalue"
    assert_success
}

@test "flag_has_value: rejects another flag" {
    run flag_has_value "--other"
    assert_failure
}

# ============================================================================
# cli.sh — parse_common_flags
# ============================================================================

@test "parse_common_flags: extracts --verbose" {
    parse_common_flags --verbose foo bar
    assert_equal "$VERBOSE" "true"
    assert_equal "${REMAINING_ARGS[0]}" "foo"
    assert_equal "${REMAINING_ARGS[1]}" "bar"
}

@test "parse_common_flags: extracts --help, --debug, --dry-run together" {
    parse_common_flags --help --debug --dry-run
    assert_equal "$SHOW_HELP" "true"
    assert_equal "$DEBUG" "true"
    assert_equal "$DRY_RUN" "true"
}

@test "parse_common_flags: defaults are false when no flags given" {
    parse_common_flags positional
    assert_equal "$SHOW_HELP" "false"
    assert_equal "$VERBOSE" "false"
    assert_equal "${REMAINING_ARGS[0]}" "positional"
}

# ============================================================================
# cli.sh — get_script_dir
# ============================================================================

@test "get_script_dir: returns absolute directory for a real file" {
    local f
    f=$(mktemp)
    run get_script_dir "$f"
    assert_success
    assert_output "$(dirname "$f")"
    rm -f "$f"
}

# ============================================================================
# validation.sh
# ============================================================================

@test "is_empty: empty string is empty" {
    run is_empty ""
    assert_success
}

@test "is_empty: whitespace-only string is empty" {
    run is_empty "    "
    assert_success
}

@test "is_empty: non-empty string is not empty" {
    run is_empty "hello"
    assert_failure
}

@test "is_valid_identifier: accepts a snake_case name" {
    run is_valid_identifier "my_var_1"
    assert_success
}

@test "is_valid_identifier: rejects leading digit" {
    run is_valid_identifier "1var"
    assert_failure
}

@test "is_valid_slug: accepts a kebab-case slug" {
    run is_valid_slug "my-repo-name"
    assert_success
}

@test "is_valid_slug: rejects uppercase" {
    run is_valid_slug "My-Repo"
    assert_failure
}

@test "to_slug: lowercases and hyphenates" {
    result=$(to_slug "My Project Name")
    assert_equal "$result" "my-project-name"
}

@test "to_slug: collapses repeated separators" {
    result=$(to_slug "  Hello   World  ")
    assert_equal "$result" "hello-world"
}
