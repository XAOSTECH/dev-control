#!/usr/bin/env bash
#
# Git-Control Main Wrapper
# Central entry point for all Git-Control tools
#
# Provides an interactive menu to access all git-control scripts:
#   - Alias Loading
#   - Template Loading
#   - Repository Creation
#   - Pull Request Creation
#   - Module Nesting
#   - History Fixing
#   - License Auditing
#   - MCP Setup
#   - Containerisation
#
# Usage:
#   ./git-control.sh              # Interactive menu
#   ./git-control.sh alias        # Run specific tool directly
#   ./git-control.sh help         # Show available commands
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"
export GIT_CONTROL_DIR  # Used by sourced libraries

# Source shared libraries
source "$SCRIPT_DIR/lib/colors.sh"
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
Git-Control - Comprehensive Git workflow automation toolkit

USAGE:
  git-control.sh [COMMAND] [OPTIONS]

COMMANDS:
  alias, aliases     Install bash aliases (gc-aliases)
  init, template     Initialize repo with templates (gc-init)
  repo, create       Create GitHub repository (gc-repo)
  pr                 Create pull request (gc-pr)
  modules, nest      Manage submodules (gc-modules)
  fix, history       Fix commit history (gc-fix)
  licenses, lic      Audit licenses (gc-licenses)
  mcp                Setup MCP servers (gc-mcp)
  container          Setup devcontainer (gc-container)
  help               Show this help message

INTERACTIVE MODE:
  Run without arguments to use the interactive menu.

EXAMPLES:
  ./git-control.sh                   # Interactive menu
  ./git-control.sh init              # Initialize templates
  ./git-control.sh repo              # Create repository
  ./git-control.sh pr                # Create pull request
  ./git-control.sh fix --range HEAD=5  # Fix last 5 commits
  ./git-control.sh licenses --deep   # Audit licenses recursively

ALIASES:
  After running 'gc-aliases', these shortcuts are available:
    gc          - Main git-control menu
    gc-init     - Template loading
    gc-repo     - Repository creation
    gc-pr       - Pull request creation
    gc-fix      - History fixing
    gc-modules  - Module nesting
    gc-aliases  - Alias loading
    gc-licenses - License auditing
    gc-mcp      - MCP setup

For detailed help on each tool, run the script directly:
  ./scripts/alias-loading.sh --help
  ./scripts/template-loading.sh --help
  etc.

EOF
}

# ============================================================================
# MENU SYSTEM
# ============================================================================

display_menu() {
    print_header "Git-Control"
    
    print_menu_item "1" "Alias Loading (gc-aliases)       - Install bash aliases"
    print_menu_item "2" "Template Loading (gc-init)       - Initialize repo templates"
    print_menu_item "3" "Repository Creator (gc-repo)     - Create GitHub repository"
    print_menu_item "4" "PR Creator (gc-pr)               - Create pull request"
    print_menu_item "5" "Module Nesting (gc-modules)      - Manage submodules"
    print_menu_item "6" "History Fixer (gc-fix)           - Fix commit history"
    print_menu_item "7" "License Auditor (gc-licenses)    - Audit licenses"
    print_menu_item "8" "MCP Setup (gc-mcp)               - Setup MCP servers"
    print_menu_item "9" "Containerise (gc-container)      - Setup devcontainer"
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
        2|init|template|templates)
            check_script_exists "template-loading.sh" && \
                bash "$SCRIPT_DIR/template-loading.sh" "$@"
            ;;
        3|repo|create)
            check_script_exists "create-repo.sh" && \
                bash "$SCRIPT_DIR/create-repo.sh" "$@"
            ;;
        4|pr)
            check_script_exists "create-pr.sh" && \
                bash "$SCRIPT_DIR/create-pr.sh" "$@"
            ;;
        5|modules|nest|nesting)
            check_script_exists "module-nesting.sh" && \
                bash "$SCRIPT_DIR/module-nesting.sh" "$@"
            ;;
        6|fix|history)
            check_script_exists "fix-history.sh" && \
                bash "$SCRIPT_DIR/fix-history.sh" "$@"
            ;;
        7|licenses|lic)
            check_script_exists "licenses.sh" && \
                bash "$SCRIPT_DIR/licenses.sh" "$@"
            ;;
        8|mcp)
            check_script_exists "mcp-setup.sh" && \
                bash "$SCRIPT_DIR/mcp-setup.sh" "$@"
            ;;
        9|container|containerise)
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
