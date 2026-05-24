#!/usr/bin/env bats
#
# Integration tests for the `dc` CLI entrypoint
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    DC="$BATS_TEST_DIRNAME/../dc"
}

# Basic invocation

@test "dc --help shows usage banner" {
    run bash "$DC" --help
    assert_success
    assert_output --partial "USAGE"
    assert_output --partial "Dev-Control"
}

@test "dc --help lists known commands" {
    run bash "$DC" --help
    assert_success
    assert_output --partial "COMMANDS"
    assert_output --partial "init"
    assert_output --partial "repo"
    assert_output --partial "fix"
}

@test "dc --version prints version line" {
    run bash "$DC" --version
    assert_success
    assert_output --partial "dev-control"
}

@test "dc --version --json emits structured payload" {
    run bash "$DC" --json --version
    assert_success
    assert_output --partial '"version"'
    assert_output --partial '"root"'
}

@test "dc with unknown command fails with a clear message" {
    run bash "$DC" nonexistent-command-xyz
    assert_failure
    assert_output --partial "Unknown command"
}

@test "dc --list-commands enumerates the registry" {
    run bash "$DC" --list-commands
    assert_success
    assert_output --partial "init"
    assert_output --partial "status"
    assert_output --partial "config"
}

# Built-in subcommands

@test "dc status --json emits valid-shaped JSON" {
    run bash "$DC" status --json
    assert_success
    assert_output --partial '"dc"'
    assert_output --partial '"git"'
    assert_output --partial '"version"'
}

@test "dc config --help is documented" {
    run bash "$DC" config --help
    assert_success
    assert_output --partial "Configuration"
    assert_output --partial "USAGE"
}

@test "dc plugin --help is documented" {
    run bash "$DC" plugin --help
    assert_success
    assert_output --partial "Plugin Manager"
    assert_output --partial "list"
}

@test "dc version --help is documented" {
    run bash "$DC" version --help
    assert_success
    assert_output --partial "Version"
    assert_output --partial "USAGE"
}

# JSON structural validation (requires jq)

@test "dc status --json parses as valid JSON" {
    if ! command -v jq &>/dev/null; then skip "jq not installed"; fi
    run bash -c "bash '$DC' status --json | jq -e ."
    assert_success
}

@test "dc status --json has expected top-level keys" {
    if ! command -v jq &>/dev/null; then skip "jq not installed"; fi
    run bash -c "bash '$DC' status --json | jq -er '[.dc, .git, .config, .tools] | length'"
    assert_success
    assert_output "4"
}

@test "dc status --json reports inRepo=true inside the dev-control checkout" {
    if ! command -v jq &>/dev/null; then skip "jq not installed"; fi
    run bash -c "bash '$DC' status --json | jq -er '.git.inRepo'"
    assert_success
    assert_output "true"
}

@test "dc status --json exposes dc.version as a non-empty string" {
    if ! command -v jq &>/dev/null; then skip "jq not installed"; fi
    run bash -c "bash '$DC' status --json | jq -er '.dc.version | test(\"^[0-9]+\\\\.\")'"
    assert_success
    assert_output "true"
}

@test "dc --json --version parses as valid JSON with version + root fields" {
    if ! command -v jq &>/dev/null; then skip "jq not installed"; fi
    run bash -c "bash '$DC' --json --version | jq -er '[.version, .root] | all(type == \"string\")'"
    assert_success
    assert_output "true"
}
