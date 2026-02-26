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

@test "gc_config returns empty for missing key" {
    result=$(gc_config "nonexistent.key")
    assert_equal "$result" ""
}

@test "gc_config returns default for missing key" {
    result=$(gc_config "nonexistent.key" "default_value")
    assert_equal "$result" "default_value"
}

@test "gc_config reads from config file" {
    cat > "$TEST_CONFIG_DIR/dev-control/config.yaml" << 'EOF'
defaults:
  author: "Test Author"
  licence: MIT
EOF
    
    load_gc_config
    result=$(gc_config "defaults.author")
    assert_equal "$result" "Test Author"
}

@test "gc_config_set writes to config" {
    gc_config_set "test.key" "test_value"
    result=$(gc_config "test.key")
    assert_equal "$result" "test_value"
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

@test "parse_yaml handles nested structure" {
    local yaml_file=$(mktemp)
    cat > "$yaml_file" << 'EOF'
parent:
  child: nested_value
EOF
    
    eval $(parse_yaml "$yaml_file" "test_")
    assert_equal "$test_parent_child" "nested_value"
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
    # Create global config
    cat > "$TEST_CONFIG_DIR/dev-control/config.yaml" << 'EOF'
defaults:
  licence: MIT
EOF
    
    # Create project config in temp dir
    local project_dir=$(mktemp -d)
    cat > "$project_dir/.dc-init.yaml" << 'EOF'
defaults:
  licence: GPL-3.0
EOF
    
    cd "$project_dir"
    git init --quiet
    
    load_gc_config
    result=$(gc_config "defaults.licence")
    assert_equal "$result" "GPL-3.0"
    
    rm -rf "$project_dir"
}
