#!/usr/bin/env bash
#
# Git-Control Installer
# Single-file installer for easy distribution
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/xaoscience/git-control/Main/install.sh | bash
#   curl -sSL ... | bash -s -- --prefix=/custom/path
#   curl -sSL ... | bash -s -- --uninstall
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

set -e

# Configuration
GC_REPO="xaoscience/git-control"
GC_BRANCH="Main"
DEFAULT_PREFIX="$HOME/.local/share/git-control"
DEFAULT_BIN="$HOME/.local/bin"

# Colors
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
Git-Control Installer

USAGE:
  curl -sSL https://raw.githubusercontent.com/$GC_REPO/$GC_BRANCH/install.sh | bash
  ./install.sh [OPTIONS]

OPTIONS:
  --prefix=PATH     Installation directory (default: $DEFAULT_PREFIX)
  --bin=PATH        Binary directory for 'gc' symlink (default: $DEFAULT_BIN)
  --uninstall       Remove git-control
  --upgrade         Update existing installation
  --no-aliases      Skip bash aliases installation
  --quiet           Minimal output
  -h, --help        Show this help

EXAMPLES:
  # Install to default location
  curl -sSL https://raw.githubusercontent.com/$GC_REPO/$GC_BRANCH/install.sh | bash

  # Install to custom location
  ./install.sh --prefix=/opt/git-control --bin=/usr/local/bin

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

install_git_control() {
    print_info "Installing git-control to $PREFIX"
    
    # Create directories
    mkdir -p "$PREFIX"
    mkdir -p "$BIN_DIR"
    
    # Clone repository
    if [[ -d "$PREFIX/.git" ]]; then
        if [[ "$UPGRADE" == "true" ]]; then
            print_info "Updating existing installation..."
            git -C "$PREFIX" fetch origin
            git -C "$PREFIX" reset --hard "origin/$GC_BRANCH"
        else
            print_error "git-control already installed at $PREFIX"
            print_info "Use --upgrade to update, or --uninstall first"
            exit 1
        fi
    else
        print_info "Cloning repository..."
        git clone --depth 1 -b "$GC_BRANCH" "https://github.com/$GC_REPO.git" "$PREFIX"
    fi
    
    # Make scripts executable
    print_info "Setting permissions..."
    chmod +x "$PREFIX/gc"
    chmod +x "$PREFIX/scripts/"*.sh
    chmod +x "$PREFIX/commands/"*.sh 2>/dev/null || true
    
    # Create symlink
    print_info "Creating symlink: $BIN_DIR/gc -> $PREFIX/gc"
    ln -sf "$PREFIX/gc" "$BIN_DIR/gc"
    
    # Create config directory
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/git-control"
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
    
    print_success "git-control installed successfully!"
}

install_aliases() {
    print_info "Installing bash aliases..."
    
    local bash_aliases="$HOME/.bash_aliases"
    local bashrc="$HOME/.bashrc"
    local marker="# git-control aliases"
    
    # Check if already installed
    if grep -q "$marker" "$bash_aliases" 2>/dev/null; then
        print_info "Aliases already installed, updating..."
        # Remove old aliases
        sed -i "/$marker/,/# end git-control/d" "$bash_aliases"
    fi
    
    # Append aliases
    cat >> "$bash_aliases" << EOF
$marker
alias gc='$PREFIX/gc'
alias gc-init='$PREFIX/gc init'
alias gc-repo='$PREFIX/gc repo'
alias gc-pr='$PREFIX/gc pr'
alias gc-fix='$PREFIX/gc fix'
alias gc-modules='$PREFIX/gc modules'
alias gc-licenses='$PREFIX/gc licenses'
alias gc-mcp='$PREFIX/gc mcp'
alias gc-aliases='$PREFIX/gc aliases'
# end git-control
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

uninstall_git_control() {
    print_info "Uninstalling git-control..."
    
    # Remove symlink
    if [[ -L "$BIN_DIR/gc" ]]; then
        rm "$BIN_DIR/gc"
        print_info "Removed symlink: $BIN_DIR/gc"
    fi
    
    # Remove installation
    if [[ -d "$PREFIX" ]]; then
        rm -rf "$PREFIX"
        print_info "Removed: $PREFIX"
    fi
    
    # Remove aliases
    local bash_aliases="$HOME/.bash_aliases"
    if grep -q "# git-control aliases" "$bash_aliases" 2>/dev/null; then
        sed -i '/# git-control aliases/,/# end git-control/d' "$bash_aliases"
        print_info "Removed aliases from .bash_aliases"
    fi
    
    print_success "git-control uninstalled"
    print_info "Note: Configuration in ~/.config/git-control was preserved"
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
    echo "  2. Run: gc --help"
    echo ""
    echo -e "${BOLD}Available Commands:${NC}"
    echo "  gc init       - Initialize repo with templates"
    echo "  gc repo       - Create GitHub repository"
    echo "  gc pr         - Create pull request"
    echo "  gc fix        - Fix commit history"
    echo "  gc modules    - Manage submodules"
    echo "  gc licenses   - Audit licenses"
    echo "  gc mcp        - Configure MCP servers"
    echo "  gc config     - Manage configuration"
    echo "  gc status     - Show status"
    echo ""
    echo -e "${BOLD}Configuration:${NC}"
    echo "  Global:  ~/.config/git-control/config.yaml"
    echo "  Project: .gc-init.yaml (in repo root)"
    echo ""
    echo -e "${BOLD}More Info:${NC}"
    echo "  https://github.com/$GC_REPO"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    parse_args "$@"
    
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║         Git-Control Installer         ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo -e "${NC}"
    
    if [[ "$UNINSTALL" == "true" ]]; then
        uninstall_git_control
        exit 0
    fi
    
    check_prerequisites
    install_git_control
    
    if [[ "$QUIET" != "true" ]]; then
        show_post_install
    fi
}

main "$@"
