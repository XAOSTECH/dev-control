#!/usr/bin/env bash
#
# Dev-Control Packaging Automation
# Build multi-platform packages for any bash-based CLI tool
#
# Supports generating:
#   - Tarballs (release archives)
#   - Homebrew formulas
#   - Snap packages
#   - Debian packages (.deb)
#   - Nix flakes
#   - Docker images (for web/ttyd interface)
#
# Usage:
#   ./packaging.sh                           # Interactive mode
#   ./packaging.sh --all                     # Build all package types
#   ./packaging.sh --tarball                 # Build tarball only
#   ./packaging.sh --homebrew                # Generate Homebrew formula
#   ./packaging.sh --snap                    # Build snap package
#   ./packaging.sh --debian                  # Build Debian package
#   ./packaging.sh --docker                  # Build Docker image
#   ./packaging.sh --init                    # Initialize packaging config
#
# Aliases: dc-package, dc-pkg
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"
export DEV_CONTROL_DIR

# Source shared libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/print.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

# Default config file location
PKG_CONFIG_FILE=".dc-package.yaml"
PKG_OUTPUT_DIR="./dist"

# Package info (loaded from config or detected)
PKG_NAME=""
PKG_VERSION=""
PKG_DESCRIPTION=""
PKG_HOMEPAGE=""
PKG_LICENSE=""
PKG_MAINTAINER=""
PKG_DEPENDENCIES=""
PKG_ENTRY_POINT=""
PKG_INCLUDE_DIRS=""
PKG_INCLUDE_FILES=""

# CLI options
BUILD_TARBALL=false
BUILD_HOMEBREW=false
BUILD_SNAP=false
BUILD_DEBIAN=false
BUILD_NIX=false
BUILD_DOCKER=false
BUILD_ALL=false
INIT_CONFIG=false
DRY_RUN=false
VERBOSE=false

# ============================================================================
# CLI ARGUMENT PARSING
# ============================================================================

show_help() {
    cat << 'EOF'
Dev-Control Packaging Automation - Build multi-platform packages

USAGE:
  packaging.sh [OPTIONS]

OPTIONS:
  --init                Initialize packaging configuration (.dc-package.yaml)
  --all                 Build all package types
  --tarball             Build release tarball
  --homebrew            Generate Homebrew formula
  --snap                Build Snap package
  --debian              Build Debian package (.deb)
  --nix                 Generate Nix flake
  --docker              Build Docker image with ttyd web interface
  -o, --output DIR      Output directory (default: ./dist)
  -c, --config FILE     Config file path (default: .dc-package.yaml)
  -v, --version VER     Override version
  --dry-run             Show what would be built without building
  --verbose             Enable verbose output
  -h, --help            Show this help message

EXAMPLES:
  packaging.sh --init                    # Create config file
  packaging.sh --tarball --homebrew      # Build tarball + Homebrew
  packaging.sh --all                     # Build everything
  packaging.sh --snap --verbose          # Build snap with details
  packaging.sh --docker                  # Build Docker image

CONFIG FILE (.dc-package.yaml):
  name: my-tool
  version: 1.0.0
  description: "My awesome CLI tool"
  homepage: "https://github.com/user/repo"
  license: MIT
  maintainer: "Name <email@example.com>"
  entry_point: ./main.sh
  include:
    - scripts/
    - lib/
    - README.md
  dependencies:
    - git
    - jq
    - gh

ALIASES:
  dc-package, dc-pkg

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --init)
                INIT_CONFIG=true
                shift
                ;;
            --all)
                BUILD_ALL=true
                shift
                ;;
            --tarball)
                BUILD_TARBALL=true
                shift
                ;;
            --homebrew)
                BUILD_HOMEBREW=true
                shift
                ;;
            --snap)
                BUILD_SNAP=true
                shift
                ;;
            --debian)
                BUILD_DEBIAN=true
                shift
                ;;
            --nix)
                BUILD_NIX=true
                shift
                ;;
            --docker)
                BUILD_DOCKER=true
                shift
                ;;
            -o|--output)
                PKG_OUTPUT_DIR="$2"
                shift 2
                ;;
            -c|--config)
                PKG_CONFIG_FILE="$2"
                shift 2
                ;;
            -v|--version)
                PKG_VERSION="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # If --all, enable everything
    if [[ "$BUILD_ALL" == "true" ]]; then
        BUILD_TARBALL=true
        BUILD_HOMEBREW=true
        BUILD_SNAP=true
        BUILD_DEBIAN=true
        BUILD_NIX=true
        BUILD_DOCKER=true
    fi
}

# ============================================================================
# CONFIG LOADING
# ============================================================================

detect_package_info() {
    # Try to detect from various sources
    
    # Package name from folder
    [[ -z "$PKG_NAME" ]] && PKG_NAME=$(basename "$(pwd)")
    
    # Version from git tag or CHANGELOG
    if [[ -z "$PKG_VERSION" ]]; then
        PKG_VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.1.0")
    fi
    
    # Homepage from git remote
    if [[ -z "$PKG_HOMEPAGE" ]]; then
        local remote_url
        remote_url=$(git config --get remote.origin.url 2>/dev/null || echo "")
        if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
            PKG_HOMEPAGE="https://github.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        fi
    fi
    
    # Description from README or git config
    if [[ -z "$PKG_DESCRIPTION" ]]; then
        if command -v gh &>/dev/null && [[ -n "$PKG_HOMEPAGE" ]]; then
            local repo_path
            repo_path=$(echo "$PKG_HOMEPAGE" | sed 's|https://github.com/||')
            PKG_DESCRIPTION=$(gh repo view "$repo_path" --json description --jq '.description' 2>/dev/null || echo "")
        fi
        [[ -z "$PKG_DESCRIPTION" ]] && PKG_DESCRIPTION="A CLI tool"
    fi
    
    # License from LICENSE file or git config
    if [[ -z "$PKG_LICENSE" ]]; then
        PKG_LICENSE=$(git config --local dc-init.license-type 2>/dev/null || echo "MIT")
    fi
    
    # Maintainer from git
    if [[ -z "$PKG_MAINTAINER" ]]; then
        local name email
        name=$(git config --get user.name 2>/dev/null || echo "Maintainer")
        email=$(git config --get user.email 2>/dev/null || echo "maintainer@example.com")
        PKG_MAINTAINER="$name <$email>"
    fi
}

load_config() {
    if [[ -f "$PKG_CONFIG_FILE" ]]; then
        print_info "Loading config from $PKG_CONFIG_FILE"
        
        # Parse YAML config (simple parser)
        while IFS=':' read -r key value; do
            key=$(echo "$key" | tr -d ' ')
            value=$(echo "$value" | sed 's/^[ ]*//;s/[ ]*$//' | tr -d '"')
            
            case "$key" in
                name) [[ -z "$PKG_NAME" ]] && PKG_NAME="$value" ;;
                version) [[ -z "$PKG_VERSION" ]] && PKG_VERSION="$value" ;;
                description) [[ -z "$PKG_DESCRIPTION" ]] && PKG_DESCRIPTION="$value" ;;
                homepage) [[ -z "$PKG_HOMEPAGE" ]] && PKG_HOMEPAGE="$value" ;;
                license) [[ -z "$PKG_LICENSE" ]] && PKG_LICENSE="$value" ;;
                maintainer) [[ -z "$PKG_MAINTAINER" ]] && PKG_MAINTAINER="$value" ;;
                entry_point) [[ -z "$PKG_ENTRY_POINT" ]] && PKG_ENTRY_POINT="$value" ;;
            esac
        done < <(grep -v '^#' "$PKG_CONFIG_FILE" | grep -v '^$' | grep -v '^  -')
        
        # Parse include list
        PKG_INCLUDE_DIRS=$(grep -A 100 '^include:' "$PKG_CONFIG_FILE" 2>/dev/null | grep '^  -' | sed 's/^  - //' | tr '\n' ' ' || echo "")
        
        # Parse dependencies list
        PKG_DEPENDENCIES=$(grep -A 100 '^dependencies:' "$PKG_CONFIG_FILE" 2>/dev/null | grep '^  -' | sed 's/^  - //' | tr '\n' ' ' || echo "")
    else
        print_warning "No config file found. Using auto-detection."
    fi
    
    # Fill in missing values with detection
    detect_package_info
}

# ============================================================================
# CONFIG INITIALIZATION
# ============================================================================

init_config() {
    print_header "Package Configuration Setup"
    
    detect_package_info
    
    echo -e "${BOLD}Package Information${NC}"
    
    read -rp "Package name [$PKG_NAME]: " input
    PKG_NAME="${input:-$PKG_NAME}"
    
    read -rp "Version [$PKG_VERSION]: " input
    PKG_VERSION="${input:-$PKG_VERSION}"
    
    read -rp "Description [$PKG_DESCRIPTION]: " input
    PKG_DESCRIPTION="${input:-$PKG_DESCRIPTION}"
    
    read -rp "Homepage [$PKG_HOMEPAGE]: " input
    PKG_HOMEPAGE="${input:-$PKG_HOMEPAGE}"
    
    read -rp "License [$PKG_LICENSE]: " input
    PKG_LICENSE="${input:-$PKG_LICENSE}"
    
    read -rp "Maintainer [$PKG_MAINTAINER]: " input
    PKG_MAINTAINER="${input:-$PKG_MAINTAINER}"
    
    read -rp "Entry point script [./dc or ./main.sh]: " input
    PKG_ENTRY_POINT="${input:-./dc}"
    
    echo ""
    echo "Directories/files to include (comma-separated):"
    read -rp "Include [scripts/,docs/,README.md,LICENSE]: " input
    PKG_INCLUDE_DIRS="${input:-scripts/,docs/,README.md,LICENSE}"
    
    echo ""
    echo "Runtime dependencies (comma-separated):"
    read -rp "Dependencies [git,gh,jq]: " input
    PKG_DEPENDENCIES="${input:-git,gh,jq}"
    
    # Generate config file
    cat > "$PKG_CONFIG_FILE" << EOF
# Dev-Control Packaging Configuration
# Generated by dc-package --init

name: $PKG_NAME
version: $PKG_VERSION
description: "$PKG_DESCRIPTION"
homepage: $PKG_HOMEPAGE
license: $PKG_LICENSE
maintainer: "$PKG_MAINTAINER"
entry_point: $PKG_ENTRY_POINT

# Files and directories to include in packages
include:
$(echo "$PKG_INCLUDE_DIRS" | tr ',' '\n' | sed 's/^/  - /')

# Runtime dependencies
dependencies:
$(echo "$PKG_DEPENDENCIES" | tr ',' '\n' | sed 's/^/  - /')

# Platform-specific settings (optional)
# homebrew:
#   tap: username/tap-name
# snap:
#   confinement: classic
# docker:
#   base_image: ubuntu:22.04
#   port: 8080
EOF
    
    print_success "Created $PKG_CONFIG_FILE"
    echo ""
    echo "Next steps:"
    echo "  1. Review and edit $PKG_CONFIG_FILE"
    echo "  2. Run: dc-package --tarball       # Build tarball"
    echo "  3. Run: dc-package --all           # Build all packages"
}

# ============================================================================
# TARBALL BUILD
# ============================================================================

build_tarball() {
    local tarball_name="${PKG_NAME}-${PKG_VERSION}"
    local tarball_file="${PKG_OUTPUT_DIR}/${tarball_name}.tar.gz"
    local temp_dir
    temp_dir=$(mktemp -d)
    
    print_info "Building tarball: $tarball_file"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] Would create: $tarball_file"
        return 0
    fi
    
    mkdir -p "$PKG_OUTPUT_DIR"
    mkdir -p "$temp_dir/$tarball_name"
    
    # Copy included files/dirs
    for item in $PKG_INCLUDE_DIRS; do
        item=$(echo "$item" | tr -d ',')
        if [[ -e "$item" ]]; then
            cp -r "$item" "$temp_dir/$tarball_name/"
            [[ "$VERBOSE" == "true" ]] && print_info "  Added: $item"
        fi
    done
    
    # Copy entry point
    if [[ -n "$PKG_ENTRY_POINT" && -f "$PKG_ENTRY_POINT" ]]; then
        cp "$PKG_ENTRY_POINT" "$temp_dir/$tarball_name/"
    fi
    
    # Create install script if not exists
    if [[ ! -f "$temp_dir/$tarball_name/install.sh" ]]; then
        create_install_script "$temp_dir/$tarball_name/install.sh"
    fi
    
    # Create tarball
    tar -czvf "$tarball_file" -C "$temp_dir" "$tarball_name" >/dev/null
    
    # Generate SHA256
    local sha256
    sha256=$(sha256sum "$tarball_file" | cut -d ' ' -f 1)
    echo "$sha256" > "${tarball_file}.sha256"
    
    rm -rf "$temp_dir"
    
    print_success "Tarball created: $tarball_file"
    print_info "SHA256: $sha256"
}

create_install_script() {
    local path="$1"
    cat > "$path" << 'INSTALL_EOF'
#!/usr/bin/env bash
# Auto-generated install script
set -e

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/share/PKG_NAME_PLACEHOLDER}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

echo "Installing PKG_NAME_PLACEHOLDER to $INSTALL_DIR..."

mkdir -p "$INSTALL_DIR" "$BIN_DIR"

# Copy files
cp -r . "$INSTALL_DIR/"

# Create symlink
ln -sf "$INSTALL_DIR/ENTRY_POINT_PLACEHOLDER" "$BIN_DIR/PKG_NAME_PLACEHOLDER"

echo "Installation complete!"
echo "Make sure $BIN_DIR is in your PATH"
INSTALL_EOF
    
    # Replace placeholders
    sed -i "s|PKG_NAME_PLACEHOLDER|$PKG_NAME|g" "$path"
    sed -i "s|ENTRY_POINT_PLACEHOLDER|$(basename "$PKG_ENTRY_POINT")|g" "$path"
    chmod +x "$path"
}

# ============================================================================
# HOMEBREW FORMULA
# ============================================================================

build_homebrew() {
    local formula_dir="${PKG_OUTPUT_DIR}/homebrew"
    local formula_file="${formula_dir}/${PKG_NAME}.rb"
    
    print_info "Generating Homebrew formula: $formula_file"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] Would create: $formula_file"
        return 0
    fi
    
    mkdir -p "$formula_dir"
    
    # Convert name to Ruby class name (capitalize, remove hyphens)
    local class_name
    class_name=$(echo "$PKG_NAME" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1' | tr -d ' ')
    
    # Get SHA256 from tarball if exists
    local sha256="REPLACE_WITH_SHA256"
    if [[ -f "${PKG_OUTPUT_DIR}/${PKG_NAME}-${PKG_VERSION}.tar.gz.sha256" ]]; then
        sha256=$(cat "${PKG_OUTPUT_DIR}/${PKG_NAME}-${PKG_VERSION}.tar.gz.sha256")
    fi
    
    cat > "$formula_file" << EOF
# Homebrew Formula for $PKG_NAME
# Generated by Dev-Control Packaging (dc-package)
#
# To install:
#   brew tap username/tap-name
#   brew install $PKG_NAME

class $class_name < Formula
  desc "$PKG_DESCRIPTION"
  homepage "$PKG_HOMEPAGE"
  url "${PKG_HOMEPAGE}/archive/refs/tags/v${PKG_VERSION}.tar.gz"
  sha256 "$sha256"
  license "$PKG_LICENSE"
  
  # Dependencies
EOF
    
    # Add dependencies
    for dep in $PKG_DEPENDENCIES; do
        dep=$(echo "$dep" | tr -d ',')
        echo "  depends_on \"$dep\"" >> "$formula_file"
    done
    
    cat >> "$formula_file" << EOF

  def install
    # Install scripts directory
    prefix.install Dir["scripts"]
    prefix.install Dir["*-templates"] if Dir.exist?("docs-templates")
    
    # Install main entry point
    bin.install "$(basename "$PKG_ENTRY_POINT")" => "$PKG_NAME"
  end

  test do
    system "#{bin}/$PKG_NAME", "--help"
  end
end
EOF
    
    print_success "Homebrew formula created: $formula_file"
    print_info "Next: Create a tap repo and copy the formula there"
}

# ============================================================================
# SNAP PACKAGE
# ============================================================================

build_snap() {
    local snap_dir="${PKG_OUTPUT_DIR}/snap"
    local snapcraft_file="${snap_dir}/snapcraft.yaml"
    
    print_info "Generating Snap package config: $snapcraft_file"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] Would create: $snapcraft_file"
        return 0
    fi
    
    mkdir -p "$snap_dir"
    
    cat > "$snapcraft_file" << EOF
name: $PKG_NAME
version: '$PKG_VERSION'
summary: $PKG_DESCRIPTION
description: |
  $PKG_DESCRIPTION
  
  Generated by Dev-Control Packaging (dc-package)

base: core22
confinement: classic
grade: stable

apps:
  $PKG_NAME:
    command: bin/$(basename "$PKG_ENTRY_POINT")
    environment:
      PATH: \$SNAP/usr/bin:\$SNAP/bin:\$PATH

parts:
  $PKG_NAME:
    plugin: dump
    source: .
    organize:
      scripts: bin/scripts
      $(basename "$PKG_ENTRY_POINT"): bin/$(basename "$PKG_ENTRY_POINT")
    stage-packages:
EOF
    
    # Add dependencies as stage-packages
    for dep in $PKG_DEPENDENCIES; do
        dep=$(echo "$dep" | tr -d ',')
        echo "      - $dep" >> "$snapcraft_file"
    done
    
    print_success "Snap config created: $snapcraft_file"
    echo ""
    echo "To build the snap:"
    echo "  cd ${snap_dir}"
    echo "  snapcraft"
    echo ""
    echo "To publish:"
    echo "  snapcraft login"
    echo "  snapcraft upload ${PKG_NAME}_${PKG_VERSION}_amd64.snap --release=stable"
}

# ============================================================================
# DEBIAN PACKAGE
# ============================================================================

build_debian() {
    local deb_dir="${PKG_OUTPUT_DIR}/debian/${PKG_NAME}-${PKG_VERSION}"
    
    print_info "Generating Debian package structure: $deb_dir"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] Would create: $deb_dir"
        return 0
    fi
    
    mkdir -p "$deb_dir/DEBIAN"
    mkdir -p "$deb_dir/usr/share/$PKG_NAME"
    mkdir -p "$deb_dir/usr/bin"
    
    # Control file
    cat > "$deb_dir/DEBIAN/control" << EOF
Package: $PKG_NAME
Version: $PKG_VERSION
Section: utils
Priority: optional
Architecture: all
Depends: bash (>= 4.0), $(echo "$PKG_DEPENDENCIES" | tr ' ' ',' | sed 's/,,*/,/g')
Maintainer: $PKG_MAINTAINER
Description: $PKG_DESCRIPTION
 Generated by Dev-Control Packaging (dc-package)
Homepage: $PKG_HOMEPAGE
EOF
    
    # Post-install script
    cat > "$deb_dir/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e
ln -sf /usr/share/PKG_NAME/ENTRY_POINT /usr/bin/PKG_NAME
echo "PKG_NAME installed successfully!"
EOF
    sed -i "s|PKG_NAME|$PKG_NAME|g" "$deb_dir/DEBIAN/postinst"
    sed -i "s|ENTRY_POINT|$(basename "$PKG_ENTRY_POINT")|g" "$deb_dir/DEBIAN/postinst"
    chmod 755 "$deb_dir/DEBIAN/postinst"
    
    # Copy files
    for item in $PKG_INCLUDE_DIRS; do
        item=$(echo "$item" | tr -d ',')
        if [[ -e "$item" ]]; then
            cp -r "$item" "$deb_dir/usr/share/$PKG_NAME/"
        fi
    done
    
    # Copy entry point
    if [[ -n "$PKG_ENTRY_POINT" && -f "$PKG_ENTRY_POINT" ]]; then
        cp "$PKG_ENTRY_POINT" "$deb_dir/usr/share/$PKG_NAME/"
        chmod +x "$deb_dir/usr/share/$PKG_NAME/$(basename "$PKG_ENTRY_POINT")"
    fi
    
    print_success "Debian package structure created: $deb_dir"
    echo ""
    echo "To build the .deb file:"
    echo "  dpkg-deb --build $deb_dir"
    echo ""
    echo "To install locally:"
    echo "  sudo dpkg -i ${deb_dir}.deb"
}

# ============================================================================
# NIX FLAKE
# ============================================================================

build_nix() {
    local nix_dir="${PKG_OUTPUT_DIR}/nix"
    local flake_file="${nix_dir}/flake.nix"
    
    print_info "Generating Nix flake: $flake_file"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] Would create: $flake_file"
        return 0
    fi
    
    mkdir -p "$nix_dir"
    
    cat > "$flake_file" << EOF
{
  description = "$PKG_DESCRIPTION";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.\${system};
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "$PKG_NAME";
          version = "$PKG_VERSION";
          
          src = ./.;
          
          nativeBuildInputs = [ pkgs.makeWrapper ];
          
          buildInputs = with pkgs; [
            bash
            $(echo "$PKG_DEPENDENCIES" | tr ',' ' ' | tr ' ' '\n' | sort -u | tr '\n' ' ')
          ];
          
          installPhase = ''
            mkdir -p \$out/share/$PKG_NAME \$out/bin
            cp -r scripts \$out/share/$PKG_NAME/
            cp $(basename "$PKG_ENTRY_POINT") \$out/share/$PKG_NAME/
            
            makeWrapper \$out/share/$PKG_NAME/$(basename "$PKG_ENTRY_POINT") \$out/bin/$PKG_NAME \\
              --prefix PATH : \${pkgs.lib.makeBinPath (with pkgs; [ bash git gh jq ])}
          '';
          
          meta = with pkgs.lib; {
            description = "$PKG_DESCRIPTION";
            homepage = "$PKG_HOMEPAGE";
            license = licenses.$(echo "$PKG_LICENSE" | tr '[:upper:]' '[:lower:]' | tr '-' '_');
            platforms = platforms.unix;
          };
        };
        
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            bash
            $(echo "$PKG_DEPENDENCIES" | tr ',' ' ' | tr ' ' '\n' | sort -u | tr '\n' ' ')
          ];
        };
      }
    );
}
EOF
    
    print_success "Nix flake created: $flake_file"
    echo ""
    echo "To build with Nix:"
    echo "  nix build .#default"
    echo ""
    echo "To enter dev shell:"
    echo "  nix develop"
}

# ============================================================================
# DOCKER IMAGE
# ============================================================================

build_docker() {
    local docker_dir="${PKG_OUTPUT_DIR}/docker"
    local dockerfile="${docker_dir}/Dockerfile"
    
    print_info "Generating Docker config: $dockerfile"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] Would create: $dockerfile"
        return 0
    fi
    
    mkdir -p "$docker_dir"
    
    cat > "$dockerfile" << EOF
# Dockerfile for $PKG_NAME with web terminal (ttyd)
# Generated by Dev-Control Packaging (dc-package)
#
# Build: docker build -t $PKG_NAME .
# Run:   docker run -p 8080:8080 $PKG_NAME
# Access: http://localhost:8080

FROM ubuntu:22.04

LABEL maintainer="$PKG_MAINTAINER"
LABEL description="$PKG_DESCRIPTION"
LABEL version="$PKG_VERSION"

# Install dependencies
RUN apt-get update && apt-get install -y \\
    bash \\
    curl \\
    git \\
    jq \\
    ttyd \\
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \\
    && echo "deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \\
    && apt-get update \\
    && apt-get install -y gh \\
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy application files
COPY scripts/ /app/scripts/
COPY $(basename "$PKG_ENTRY_POINT") /app/

# Make scripts executable
RUN chmod +x /app/$(basename "$PKG_ENTRY_POINT") /app/scripts/*.sh

# Add to PATH
ENV PATH="/app:\$PATH"

# Expose ttyd port
EXPOSE 8080

# Start ttyd with the main script
CMD ["ttyd", "-p", "8080", "-W", "/app/$(basename "$PKG_ENTRY_POINT")"]
EOF
    
    # Create docker-compose.yml
    cat > "${docker_dir}/docker-compose.yml" << EOF
version: '3.8'

services:
  $PKG_NAME:
    build: .
    ports:
      - "8080:8080"
    volumes:
      - ./workspace:/workspace
    environment:
      - TERM=xterm-256color
    restart: unless-stopped
EOF
    
    print_success "Docker files created: $docker_dir"
    echo ""
    echo "To build and run:"
    echo "  cd $docker_dir"
    echo "  docker build -t $PKG_NAME ."
    echo "  docker run -p 8080:8080 $PKG_NAME"
    echo ""
    echo "Or with docker-compose:"
    echo "  docker-compose up --build"
    echo ""
    echo "Access web terminal at: http://localhost:8080"
}

# ============================================================================
# MENU SYSTEM
# ============================================================================

display_menu() {
    print_header "Package Builder"
    
    echo -e "${BOLD}Package: ${CYAN}$PKG_NAME${NC} v${PKG_VERSION}"
    echo ""
    
    echo -e "${BOLD}Build Options${NC}"
    print_menu_item "1" "Tarball (.tar.gz)        - Universal release archive"
    print_menu_item "2" "Homebrew Formula         - macOS/Linux (brew install)"
    print_menu_item "3" "Snap Package             - Ubuntu/Linux (snap install)"
    print_menu_item "4" "Debian Package (.deb)    - Debian/Ubuntu (apt install)"
    print_menu_item "5" "Nix Flake                - NixOS/Nix (nix build)"
    print_menu_item "6" "Docker Image             - Web terminal (ttyd)"
    echo ""
    print_menu_item "A" "Build ALL packages"
    print_menu_item "I" "Initialize/update config"
    print_menu_item "0" "Exit"
    echo ""
}

run_interactive() {
    while true; do
        display_menu
        read -rp "Select option: " choice
        echo ""
        
        case "$choice" in
            1) build_tarball ;;
            2) build_homebrew ;;
            3) build_snap ;;
            4) build_debian ;;
            5) build_nix ;;
            6) build_docker ;;
            [Aa])
                build_tarball
                build_homebrew
                build_snap
                build_debian
                build_nix
                build_docker
                ;;
            [Ii]) init_config ;;
            0|q|Q) 
                print_info "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        
        echo ""
        read -rp "Press Enter to continue..."
    done
}

# ============================================================================
# SUMMARY
# ============================================================================

show_build_summary() {
    print_header_success "Build Complete!"
    
    print_section "Package Info:"
    print_detail "Name" "$PKG_NAME"
    print_detail "Version" "$PKG_VERSION"
    print_detail "Output" "$PKG_OUTPUT_DIR"
    
    echo ""
    echo "Built packages:"
    
    [[ "$BUILD_TARBALL" == "true" ]] && print_list_item "Tarball: ${PKG_OUTPUT_DIR}/${PKG_NAME}-${PKG_VERSION}.tar.gz"
    [[ "$BUILD_HOMEBREW" == "true" ]] && print_list_item "Homebrew: ${PKG_OUTPUT_DIR}/homebrew/${PKG_NAME}.rb"
    [[ "$BUILD_SNAP" == "true" ]] && print_list_item "Snap: ${PKG_OUTPUT_DIR}/snap/snapcraft.yaml"
    [[ "$BUILD_DEBIAN" == "true" ]] && print_list_item "Debian: ${PKG_OUTPUT_DIR}/debian/"
    [[ "$BUILD_NIX" == "true" ]] && print_list_item "Nix: ${PKG_OUTPUT_DIR}/nix/flake.nix"
    [[ "$BUILD_DOCKER" == "true" ]] && print_list_item "Docker: ${PKG_OUTPUT_DIR}/docker/Dockerfile"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    parse_args "$@"
    
    # Initialize config mode
    if [[ "$INIT_CONFIG" == "true" ]]; then
        init_config
        exit 0
    fi
    
    # Load configuration
    load_config
    
    # If no build options specified, run interactive
    if [[ "$BUILD_TARBALL" != "true" && "$BUILD_HOMEBREW" != "true" && 
          "$BUILD_SNAP" != "true" && "$BUILD_DEBIAN" != "true" && 
          "$BUILD_NIX" != "true" && "$BUILD_DOCKER" != "true" ]]; then
        run_interactive
        exit 0
    fi
    
    print_header "Dev-Control Package Builder"
    
    print_info "Building packages for: ${CYAN}$PKG_NAME${NC} v${PKG_VERSION}"
    echo ""
    
    # Run requested builds
    [[ "$BUILD_TARBALL" == "true" ]] && build_tarball
    [[ "$BUILD_HOMEBREW" == "true" ]] && build_homebrew
    [[ "$BUILD_SNAP" == "true" ]] && build_snap
    [[ "$BUILD_DEBIAN" == "true" ]] && build_debian
    [[ "$BUILD_NIX" == "true" ]] && build_nix
    [[ "$BUILD_DOCKER" == "true" ]] && build_docker
    
    # Show summary
    show_build_summary
}

main "$@"
