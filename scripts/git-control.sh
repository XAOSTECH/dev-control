#!/usr/bin/env bash
#
# Dev-Control Git Services Wrapper
# Unified interface for all git-related workflow tools
#
# Provides a single entry point for:
#   - Repository initialisation (templates, licenses)
#   - Repository creation (GitHub)
#   - Pull request creation
#   - History fixing and rewriting
#   - License auditing
#
# Usage:
#   ./git-control.sh                    # Interactive menu
#   ./git-control.sh init               # Initialize repo templates
#   ./git-control.sh repo               # Create GitHub repository
#   ./git-control.sh pr                 # Create pull request
#   ./git-control.sh fix [OPTIONS]      # Fix commit history
#   ./git-control.sh licenses [OPTIONS] # Audit licenses
#   ./git-control.sh help               # Show this help
#
# Aliases: dc-git, gc-git
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"
export DEV_CONTROL_DIR  # Used by sourced libraries

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
    print_error "Script not found: $script"
    return 1
}

# ============================================================================
# HELP DISPLAY
# ============================================================================

show_help() {
    cat << 'EOF'
Dev-Control Git Services - Unified git workflow automation

USAGE:
  git-control.sh [COMMAND] [OPTIONS]

COMMANDS:
  init, template      Initialise repository with templates (dc-init)
                      Copy standardised documentation, workflows, and licenses

  repo, create        Create GitHub repository (dc-repo)
                      Set up GitHub repo from current folder with topics

  pr                  Create pull request (dc-pr)
                      Interactive PR creation from current branch

  fix, history        Fix commit history (dc-fix)
                      Interactive commit rewriting, signing, date fixing

  licenses, lic       Audit repository licenses (dc-licenses)
                      Detect and manage licenses across submodules

  help                Show this help message

INTERACTIVE MODE:
  Run without arguments to use the interactive menu.

WORKFLOW EXAMPLE:
  1. Initialise templates:     git-control init
  2. Create GitHub repo:       git-control repo
  3. Make changes and commit
  4. Create pull request:      git-control pr

EXAMPLES:
  git-control.sh                         # Interactive menu
  git-control.sh init                    # Initialize templates
  git-control.sh init --batch -y         # Batch init multiple repos
  git-control.sh repo                    # Create repository
  git-control.sh pr                      # Create pull request
  git-control.sh fix --range HEAD=5      # Fix last 5 commits
  git-control.sh fix --sign --dry-run    # Preview signing commits
  git-control.sh licenses --deep         # Deep license scan
  git-control.sh licenses --apply MIT    # Apply MIT license

ALIASES (after running dc-aliases):
  dc-git         - This unified wrapper
  dc-init        - Template loading
  dc-repo        - Repository creation
  dc-pr          - Pull request creation
  dc-fix         - History fixing
  dc-licenses    - License auditing

For detailed help on each subcommand:
  git-control.sh init --help
  git-control.sh fix --help
  etc.

EOF
}

# ============================================================================
# MENU SYSTEM
# ============================================================================

display_menu() {
    print_header "Git Control"
    
    echo -e "${BOLD}Repository Setup${NC}"
    print_menu_item "1" "Initialise Templates (dc-init)   - Copy docs, workflows, licenses"
    print_menu_item "2" "Create Repository (dc-repo)      - Create GitHub repository"
    echo ""
    
    echo -e "${BOLD}Collaboration${NC}"
    print_menu_item "3" "Create Pull Request (dc-pr)      - Create PR from branch"
    echo ""
    
    echo -e "${BOLD}Maintenance${NC}"
    print_menu_item "4" "Fix History (dc-fix)             - Rewrite commit history"
    print_menu_item "5" "License Auditor (dc-licenses)    - Audit and manage licenses"
    echo ""
    
    print_menu_item "h" "Help"
    print_menu_item "0" "Exit / Back to main menu"
    echo ""
}

# ============================================================================
# SUBCOMMAND DISPATCH
# ============================================================================

run_subcommand() {
    local cmd="$1"
    shift
    
    case "$cmd" in
        1|init|template|templates)
            check_script_exists "template-loading.sh" && \
                bash "$SCRIPT_DIR/template-loading.sh" "$@"
            ;;
        2|repo|create)
            check_script_exists "create-repo.sh" && \
                bash "$SCRIPT_DIR/create-repo.sh" "$@"
            ;;
        3|pr|pull-request)
            check_script_exists "create-pr.sh" && \
                bash "$SCRIPT_DIR/create-pr.sh" "$@"
            ;;
        4|fix|history)
            check_script_exists "fix-history.sh" && \
                bash "$SCRIPT_DIR/fix-history.sh" "$@"
            ;;
        5|licenses|lic|license)
            check_script_exists "licenses.sh" && \
                bash "$SCRIPT_DIR/licenses.sh" "$@"
            ;;
        h|help|-h|--help)
            show_help
            ;;
        0|exit|q|quit|back)
            return 1  # Signal to exit/return
            ;;
        "")
            # Empty input in interactive mode - just redisplay menu
            return 0
            ;;
        *)
            print_error "Unknown command: $cmd"
            echo "Use 'help' or run with '-h' for available commands"
            return 2
            ;;
    esac
    
    return 0
}

# ============================================================================
# QUICK COMMANDS
# ============================================================================

# Show quick workflow tips after menu exit
show_quick_tips() {
    echo ""
    print_section "Quick Commands:"
    print_command_hint "Initialise repo" "dc-git init"
    print_command_hint "Create GitHub repo" "dc-git repo"
    print_command_hint "Create PR" "dc-git pr"
    print_command_hint "Fix history" "dc-git fix"
    print_command_hint "Audit licenses" "dc-git lic"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    # If arguments provided, dispatch directly
    if [[ $# -gt 0 ]]; then
        run_subcommand "$@"
        exit $?
    fi
    
    # Interactive mode
    while true; do
        display_menu
        read -rp "Select option: " choice
        echo ""
        
        if [[ "$choice" == "0" || "$choice" == "q" || "$choice" == "quit" ]]; then
            print_info "Returning to main menu..."
            show_quick_tips
            exit 0
        fi
        
        run_subcommand "$choice"
        local status=$?
        
        if [[ $status -eq 1 ]]; then
            # Exit requested
            show_quick_tips
            exit 0
        fi
        
        echo ""
        read -rp "Press Enter to continue..."
    done
}

main "$@"
