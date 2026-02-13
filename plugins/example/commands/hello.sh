#!/usr/bin/env bash
#
# Example Plugin Command
# Demonstrates how to create a plugin command
#
set -e

# Use DC_ROOT for shared libraries
if [[ -z "$DC_ROOT" ]]; then
    echo "Error: DC_ROOT not set. Run via 'gc hello' instead." >&2
    exit 1
fi

source "$DC_ROOT/scripts/lib/colours.sh"
source "$DC_ROOT/scripts/lib/print.sh"

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
if [[ "$DC_QUIET" == "true" ]]; then
    exit 0
fi

# Main logic
name="${1:-Developer}"
print_header "Hello from Plugin!"
print_info "Hello, $name!"
print_success "This is an example plugin command."
echo ""
print_section "Plugin Info:"
echo "  DC_ROOT: $DC_ROOT"
echo "  DC_VERSION: ${DC_VERSION:-unknown}"
echo ""
