#!/usr/bin/env bats
#
# Tests for the unified GPG / dc-key flow (scripts/lib/gpg.sh + keygen.sh).
#
# Everything runs against a throw-away dummy DEV_CONTROL_DIR with a fake repoVars.env
# (dummy secret NAMES, dummy owner) and an emulated GitHub/GPG side (test_helper/fake-bin
# gh + gpg). No real names, keys, account or repository are ever touched, and the tests
# assert that key material never appears in terminal output.
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    GPG_LIB="$BATS_TEST_DIRNAME/../scripts/lib/gpg.sh"
    KEYGEN="$BATS_TEST_DIRNAME/../scripts/lib/keygen.sh"

    TEST_HOME=$(mktemp -d)
    mkdir -p "$TEST_HOME/config/profiles" "$TEST_HOME/secrets" "$TEST_HOME/xdg"

    cat > "$TEST_HOME/config/profiles/repoVars.env" <<'EOF'
REPO_OWNER="dummyorg"
BOT_NAME="dummy-bot"
BOT_EMAIL="0+dummy-bot@users.noreply.invalid"
GPG_PRIVATE_KEY_SECRET="DUMMY_GK"
GPG_PASSPHRASE_SECRET="DUMMY_GP"
USER_TOKEN_SECRET="DUMMY_UT"
EOF
    cat > "$TEST_HOME/config/profiles/xaos-bot[bot]_gpg.yml" <<'EOF'
Key-Type: RSA
Key-Length: 4096
Expire-Date: 1y
EOF

    export DEV_CONTROL_DIR="$TEST_HOME"
    export GH_FAKE_SECRETS="$TEST_HOME/secrets"
    export XDG_CONFIG_HOME="$TEST_HOME/xdg"
    export PATH="$BATS_TEST_DIRNAME/fake-bin:$PATH"
}

teardown() {
    rm -rf "$TEST_HOME"
}

@test "gpg_mask hides the middle of a value" {
    run bash -c "source '$GPG_LIB'; gpg_mask ABCDEF0123456789 4"
    assert_success
    assert_output "ABCD********6789"
}

@test "resolver reads dummy secret names from repoVars, never real ones" {
    run bash -c "source '$GPG_LIB'; gpg_resolve_vars; echo \"\$GPG_PRIVATE_KEY_SECRET \$GPG_PASSPHRASE_SECRET \$USER_TOKEN_SECRET \$BOT_NAME\""
    assert_success
    assert_output --partial "DUMMY_GK DUMMY_GP DUMMY_UT dummy-bot"
    refute_output --partial "XB_"
}

@test "bot refresh --dry-run writes no secrets" {
    run bash -c "source '$GPG_LIB'; gpg_refresh_bot_secrets true"
    assert_success
    assert_output --partial "[dry-run]"
    assert [ ! -e "$GH_FAKE_SECRETS/DUMMY_GK" ]
    assert [ ! -e "$GH_FAKE_SECRETS/DUMMY_GP" ]
}

@test "bot refresh sets both secrets and never leaks key material" {
    run bash -c "source '$GPG_LIB'; printf 'y\n' | gpg_refresh_bot_secrets false"
    assert_success
    assert [ -s "$GH_FAKE_SECRETS/DUMMY_GK" ]
    assert [ -s "$GH_FAKE_SECRETS/DUMMY_GP" ]
    refute_output --partial "BEGIN PGP PRIVATE KEY BLOCK"
    assert_output --partial "****"
    run cat "$GH_FAKE_SECRETS/DUMMY_GK"
    assert_output --partial "BEGIN PGP PRIVATE KEY BLOCK"
}

@test "user token is captured from stdin and never echoed" {
    run bash -c "source '$GPG_LIB'; printf 'ghp_DUMMYTOKEN123\n' | gpg_set_user_token false"
    assert_success
    assert [ -s "$GH_FAKE_SECRETS/DUMMY_UT" ]
    refute_output --partial "ghp_DUMMYTOKEN123"
    run cat "$GH_FAKE_SECRETS/DUMMY_UT"
    assert_output --partial "ghp_DUMMYTOKEN123"
}

@test "dc-key --status is read-only and shows resolved dummy names" {
    run bash "$KEYGEN" --status
    assert_success
    assert_output --partial "DUMMY_GK"
    assert_output --partial "dummyorg/dummyrepo"
    assert [ ! -e "$GH_FAKE_SECRETS/DUMMY_GK" ]
}

@test "dc-key --bot --dry-run routes through the hub without writing" {
    run bash "$KEYGEN" --bot --dry-run
    assert_success
    assert_output --partial "[dry-run]"
    assert_output --partial "DUMMY_GK"
    assert [ ! -e "$GH_FAKE_SECRETS/DUMMY_GK" ]
}
