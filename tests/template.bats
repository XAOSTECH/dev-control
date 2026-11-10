#!/usr/bin/env bats
#
# Tests for scripts/template-loading.sh — specifically the helper functions
# that run without a full interactive session: describe_template_choices,
# process_template placeholder substitution, and install_workflows_templates
# file filtering.
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

# Source template-loading.sh with main() stubbed out so the script doesn't
# actually execute on load.
_load_tpl() {
    # shellcheck disable=SC1090
    bash -c 'main() { :; }; source '"$BATS_TEST_DIRNAME/../scripts/template-loading.sh"'; '"$1"
}

LOADER="$BATS_TEST_DIRNAME/../scripts/template-loading.sh"
DC_DIR="$BATS_TEST_DIRNAME/.."

# ============================================================================
# describe_template_choices
# ============================================================================

@test "describe_template_choices: 'A' returns 'all templates'" {
    run bash -c "
        main() { :; }
        DEV_CONTROL_DIR=\"$DC_DIR\"
        source \"$LOADER\"
        build_template_folders
        describe_template_choices 'A'
    "
    assert_success
    assert_output "all templates"
}

@test "describe_template_choices: 'a' (lowercase) also returns 'all templates'" {
    run bash -c "
        main() { :; }
        DEV_CONTROL_DIR=\"$DC_DIR\"
        source \"$LOADER\"
        build_template_folders
        describe_template_choices 'a'
    "
    assert_success
    assert_output "all templates"
}

@test "describe_template_choices: single numeric token returns folder name" {
    run bash -c "
        main() { :; }
        DEV_CONTROL_DIR=\"$DC_DIR\"
        source \"$LOADER\"
        build_template_folders
        describe_template_choices '2'
    "
    assert_success
    # slot 2 is 'workflows' (docs is 1, workflows is 2 in standard order)
    assert_output --partial "workflows"
}

@test "describe_template_choices: '1AX' does not trigger 'all templates'" {
    run bash -c "
        main() { :; }
        DEV_CONTROL_DIR=\"$DC_DIR\"
        source \"$LOADER\"
        build_template_folders
        describe_template_choices '1AX'
    "
    assert_success
    refute_output "all templates"
}

@test "describe_template_choices: '1,2' returns both folder names" {
    run bash -c "
        main() { :; }
        DEV_CONTROL_DIR=\"$DC_DIR\"
        source \"$LOADER\"
        build_template_folders
        describe_template_choices '1,2'
    "
    assert_success
    assert_output --partial "docs"
    assert_output --partial "workflows"
}

# ============================================================================
# process_template — placeholder substitution
# ============================================================================

setup() {
    WORK_DIR=$(mktemp -d)
    SRC="$WORK_DIR/tpl.yml"
    DEST="$WORK_DIR/out.yml"
}

teardown() {
    rm -rf "$WORK_DIR"
}

@test "process_template substitutes {{PROJECT_NAME}}" {
    printf 'name: {{PROJECT_NAME}}\n' > "$SRC"
    run bash -c "
        main() { :; }
        DEV_CONTROL_DIR=\"$DC_DIR\"
        source \"$LOADER\"
        PROJECT_NAME='my-project'
        REPO_SLUG='' ORG_NAME='' REPO_URL='' SHORT_DESCRIPTION='' LONG_DESCRIPTION=''
        LICENCE_TYPE='' STABILITY='' STABILITY_COLOR='' CURRENT_YEAR=2026
        BOT_NAME='' BOT_EMAIL='' BOT_APP_ID_SECRET='' BOT_CLIENT_ID_SECRET=''
        BOT_PRIVATE_KEY_SECRET='' GPG_PRIVATE_KEY_SECRET='' GPG_PASSPHRASE_SECRET=''
        USER_TOKEN_SECRET='' SECURITY_APP_ID_SECRET='' SECURITY_CLIENT_ID_SECRET=''
        SECURITY_PRIVATE_KEY_SECRET=''
        process_template '$SRC' '$DEST'
        cat '$DEST'
    "
    assert_success
    assert_output --partial "name: my-project"
}

@test "process_template: BOT_CLIENT_ID_SECRET falls back to BOT_APP_ID_SECRET" {
    printf '{{BOT_CLIENT_ID_SECRET}}\n' > "$SRC"
    run bash -c "
        main() { :; }
        DEV_CONTROL_DIR=\"$DC_DIR\"
        source \"$LOADER\"
        PROJECT_NAME='' REPO_SLUG='' ORG_NAME='' REPO_URL='' SHORT_DESCRIPTION=''
        LONG_DESCRIPTION='' LICENCE_TYPE='' STABILITY='' STABILITY_COLOR='' CURRENT_YEAR=2026
        BOT_NAME='' BOT_EMAIL='' BOT_APP_ID_SECRET='MY_APP_SECRET' BOT_CLIENT_ID_SECRET=''
        BOT_PRIVATE_KEY_SECRET='' GPG_PRIVATE_KEY_SECRET='' GPG_PASSPHRASE_SECRET=''
        USER_TOKEN_SECRET='' SECURITY_APP_ID_SECRET='' SECURITY_CLIENT_ID_SECRET=''
        SECURITY_PRIVATE_KEY_SECRET=''
        process_template '$SRC' '$DEST'
        cat '$DEST'
    "
    assert_success
    assert_output --partial "MY_APP_SECRET"
}

@test "process_template: explicit BOT_CLIENT_ID_SECRET takes precedence over BOT_APP_ID_SECRET" {
    printf '{{BOT_CLIENT_ID_SECRET}}\n' > "$SRC"
    run bash -c "
        main() { :; }
        DEV_CONTROL_DIR=\"$DC_DIR\"
        source \"$LOADER\"
        PROJECT_NAME='' REPO_SLUG='' ORG_NAME='' REPO_URL='' SHORT_DESCRIPTION=''
        LONG_DESCRIPTION='' LICENCE_TYPE='' STABILITY='' STABILITY_COLOR='' CURRENT_YEAR=2026
        BOT_NAME='' BOT_EMAIL='' BOT_APP_ID_SECRET='OLD_SECRET' BOT_CLIENT_ID_SECRET='NEW_CLIENT_ID'
        BOT_PRIVATE_KEY_SECRET='' GPG_PRIVATE_KEY_SECRET='' GPG_PASSPHRASE_SECRET=''
        USER_TOKEN_SECRET='' SECURITY_APP_ID_SECRET='' SECURITY_CLIENT_ID_SECRET=''
        SECURITY_PRIVATE_KEY_SECRET=''
        process_template '$SRC' '$DEST'
        cat '$DEST'
    "
    assert_success
    assert_output --partial "NEW_CLIENT_ID"
}

@test "process_template: {{LICENCE_TYPE_BADGE}} encodes dashes as double-dash" {
    printf '{{LICENCE_TYPE_BADGE}}\n' > "$SRC"
    run bash -c "
        main() { :; }
        DEV_CONTROL_DIR=\"$DC_DIR\"
        source \"$LOADER\"
        PROJECT_NAME='' REPO_SLUG='' ORG_NAME='' REPO_URL='' SHORT_DESCRIPTION=''
        LONG_DESCRIPTION='' LICENCE_TYPE='GPL-3.0' STABILITY='' STABILITY_COLOR='' CURRENT_YEAR=2026
        BOT_NAME='' BOT_EMAIL='' BOT_APP_ID_SECRET='' BOT_CLIENT_ID_SECRET=''
        BOT_PRIVATE_KEY_SECRET='' GPG_PRIVATE_KEY_SECRET='' GPG_PASSPHRASE_SECRET=''
        USER_TOKEN_SECRET='' SECURITY_APP_ID_SECRET='' SECURITY_CLIENT_ID_SECRET=''
        SECURITY_PRIVATE_KEY_SECRET=''
        process_template '$SRC' '$DEST'
        cat '$DEST'
    "
    assert_success
    assert_output --partial "GPL--3.0"
}

# ============================================================================
# install_workflows_templates — skips init.yml and remote-init.yml
# Tests inspect the template source directory directly rather than running
# the full install (which processes 20+ large files and is expensive).
# ============================================================================

@test "workflows-templates/ does not contain central-loader.yml (dev-control-only)" {
    # central-loader.yml is intentionally absent from the template folder
    run bash -c "ls '$DC_DIR/workflows-templates/'"
    assert_success
    refute_output --partial "central-loader.yml"
}

@test "workflows-templates/ contains dependabot-automerge.yml" {
    run bash -c "ls '$DC_DIR/workflows-templates/'"
    assert_success
    assert_output --partial "dependabot-automerge.yml"
}

@test "workflows-templates/ contains validate-pr.yml" {
    run bash -c "ls '$DC_DIR/workflows-templates/'"
    assert_success
    assert_output --partial "validate-pr.yml"
}

@test "workflows-templates/ contains static.yml and test.yml" {
    run bash -c "ls '$DC_DIR/workflows-templates/'"
    assert_success
    assert_output --partial "static.yml"
    assert_output --partial "test.yml"
}

@test "install_workflows_templates skips init.yml and remote-init.yml (code inspection)" {
    # Verify the guard is present in the source without executing the function
    run grep 'init.yml.*remote-init.yml\|remote-init.yml.*init.yml' "$DC_DIR/scripts/template-loading.sh"
    assert_success
}
