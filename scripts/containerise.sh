#!/usr/bin/env bash
#
# Containerisation Setup Script
# Configures rootless podman/docker and creates optimised devcontainer for projects
#
# Features:
#   ✓ Detects or prompts for project folder
#   ✓ Installs/verifies rootless podman on Ubuntu
#   ✓ Generates optimised .devcontainer/devcontainer.json
#   ✓ Configures mount points (GPG, podman, git, etc.)
#   ✓ Includes git & GPG signing configuration
#   ✓ Guides through VSCode devcontainer activation
#
# Usage:
#   ./containerise.sh [PROJECT_PATH]
#   ./containerise.sh                    # Uses current directory
#   ./containerise.sh /path/to/project   # Uses specified path
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience
################################################################################

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"

# Source shared libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/print.sh"
source "$SCRIPT_DIR/lib/validation.sh"

################################################################################
# Functions
################################################################################

# Detect or prompt for project path
detect_project_path() {
    local path="${1:-}"
    
    if [[ -n "$path" ]]; then
        if is_directory "$path"; then
            PROJECT_PATH=$(to_absolute_path "$path")
        else
            print_error "Directory not found: $path"
            exit 1
        fi
    else
        PROJECT_PATH=$(pwd)
    fi
    
    print_info "Project path: ${CYAN}$PROJECT_PATH${NC}"
}

# Check if running in devcontainer
is_in_devcontainer() {
    [[ -f "/.dockerenv" ]] || [[ -n "${REMOTE_CONTAINERS:-}" ]] || [[ -n "${CODESPACES:-}" ]]
}

# Check rootless podman availability
check_podman() {
    if ! command -v podman &>/dev/null; then
        print_warning "Podman not found"
        return 1
    fi
    
    # Check if rootless
    if podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null | grep -q true; then
        print_success "Rootless podman available"
        return 0
    else
        print_warning "Podman not configured for rootless operation"
        return 1
    fi
}

# Install rootless podman on Ubuntu
install_rootless_podman() {
    print_header "Installing Rootless Podman"
    
    print_info "Updating package lists..."
    sudo apt-get update -qq
    
    print_info "Installing podman..."
    sudo apt-get install -y podman uidmap slirp4netns fuse-overlayfs
    
    print_info "Configuring rootless podman..."
    
    # Enable user namespaces
    if [[ ! -f /etc/subuid ]] || ! grep -q "^$(whoami):" /etc/subuid; then
        sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$(whoami)"
    fi
    
    # Initialize rootless podman
    podman system migrate 2>/dev/null || true
    
    print_success "Rootless podman installed and configured"
}

# Detect system paths needed for mounts
detect_system_paths() {
    local gnupg_path="${HOME}/.gnupg"
    local ssh_path="${HOME}/.ssh"
    local git_config="${HOME}/.gitconfig"
    local podman_socket="/run/user/$(id -u)/podman/podman.sock"
    
    # Check for XDG runtime dir
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
        podman_socket="${XDG_RUNTIME_DIR}/podman/podman.sock"
    fi
    
    cat <<EOF
{
  "gnupg": "$gnupg_path",
  "ssh": "$ssh_path",
  "gitconfig": "$git_config",
  "podman_socket": "$podman_socket"
}
EOF
}

# Generate devcontainer.json
generate_devcontainer() {
    local devcontainer_dir="$PROJECT_PATH/.devcontainer"
    local devcontainer_file="$devcontainer_dir/devcontainer.json"
    
    print_info "Generating devcontainer configuration..."
    
    mkdir -p "$devcontainer_dir"
    
    # Get system paths
    local paths
    paths=$(detect_system_paths)
    local gnupg_path ssh_path git_config podman_socket
    gnupg_path=$(echo "$paths" | jq -r '.gnupg')
    ssh_path=$(echo "$paths" | jq -r '.ssh')
    git_config=$(echo "$paths" | jq -r '.gitconfig')
    podman_socket=$(echo "$paths" | jq -r '.podman_socket')
    
    # Determine image based on project
    local base_image="mcr.microsoft.com/devcontainers/base:ubuntu"
    
    # Detect project type
    if [[ -f "$PROJECT_PATH/package.json" ]]; then
        base_image="mcr.microsoft.com/devcontainers/javascript-node:22"
    elif [[ -f "$PROJECT_PATH/requirements.txt" ]] || [[ -f "$PROJECT_PATH/pyproject.toml" ]]; then
        base_image="mcr.microsoft.com/devcontainers/python:3.12"
    elif [[ -f "$PROJECT_PATH/Cargo.toml" ]]; then
        base_image="mcr.microsoft.com/devcontainers/rust:latest"
    elif [[ -f "$PROJECT_PATH/go.mod" ]]; then
        base_image="mcr.microsoft.com/devcontainers/go:latest"
    fi
    
    cat > "$devcontainer_file" << DEVCONTAINER_EOF
{
  "name": "$(basename "$PROJECT_PATH")",
  "image": "$base_image",
  "features": {
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/devcontainers/features/git:1": {
      "version": "latest",
      "ppa": true
    }
  },
  "mounts": [
    "source=$gnupg_path,target=/home/vscode/.gnupg,type=bind,consistency=cached",
    "source=$ssh_path,target=/home/vscode/.ssh,type=bind,consistency=cached",
    "source=$git_config,target=/home/vscode/.gitconfig,type=bind,consistency=cached"
  ],
  "containerEnv": {
    "GPG_TTY": "/dev/pts/0",
    "GIT_TERMINAL_PROMPT": "1"
  },
  "customizations": {
    "vscode": {
      "settings": {
        "git.enableSmartCommit": true,
        "git.autofetch": true,
        "terminal.integrated.defaultProfile.linux": "bash"
      },
      "extensions": [
        "github.copilot",
        "github.copilot-chat"
      ]
    }
  },
  "postCreateCommand": "git config --global gpg.program $(which gpg) && echo 'Container ready!'",
  "remoteUser": "vscode"
}
DEVCONTAINER_EOF
    
    print_success "Created: $devcontainer_file"
}

# Show activation instructions
show_activation_instructions() {
    print_header_success "Containerisation Complete!"
    
    print_section "Next Steps:"
    echo -e "  1. Open the project in VS Code: ${GREEN}code $PROJECT_PATH${NC}"
    echo -e "  2. Press ${CYAN}F1${NC} and run: ${CYAN}Dev Containers: Reopen in Container${NC}"
    echo ""
    
    print_section "Alternative:"
    echo -e "  Use the Remote-Containers icon in the bottom-left corner"
    echo ""
    
    print_section "Files Created:"
    print_list_item ".devcontainer/devcontainer.json"
    echo ""
}

# Main execution
main() {
    print_header "Git-Control Containerisation"
    
    # Check if already in devcontainer
    if is_in_devcontainer; then
        print_warning "Already running inside a devcontainer"
        print_info "This script is meant to be run on the host machine"
        exit 0
    fi
    
    # Detect project path
    detect_project_path "${1:-}"
    
    # Check/install podman
    if ! check_podman; then
        if confirm "Install rootless podman?"; then
            install_rootless_podman
        else
            print_warning "Continuing without podman verification"
        fi
    fi
    
    # Generate devcontainer
    if [[ -f "$PROJECT_PATH/.devcontainer/devcontainer.json" ]]; then
        if confirm "Devcontainer config exists. Overwrite?"; then
            generate_devcontainer
        else
            print_info "Keeping existing configuration"
        fi
    else
        generate_devcontainer
    fi
    
    show_activation_instructions
}

main "$@"
