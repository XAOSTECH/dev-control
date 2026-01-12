#!/usr/bin/env bash
#
# Example Plugin Command
# Demonstrates how to create a plugin command
#
set -e

# Use GC_ROOT for shared libraries
if [[ -z "$GC_ROOT" ]]; then
    echo "Error: GC_ROOT not set. Run via 'gc hello' instead." >&2
    exit 1
fi

source "$GC_ROOT/scripts/lib/colors.sh"
source "$GC_ROOT/scripts/lib/print.sh"

# Handle --help
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    cat << 'EOF'
Hello - Example plugin command

Usage: gc hello [name]

Options:
  -h, --help    Show this help

Examples:
  gc hello
  gc hello World

EOF
    exit 0
fi

# Respect quiet mode
if [[ "$GC_QUIET" == "true" ]]; then
    exit 0
fi

# Main logic
name="${1:-Developer}"
print_header "Hello from Plugin!"
print_info "Hello, $name!"
print_success "This is an example plugin command."
echo ""
print_section "Plugin Info:"
echo "  GC_ROOT: $GC_ROOT"
echo "  GC_VERSION: ${GC_VERSION:-unknown}"
echo ""
