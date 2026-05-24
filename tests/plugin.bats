#!/usr/bin/env bats
#
# Tests for the plugin subsystem.
# Verifies that the bundled `example` plugin is discoverable and that `dc plugin <list|info>` returns sensible results.
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    DC="$BATS_TEST_DIRNAME/../dc"
}

@test "dc plugin list discovers the bundled example plugin" {
    run bash "$DC" plugin list
    assert_success
    assert_output --partial "example"
}

@test "dc plugin info example returns metadata" {
    run bash "$DC" plugin info example
    assert_success
    assert_output --partial "name: example"
    assert_output --partial "version: 1.0.0"
    assert_output --partial "description:"
}

@test "dc plugin info <unknown> fails cleanly" {
    run bash "$DC" plugin info no-such-plugin-xyz
    assert_failure
}

@test "example plugin contributes a hello command" {
    run bash "$DC" plugin info example
    assert_success
    assert_output --partial "hello"
}
