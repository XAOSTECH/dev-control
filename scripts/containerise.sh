#!/usr/bin/env bash
#
# Containerisation Setup Script
# Configures rootless podman/docker and creates optimised devcontainer for projects
#
# Features:
#   ✓ Interactive configuration with config file support
#   ✓ Generates complete .devcontainer (devcontainer.json, Dockerfile, .dockerignore)
#   ✓ Configurable timezone, locale, mirror, base image
#   ✓ GPG signing and GitHub profile configuration
#   ✓ Option to save selections as default config
#   ✓ Detects or prompts for project folder
#   ✓ Installs/verifies rootless podman on Ubuntu
#   ✓ Guides through VSCode devcontainer activation
#
# Usage:
#   ./containerise.sh [PROJECT_PATH] [OPTIONS]
#   ./containerise.sh                    # Interactive mode
#   ./containerise.sh --defaults         # Use saved defaults (one-click)
#   ./containerise.sh --config FILE      # Use specific config file
#   ./containerise.sh --help             # Show help
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience
################################################################################

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"
export DEV_CONTROL_DIR  # Export to avoid SC2034 warning

# Source shared libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/print.sh"
source "$SCRIPT_DIR/lib/validation.sh"

################################################################################
# Default Configuration
################################################################################

# Configuration file paths
DC_CONTAINER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dev-control"
DC_CONTAINER_CONFIG="$DC_CONTAINER_CONFIG_DIR/container.yaml"
DC_PROJECT_CONTAINER_CONFIG=".devcontainer.yaml"

# Default values (neutral defaults, customisable for any region)
declare -A CONTAINER_DEFAULTS=(
    ["container_name"]=""  # Will be set to folder name if empty
    ["github_user"]=""
    ["github_user_email"]=""
    ["gpg_key_id"]=""
    ["timezone"]="UTC"
    ["locale"]="en_US.UTF-8"
    ["ubuntu_mirror"]="http://archive.ubuntu.com/ubuntu"
    ["base_image"]="ubuntu:latest"
    ["hush_login"]="true"
    ["vscode_extensions"]="github.copilot,github.copilot-chat"
    ["mount_gpg"]="true"
    ["mount_gh_config"]="true"
    ["mount_docker_socket"]="true"
    ["install_gh_cli"]="true"
    ["install_git_control"]="true"
    ["git_control_version"]="latest"
)

# Common base images for selection
declare -a BASE_IMAGES=(
    "ubuntu:latest"
    "ubuntu:noble"
    "ubuntu:jammy"
    "mcr.microsoft.com/devcontainers/universal:2-linux"
    "mcr.microsoft.com/devcontainers/base:ubuntu"
    "mcr.microsoft.com/devcontainers/python:3.12"
    "mcr.microsoft.com/devcontainers/javascript-node:22"
    "mcr.microsoft.com/devcontainers/rust:latest"
    "mcr.microsoft.com/devcontainers/go:latest"
)

# Common mirrors for selection (main continental servers)
# Users can enter any custom mirror URL during selection
declare -A UBUNTU_MIRRORS=(
    ["Main Archive"]="http://archive.ubuntu.com/ubuntu"
    ["North America"]="https://us.archive.ubuntu.com/ubuntu"
    ["South America"]="https://br.archive.ubuntu.com/ubuntu"
    ["Europe"]="https://eu.archive.ubuntu.com/ubuntu"
    ["Asia"]="https://asia.archive.ubuntu.com/ubuntu"
    ["Oceania"]="https://au.archive.ubuntu.com/ubuntu"
    ["Africa"]="https://za.archive.ubuntu.com/ubuntu"
)

# Common timezones for selection (main continental zones)
# Users can enter any valid TZ database name during selection
declare -a TIMEZONES=(
    "UTC"
    "America/New_York"
    "America/Los_Angeles"
    "America/Sao_Paulo"
    "Europe/London"
    "Europe/Paris"
    "Asia/Tokyo"
    "Asia/Shanghai"
    "Asia/Kolkata"
    "Australia/Sydney"
    "Africa/Johannesburg"
)

# Common locales for selection (major language/region combinations)
# Users can enter any valid locale during selection
declare -a LOCALES=(
    "en_US.UTF-8"
    "en_GB.UTF-8"
    "pt_BR.UTF-8"
    "es_ES.UTF-8"
    "fr_FR.UTF-8"
    "de_DE.UTF-8"
    "ja_JP.UTF-8"
    "zh_CN.UTF-8"
    "hi_IN.UTF-8"
    "ar_SA.UTF-8"
)

# CLI options
USE_DEFAULTS=false
CONFIG_FILE=""
PROJECT_PATH=""
SHOW_HELP=false

################################################################################
# Help
################################################################################

show_help() {
    cat << 'EOF'
Dev-Control Containerisation - Create optimised devcontainer configurations

USAGE:
  containerise.sh [PROJECT_PATH] [OPTIONS]

OPTIONS:
  --defaults, -d      Use saved defaults from config file (one-click mode)
  --config FILE, -c   Use specific configuration file
  --help, -h          Show this help message

CONFIGURATION:
  Global config:    ~/.config/dev-control/container.yaml
  Project config:   .devcontainer.yaml (in project root)

  Configuration hierarchy (highest priority first):
    1. CLI arguments
    2. Project config (.devcontainer.yaml)
    3. Global config (~/.config/dev-control/container.yaml)
    4. Built-in defaults (UTC/en_US)

GENERATED FILES:
  .devcontainer/devcontainer.json  - VS Code devcontainer configuration
  .devcontainer/Dockerfile         - Container build instructions
  .devcontainer/.dockerignore      - Build context exclusions

EXAMPLES:
  containerise.sh                     # Interactive mode in current directory
  containerise.sh ~/projects/myapp    # Interactive mode for specific project
  containerise.sh --defaults          # Use saved config (one-click)
  containerise.sh -c myconfig.yaml    # Use custom config file

ALIASES:
  dc-container, dc-containerise, dc-devcontainer

EOF
}

################################################################################
# YAML Configuration Parsing
################################################################################

# Parse container YAML config file
parse_container_yaml() {
    local file="$1"
    local line key value
    
    [[ ! -f "$file" ]] && return 1
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        
        # Match key: value
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_-]*)[[:space:]]*:[[:space:]]*(.*)[[:space:]]*$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            
            # Remove quotes
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            
            # Replace hyphens with underscores for variable names
            key="${key//-/_}"
            
            # Export to current config
            case "$key" in
                container_name)   CFG_CONTAINER_NAME="$value" ;;
                github_user)      CFG_GITHUB_USER="$value" ;;
                github_user_email) CFG_GITHUB_USER_EMAIL="$value" ;;
                gpg_key_id)       CFG_GPG_KEY_ID="$value" ;;
                timezone)         CFG_TIMEZONE="$value" ;;
                locale)           CFG_LOCALE="$value" ;;
                ubuntu_mirror)    CFG_UBUNTU_MIRROR="$value" ;;
                base_image)       CFG_BASE_IMAGE="$value" ;;
                hush_login)       CFG_HUSH_LOGIN="$value" ;;
                vscode_extensions) CFG_VSCODE_EXTENSIONS="$value" ;;
                mount_gpg)        CFG_MOUNT_GPG="$value" ;;
                mount_gh_config)  CFG_MOUNT_GH_CONFIG="$value" ;;
                mount_docker_socket) CFG_MOUNT_DOCKER_SOCKET="$value" ;;
                install_gh_cli)   CFG_INSTALL_GH_CLI="$value" ;;
                install_git_control) CFG_INSTALL_DEV_CONTROL="$value" ;;
                git_control_version) CFG_DEV_CONTROL_VERSION="$value" ;;
            esac
        fi
    done < "$file"
}

# Load configuration from all sources
load_container_config() {
    # Start with defaults
    CFG_CONTAINER_NAME="${CONTAINER_DEFAULTS[container_name]}"
    CFG_GITHUB_USER="${CONTAINER_DEFAULTS[github_user]}"
    CFG_GITHUB_USER_EMAIL="${CONTAINER_DEFAULTS[github_user_email]}"
    CFG_GPG_KEY_ID="${CONTAINER_DEFAULTS[gpg_key_id]}"
    CFG_TIMEZONE="${CONTAINER_DEFAULTS[timezone]}"
    CFG_LOCALE="${CONTAINER_DEFAULTS[locale]}"
    CFG_UBUNTU_MIRROR="${CONTAINER_DEFAULTS[ubuntu_mirror]}"
    CFG_BASE_IMAGE="${CONTAINER_DEFAULTS[base_image]}"
    CFG_HUSH_LOGIN="${CONTAINER_DEFAULTS[hush_login]}"
    CFG_VSCODE_EXTENSIONS="${CONTAINER_DEFAULTS[vscode_extensions]}"
    CFG_MOUNT_GPG="${CONTAINER_DEFAULTS[mount_gpg]}"
    CFG_MOUNT_GH_CONFIG="${CONTAINER_DEFAULTS[mount_gh_config]}"
    CFG_MOUNT_DOCKER_SOCKET="${CONTAINER_DEFAULTS[mount_docker_socket]}"
    CFG_INSTALL_GH_CLI="${CONTAINER_DEFAULTS[install_gh_cli]}"
    CFG_INSTALL_DEV_CONTROL="${CONTAINER_DEFAULTS[install_git_control]}"
    CFG_DEV_CONTROL_VERSION="${CONTAINER_DEFAULTS[git_control_version]}"
    
    # Load global config if exists
    if [[ -f "$DC_CONTAINER_CONFIG" ]]; then
        parse_container_yaml "$DC_CONTAINER_CONFIG"
    fi
    
    # Load project config if exists
    if [[ -n "$PROJECT_PATH" && -f "$PROJECT_PATH/$DC_PROJECT_CONTAINER_CONFIG" ]]; then
        parse_container_yaml "$PROJECT_PATH/$DC_PROJECT_CONTAINER_CONFIG"
    fi
    
    # Load explicit config file if provided
    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
        parse_container_yaml "$CONFIG_FILE"
    fi
    
    # Set container name to folder name if not specified
    if [[ -z "$CFG_CONTAINER_NAME" && -n "$PROJECT_PATH" ]]; then
        CFG_CONTAINER_NAME=$(basename "$PROJECT_PATH")
    fi
}

# Save configuration to file
save_container_config() {
    local file="$1"
    local dir
    dir=$(dirname "$file")
    
    mkdir -p "$dir"
    
    cat > "$file" << EOF
# Dev-Control container configuration
# Generated by containerise.sh on $(date +%Y-%m-%d)
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

# User & Project Identification
container-name: ${CFG_CONTAINER_NAME}
github-user: ${CFG_GITHUB_USER}
github-user-email: ${CFG_GITHUB_USER_EMAIL}
gpg-key-id: ${CFG_GPG_KEY_ID}

# System Locale & Timezone
timezone: ${CFG_TIMEZONE}
locale: ${CFG_LOCALE}

# Ubuntu Mirror
ubuntu-mirror: ${CFG_UBUNTU_MIRROR}

# Docker Base Image
base-image: ${CFG_BASE_IMAGE}
hush-login: ${CFG_HUSH_LOGIN}

# VS Code Extensions
vscode-extensions: ${CFG_VSCODE_EXTENSIONS}

# Mount Points
mount-gpg: ${CFG_MOUNT_GPG}
mount-gh-config: ${CFG_MOUNT_GH_CONFIG}
mount-docker-socket: ${CFG_MOUNT_DOCKER_SOCKET}

# Additional Features
install-gh-cli: ${CFG_INSTALL_GH_CLI}
install-dev-control: ${CFG_INSTALL_DEV_CONTROL}
dev-control-version: ${CFG_DEV_CONTROL_VERSION}
EOF

    print_success "Configuration saved to: $file"
}

################################################################################
# CLI Argument Parsing
################################################################################

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                SHOW_HELP=true
                shift
                ;;
            -d|--defaults)
                USE_DEFAULTS=true
                shift
                ;;
            -c|--config)
                if [[ -n "${2:-}" && "$2" != -* ]]; then
                    CONFIG_FILE="$2"
                    shift 2
                else
                    print_error "--config requires a file path"
                    exit 1
                fi
                ;;
            -*)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                # Positional argument = project path
                if [[ -z "$PROJECT_PATH" ]]; then
                    PROJECT_PATH="$1"
                fi
                shift
                ;;
        esac
    done
}

################################################################################
# Interactive Configuration
################################################################################

# Numbered selection menu
select_from_list() {
    local prompt="$1"
    local default="$2"
    shift 2
    local options=("$@")
    local choice
    local i=1
    
    # Send UI output to stderr so it's not captured by command substitution
    echo "" >&2
    echo -e "${BOLD}$prompt${NC}" >&2
    for opt in "${options[@]}"; do
        if [[ "$opt" == "$default" ]]; then
            echo -e "  ${CYAN}${i})${NC} $opt ${GREEN}(default)${NC}" >&2
        else
            echo -e "  ${CYAN}${i})${NC} $opt" >&2
        fi
        ((i++))
    done
    echo -e "  ${CYAN}${i})${NC} ${DIM}Custom value...${NC}" >&2
    
    read -rp "Select [1-$i] or press Enter for default: " choice
    
    if [[ -z "$choice" ]]; then
        echo "$default"
        return
    fi
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
        echo "${options[$((choice-1))]}"
    elif [[ "$choice" == "$i" ]] || [[ "$choice" == "c" ]] || [[ "$choice" == "C" ]]; then
        read -rp "Enter custom value: " custom
        echo "$custom"
    else
        # Treat as custom input
        echo "$choice"
    fi
}

# Mirror selection (key-value based)
select_mirror() {
    local default="$1"
    local choice
    local i=1
    local keys=()
    
    # Send UI output to stderr so it's not captured by command substitution
    echo "" >&2
    echo -e "${BOLD}Select Ubuntu archive mirror:${NC}" >&2
    for key in "${!UBUNTU_MIRRORS[@]}"; do
        keys+=("$key")
        local url="${UBUNTU_MIRRORS[$key]}"
        if [[ "$url" == "$default" ]]; then
            echo -e "  ${CYAN}${i})${NC} $key ${GREEN}(default)${NC}" >&2
        else
            echo -e "  ${CYAN}${i})${NC} $key" >&2
        fi
        ((i++))
    done
    echo -e "  ${CYAN}${i})${NC} ${DIM}Custom URL...${NC}" >&2
    
    read -rp "Select [1-$i] or press Enter for default: " choice
    
    if [[ -z "$choice" ]]; then
        echo "$default"
        return
    fi
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#keys[@]} )); then
        echo "${UBUNTU_MIRRORS[${keys[$((choice-1))]}]}"
    elif [[ "$choice" == "$i" ]]; then
        read -rp "Enter custom mirror URL: " custom
        echo "$custom"
    else
        echo "$default"
    fi
}

# Interactive configuration prompts
run_interactive_config() {
    print_header "Container Configuration"
    
    echo -e "${DIM}Press Enter to accept default values shown in green${NC}"
    
    # Container/User name
    local default_name
    default_name=$(basename "$PROJECT_PATH")
    if [[ -n "$CFG_CONTAINER_NAME" ]]; then
        default_name="$CFG_CONTAINER_NAME"
    fi
    echo ""
    echo -e "${BOLD}Container/User name:${NC}"
    echo -e "  ${DIM}Used for container name, user account, and project reference${NC}"
    read -rp "Name [$default_name]: " input
    CFG_CONTAINER_NAME="${input:-$default_name}"
    
    # GitHub user
    echo ""
    echo -e "${BOLD}GitHub username/organisation:${NC}"
    local gh_default="${CFG_GITHUB_USER:-$(git config --get user.name 2>/dev/null || echo "")}"
    read -rp "GitHub user [$gh_default]: " input
    CFG_GITHUB_USER="${input:-$gh_default}"
    
    # GPG key
    echo ""
    echo -e "${BOLD}GPG signing key ID:${NC}"
    echo -e "  ${DIM}For commit signing (leave empty to disable)${NC}"
    local gpg_default="${CFG_GPG_KEY_ID:-$(git config --get user.signingkey 2>/dev/null || echo "")}"
    if [[ -n "$gpg_default" ]]; then
        read -rp "GPG key ID [$gpg_default]: " input
        CFG_GPG_KEY_ID="${input:-$gpg_default}"
    else
        read -rp "GPG key ID (optional): " CFG_GPG_KEY_ID
    fi
    
    # Base image
    CFG_BASE_IMAGE=$(select_from_list "Select base Docker image:" "$CFG_BASE_IMAGE" "${BASE_IMAGES[@]}")
    
    # Timezone
    CFG_TIMEZONE=$(select_from_list "Select timezone:" "$CFG_TIMEZONE" "${TIMEZONES[@]}")
    
    # Locale
    CFG_LOCALE=$(select_from_list "Select locale:" "$CFG_LOCALE" "${LOCALES[@]}")
    
    # Mirror
    CFG_UBUNTU_MIRROR=$(select_mirror "$CFG_UBUNTU_MIRROR")
    
    # Show summary
    echo ""
    print_separator
    echo -e "${BOLD}Configuration Summary:${NC}"
    print_kv "Container name" "$CFG_CONTAINER_NAME"
    print_kv "GitHub user" "$CFG_GITHUB_USER"
    print_kv "GPG key" "${CFG_GPG_KEY_ID:-none}"
    print_kv "Base image" "$CFG_BASE_IMAGE"
    print_kv "Timezone" "$CFG_TIMEZONE"
    print_kv "Locale" "$CFG_LOCALE"
    print_kv "Ubuntu mirror" "$CFG_UBUNTU_MIRROR"
    print_separator
    
    # Offer to save as defaults
    echo ""
    if confirm "Save these settings as global defaults?"; then
        save_container_config "$DC_CONTAINER_CONFIG"
    fi
}

################################################################################
# Detection Functions
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
    
    # Initialise rootless podman
    podman system migrate 2>/dev/null || true
    
    print_success "Rootless podman installed and configured"
}

################################################################################
# File Generation
################################################################################

# Generate .dockerignore
generate_dockerignore() {
    local devcontainer_dir="$1"
    local dockerignore_file="$devcontainer_dir/.dockerignore"
    
    cat > "$dockerignore_file" << 'DOCKERIGNORE_EOF'
# Git
.git/
.gitignore

# VS Code
.vscode/
*.code-workspace

# IDE/Editor
.idea/
*.swp
*.swo
*~

# Build artifacts
builds/
export/
dist/
build/
node_modules/
__pycache__/
*.pyc
*.pyo
.cache/
.npm/
.yarn/

# OS generated files
.DS_Store
Thumbs.db

# Environment/secrets
.env
.env.local
.env.*.local

# Temporary files
*.tmp
*.log
logs/

# Test coverage
coverage/
.coverage
htmlcov/

# Project-specific
.tmp/
.bak/
DOCKERIGNORE_EOF

    print_success "Created: $dockerignore_file"
}

# Generate Dockerfile
generate_dockerfile() {
    local devcontainer_dir="$1"
    local dockerfile_path="$devcontainer_dir/Dockerfile"
    
    # Determine if we need to customise a base ubuntu image
    local is_ubuntu_base=false
    if [[ "$CFG_BASE_IMAGE" == ubuntu:* ]]; then
        is_ubuntu_base=true
    fi
    
    cat > "$dockerfile_path" << DOCKERFILE_EOF
FROM ${CFG_BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive
DOCKERFILE_EOF

    # For Ubuntu base images, add full customisation
    if [[ "$is_ubuntu_base" == true ]]; then
        cat >> "$dockerfile_path" << DOCKERFILE_EOF

# Install tool development tools and dependencies
RUN apt-get update && apt-get upgrade -y && apt-get install -y \\
    git \\
    build-essential \\
    sudo \\
    locales \\
    lsb-release \\
    curl \\
    ca-certificates \\
    gnupg \\
    libsecret-tools \\
    nano \\
    && sed -i 's|http://archive.ubuntu.com/ubuntu|${CFG_UBUNTU_MIRROR}|g' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || \\
       sed -i 's|http://archive.ubuntu.com/ubuntu|${CFG_UBUNTU_MIRROR}|g' /etc/apt/sources.list 2>/dev/null || true \\
    && sed -i '/${CFG_LOCALE%.*}/s/^# //g' /etc/locale.gen \\
    && locale-gen ${CFG_LOCALE} \\
    && update-locale LANG=${CFG_LOCALE} LC_ALL=${CFG_LOCALE} \\
    && rm -rf /var/lib/apt/lists/*

# Set locale and timezone
ENV LANG=${CFG_LOCALE} \\
    LC_ALL=${CFG_LOCALE} \\
    TZ=${CFG_TIMEZONE} \\
    EDITOR=nano

# Configure timezone
RUN ln -snf /usr/share/zoneinfo/\${TZ} /etc/localtime && echo \${TZ} > /etc/timezone
DOCKERFILE_EOF

        # Add GitHub CLI installation if enabled
        if [[ "$CFG_INSTALL_GH_CLI" == "true" ]]; then
            cat >> "$dockerfile_path" << 'DOCKERFILE_EOF'

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*
DOCKERFILE_EOF
        fi

        cat >> "$dockerfile_path" << DOCKERFILE_EOF

# Create user ${CFG_CONTAINER_NAME} with sudo privileges
RUN if id ubuntu &>/dev/null; then \\
        # Rename ubuntu user and ensure home exists
        groupmod -n ${CFG_CONTAINER_NAME} ubuntu && \\
        usermod -l ${CFG_CONTAINER_NAME} -d /home/${CFG_CONTAINER_NAME} ubuntu && \\
        if [ ! -d /home/${CFG_CONTAINER_NAME} ]; then mkdir -p /home/${CFG_CONTAINER_NAME}; fi && \\
        if [ -d /home/ubuntu ] && [ ! -d /home/${CFG_CONTAINER_NAME} ]; then \\
            mv /home/ubuntu /home/${CFG_CONTAINER_NAME}; \\
        fi; \\
    else \\
        useradd -m -s /bin/bash ${CFG_CONTAINER_NAME}; \\
    fi && \\
    usermod -aG sudo ${CFG_CONTAINER_NAME} && \\
    echo "${CFG_CONTAINER_NAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \\
    mkdir -p /home/${CFG_CONTAINER_NAME}/.config /home/${CFG_CONTAINER_NAME}/.cache /home/${CFG_CONTAINER_NAME}/.local/share && \\
    chown -R ${CFG_CONTAINER_NAME}:${CFG_CONTAINER_NAME} /home/${CFG_CONTAINER_NAME}

USER ${CFG_CONTAINER_NAME}
WORKDIR /home/${CFG_CONTAINER_NAME}
DOCKERFILE_EOF

        # Add hush login if enabled
        if [[ "$CFG_HUSH_LOGIN" == "true" ]]; then
            cat >> "$dockerfile_path" << DOCKERFILE_EOF

RUN touch ~/.hushlogin
DOCKERFILE_EOF
        fi

        # Add nvm, Node.js, and Dev-Control installation if enabled
        if [[ "$CFG_INSTALL_DEV_CONTROL" == "true" ]]; then
            cat >> "$dockerfile_path" << DOCKERFILE_EOF

# Install nvm, Node.js, and Dev-Control
ENV NVM_DIR=/home/${CFG_CONTAINER_NAME}/.config/nvm
ENV BASH_ENV=/home/${CFG_CONTAINER_NAME}/.bashrc
RUN mkdir -p "\$NVM_DIR" && \\
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash && \\
    echo 'export NVM_DIR="\$HOME/.config/nvm"' >> ~/.bashrc && \\
    echo '[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"' >> ~/.bashrc && \\
    bash -c 'source \$NVM_DIR/nvm.sh && nvm install 25 && nvm alias default 25' && \\
    curl -fsSL https://github.com/${CFG_GITHUB_USER}/dev-control/archive/refs/tags/latest.tar.gz | tar -xz && \\
    mv dev-control-* ~/.dev-control && \\
    bash -c 'bash ~/.dev-control/scripts/alias-loading.sh <<< A'

# Add node/npm/npx to PATH for VS Code extension host discovery
ENV PATH=\$NVM_DIR/versions/node/v25.4.0/bin:\$PATH
DOCKERFILE_EOF
        fi

        # Add git configuration if user provided
        if [[ -n "$CFG_GITHUB_USER" && -n "$CFG_GITHUB_USER_EMAIL" ]]; then
            local git_config_cmd="git config --global user.email ${CFG_GITHUB_USER_EMAIL} && \\\n    git config --global user.name ${CFG_GITHUB_USER} && \\\n    git config --global init.defaultBranch main"
            
            # Add GPG config if key provided
            if [[ -n "$CFG_GPG_KEY_ID" ]]; then
                git_config_cmd="$git_config_cmd && \\\n    git config --global commit.gpgsign true && \\\n    git config --global user.signingkey ${CFG_GPG_KEY_ID} && \\\n    git config --global gpg.program gpg"
            fi
            
            cat >> "$dockerfile_path" << DOCKERFILE_EOF

# Bake user-specific git config into image
RUN $git_config_cmd
DOCKERFILE_EOF
        fi

        cat >> "$dockerfile_path" << DOCKERFILE_EOF

WORKDIR /workspaces
DOCKERFILE_EOF

    else
        # For devcontainer images, minimal customisation
        cat >> "$dockerfile_path" << DOCKERFILE_EOF

# Set timezone
ENV TZ=${CFG_TIMEZONE}
RUN ln -snf /usr/share/zoneinfo/\${TZ} /etc/localtime && echo \${TZ} > /etc/timezone 2>/dev/null || true
DOCKERFILE_EOF
    fi

    print_success "Created: $dockerfile_path"
}

# Generate devcontainer.json
generate_devcontainer_json() {
    local devcontainer_dir="$1"
    local devcontainer_file="$devcontainer_dir/devcontainer.json"
    local project_name
    project_name=$(basename "$PROJECT_PATH")
    
    # Build mounts array
    local mounts=""
    local uid
    uid=$(id -u)
    
    if [[ "$CFG_MOUNT_GPG" == "true" ]]; then
        mounts+="\"source=/run/user/${uid}/gnupg/S.gpg-agent,target=/run/user/${uid}/gnupg/S.gpg-agent,type=bind\""
    fi
    
    if [[ "$CFG_MOUNT_DOCKER_SOCKET" == "true" ]]; then
        if [[ -n "$mounts" ]]; then mounts+=","; fi
        mounts+="\"source=/run/user/${uid}/podman/podman.sock,target=/var/run/docker.sock,type=bind\""
    fi
    
    if [[ "$CFG_MOUNT_GH_CONFIG" == "true" ]]; then
        if [[ -n "$mounts" ]]; then mounts+=","; fi
        mounts+="\"source=\${localEnv:HOME}/.config/gh,target=/home/${CFG_CONTAINER_NAME}/.config/gh,type=bind,consistency=cached\""
    fi
    
    # Build extensions array
    local extensions=""
    IFS=',' read -ra ext_array <<< "$CFG_VSCODE_EXTENSIONS"
    for ext in "${ext_array[@]}"; do
        if [[ -n "$extensions" ]]; then extensions+=","; fi
        extensions+="\"${ext}\""
    done
    
    # Determine remote user based on image type
    local remote_user="$CFG_CONTAINER_NAME"
    if [[ "$CFG_BASE_IMAGE" == mcr.microsoft.com/* ]]; then
        remote_user="vscode"
    fi
    
    cat > "$devcontainer_file" << DEVCONTAINER_EOF
{
  "name": "${project_name^^}",
  "build": {
    "dockerfile": "Dockerfile"
  },
  "remoteUser": "${remote_user}",
  "workspaceFolder": "/workspaces/${project_name}",
  "mounts": [
    ${mounts}
  ],
  "containerEnv": {
    "GPG_TTY": "\$(tty)",
    "DOCKER_HOST": "unix:///var/run/docker.sock",
    "DISPLAY": "\${localEnv:DISPLAY}",
    "TZ": "${CFG_TIMEZONE}"
  },
  "postCreateCommand": "git config --global --add safe.directory '*' && gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true",
  "customizations": {
    "vscode": {
      "settings": {
        "terminal.integrated.cwd": "/workspaces/${project_name}",
        "git.enableSmartCommit": true,
        "git.autofetch": true
      },
      "extensions": [
        ${extensions}
      ]
    }
  }
}
DEVCONTAINER_EOF

    print_success "Created: $devcontainer_file"
}

# Generate all devcontainer files
generate_devcontainer() {
    local devcontainer_dir="$PROJECT_PATH/.devcontainer"
    
    print_info "Generating devcontainer configuration..."
    
    mkdir -p "$devcontainer_dir"
    
    generate_dockerignore "$devcontainer_dir"
    generate_dockerfile "$devcontainer_dir"
    generate_devcontainer_json "$devcontainer_dir"
}

################################################################################
# Output
################################################################################

show_activation_instructions() {
    print_header_success "Containerisation Complete!"
    
    print_section "Generated Files:"
    print_list_item ".devcontainer/devcontainer.json"
    print_list_item ".devcontainer/Dockerfile"
    print_list_item ".devcontainer/.dockerignore"
    echo ""
    
    print_section "Configuration:"
    print_kv "Container name" "$CFG_CONTAINER_NAME" 20
    print_kv "Base image" "$CFG_BASE_IMAGE" 20
    print_kv "Timezone" "$CFG_TIMEZONE" 20
    print_kv "Locale" "$CFG_LOCALE" 20
    echo ""
    
    print_section "Next Steps:"
    echo -e "  1. Open the project in VS Code: ${GREEN}code $PROJECT_PATH${NC}"
    echo -e "  2. Press ${CYAN}F1${NC} and run: ${CYAN}Dev Containers: Reopen in Container${NC}"
    echo ""
    
    print_section "Alternative:"
    echo -e "  Use the Remote-Containers icon in the bottom-left corner"
    echo ""
    
    print_section "One-Click Mode:"
    echo -e "  Next time, run: ${GREEN}dc-container --defaults${NC}"
    echo ""
}

################################################################################
# Main
################################################################################

main() {
    # Parse arguments
    parse_args "$@"
    
    # Show help if requested
    if [[ "$SHOW_HELP" == true ]]; then
        show_help
        exit 0
    fi
    
    print_header "Dev-Control Containerisation"
    
    # Check if already in devcontainer
    if is_in_devcontainer; then
        print_warning "Already running inside a devcontainer"
        print_info "This script is meant to be run on the host machine"
        exit 0
    fi
    
    # Detect project path
    detect_project_path "$PROJECT_PATH"
    
    # Load configuration
    load_container_config
    
    # Run interactive config unless using defaults
    if [[ "$USE_DEFAULTS" != true ]]; then
        run_interactive_config
    else
        print_info "Using saved defaults from configuration"
        # Ensure container name is set
        if [[ -z "$CFG_CONTAINER_NAME" ]]; then
            CFG_CONTAINER_NAME=$(basename "$PROJECT_PATH")
        fi
    fi
    
    # Check/install podman (optional)
    if ! check_podman; then
        if confirm "Install rootless podman?"; then
            install_rootless_podman
        else
            print_warning "Continuing without podman verification"
        fi
    fi
    
    # Generate devcontainer
    if [[ -d "$PROJECT_PATH/.devcontainer" ]]; then
        if confirm "Devcontainer directory exists. Overwrite?"; then
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
