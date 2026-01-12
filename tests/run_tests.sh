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

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
print_error() { echo -e "${RED}[FAIL]${NC} $1"; }

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
    
    export PATH="$SCRIPT_DIR/test_helper/bats/bin:$PATH"
}

# ============================================================================
# TEST EXECUTION
# ============================================================================

run_tests() {
    local test_target="${1:-.}"
    
    echo -e "${BOLD}${BLUE}"
    echo "  ┌───────────────────────────────────────┐"
    echo "  │       Git-Control Test Suite          │"
    echo "  └───────────────────────────────────────┘"
    echo -e "${NC}"
    
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
