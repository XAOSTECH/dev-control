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
# SPDX-FileCopyrightText: 2025-2026 xaoscience

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
# CLUSTER MODE - Setup: init + container + mcp
# ============================================================================

run_cluster_setup() {
    print_header "Dev-Control Cluster Setup"
    echo ""
    print_info "Setup fully fledged cluster: templates + container + MCP"
    echo ""
    
    # Step 1: Select container type
    echo -e "${BOLD}Step 1: Select container type${NC}"
    echo "  1) Custom base image (--bare)"
    echo "  2) Category-based (--img with built base)"
    echo "  3) Just templates & MCP (skip   container)"
    echo ""
    read -rp "Choice [1-3]: " container_choice
    
    case "$container_choice" in
        1)
            CLUSTER_MODE="bare"
            echo -e "${CYAN}→ Using custom base image${NC}"
            ;;
        2)
            CLUSTER_MODE="img"
            echo -e "${CYAN}→ Using category base image${NC}"
            echo ""
            echo -e "${BOLD}Step 2: Select category${NC}"
            echo "  1) game-dev    - Godot, Vulkan, SDL2, GLFW, CUDA"
            echo "  2) art         - Krita, GIMP, Inkscape, Blender"
            echo "  3) data-science - CUDA, FFmpeg, NVIDIA"
            echo "  4) streaming   - FFmpeg+NVENC, NGINX-RTMP, ONNX"
            echo "  5) web-dev     - Node.js, npm, Cloudflare Workers"
            echo "  6) dev-tools   - GCC, build-essential, compilers"
            echo ""
            read -rp "Choice [1-6]: " category_choice
            
            case "$category_choice" in
                1) CLUSTER_CATEGORY="--game-dev" ;;
                2) CLUSTER_CATEGORY="--art" ;;
                3) CLUSTER_CATEGORY="--data-science" ;;
                4) CLUSTER_CATEGORY="--streaming" ;;
                5) CLUSTER_CATEGORY="--web-dev" ;;
                6) CLUSTER_CATEGORY="--dev-tools" ;;
                *) print_error "Invalid choice"; exit 1 ;;
            esac
            echo -e "${CYAN}→ Using category: ${CLUSTER_CATEGORY}${NC}"
            ;;
        3)
            CLUSTER_MODE="templates-only"
            echo -e "${CYAN}→ Skipping container setup${NC}"
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
    
    echo ""
    print_step "Starting cluster setup..."
    echo ""
    
    # Step: Initialise templates
    print_step "1/3 Initialising templates..."
    check_script_exists "template-loading.sh" && \
        bash "$SCRIPT_DIR/template-loading.sh" -y --reuse-owner <<< "y" 2>/dev/null || true
    echo ""
    
    # Step: Setup container (unless templates-only)
    if [[ "$CLUSTER_MODE" != "templates-only" ]]; then
        print_step "2/3 Setting up container..."
        local containerise_args="--defaults"
        if [[ "$CLUSTER_MODE" == "bare" ]]; then
            containerise_args="--bare --defaults"
        elif [[ "$CLUSTER_MODE" == "img" ]]; then
            containerise_args="--img $CLUSTER_CATEGORY --defaults"
        fi
        check_script_exists "containerise.sh" && \
           bash "$SCRIPT_DIR/containerise.sh" $containerise_args 2>/dev/null || true
        echo ""
    else
        print_info "Skipped: container setup (templates-only mode)"
        echo ""
    fi
    
    # Step: Setup MCP
    print_step "3/3 Setting up MCP servers..."
    check_script_exists "mcp-setup.sh" && \
        bash "$SCRIPT_DIR/mcp-setup.sh" --config-only 2>/dev/null || true
    echo ""
    
    print_header_success "Cluster setup complete!"
    echo ""
    print_section "What's been set up:"
    print_list_item "✓ Templates (docs, workflows, licenses)"
    if [[ "$CLUSTER_MODE" != "templates-only" ]]; then
        print_list_item "✓ Devcontainer ($([ "$CLUSTER_MODE" = "bare" ] && echo "bare" || echo "with $CLUSTER_CATEGORY"))"
    fi
    print_list_item "✓ MCP servers (GitHub, Stack Overflow, Firecrawl)"
    echo ""
    print_info "Your project is ready for development!"
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
  cluster            Setup fully fledged cluster (init + container + mcp)
  container          Setup devcontainer (dc-container)
  help               Show this help message

INTERACTIVE MODE:
  Run without arguments to use the interactive menu.

EXAMPLES:
  ./dev-control.sh                      # Interactive menu
  ./dev-control.sh init                 # Initialise templates
  ./dev-control.sh repo                 # Create repository
  ./dev-control.sh cluster              # Init, Containerise, MCP-setup (also add to aliases as dc-cluster and nothing else)
  ./dev-control.sh pr                   # Create pull request
  ./dev-control.sh fix --range HEAD=5   # Fix last 5 commits
  ./dev-control.sh licenses --deep      # Audit licenses recursively
  ./dev-control.sh package --all        # Build all package types

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
    print_menu_item "l" "Cluster Setup (dc-cluster)       - Full project setup (templates+container+mcp)"
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
        l|L|cluster)
            run_cluster_setup
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
