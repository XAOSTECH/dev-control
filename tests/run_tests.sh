#!/usr/bin/env bash
#
# Test runner for git-control
#
# Usage:
#   ./run_tests.sh           # Run all tests
#   ./run_tests.sh lib/      # Run lib tests only
#   ./run_tests.sh gc.bats   # Run specific test file
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source shared libraries
LIB_DIR="$(cd "$SCRIPT_DIR/../scripts/lib" && pwd)"
source "$LIB_DIR/colors.sh"
source "$LIB_DIR/print.sh"

# ============================================================================
# SETUP
# ============================================================================

ensure_bats_installed() {
    if command -v bats &>/dev/null; then
        print_info "Using system bats: $(bats --version)"
        return 0
    fi
    
    # Check for local bats
    if [[ -x "$SCRIPT_DIR/test_helper/bats/bin/bats" ]]; then
        export PATH="$SCRIPT_DIR/test_helper/bats/bin:$PATH"
        print_info "Using local bats"
        return 0
    fi
    
    print_info "Installing bats locally..."
    mkdir -p test_helper
    git clone --depth 1 https://github.com/bats-core/bats-core.git test_helper/bats
    git clone --depth 1 https://github.com/bats-core/bats-support.git test_helper/bats-support
    git clone --depth 1 https://github.com/bats-core/bats-assert.git test_helper/bats-assert
    
    rm -rf test_helper/bats/.git
    rm -rf test_helper/bats-support/.git
    rm -rf test_helper/bats-assert/.git
    
    export PATH="$SCRIPT_DIR/test_helper/bats/bin:$PATH"
}

# ============================================================================
# TEST EXECUTION
# ============================================================================

run_tests() {
    local test_target="${1:-.}"
    
    print_header "Git-Control Test Suite" 68
    
    ensure_bats_installed
    
    print_info "Running tests: $test_target"
    echo ""
    
    if [[ -d "$test_target" ]]; then
        bats --recursive "$test_target"
    else
        bats "$test_target"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    run_tests "$@"
}

main "$@"
