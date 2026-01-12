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
################################################################################

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"

# Source shared libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/print.sh"

################################################################################
# Functions
################################################################################

# Detect or prompt for project path
detect_project_path() {
    local provided_path="$1"
    
    if [ -n "$provided_path" ]; then
        if [ -d "$provided_path" ]; then
            echo "$provided_path"
            return 0
        else
            print_error "Provided path does not exist: $provided_path"
            exit 1
        fi
    fi
    
    # Use current working directory
    local cwd
    cwd=$(pwd)
    
    print_info "Detected project path: $cwd"
    echo ""
    read -p "Use this path? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        read -p "Enter project path: " custom_path
        if [ ! -d "$custom_path" ]; then
            print_error "Path does not exist: $custom_path"
            exit 1
        fi
        echo "$custom_path"
    else
        echo "$cwd"
    fi
}

# Check if running in devcontainer
is_in_devcontainer() {
    [ -n "$DEVCONTAINER" ] || [ -n "$CODESPACES" ]
}

# Check rootless podman availability
check_podman() {
    print_step "Checking for rootless podman..."
    
    if command -v podman &> /dev/null; then
        local podman_version
        podman_version=$(podman --version)
        print_success "Podman found: $podman_version"
        return 0
    else
        return 1
    fi
}

# Install rootless podman on Ubuntu
install_rootless_podman() {
    print_header "Installing Rootless Podman"
    
    print_info "This requires sudo privileges for one-time setup"
    echo ""
    
    # Update package lists
    print_step "Updating package lists..."
    sudo apt-get update -qq
    
    # Install podman
    print_step "Installing podman..."
    sudo apt-get install -y -qq podman podman-docker uidmap slirp4netns
    
    # Setup rootless podman (requires user interaction)
    print_step "Setting up rootless mode..."
    echo ""
    print_info "You may be prompted to enter your password to configure user namespaces"
    echo ""
    
    podman system migrate 2>/dev/null || true
    
    # Enable lingering for systemd user session (keeps containers running)
    print_step "Enabling user systemd session..."
    sudo loginctl enable-linger "$(id -un)" 2>/dev/null || true
    
    print_success "Rootless podman setup complete"
    echo ""
    
    # Verify installation
    if podman run --rm --quiet alpine echo "Podman is working" &>/dev/null; then
        print_success "Podman verification passed"
        return 0
    else
        print_warning "Podman test failed - you may need to restart your session"
        return 1
    fi
}

# Detect system paths needed for mounts
detect_system_paths() {
    local username="$1"
    local home_dir="/home/$username"
    
    # Detect GPG socket (standard location)
    local gpg_socket
    if [ -S "$home_dir/.gnupg/S.gpg-agent" ]; then
        gpg_socket="$home_dir/.gnupg/S.gpg-agent"
    elif [ -S "/run/user/1000/gnupg/S.gpg-agent" ]; then
        gpg_socket="/run/user/1000/gnupg/S.gpg-agent"
    fi
    
    # Detect podman socket (standard location)
    local podman_socket
    if [ -S "/run/user/1000/podman/podman.sock" ]; then
        podman_socket="/run/user/1000/podman/podman.sock"
    fi
    
    # Wrangler config location
    local wrangler_config="$home_dir/.wrangler"
    
    # Output detected paths (JSON format for later use)
    cat <<EOF
{
  "gpg_socket": "${gpg_socket}",
  "podman_socket": "${podman_socket}",
  "wrangler_config": "${wrangler_config}",
  "home_dir": "${home_dir}",
  "username": "${username}"
}
EOF
}

# Generate devcontainer.json
generate_devcontainer() {
    local project_path="$1"
    local devcontainer_dir="$project_path/.devcontainer"
    local devcontainer_file="$devcontainer_dir/devcontainer.json"
    
    # Get current user info
    local current_user
    current_user=$(whoami)
    
    # Detect system paths
    local paths_json
    paths_json=$(detect_system_paths "$current_user")
    
    local gpg_socket
    local podman_socket
    local wrangler_config
    
    gpg_socket=$(echo "$paths_json" | jq -r '.gpg_socket')
    podman_socket=$(echo "$paths_json" | jq -r '.podman_socket')
    wrangler_config=$(echo "$paths_json" | jq -r '.wrangler_config')
    
    print_header "Generating Devcontainer Configuration"
    print_info "Project path: $project_path"
    print_info "Config location: $devcontainer_file"
    echo ""

    # Ask about enabling GPG commit signing (do NOT embed private key material)
    local enable_signing="n"
    read -p "Enable GPG commit signing in the devcontainer? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        enable_signing="y"
    fi

    signing_key=""
    if [[ "$enable_signing" == "y" ]]; then
        # Prompt user for a signing key ID (short or long). Do not attempt to read local secret keys.
        read -p "Enter signing key ID to use in devcontainer (short or long, e.g., 31B0D171): " signing_key
        if [ -z "$signing_key" ]; then
            print_warning "No signing key provided; skipping signing setup."
            enable_signing="n"
        else
            print_step "Configured signing key ID: $signing_key (no key material stored)"
        fi
    fi

    # Create directory if needed
    mkdir -p "$devcontainer_dir"

    # Build mounts array
    local mounts_json="["

    # GPG socket (if available)
    if [ -n "$gpg_socket" ] && [ -S "$gpg_socket" ]; then
        mounts_json+="
    \"source=$gpg_socket,target=/run/user/1000/gnupg/S.gpg-agent,type=bind\"," 
        print_step "Added GPG socket mount: $gpg_socket"
    else
        print_warning "GPG socket not found at $gpg_socket (optional)"
    fi

    # Podman socket (if available)
    if [ -n "$podman_socket" ] && [ -S "$podman_socket" ]; then
        mounts_json+="
    \"source=$podman_socket,target=/var/run/docker.sock,type=bind\"," 
        print_step "Added podman socket mount: $podman_socket"
    else
        print_warning "Podman socket not found at $podman_socket (optional, docker will be unavailable)"
    fi

    # Wrangler config (if exists)
    if [ -d "$wrangler_config" ]; then
        mounts_json+="
    \"source=$wrangler_config,target=/home/codespace/.wrangler,type=bind,consistency=cached\""
        print_step "Added Wrangler config mount: $wrangler_config"
    else
        # Remove trailing comma from previous mount if wrangler doesn't exist
        mounts_json="${mounts_json%,}"
    fi

    mounts_json+="
  ]"
    
    # Create devcontainer.json
    cat > "$devcontainer_file" <<'DEVCONTAINER_EOF'
{
  "name": "PROJECTS",
  "image": "mcr.microsoft.com/devcontainers/universal:2",
  "remoteUser": "codespace",
  "features": {
    "ghcr.io/devcontainers/features/git:1": {}
  },
DEVCONTAINER_EOF
    
    # Add mounts
    echo "  \"mounts\": $mounts_json," >> "$devcontainer_file"
    
    # Construct postCreateCommand dynamically (uses public Github GPG key to reproduce signin on container rebuild)
    local post_create_cmd="sudo chown -R codespace:codespace /workspaces && sudo rm -f /etc/bash.bashrc.d/codespaces-motd.sh /etc/profile.d/codespaces-motd.sh /usr/local/etc/vscode-dev-containers/first-run-notice.txt && touch /home/codespace/.hushlogin && chmod 644 /home/codespace/.hushlogin && git config --global --add safe.directory \"/workspaces\" && git config --global --add safe.directory \"/workspaces/*\" && git config --global user.email 69734795+xaoscience@users.noreply.github.com && git config --global user.name xaoscience"

    if [[ "$enable_signing" == "y" && -n "$signing_key" ]]; then
        post_create_cmd+=" && git config --global commit.gpgsign true && git config --global user.signingkey $signing_key"
    fi

    post_create_cmd+=" && git config --global gpg.program gpg && sudo ln -sf /usr/bin/podman /usr/local/bin/docker"

    # Add the rest (allow variable expansion)
    cat >> "$devcontainer_file" <<DEVCONTAINER_EOF
  "containerEnv": {
    "GPG_TTY": "$(tty)",
    "DOCKER_HOST": "unix:///var/run/docker.sock"
  },
  "forwardPorts": [],
  "postCreateCommand": "bash -c '$post_create_cmd'",
  "customizations": {
    "vscode": {
      "extensions": []
    }
  }
}
DEVCONTAINER_EOF
    
    print_success "Generated $devcontainer_file"
    echo ""
}

# Show activation instructions
show_activation_instructions() {
    local project_path="$1"
    
    print_header "Next Steps: Activate Devcontainer in VSCode"
    
    echo "To open your project in a devcontainer:"
    echo ""
    echo "1. Open VSCode with your project:"
    echo "   ${CYAN}code $project_path${NC}"
    echo ""
    echo "2. When prompted by VSCode:"
    echo "   - Click 'Reopen in Container' or"
    echo "   - Run command: ${CYAN}Dev Containers: Reopen in Container${NC}"
    echo ""
    echo "3. VSCode will:"
    echo "   ✓ Build/pull the container image"
    echo "   ✓ Mount your project and config directories"
    echo "   ✓ Run postCreateCommand to set up git & GPG"
    echo "   ✓ Connect all necessary services (docker, gpg, git)"
    echo ""
    echo "4. Verify container is working:"
    echo "   - Terminal should show: ${CYAN}codespace@<container>:/workspaces$${NC}"
    echo "   - Run: ${CYAN}podman --version${NC} to verify docker/podman"
    echo "   - Run: ${CYAN}git config user.name${NC} to verify git config"
    echo ""
    echo "Configuration stored in:"
    echo "  ${CYAN}$project_path/.devcontainer/devcontainer.json${NC}"
    echo ""
}

# Main execution
main() {
    local project_path
    
    print_header "Containerisation Setup"
    
    # Check if already in devcontainer
    if is_in_devcontainer; then
        print_warning "Detected that you're already running in a devcontainer"
        echo ""
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Cancelled"
            return 0
        fi
    fi
    
    # Detect or prompt for project path
    project_path=$(detect_project_path "$1")
    echo ""
    
    # Check/install rootless podman
    if ! check_podman; then
        echo ""
        print_warning "Rootless podman not found"
        echo ""
        read -p "Install rootless podman now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_rootless_podman
        else
            print_warning "Skipped podman installation"
            print_info "Docker/podman features will be unavailable in the container"
            echo ""
        fi
    fi
    
    echo ""
    
    # Generate devcontainer
    generate_devcontainer "$project_path"
    echo ""
    
    # Show activation instructions
    show_activation_instructions "$project_path"
    
    print_success "Containerisation setup complete!"
}

main "$@"
