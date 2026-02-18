#!/usr/bin/env bash
#
# Dev-Control Installer
# Single-file installer for easy distribution
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/xaoscience/dev-control/Main/install.sh | bash
#   curl -sSL ... | bash -s -- --prefix=/custom/path
#   curl -sSL ... | bash -s -- --uninstall
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

set -e

# Configuration
DC_REPO="xaoscience/dev-control"
DC_BRANCH="Main"
DEFAULT_PREFIX="$HOME/.local/share/dev-control"
DEFAULT_BIN="$HOME/.local/bin"

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Options
PREFIX="$DEFAULT_PREFIX"
BIN_DIR="$DEFAULT_BIN"
UNINSTALL=false
UPGRADE=false
NO_ALIASES=false
QUIET=false

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

show_help() {
    cat << EOF
Dev-Control Installer

USAGE:
  curl -sSL https://raw.githubusercontent.com/$DC_REPO/$DC_BRANCH/install.sh | bash
  ./install.sh [OPTIONS]

OPTIONS:
  --prefix=PATH     Installation directory (default: $DEFAULT_PREFIX)
  --bin=PATH        Binary directory for 'dc' symlink (default: $DEFAULT_BIN)
  --uninstall       Remove Dev-Control
  --upgrade         Update existing installation
  --no-aliases      Skip bash aliases installation
  --quiet           Minimal output
  -h, --help        Show this help

EXAMPLES:
  # Install to default location
  curl -sSL https://raw.githubusercontent.com/$DC_REPO/$DC_BRANCH/install.sh | bash

  # Install to custom location
  ./install.sh --prefix=/opt/dev-control --bin=/usr/local/bin

  # Update existing installation
  ./install.sh --upgrade

  # Uninstall
  ./install.sh --uninstall

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prefix=*) PREFIX="${1#*=}"; shift ;;
            --bin=*) BIN_DIR="${1#*=}"; shift ;;
            --uninstall) UNINSTALL=true; shift ;;
            --upgrade) UPGRADE=true; shift ;;
            --no-aliases) NO_ALIASES=true; shift ;;
            --quiet|-q) QUIET=true; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) print_error "Unknown option: $1"; exit 1 ;;
        esac
    done
}

# ============================================================================
# PREREQUISITES
# ============================================================================

check_prerequisites() {
    local missing=()
    
    command -v git &>/dev/null || missing+=("git")
    command -v curl &>/dev/null || missing+=("curl")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing required tools: ${missing[*]}"
        echo "Please install them first:"
        echo "  sudo apt install ${missing[*]}"
        exit 1
    fi
    
    # Optional tools
    if ! command -v gh &>/dev/null; then
        print_warning "GitHub CLI (gh) not found - some features will be limited"
        echo "  Install with: sudo apt install gh && gh auth login"
    fi
}

# ============================================================================
# INSTALLATION
# ============================================================================

install_dev_control() {
    print_info "Installing Dev-Control to $PREFIX"
    
    # Create directories
    mkdir -p "$PREFIX"
    mkdir -p "$BIN_DIR"
    
    # Clone repository
    if [[ -d "$PREFIX/.git" ]]; then
        if [[ "$UPGRADE" == "true" ]]; then
            print_info "Updating existing installation..."
            git -C "$PREFIX" fetch origin
            git -C "$PREFIX" reset --hard "origin/$DC_BRANCH"
        else
            print_error "Dev-Control already installed at $PREFIX"
            print_info "Use --upgrade to update, or --uninstall first"
            exit 1
        fi
    else
        print_info "Cloning repository..."
        git clone --depth 1 -b "$DC_BRANCH" "https://github.com/$DC_REPO.git" "$PREFIX"
    fi
    
    # Make scripts executable
    print_info "Setting permissions..."
    chmod +x "$PREFIX/dc"
    chmod +x "$PREFIX/scripts/"*.sh
    chmod +x "$PREFIX/commands/"*.sh 2>/dev/null || true
    
    # Create symlink
    print_info "Creating symlink: $BIN_DIR/dc -> $PREFIX/dc"
    ln -sf "$PREFIX/dc" "$BIN_DIR/dc"
    
    # Create config directory
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/dev-control"
    mkdir -p "$config_dir"
    
    # Copy example config if doesn't exist
    if [[ ! -f "$config_dir/config.yaml" ]]; then
        if [[ -f "$PREFIX/config/example-global.config.yaml" ]]; then
            cp "$PREFIX/config/example-global.config.yaml" "$config_dir/config.yaml"
            print_info "Created default config: $config_dir/config.yaml"
        fi
    fi
    
    # Install aliases if requested
    if [[ "$NO_ALIASES" != "true" ]]; then
        install_aliases
    fi
    
    print_success "Dev-Control installed successfully!"
}

install_aliases() {
    print_info "Installing bash aliases..."
    
    local bash_aliases="$HOME/.bash_aliases"
    local bashrc="$HOME/.bashrc"
    local marker="# Dev-Control aliases"
    
    # Check if already installed
    if grep -q "$marker" "$bash_aliases" 2>/dev/null; then
        print_info "Aliases already installed, updating..."
        # Remove old aliases
        sed -i "/$marker/,/# end dev-control/d" "$bash_aliases"
    fi
    
    # Append aliases
    cat >> "$bash_aliases" << EOF
$marker
alias dc='$PREFIX/dc'
alias dc-init='$PREFIX/dc init'
alias dc-repo='$PREFIX/dc repo'
alias dc-pr='$PREFIX/dc pr'
alias dc-fix='$PREFIX/dc fix'
alias dc-modules='$PREFIX/dc modules'
alias dc-licenses='$PREFIX/dc licenses'
alias dc-mcp='$PREFIX/dc mcp'
alias dc-aliases='$PREFIX/dc aliases'
# end dev-control
EOF
    
    # Ensure .bashrc sources .bash_aliases
    if ! grep -q "\.bash_aliases" "$bashrc" 2>/dev/null; then
        cat >> "$bashrc" << 'EOF'

# Load aliases
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi
EOF
        print_info "Updated .bashrc to load .bash_aliases"
    fi
    
    print_success "Aliases installed"
}

# ============================================================================
# UNINSTALLATION
# ============================================================================

uninstall_dev_control() {
    print_info "Uninstalling Dev-Control..."
    
    # Remove symlink
    if [[ -L "$BIN_DIR/dc" ]]; then
        rm "$BIN_DIR/dc"
        print_info "Removed symlink: $BIN_DIR/dc"
    fi
    
    # Remove installation
    if [[ -d "$PREFIX" ]]; then
        rm -rf "$PREFIX"
        print_info "Removed: $PREFIX"
    fi
    
    # Remove aliases
    local bash_aliases="$HOME/.bash_aliases"
    if grep -q "# dev-control aliases" "$bash_aliases" 2>/dev/null; then
        sed -i '/# dev-control aliases/,/# end dev-control/d' "$bash_aliases"
        print_info "Removed aliases from .bash_aliases"
    fi
    
    print_success "Dev-Control uninstalled"
    print_info "Note: Configuration in ~/.config/dev-control was preserved"
}

# ============================================================================
# POST-INSTALL
# ============================================================================

show_post_install() {
    echo ""
    echo -e "${BOLD}${GREEN}✓ Installation Complete!${NC}"
    echo ""
    echo -e "${BOLD}Quick Start:${NC}"
    echo "  1. Reload your shell: source ~/.bashrc"
    echo "  2. Run: dc --help"
    echo ""
    echo -e "${BOLD}Available Commands:${NC}"
    echo "  dc init       - Initialise repo with templates"
    echo "  dc repo       - Create GitHub repository"
    echo "  dc pr         - Create pull request"
    echo "  dc fix        - Fix commit history"
    echo "  dc modules    - Manage submodules"
    echo "  dc licenses   - Audit licenses"
    echo "  dc mcp        - Configure MCP servers"
    echo "  dc config     - Manage configuration"
    echo "  dc status     - Show status"
    echo ""
    echo -e "${BOLD}Configuration:${NC}"
    echo "  Global:  ~/.config/dev-control/config.yaml"
    echo "  Project: .dc-init.yaml (in repo root)"
    echo ""
    echo -e "${BOLD}More Info:${NC}"
    echo "  https://github.com/$DC_REPO"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    parse_args "$@"
    
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║         Dev-Control Installer         ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo -e "${NC}"
    
    if [[ "$UNINSTALL" == "true" ]]; then
        uninstall_dev_control
        exit 0
    fi
    
    check_prerequisites
    install_dev_control
    
    if [[ "$QUIET" != "true" ]]; then
        show_post_install
    fi
}

main "$@"
