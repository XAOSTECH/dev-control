#!/usr/bin/env bats
#
# Tests for scripts/lib/config.sh
#

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

setup() {
    # Create temp directory for test configs
    TEST_CONFIG_DIR=$(mktemp -d)
    export XDG_CONFIG_HOME="$TEST_CONFIG_DIR"
    
    # Create test config structure
    mkdir -p "$TEST_CONFIG_DIR/dev-control"
    
    # Load the library
    source "$BATS_TEST_DIRNAME/../../scripts/lib/config.sh"
}

teardown() {
    rm -rf "$TEST_CONFIG_DIR"
}

# ============================================================================
# Config loading tests
# ============================================================================

@test "dc_config returns empty for missing key" {
    result=$(dc_config "nonexistent.key")
    assert_equal "$result" ""
}

@test "dc_config returns default for missing key" {
    result=$(dc_config "nonexistent.key" "default_value")
    assert_equal "$result" "default_value"
}

@test "dc_config reads from config file" {
    cat > "$TEST_CONFIG_DIR/dev-control/config.yaml" << 'EOF'
author: "Test Author"
default_licence: MIT
EOF
    
    load_dc_config
    result=$(dc_config "author")
    assert_equal "$result" "Test Author"
}

@test "dc_config_set writes to config" {
    local project_dir
    project_dir=$(mktemp -d)
    cd "$project_dir"
    git init --quiet
    
    dc_config_set "test_key" "test_value"
    load_dc_config
    result=$(dc_config "test_key")
    assert_equal "$result" "test_value"
    
    rm -rf "$project_dir"
}

# ============================================================================
# YAML parsing tests
# ============================================================================

@test "parse_yaml handles simple key-value" {
    local yaml_file=$(mktemp)
    cat > "$yaml_file" << 'EOF'
key: value
EOF
    
    eval $(parse_yaml "$yaml_file" "test_")
    assert_equal "$test_key" "value"
    rm "$yaml_file"
}

@test "parse_yaml maps hyphens to underscores in keys" {
    local yaml_file
    yaml_file=$(mktemp)
    cat > "$yaml_file" << 'EOF'
default-licence: GPL-3.0
EOF
    
    eval $(parse_yaml "$yaml_file" "test_")
    assert_equal "$test_default_licence" "GPL-3.0"
    rm "$yaml_file"
}

@test "parse_yaml handles quoted values" {
    local yaml_file=$(mktemp)
    cat > "$yaml_file" << 'EOF'
quoted: "value with spaces"
EOF
    
    eval $(parse_yaml "$yaml_file" "test_")
    assert_equal "$test_quoted" "value with spaces"
    rm "$yaml_file"
}

# ============================================================================
# Config hierarchy tests
# ============================================================================

@test "project config overrides global config" {
    # Create global config (flat schema)
    cat > "$TEST_CONFIG_DIR/dev-control/config.yaml" << 'EOF'
default_licence: MIT
EOF
    
    # Create project config in temp dir
    local project_dir
    project_dir=$(mktemp -d)
    cat > "$project_dir/.dc-init.yaml" << 'EOF'
default_licence: GPL-3.0
EOF
    
    cd "$project_dir"
    git init --quiet
    
    load_dc_config
    result=$(dc_config "default_licence")
    assert_equal "$result" "GPL-3.0"
    
    rm -rf "$project_dir"
}
