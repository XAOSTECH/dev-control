#!/usr/bin/env bash
#
# Dev-Control Main Wrapper
# Central entry point for all Dev-Control tools
#
# Provides an interactive menu to access all Dev-Control scripts:
#   - Alias Loading
#   - Template Loading
#   - Repository Creation
#   - Pull Request Creation
#   - Module Nesting
#   - History Fixing
#   - License Auditing
#   - MCP Setup
#   - Containerisation
#   - Packaging
#
# Usage:
#   ./dev-control.sh              # Interactive menu
#   ./dev-control.sh alias        # Run specific tool directly
#   ./dev-control.sh help         # Show available commands
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"
export DEV_CONTROL_DIR  # Used by sourced libraries

# Source shared libraries
source "$SCRIPT_DIR/lib/colours.sh"
source "$SCRIPT_DIR/lib/print.sh"

# ============================================================================
# SCRIPT AVAILABILITY CHECKS
# ============================================================================

check_script_exists() {
    local script="$1"
    local path="$SCRIPT_DIR/$script"
    
    if [[ -f "$path" && -x "$path" ]]; then
        return 0
    elif [[ -f "$path" ]]; then
        chmod +x "$path"
        return 0
    fi
    return 1
}

# ============================================================================
# HELP DISPLAY
# ============================================================================

show_help() {
    cat << 'EOF'
Dev-Control - Comprehensive Git workflow automation toolkit

USAGE:
  dev-control.sh [COMMAND] [OPTIONS]

COMMANDS:
  alias, aliases     Install bash aliases (dc-aliases)
  git                Git services menu (dc-git) - unified git workflows
  init, template     Initialise repo with templates (dc-init)
  repo, create       Create GitHub repository (dc-repo)
  pr                 Create pull request (dc-pr)
  modules, nest      Manage submodules (dc-modules)
  fix, history       Fix commit history (dc-fix)
  licenses, lic      Audit licenses (dc-licenses)
  package, pkg       Build multi-platform packages (dc-package)
  mcp                Setup MCP servers (dc-mcp)
  container          Setup devcontainer (dc-container)
  help               Show this help message

INTERACTIVE MODE:
  Run without arguments to use the interactive menu.

EXAMPLES:
  ./dev-control.sh                   # Interactive menu
  ./dev-control.sh init              # Initialize templates
  ./dev-control.sh repo              # Create repository
  ./dev-control.sh pr                # Create pull request
  ./dev-control.sh fix --range HEAD=5  # Fix last 5 commits
  ./dev-control.sh licenses --deep   # Audit licenses recursively
  ./dev-control.sh package --all     # Build all package types

ALIASES:
  After running 'dc-aliases', these shortcuts are available:
    dc          - Main Dev-Control menu
    dc-git      - Git services submenu
    dc-init     - Template loading
    dc-repo     - Repository creation
    dc-pr       - Pull request creation
    dc-fix      - History fixing
    dc-modules  - Module nesting
    dc-aliases  - Alias loading
    dc-licenses - License auditing
    dc-package  - Package builder
    dc-mcp      - MCP setup

For detailed help on each tool, run the script directly:
  ./scripts/alias-loading.sh --help
  ./scripts/template-loading.sh --help
  ./scripts/packaging.sh --help
  etc.

EOF
}

# ============================================================================
# MENU SYSTEM
# ============================================================================

display_menu() {
    print_header "Dev-Control"
    
    echo -e "${BOLD}Setup & Configuration${NC}"
    print_menu_item "1" "Alias Loading (dc-aliases)       - Install bash aliases"
    print_menu_item "2" "Git Services (dc-git)            - Unified git workflow tools"
    echo ""
    
    echo -e "${BOLD}Repository Management${NC}"
    print_menu_item "3" "Template Loading (dc-init)       - Initialise repo templates"
    print_menu_item "4" "Repository Creator (dc-repo)     - Create GitHub repository"
    print_menu_item "5" "PR Creator (dc-pr)               - Create pull request"
    print_menu_item "6" "Module Nesting (dc-modules)      - Manage submodules"
    echo ""
    
    echo -e "${BOLD}Maintenance & Tools${NC}"
    print_menu_item "7" "History Fixer (dc-fix)           - Fix commit history"
    print_menu_item "8" "License Auditor (dc-licenses)    - Audit licenses"
    print_menu_item "9" "Package Builder (dc-package)     - Build release packages"
    echo ""
    
    echo -e "${BOLD}Environment${NC}"
    print_menu_item "m" "MCP Setup (dc-mcp)               - Setup MCP servers"
    print_menu_item "c" "Containerise (dc-container)      - Setup devcontainer"
    print_menu_item "0" "Exit"
    echo ""
}

run_tool() {
    local choice="$1"
    shift
    
    case "$choice" in
        1|alias|aliases)
            check_script_exists "alias-loading.sh" && \
                bash "$SCRIPT_DIR/alias-loading.sh" "$@"
            ;;
        2|git|git-control)
            check_script_exists "git-control.sh" && \
                bash "$SCRIPT_DIR/git-control.sh" "$@"
            ;;
        3|init|template|templates)
            check_script_exists "template-loading.sh" && \
                bash "$SCRIPT_DIR/template-loading.sh" "$@"
            ;;
        4|repo|create)
            check_script_exists "create-repo.sh" && \
                bash "$SCRIPT_DIR/create-repo.sh" "$@"
            ;;
        5|pr)
            check_script_exists "create-pr.sh" && \
                bash "$SCRIPT_DIR/create-pr.sh" "$@"
            ;;
        6|modules|nest|nesting)
            check_script_exists "module-nesting.sh" && \
                bash "$SCRIPT_DIR/module-nesting.sh" "$@"
            ;;
        7|fix|history)
            check_script_exists "fix-history.sh" && \
                bash "$SCRIPT_DIR/fix-history.sh" "$@"
            ;;
        8|licenses|lic)
            check_script_exists "licenses.sh" && \
                bash "$SCRIPT_DIR/licenses.sh" "$@"
            ;;
        9|package|pkg)
            check_script_exists "packaging.sh" && \
                bash "$SCRIPT_DIR/packaging.sh" "$@"
            ;;
        m|M|mcp)
            check_script_exists "mcp-setup.sh" && \
                bash "$SCRIPT_DIR/mcp-setup.sh" "$@"
            ;;
        c|C|container|containerise)
            check_script_exists "containerise.sh" && \
                bash "$SCRIPT_DIR/containerise.sh" "$@"
            ;;
        0|exit|q|quit)
            print_info "Goodbye!"
            exit 0
            ;;
        help|-h|--help)
            show_help
            ;;
        *)
            print_error "Unknown command: $choice"
            echo "Use 'help' for available commands"
            return 1
            ;;
    esac
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    # If arguments provided, run directly
    if [[ $# -gt 0 ]]; then
        run_tool "$@"
        exit $?
    fi
    
    # Interactive mode
    while true; do
        display_menu
        read -rp "Select option: " choice
        echo ""
        
        if [[ "$choice" == "0" ]]; then
            print_info "Goodbye!"
            exit 0
        fi
        
        run_tool "$choice"
        echo ""
        read -rp "Press Enter to continue..."
    done
}

main "$@"
