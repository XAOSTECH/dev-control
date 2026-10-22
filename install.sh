#!/usr/bin/env bash
#
# Dev-Control Installer
# Single-file installer for easy distribution
#
# Usage (fresh install via curl):
#   curl -sSL https://raw.githubusercontent.com/xaoscience/dev-control/Main/install.sh | bash
#   curl -sSL ... | bash -s -- --prefix=/custom/path
#
# Usage (from an already-unpacked or cloned dev-control folder):
#   ./install.sh             # installs from current folder to /opt/dev-control
#   ./install.sh --upgrade   # refresh an existing /opt/dev-control install
#   ./install.sh --uninstall
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

set -e

# Configuration
DC_REPO="xaoscience/dev-control"
DC_BRANCH="main"
DEFAULT_PREFIX="/opt/dev-control"
DEFAULT_BIN="/usr/local/bin"

# Detect whether this script lives inside an unpacked dev-control folder
# (i.e. scripts/ and dc exist next to install.sh — tarball or git clone).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || pwd)"
if [[ -f "$SCRIPT_DIR/dc" && -d "$SCRIPT_DIR/scripts" ]]; then
    DC_SOURCE_DIR="$SCRIPT_DIR"
else
    DC_SOURCE_DIR=""
fi

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
NO_CLEANUP_PROMPT=false

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

show_help() {
    cat << EOF
Dev-Control Installer

USAGE:
  # Fresh install
  curl -sSL https://raw.githubusercontent.com/$DC_REPO/$DC_BRANCH/install.sh | bash

  # From an unpacked tarball or cloned folder
  ./install.sh [OPTIONS]

OPTIONS:
  --prefix=PATH     Installation directory (default: $DEFAULT_PREFIX)
  --bin=PATH        Binary directory for 'dc' symlink (default: $DEFAULT_BIN)
  --uninstall       Remove Dev-Control
  --upgrade         Update existing installation
  --no-aliases      Skip bash aliases installation
  --no-cleanup      Skip post-install source cleanup prompt
  --quiet           Minimal output
  -h, --help        Show this help

EXAMPLES:
  # Install from release tarball
  tar xzf dev-control-*.tar.gz && cd dev-control-* && sudo ./install.sh

  # Install to custom location
  ./install.sh --prefix=/home/user/.local/share/dev-control --bin=/home/user/.local/bin

  # Update existing installation
  sudo ./install.sh --upgrade

  # Uninstall
  sudo ./install.sh --uninstall

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prefix=*) PREFIX="${1#*=}"; shift ;;
            --bin=*)    BIN_DIR="${1#*=}"; shift ;;
            --uninstall)    UNINSTALL=true; shift ;;
            --upgrade)      UPGRADE=true; shift ;;
            --no-aliases)   NO_ALIASES=true; shift ;;
            --no-cleanup)   NO_CLEANUP_PROMPT=true; shift ;;
            --quiet|-q)     QUIET=true; shift ;;
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

    if [[ -n "$DC_SOURCE_DIR" ]]; then
        # ── Unpacked-folder mode: copy from current directory ─────────────────
        print_info "Source: $DC_SOURCE_DIR (local copy)"
        if [[ -d "$PREFIX" && "$UPGRADE" != "true" && "$(realpath "$DC_SOURCE_DIR")" != "$(realpath "$PREFIX")" ]]; then
            print_error "$PREFIX already exists — use --upgrade to overwrite"
            exit 1
        fi
        if [[ "$(realpath "$DC_SOURCE_DIR")" != "$(realpath "$PREFIX")" ]]; then
            mkdir -p "$(dirname "$PREFIX")"
            # rsync preferred (content-aware, skips unchanged files); fall back to cp
            if command -v rsync &>/dev/null; then
                rsync -a --delete "$DC_SOURCE_DIR/" "$PREFIX/"
            else
                rm -rf "$PREFIX"
                cp -r "$DC_SOURCE_DIR" "$PREFIX"
            fi
        fi
    else
        # ── Remote mode: clone from GitHub ────────────────────────────────────
        mkdir -p "$PREFIX"
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
    fi

    # Make scripts executable
    print_info "Setting permissions..."
    chmod +x "$PREFIX/dc"
    chmod +x "$PREFIX/scripts/"*.sh
    chmod +x "$PREFIX/commands/"*.sh 2>/dev/null || true

    # Create symlink in BIN_DIR
    mkdir -p "$BIN_DIR"
    print_info "Creating symlink: $BIN_DIR/dc -> $PREFIX/dc"
    ln -sf "$PREFIX/dc" "$BIN_DIR/dc"
    
    # Create config directory
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/dev-control"
    mkdir -p "$config_dir"
    
    # Suppress "Emulate Docker CLI using podman" advisory (host-level).
    local _nodocker_sys=/etc/containers/nodocker
    local _nodocker_usr="${XDG_CONFIG_HOME:-$HOME/.config}/containers/nodocker"
    if [[ ! -f "$_nodocker_sys" && ! -f "$_nodocker_usr" ]]; then
        if sudo -n true 2>/dev/null; then
            sudo mkdir -p /etc/containers && sudo touch "$_nodocker_sys" && \
                print_info "Created /etc/containers/nodocker (system-wide)" || true
        else
            mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/containers"
            touch "$_nodocker_usr"
            print_info "Created $_nodocker_usr (user-level)"
        fi
    fi
    
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

    # ── Offer to clean up the unpacked source ────────────────────────────────
    if [[ -n "$DC_SOURCE_DIR" && "$NO_CLEANUP_PROMPT" != "true" && "$QUIET" != "true" ]] && \
       [[ "$(realpath "$DC_SOURCE_DIR")" != "$(realpath "$PREFIX")" ]]; then
        echo ""
        echo -e "${BOLD}Source folder:${NC} $DC_SOURCE_DIR"
        read -rp "Remove the source folder now that it is installed? [y/N]: " _rm_src
        if [[ "${_rm_src:-n}" =~ ^[Yy] ]]; then
            rm -rf "$DC_SOURCE_DIR"
            print_info "Removed: $DC_SOURCE_DIR"
            # If a tarball sits one level above with a matching name, offer to remove it too
            local _parent; _parent="$(dirname "$DC_SOURCE_DIR")"
            local _slug; _slug="$(basename "$DC_SOURCE_DIR")"
            local _tarball="${_parent}/${_slug}.tar.gz"
            if [[ -f "$_tarball" ]]; then
                read -rp "Also remove ${_tarball}? [y/N]: " _rm_tar
                [[ "${_rm_tar:-n}" =~ ^[Yy] ]] && rm -f "$_tarball" && print_info "Removed: $_tarball"
            fi
        fi
    fi
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
alias dc-licences='$PREFIX/dc licences'
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
    echo "  dc licences   - Audit licences"
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
