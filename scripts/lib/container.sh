#!/usr/bin/env bash
#
# Dev-Control Shared Library: Container Utilities
# Reusable functions for container configuration, detection, and generation
#
# Usage:
#   source "${SCRIPT_DIR}/lib/container.sh"
#
# Dependencies:
#   - lib/colours.sh (must be sourced first)
#   - lib/print.sh (must be sourced first)
#   - lib/validation.sh (must be sourced first)
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# ============================================================================
# CONFIGURATION DEFAULTS
# ============================================================================

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
    ["use_base_category"]="false"
    ["base_category"]=""
    ["timezone"]="UTC"
    ["locale"]="en_US.UTF-8"
    ["ubuntu_mirror"]="http://archive.ubuntu.com/ubuntu"
    ["base_image"]="ubuntu:latest"
    ["hush_login"]="true"
    ["vscode_extensions"]="github.copilot,github.copilot-chat"
    ["mount_gpg"]="true"
    ["mount_gh_config"]="true"
    ["mount_docker_socket"]="true"
    ["mount_wrangler"]="false"
    ["install_gh_cli"]="true"
    ["install_git_control"]="true"
    ["git_control_version"]="latest"
    # Streaming/CUDA features
    ["install_cuda"]="false"
    ["install_ffmpeg"]="false"
    ["install_nginx_rtmp"]="false"
    ["install_streaming_utils"]="false"
    ["enable_nvidia_devices"]="false"
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

# Category data (populated by load_categories from categories.yaml)
declare -A BASE_IMAGE_CATEGORIES
declare -A CATEGORY_FEATURES
declare -A CATEGORY_EXTENSIONS
declare -A CATEGORY_GITHUB_PATHS
declare -A CATEGORY_NVIDIA

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

# ============================================================================
# CATEGORY LOADING
# ============================================================================

# Parse categories.yaml and populate associative arrays
# Handles 2-level YAML: category header (no indent) + fields (indented)
load_categories() {
    local categories_file="${DEV_CONTROL_DIR}/config/containers/categories.yaml"
    [[ ! -f "$categories_file" ]] && {
        print_warning "Categories file not found: $categories_file"
        return 1
    }

    local line current_category="" field value

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        # Category header (no indentation, ends with colon only)
        if [[ "$line" =~ ^([a-zA-Z][a-zA-Z0-9_-]*):[[:space:]]*$ ]]; then
            current_category="${BASH_REMATCH[1]}"
            continue
        fi

        # Field within category (indented)
        if [[ -n "$current_category" && "$line" =~ ^[[:space:]]+([a-zA-Z][a-zA-Z0-9_-]*):[[:space:]]*(.*) ]]; then
            field="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            value="${value#\"}" ; value="${value%\"}"
            value="${value#\'}"; value="${value%\'}"

            case "$field" in
                image)       BASE_IMAGE_CATEGORIES["$current_category"]="$value" ;;
                features)    CATEGORY_FEATURES["$current_category"]="$value" ;;
                extensions)  CATEGORY_EXTENSIONS["$current_category"]="$value" ;;
                github-path) CATEGORY_GITHUB_PATHS["$current_category"]="$value" ;;
                nvidia)      CATEGORY_NVIDIA["$current_category"]="$value" ;;
            esac
        fi
    done < "$categories_file"
}

# ============================================================================
# YAML CONFIGURATION PARSING
# ============================================================================

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
                use_base_category) CFG_USE_BASE_CATEGORY="$value" ;;
                base_category)    CFG_BASE_CATEGORY="$value" ;;
                base_image)       CFG_BASE_IMAGE="$value" ;;
                hush_login)       CFG_HUSH_LOGIN="$value" ;;
                vscode_extensions) CFG_VSCODE_EXTENSIONS="$value" ;;
                mount_gpg)        CFG_MOUNT_GPG="$value" ;;
                mount_gh_config)  CFG_MOUNT_GH_CONFIG="$value" ;;
                mount_docker_socket) CFG_MOUNT_DOCKER_SOCKET="$value" ;;
                mount_wrangler)   CFG_MOUNT_WRANGLER="$value" ;;
                install_gh_cli)   CFG_INSTALL_GH_CLI="$value" ;;
                install_git_control|install_dev_control) CFG_INSTALL_DEV_CONTROL="$value" ;;
                git_control_version|dev_control_version) CFG_DEV_CONTROL_VERSION="$value" ;;
                # Streaming/CUDA features
                install_cuda)     CFG_INSTALL_CUDA="$value" ;;
                install_ffmpeg)   CFG_INSTALL_FFMPEG="$value" ;;
                install_nginx_rtmp) CFG_INSTALL_NGINX_RTMP="$value" ;;
                install_streaming_utils) CFG_INSTALL_STREAMING_UTILS="$value" ;;
                enable_nvidia_devices) CFG_ENABLE_NVIDIA_DEVICES="$value" ;;
            esac
        fi
    done < "$file"
}

# Load configuration from all sources
load_container_config() {
    # Start with defaults
    CFG_GITHUB_USER="${CONTAINER_DEFAULTS[github_user]}"
    CFG_GITHUB_USER_EMAIL="${CONTAINER_DEFAULTS[github_user_email]}"
    CFG_GPG_KEY_ID="${CONTAINER_DEFAULTS[gpg_key_id]}"
    CFG_TIMEZONE="${CONTAINER_DEFAULTS[timezone]}"
    CFG_LOCALE="${CONTAINER_DEFAULTS[locale]}"
    CFG_USE_BASE_CATEGORY="${CONTAINER_DEFAULTS[use_base_category]}"
    CFG_BASE_CATEGORY="${CONTAINER_DEFAULTS[base_category]}"
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
    CFG_MOUNT_WRANGLER="${CONTAINER_DEFAULTS[mount_wrangler]}"
    # Streaming/CUDA features
    CFG_INSTALL_CUDA="${CONTAINER_DEFAULTS[install_cuda]}"
    CFG_INSTALL_FFMPEG="${CONTAINER_DEFAULTS[install_ffmpeg]}"
    CFG_INSTALL_NGINX_RTMP="${CONTAINER_DEFAULTS[install_nginx_rtmp]}"
    CFG_INSTALL_STREAMING_UTILS="${CONTAINER_DEFAULTS[install_streaming_utils]}"
    CFG_ENABLE_NVIDIA_DEVICES="${CONTAINER_DEFAULTS[enable_nvidia_devices]}"

    # Load global config if exists
    if [[ -f "$DC_CONTAINER_CONFIG" ]]; then
        parse_container_yaml "$DC_CONTAINER_CONFIG"
    fi

    # Load project config if exists
    if [[ -n "$PROJECT_PATH" && -f "$PROJECT_PATH/$DC_PROJECT_CONTAINER_CONFIG" ]]; then
        parse_container_yaml "$PROJECT_PATH/$DC_PROJECT_CONTAINER_CONFIG"
    fi

    # Load explicit config file if provided
    if [[ -n "${CONFIG_FILE:-}" && -f "${CONFIG_FILE:-}" ]]; then
        parse_container_yaml "$CONFIG_FILE"
    fi

    # Set container name to folder name if not specified
    if [[ -z "${CFG_CONTAINER_NAME:-}" && -n "${PROJECT_PATH:-}" ]]; then
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
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

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
use-base-category: ${CFG_USE_BASE_CATEGORY}
base-category: ${CFG_BASE_CATEGORY}
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

# Mount Options
mount-wrangler: ${CFG_MOUNT_WRANGLER}

# Streaming/CUDA Features
install-cuda: ${CFG_INSTALL_CUDA}
install-ffmpeg: ${CFG_INSTALL_FFMPEG}
install-nginx-rtmp: ${CFG_INSTALL_NGINX_RTMP}
install-streaming-utils: ${CFG_INSTALL_STREAMING_UTILS}
enable-nvidia-devices: ${CFG_ENABLE_NVIDIA_DEVICES}
EOF

    print_success "Configuration saved to: $file"
}

# ============================================================================
# GIT CONFIGURATION FUNCTIONS
# ============================================================================

# Generate git config commands for Dockerfile RUN statements
# Args: user, email, gpg_key, [home_dir]
generate_git_config_dockerfile() {
    local user="$1"
    local email="$2"
    local gpg_key="$3"
    local home_dir="$4"  # Optional: if running as root for another user

    local home_prefix=""
    if [[ -n "$home_dir" ]]; then
        home_prefix="HOME=$home_dir "
    fi

    local config="${home_prefix}git config --global --add safe.directory '*' && ${home_prefix}git config --global init.defaultBranch main"

    if [[ -n "$user" && -n "$email" ]]; then
        config+=" && ${home_prefix}git config --global user.email $email && ${home_prefix}git config --global user.name $user"

        if [[ -n "$gpg_key" ]]; then
            config+=" && ${home_prefix}git config --global commit.gpgsign true && ${home_prefix}git config --global user.signingkey $gpg_key && ${home_prefix}git config --global gpg.program gpg"
        fi
    fi

    echo "$config"
}

# Generate git config commands for devcontainer.json postCreateCommand
# Args: user, email, gpg_key
generate_git_config_postcreate() {
    local user="$1"
    local email="$2"
    local gpg_key="$3"

    local config="git config --global --add safe.directory '*' && git config --global init.defaultBranch main"

    if [[ -n "$user" && -n "$email" ]]; then
        config+=" && git config --global user.email $email && git config --global user.name $user"

        if [[ -n "$gpg_key" ]]; then
            config+=" && git config --global commit.gpgsign true && git config --global user.signingkey $gpg_key && git config --global gpg.program gpg"
        fi
    fi

    echo "$config"
}

# ============================================================================
# DETECTION FUNCTIONS
# ============================================================================

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
    if podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null | grep  true; then
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
    sudo apt-get update q

    print_info "Installing podman..."
    sudo apt-get install -y podman uidmap slirp4netns fuse-overlayfs

    print_info "Configuring rootless podman..."

    # Enable user namespaces
    if [[ ! -f /etc/subuid ]] || ! grep  "^$(whoami):" /etc/subuid; then
        sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$(whoami)"
    fi

    # Initialise rootless podman
    podman system migrate 2>/dev/null || true

    print_success "Rootless podman installed and configured"
}

# ============================================================================
# INTERACTIVE SELECTION
# ============================================================================

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

# ============================================================================
# .GITIGNORE MANAGEMENT
# ============================================================================

# Add personal devcontainer files to project .gitignore
# Ensures generated Dockerfile and devcontainer.json (with personal config)
# are not committed, while _example and _minimal variants are tracked
add_devcontainer_to_gitignore() {
    local project_root="${1:-$PROJECT_PATH}"
    local gitignore="$project_root/.gitignore"

    # Entries to add
    local entries=(
        ".devcontainer/Dockerfile"
        ".devcontainer/devcontainer.json"
    )

    # Create .gitignore if it doesn't exist
    if [[ ! -f "$gitignore" ]]; then
        touch "$gitignore"
    fi

    local added=false
    for entry in "${entries[@]}"; do
        if ! grep -qxF "$entry" "$gitignore" 2>/dev/null; then
            # Add section header if first addition
            if [[ "$added" == false ]]; then
                echo "" >> "$gitignore"
                echo "# Personal devcontainer config (generated by containerise.sh)" >> "$gitignore"
                echo "# Use _example or _minimal variants as tracked references" >> "$gitignore"
                added=true
            fi
            echo "$entry" >> "$gitignore"
        fi
    done

    if [[ "$added" == true ]]; then
        print_info "Added personal devcontainer files to .gitignore"
    fi
}

# ============================================================================
# README GENERATION
# ============================================================================

# Write a devcontainer README with dev-control-specific instructions.
# Args: readme_file, category, type, base_image, image_tag, source, features, container_name
write_devcontainer_readme() {
    local readme_file="$1"
    local category="$2"
    local type="$3"
    local base_image="$4"
    local image_tag="$5"
    local source="$6"
    local features="$7"
    local container_name="$8"

    local example_category="$category"
    if [[ -z "$example_category" || "$example_category" == "custom" ]]; then
        example_category="art"
    fi

    local type_label="Custom"
    if [[ "$type" == "image" ]]; then
        type_label="Pre-built image"
    elif [[ "$type" == "build" ]]; then
        type_label="Build from Dockerfile"
    fi

    {
        echo "# Container Configuration"
        echo ""
        echo "## Metadata"
        echo "- **Category**: \`${category:-custom}\`"
        echo "- **Type**: \`${type_label}\`"
        if [[ -n "$container_name" ]]; then
            echo "- **Container Name**: \`${container_name}\`"
        fi
        echo ""
        echo "## Generated Instructions"
        echo ""
        echo "1. Download the latest dev-control release tag (latest):"
        echo ""
        echo "   \`gh release download latest --repo XAOSTECH/dev-control\`"
        echo ""
        echo "   Or download directly (no gh required):"
        echo ""
        echo "   https://github.com/XAOSTECH/dev-control/releases/tag/latest"
        echo ""
        echo "2. Load aliases (includes dc-contain):"
        echo ""
        echo "   \`source ./scripts/alias-loading.sh\`"
        echo ""
        echo "3. Build a base image (example):"
        echo ""
        echo "   \`dc-contain --base --${example_category} --defaults\`"
        echo "   \`dc-contain --base --${example_category}\`  # interactive config"
        echo ""
        echo "4. Run the script directly (same example):"
        echo ""
        echo "   \`./scripts/containerise.sh --base --${example_category} --defaults\`"
        echo ""
        if [[ "$type" == "image" ]]; then
            echo "5. Generate an image-based devcontainer (example):"
            echo ""
            echo "   \`dc-contain --img --${example_category}\`"
            echo ""
        fi
        echo "## About"
        echo ""
        if [[ "$type" == "image" ]]; then
            echo "This devcontainer uses a pre-built dev-control category image."
            [[ -n "$base_image" ]] && echo "**Base Image:** \`${base_image}\`"
            echo ""
            echo "This folder is generated from a base image. The usual flow is:"
            echo ""
            echo "- Build the base image in a parent folder"
            echo "- Then generate this image-based devcontainer using \`--img\`"
        elif [[ "$type" == "build" ]]; then
            echo "This devcontainer builds from the generated Dockerfile."
            [[ -n "$image_tag" ]] && echo "**Image tag:** \`${image_tag}\`"
        else
            echo "This devcontainer uses the project configuration and defaults."
        fi
        echo ""
        if [[ -n "$features" ]]; then
            echo "**Features:** ${features}"
            echo ""
        fi
        if [[ -n "$source" ]]; then
            echo "**Build source:** ${source}"
            echo ""
        fi
        echo "## Files"
        echo ""
        echo "- **devcontainer.json** - Your personal VS Code devcontainer configuration (gitignored)"
        echo "- **Dockerfile** - Your personal container image definition (gitignored)"
        echo "- **.dockerignore** - Files to exclude from build context"
        echo "- **README.md** - This file"
        echo "- **devcontainer_example.json** - Tracked reference with placeholder values"
        echo "- **Dockerfile_example** - Tracked reference Dockerfile"
        echo "- **devcontainer_minimal.json** - Tracked minimal configuration"
        echo "- **Dockerfile_minimal** - Tracked minimal Dockerfile"
        echo ""
        echo "## Usage"
        echo ""
        echo "1. Open this project in VS Code"
        echo "2. Press \`F1\` and run: \`Dev Containers: Reopen in Container\`"
        echo "3. The container will build and you'll work inside it"
        echo ""
        echo "## Customisation"
        echo ""
        echo "Edit \`devcontainer.json\` or \`Dockerfile\` to customise:"
        echo "- Installed tools and libraries"
        echo "- Environment variables"
        echo "- VSCode extensions"
        echo "- Mount points and volumes"
        echo ""
        echo "For more information, see the Dev Containers docs:"
        echo "https://code.visualstudio.com/docs/devcontainers/containers"
    } > "$readme_file"

    print_success "Created: $readme_file"
}
# ============================================================================
# CATEGORY DOCKERFILE GENERATION
# ============================================================================

# Generate complete Dockerfile for a category by concatenating templates
# Args: category, output_path
generate_category_dockerfile() {
    local category="$1"
    local output_path="$2"
    local containers_dir="$DEV_CONTROL_DIR/config/containers"
    
    # Validate category exists
    if [[ ! -f "$containers_dir/${category}.Dockerfile" ]]; then
        print_error "Unknown category: $category"
        return 1
    fi
    
    # Build git config command for footer template
    local git_config_cmd
    git_config_cmd=$(generate_git_config_dockerfile "$CFG_GITHUB_USER" "$CFG_GITHUB_USER_EMAIL" "$CFG_GPG_KEY_ID" "/home/${category}")
    
    # Escape & for sed (git config command contains &&)
    local git_config_cmd_escaped="${git_config_cmd//&/\\&}"
    
    # Get locale and timezone from config (with fallback defaults)
    local locale="${CFG_LOCALE:-en_US.UTF-8}"
    local timezone="${CFG_TIMEZONE:-UTC}"
    
    # Check if category needs video/render groups (streaming)
    local needs_device_groups=false
    [[ "$category" == "streaming" ]] && needs_device_groups=true
    
    # Concatenate: common + category-specific + optional groups + footer
    {
        # Common base layer (substitute locale and timezone variables)
        sed -e "s|\${LOCALE}|${locale}|g" \
            -e "s|\${TZ}|${timezone}|g" \
            "$containers_dir/common.Dockerfile"
        echo ""

        # Category-specific layer
        cat "$containers_dir/${category}.Dockerfile"
        echo ""
        
        # Add device groups if needed (before user creation)
        if [[ "$needs_device_groups" == true ]]; then
            cat << 'DOCKERFILE_GROUPS'
# ============================================================================
# Streaming: Create video and render groups for DRI/KMS device access
# ============================================================================

RUN groupadd -f -g 44 video && groupadd -f -g 109 render
DOCKERFILE_GROUPS
            echo ""
        fi
        
        # Common footer (user setup, dev-control)
        # Replace template variables: CATEGORY, GIT_CONFIG_CMD
        sed -e "s/\${CATEGORY}/${category}/g" \
            -e "s|\${GIT_CONFIG_CMD}|${git_config_cmd_escaped}|g" \
            "$containers_dir/footer.Dockerfile"
            
        # Add streaming-specific user group membership
        if [[ "$needs_device_groups" == true ]]; then
            echo ""
            cat << DOCKERFILE_STREAMING_GROUPS

# Add ${category} to video and render groups for DRI/KMS access
USER root
RUN usermod -aG video,render ${category}
USER ${category}
DOCKERFILE_STREAMING_GROUPS
        fi
        
    } > "$output_path"
    
    print_success "Generated category Dockerfile: $output_path"
}