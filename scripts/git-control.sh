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
#
# Usage:
#   ./git-control.sh              # Interactive menu
#   ./git-control.sh alias        # Run specific tool directly
#   ./git-control.sh help         # Show available commands
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

print_header() {
    echo -e "\n${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║${NC}              ${CYAN}Git-Control - Main Menu${NC}                      ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================================================
# SCRIPT AVAILABILITY CHECKS
# ============================================================================

check_script_exists() {
    local script="$1"
    if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
        print_error "Script not found: $script"
        exit 1
    fi
    
    if [[ ! -x "$SCRIPT_DIR/$script" ]]; then
        chmod +x "$SCRIPT_DIR/$script"
        print_info "Made script executable: $script"
    fi
}

# ============================================================================
# HELP DISPLAY
# ============================================================================

show_help() {
    cat << 'EOF'
Git-Control - Comprehensive Git workflow automation toolkit

USAGE:
  ./git-control.sh [COMMAND] [OPTIONS]

COMMANDS:
  alias                  Interactive alias installer with category selection
  template               Repository template initialisation tool
  repo, create           Interactive GitHub repository creator
  pr                     Interactive pull request creator from current branch
  modules                Automated .gitmodules generator for nested repos
  fix-history            Interactive commit history rewriting tool
  mcp                    GitHub MCP server setup for VS Code
  help                   Show this help message

INTERACTIVE MODE:
  If no command is specified, displays an interactive menu to choose tools.

EXAMPLES:
  ./git-control.sh                    # Show interactive menu
  ./git-control.sh alias              # Run alias installer directly
  ./git-control.sh repo               # Create new repository
  ./git-control.sh pr                 # Create pull request
  ./git-control.sh fix-history        # Fix commit history
  ./git-control.sh mcp                # Setup GitHub MCP
  ./git-control.sh help               # Show this help

ALIASES:
  You can create shell aliases by running:
    gc-aliases    - Re-run alias installer
    gc-init       - Template loading
    gc-create     - Repository creation
    gc-pr         - Pull request creation
    gc-modules    - Module nesting
    gc-fix        - History fixing
    gc-mcp        - GitHub MCP setup
    gc-control    - Show this menu

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
    echo -e "${BOLD}Select a tool:${NC}\n"
    echo -e "  ${CYAN}1)${NC}  ${BOLD}Alias Installer${NC}        - Create productive shell aliases"
    echo -e "  ${CYAN}2)${NC}  ${BOLD}Template Loader${NC}         - Initialise repos with templates"
    echo -e "  ${CYAN}3)${NC}  ${BOLD}Repository Creator${NC}      - Create GitHub repositories"
    echo -e "  ${CYAN}4)${NC}  ${BOLD}Pull Request Creator${NC}    - Create PRs from current branch"
    echo -e "  ${CYAN}5)${NC}  ${BOLD}Module Manager${NC}          - Manage git submodules"
    echo -e "  ${CYAN}6)${NC}  ${BOLD}History Fixer${NC}           - Rewrite commit history interactively"
    echo -e "  ${CYAN}7)${NC}  ${BOLD}GitHub MCP Setup${NC}        - Configure VS Code MCP server"
    echo -e "  ${CYAN}8)${NC}  ${BOLD}Help${NC}                    - Show help"
    echo -e "  ${CYAN}0)${NC}  ${BOLD}Exit${NC}                    - Quit"
    echo ""
}

run_tool() {
    local choice="$1"
    local script_name=""
    local script_path=""
    
    case "$choice" in
        1|alias)
            script_name="alias-loading.sh"
            ;;
        2|template|init)
            script_name="template-loading.sh"
            ;;
        3|repo|create)
            script_name="create-repo.sh"
            ;;
        4|pr)
            script_name="create-pr.sh"
            ;;
        5|modules)
            script_name="module-nesting.sh"
            ;;
        6|fix|fix-history)
            script_name="fix-history.sh"
            ;;
        7|mcp)
            script_name="mcp-setup.sh"
            ;;
        8|help|--help|-h)
            show_help
            return 0
            ;;
        0|exit|quit)
            print_info "Exiting..."
            exit 0
            ;;
        *)
            print_error "Invalid selection: $choice"
            return 1
            ;;
    esac
    
    if [[ -n "$script_name" ]]; then
        script_path="$SCRIPT_DIR/$script_name"
        
        if [[ ! -f "$script_path" ]]; then
            print_error "Script not found: $script_name"
            return 1
        fi
        
        if [[ ! -x "$script_path" ]]; then
            chmod +x "$script_path"
        fi
        
        print_info "Starting: ${CYAN}$script_name${NC}"
        echo ""
        
        # Run the script - pass through any additional arguments
        "$script_path" "$@"
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Handle command-line arguments
    if [[ $# -gt 0 ]]; then
        # Direct command mode
        run_tool "$@"
        exit $?
    fi
    
    # Interactive menu mode
    print_header
    print_info "Git-Control Toolkit"
    echo ""
    
    local continue_menu=true
    while [[ "$continue_menu" == "true" ]]; do
        display_menu
        read -rp "Choice [0]: " user_choice
        
        if [[ -z "$user_choice" ]] || [[ "$user_choice" == "0" ]]; then
            print_info "Exiting..."
            exit 0
        fi
        
        if run_tool "$user_choice"; then
            echo ""
            read -rp "Return to menu? [Y/n]: " return_menu
            if [[ "$return_menu" =~ ^[Nn] ]]; then
                continue_menu=false
            fi
            echo ""
        else
            echo ""
            read -rp "Try again? [Y/n]: " try_again
            if [[ ! "$try_again" =~ ^[Yy] ]]; then
                continue_menu=false
            fi
            echo ""
        fi
    done
}

main "$@"
