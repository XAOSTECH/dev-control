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

# Base image categories - these ARE the base images you build/use
# Build from: https://github.com/xaostech/dev-control/tree/main/.devcontainer
declare -A BASE_IMAGE_CATEGORIES=(
    ["game-dev"]="devcontrol/game-dev:latest"     # Godot, Vulkan, SDL2, GLFW, CUDA
    ["art"]="devcontrol/art:latest"                # 2D/3D art tools: Krita, GIMP, Blender
    ["data-science"]="devcontrol/data-science:latest"  # CUDA, FFmpeg, video/data processing
    ["streaming"]="devcontrol/streaming:latest"    # FFmpeg+NVENC, NGINX-RTMP, ONNX Runtime
    ["web-dev"]="devcontrol/web-dev:latest"        # Node.js, npm, Cloudflare Workers
    ["dev-tools"]="devcontrol/dev-tools:latest"    # GCC, build-essential, compilers
)

# Category feature descriptions
declare -A CATEGORY_FEATURES=(
    ["game-dev"]="Godot 4.x, Vulkan SDK, SDL2, GLFW 3.4 (Wayland), CUDA 13.1"
    ["art"]="2D/3D art tools: Krita, GIMP, Inkscape, Blender, ImageMagick"
    ["data-science"]="CUDA 13.1, FFmpeg (NVENC/NVDEC), NVIDIA acceleration"
    ["streaming"]="FFmpeg (NVENC/NVDEC), NGINX-RTMP, SRT, ONNX Runtime GPU, YOLOv8"
    ["web-dev"]="Node.js 25 (nvm), npm, modern web frameworks, Wrangler, dev-control"
    ["dev-tools"]="GCC, build-essential, common compilers, general development"
)

# Category-specific VS Code extensions
declare -A CATEGORY_EXTENSIONS=(
    ["game-dev"]="GodotTools.godot-tools ms-vscode.cpptools"
    ["art"]=""
    ["data-science"]="ms-python.python ms-toolsai.jupyter ms-python.vscode-pylance"
    ["streaming"]="ms-vscode.cpptools ms-python.python"
    ["web-dev"]="dbaeumer.vscode-eslint esbenp.prettier-vscode"
    ["dev-tools"]="ms-vscode.cpptools ms-python.python"
)

# GitHub build source references (for documentation)
declare -A CATEGORY_GITHUB_PATHS=(
    ["game-dev"]="https://github.com/xaostech/dev-control/tree/main/.devcontainer/game-dev"
    ["art"]="https://github.com/xaostech/dev-control/tree/main/.devcontainer/art"
    ["data-science"]="https://github.com/xaostech/dev-control/tree/main/.devcontainer/data-science"
    ["streaming"]="https://github.com/xaostech/dev-control/tree/main/.devcontainer/streaming"
    ["web-dev"]="https://github.com/xaostech/dev-control/tree/main/.devcontainer/web-dev"
    ["dev-tools"]="https://github.com/xaostech/dev-control/tree/main/.devcontainer/dev-tools"
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
MODE=""  # "base" or "image"
CATEGORY_FLAG=""
USE_DEFAULTS=false
CONFIG_FILE=""
PROJECT_PATH=""
SHOW_HELP=false
NEST_MODE=false

################################################################################
# Help
################################################################################

show_help() {
    cat << 'EOF'
Dev-Control Containerisation - Build base images or generate devcontainers

USAGE:
  containerise.sh --base --CATEGORY     # Build a base image
  containerise.sh --img --CATEGORY      # Generate devcontainer using base image
  containerise.sh [PROJECT_PATH]        # Interactive mode (legacy)

MODES:
  --base    Build a category base image (e.g., devcontrol/game-dev:latest)
  --img     Generate devcontainer.json that uses a category base image
  --nest    Recursively rebuild all base and img containers in subdirectories

CATEGORIES:
  --game-dev        Godot, Vulkan, SDL2, GLFW, CUDA
  --art             Krita, GIMP, Inkscape, Blender
  --data-science    CUDA, FFmpeg, NVIDIA acceleration
  --streaming       FFmpeg+NVENC, NGINX-RTMP, ONNX Runtime
  --web-dev         Node.js, npm, Cloudflare Workers
  --dev-tools       GCC, build-essential, compilers

EXAMPLES:
  # Build base images
  cd ~/.dev-control/.devcontainer && containerise.sh --base --game-dev
  cd ~/projects/streaming && containerise.sh --base --streaming

  # Generate devcontainers
  cd ~/projects/my-game && containerise.sh --img --game-dev
  cd ~/projects/web-app && containerise.sh --img --web-dev

  # Rebuild all containers in a project tree
  cd ~/PRO && containerise.sh --nest

OPTIONS:
  --help, -h          Show this help message

LEGACY MODE (interactive):
  containerise.sh [PROJECT_PATH]
  containerise.sh --defaults
  containerise.sh --config FILE

ALIASES:
  dc-contain, dc-containerise, dc-devcontainer

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
                mount_wrangler)   CFG_MOUNT_WRANGLER="$value" ;;
                install_gh_cli)   CFG_INSTALL_GH_CLI="$value" ;;
                install_git_control) CFG_INSTALL_DEV_CONTROL="$value" ;;
                git_control_version) CFG_DEV_CONTROL_VERSION="$value" ;;
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
            --base)
                MODE="base"
                shift
                ;;
            --img)
                MODE="image"
                shift
                ;;
            --nest)
                NEST_MODE=true
                USE_DEFAULTS=true
                shift
                ;;
            --game-dev|--art|--data-science|--streaming|--web-dev|--dev-tools)
                CATEGORY_FLAG="${1#--}"
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
    
    # Base image category or custom
    echo ""
    echo -e "${BOLD}Base Image Selection:${NC}"
    echo -e "  ${DIM}Choose a dev-control category (pre-built) or custom image${NC}"
    echo ""
    echo -e "  ${CYAN}Dev-Control Categories:${NC}"
    for category in "${!BASE_IMAGE_CATEGORIES[@]}"; do
        local image="${BASE_IMAGE_CATEGORIES[$category]}"
        local desc="${CATEGORY_FEATURES[$category]}"
        echo -e "    ${GREEN}$category${NC} → ${YELLOW}$image${NC}"
        echo -e "      ${DIM}$desc${NC}"
    done
    echo ""
    
    if confirm "Use a dev-control category image?"; then
        CFG_USE_BASE_CATEGORY="true"
        local categories=("${!BASE_IMAGE_CATEGORIES[@]}")
        echo ""
        echo -e "${BOLD}Select category:${NC}"
        select category in "${categories[@]}" "Custom image..."; do
            if [[ -n "$category" && "$category" != "Custom image..." ]]; then
                CFG_BASE_CATEGORY="$category"
                CFG_BASE_IMAGE="${BASE_IMAGE_CATEGORIES[$category]}"
                print_success "Selected: $category (${BASE_IMAGE_CATEGORIES[$category]})"
                break
            elif [[ "$category" == "Custom image..." ]]; then
                CFG_USE_BASE_CATEGORY="false"
                CFG_BASE_IMAGE=$(select_from_list "Select custom base Docker image:" "$CFG_BASE_IMAGE" "${BASE_IMAGES[@]}")
                break
            fi
        done
    else
        CFG_USE_BASE_CATEGORY="false"
        CFG_BASE_IMAGE=$(select_from_list "Select base Docker image:" "$CFG_BASE_IMAGE" "${BASE_IMAGES[@]}")
    fi
    
    # Timezone
    CFG_TIMEZONE=$(select_from_list "Select timezone:" "$CFG_TIMEZONE" "${TIMEZONES[@]}")
    
    # Locale
    CFG_LOCALE=$(select_from_list "Select locale:" "$CFG_LOCALE" "${LOCALES[@]}")
    
    # Mirror
    CFG_UBUNTU_MIRROR=$(select_mirror "$CFG_UBUNTU_MIRROR")
    
    # Streaming/CUDA features
    echo ""
    print_separator
    echo -e "${BOLD}Streaming & CUDA Features:${NC}"
    echo -e "  ${DIM}Enable these for video streaming, transcoding, and GPU-accelerated workflows${NC}"
    echo ""
    
    if confirm "Install CUDA Toolkit 13.1? (for GPU-accelerated compute)"; then
        CFG_INSTALL_CUDA="true"
        CFG_ENABLE_NVIDIA_DEVICES="true"
    fi
    
    if confirm "Install FFmpeg from source with NVENC/NVDEC? (requires CUDA)"; then
        CFG_INSTALL_FFMPEG="true"
        if [[ "$CFG_INSTALL_CUDA" != "true" ]]; then
            print_warning "Enabling CUDA automatically (required for FFmpeg NVENC/NVDEC)"
            CFG_INSTALL_CUDA="true"
            CFG_ENABLE_NVIDIA_DEVICES="true"
        fi
    fi
    
    if confirm "Install NGINX with RTMP module? (for streaming server)"; then
        CFG_INSTALL_NGINX_RTMP="true"
    fi
    
    if confirm "Install streaming utilities? (mediainfo, sox, v4l-utils, imagemagick)"; then
        CFG_INSTALL_STREAMING_UTILS="true"
    fi
    
    if confirm "Mount Cloudflare Wrangler config? (for Workers development)"; then
        CFG_MOUNT_WRANGLER="true"
    fi
    
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
    print_kv "CUDA 13.1" "${CFG_INSTALL_CUDA:-false}"
    print_kv "FFmpeg (NVENC)" "${CFG_INSTALL_FFMPEG:-false}"
    print_kv "NGINX-RTMP" "${CFG_INSTALL_NGINX_RTMP:-false}"
    print_kv "Streaming utils" "${CFG_INSTALL_STREAMING_UTILS:-false}"
    print_kv "NVIDIA devices" "${CFG_ENABLE_NVIDIA_DEVICES:-false}"
    print_kv "Wrangler mount" "${CFG_MOUNT_WRANGLER:-false}"
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

        # Add CUDA Toolkit if enabled
        if [[ "$CFG_INSTALL_CUDA" == "true" ]]; then
            cat >> "$dockerfile_path" << 'DOCKERFILE_EOF'

# Install CUDA Toolkit 13.1
RUN curl -fsSL --retry 5 --retry-delay 10 https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb -o /tmp/cuda-keyring.deb \
    && dpkg -i /tmp/cuda-keyring.deb && rm /tmp/cuda-keyring.deb \
    && apt-get update && apt-get install -y --no-install-recommends \
        cuda-toolkit-13-1 \
        cuda-nvcc-13-1 \
        cuda-libraries-dev-13-1 \
        cuda-cudart-dev-13-1 \
    && rm -rf /var/lib/apt/lists/*

ENV PATH=/usr/local/cuda-13.1/bin:$PATH \
    LD_LIBRARY_PATH=/usr/local/cuda-13.1/lib64:$LD_LIBRARY_PATH \
    CUDA_HOME=/usr/local/cuda-13.1
DOCKERFILE_EOF
        fi

        # Add FFmpeg from source with NVENC/NVDEC if enabled
        if [[ "$CFG_INSTALL_FFMPEG" == "true" ]]; then
            cat >> "$dockerfile_path" << 'DOCKERFILE_EOF'

# Install FFmpeg build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf automake cmake git-core libass-dev libfreetype6-dev \
    libgnutls28-dev libmp3lame-dev libtool libvorbis-dev meson ninja-build \
    pkg-config texinfo wget yasm zlib1g-dev nasm libx264-dev libx265-dev \
    libnuma-dev libvpx-dev libfdk-aac-dev libopus-dev libdav1d-dev \
    libaom-dev libwebp-dev libzmq3-dev librist-dev \
    && rm -rf /var/lib/apt/lists/*

# Build SRT from source (not in Ubuntu 24.04 repos)
RUN cd /tmp && git clone --depth 1 --branch v1.5.4 https://github.com/Haivision/srt.git \
    && cd srt && mkdir build && cd build \
    && cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local -DENABLE_SHARED=ON -DENABLE_STATIC=OFF \
    && make -j$(nproc) && make install && ldconfig \
    && cd / && rm -rf /tmp/srt

# Install nv-codec-headers for NVENC/NVDEC
RUN cd /tmp && git clone --depth 1 https://github.com/FFmpeg/nv-codec-headers.git \
    && cd nv-codec-headers && make install PREFIX=/usr/local \
    && cd / && rm -rf /tmp/nv-codec-headers

# Build FFmpeg from master with hardware acceleration
RUN cd /tmp && git clone --depth 1 https://github.com/FFmpeg/FFmpeg.git ffmpeg \
    && cd ffmpeg && ./configure \
        --prefix=/usr/local \
        --enable-gpl --enable-nonfree \
        --enable-libx264 --enable-libx265 --enable-libvpx \
        --enable-libfdk-aac --enable-libmp3lame --enable-libopus --enable-libvorbis \
        --enable-libass --enable-libfreetype --enable-libwebp \
        --enable-libaom --enable-libdav1d \
        --enable-libsrt --enable-librist --enable-libzmq \
        --enable-cuda-nvcc --enable-cuvid --enable-nvenc --enable-nvdec \
        --enable-ffnvcodec \
        --extra-cflags="-I/usr/local/cuda-13.1/include" \
        --extra-ldflags="-L/usr/local/cuda-13.1/lib64" \
    && make -j$(nproc) && make install && ldconfig \
    && cd / && rm -rf /tmp/ffmpeg
DOCKERFILE_EOF
        fi

        # Add NGINX with RTMP if enabled
        if [[ "$CFG_INSTALL_NGINX_RTMP" == "true" ]]; then
            cat >> "$dockerfile_path" << 'DOCKERFILE_EOF'

# Build NGINX with RTMP module (mainline 1.29.x with GPG verification)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpcre3-dev libssl-dev libgeoip-dev \
    && rm -rf /var/lib/apt/lists/* \
    && cd /tmp \
    && curl -fsSL --retry 5 --retry-delay 10 -o nginx.tar.gz https://nginx.org/download/nginx-1.29.0.tar.gz \
    && curl -fsSL --retry 5 --retry-delay 10 -o nginx.tar.gz.asc https://nginx.org/download/nginx-1.29.0.tar.gz.asc \
    && gpg --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys \
        B0F4253373F8F6F510D42178520A9993A1C052F8 \
        43387825DDB1BB97EC36BA5D007C8D7C15D87369 \
        D6786CE303D9A9022998DC6CC8464D549AF75C0A \
        13C82A63B603576156E30A4EA0EA981B66B0D967 \
        573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62 \
    && gpg --batch --verify nginx.tar.gz.asc nginx.tar.gz \
    && tar -xzf nginx.tar.gz \
    && git clone --depth 1 https://github.com/arut/nginx-rtmp-module.git \
    && cd nginx-1.29.0 \
    && ./configure --prefix=/usr/local/nginx \
        --with-http_ssl_module --with-http_v2_module --with-http_realip_module \
        --with-http_geoip_module --with-stream --with-stream_ssl_module \
        --add-module=../nginx-rtmp-module \
    && make -j$(nproc) && make install \
    && ln -s /usr/local/nginx/sbin/nginx /usr/local/bin/nginx \
    && cd / && rm -rf /tmp/nginx* /tmp/nginx-rtmp-module
DOCKERFILE_EOF
        fi

        # Add streaming utilities if enabled
        if [[ "$CFG_INSTALL_STREAMING_UTILS" == "true" ]]; then
            cat >> "$dockerfile_path" << 'DOCKERFILE_EOF'

# Install streaming utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    mediainfo \
    sox libsox-fmt-all \
    v4l-utils \
    imagemagick \
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
    curl -fsSL https://github.com/xaostech/dev-control/archive/refs/tags/latest.tar.gz | tar -xz && \\
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

        # Clean up build-time GPG keyring if packages used gpg --import
        # This prevents interference with the mounted host GPG agent socket
        if [[ "$CFG_INSTALL_NGINX_RTMP" == "true" ]]; then
            cat >> "$dockerfile_path" << 'DOCKERFILE_EOF'

# Clean up GPG keyring created during package verification (interferes with host GPG agent mount)
RUN rm -rf ~/.gnupg
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
    local use_image="${2:-}"  # Optional: image tag to use instead of building
    local category="${3:-}"   # Optional: category for header comments
    local devcontainer_file="$devcontainer_dir/devcontainer.json"
    local project_name
    project_name=$(basename "${PROJECT_PATH:-$(pwd)}")
    
    # Determine remote user FIRST (needed for mount paths)
    local remote_user
    if [[ -n "$use_image" || -n "$category" ]]; then
        # --img and --base modes: use category name (matches user in base image)
        remote_user="${category,,}"  # Force lowercase
    elif [[ "$CFG_BASE_IMAGE" == mcr.microsoft.com/* ]]; then
        remote_user="vscode"
    else
        # General mode: use folder name
        remote_user="$CFG_CONTAINER_NAME"
    fi
    
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
        mounts+="\"source=\${localEnv:HOME}/.config/gh,target=/home/${remote_user}/.config/gh,type=bind,consistency=cached\""
    fi
    
    if [[ "$CFG_MOUNT_WRANGLER" == "true" ]]; then
        if [[ -n "$mounts" ]]; then mounts+=","; fi
        mounts+="\"source=\${localEnv:HOME}/.config/.wrangler,target=/home/${remote_user}/.config/.wrangler,type=bind,consistency=cached\""
    fi
    
    # Add Wayland/X11 mounts for NVIDIA categories
    if [[ "$CFG_ENABLE_NVIDIA_DEVICES" == "true" ]]; then
        if [[ -n "$mounts" ]]; then mounts+=","; fi
        mounts+="\"source=\${localEnv:XDG_RUNTIME_DIR}/\${localEnv:WAYLAND_DISPLAY},target=/tmp/wayland-0,type=bind,readonly\","
        mounts+="\"source=/run/user/${uid}/wayland-0.lock,target=/tmp/wayland-0.lock,type=bind\","
        mounts+="\"source=/tmp/.X11-unix,target=/tmp/.X11-unix,type=bind\","
        mounts+="\"source=/usr/lib/x86_64-linux-gnu/libcuda.so.1,target=/usr/lib/x86_64-linux-gnu/libcuda.so.1,type=bind,readonly\","
        mounts+="\"source=/usr/lib/x86_64-linux-gnu/libnvcuvid.so.1,target=/usr/lib/x86_64-linux-gnu/libnvcuvid.so.1,type=bind,readonly\""
    fi
    
    # Build NVIDIA device mounts if enabled
    # Always include --userns=keep-id for rootless podman socket permission compatibility
    local run_args="\"--userns=keep-id\""
    if [[ "$CFG_ENABLE_NVIDIA_DEVICES" == "true" ]]; then
        run_args+=",\"--shm-size=1g\",\"--device=/dev/dri\",\"--device=/dev/nvidia0\",\"--device=/dev/nvidiactl\",\"--device=/dev/nvidia-modeset\",\"--device=/dev/nvidia-uvm\",\"--device=/dev/nvidia-uvm-tools\""
    fi
    
    # Build extensions array (default + category-specific)
    local extensions=""
    IFS=',' read -ra ext_array <<< "$CFG_VSCODE_EXTENSIONS"
    for ext in "${ext_array[@]}"; do
        if [[ -n "$extensions" ]]; then extensions+=","; fi
        extensions+="\"${ext}\""
    done
    
    # Add category-specific extensions if available
    if [[ -n "$category" && -n "${CATEGORY_EXTENSIONS[$category]}" ]]; then
        for ext in ${CATEGORY_EXTENSIONS[$category]}; do
            if [[ -n "$extensions" ]]; then extensions+=","; fi
            extensions+="\"${ext}\""
        done
    fi
    
    # Build container environment vars
    local container_env="\"GPG_TTY\": \"\$(tty)\",
    \"GPG_KEY_ID\": \"${CFG_GPG_KEY_ID}\",
    \"GITHUB_USER\": \"${CFG_GITHUB_USER}\",
    \"DOCKER_HOST\": \"unix:///var/run/docker.sock\",
    \"DISPLAY\": \"\${localEnv:DISPLAY}\",
    \"TZ\": \"${CFG_TIMEZONE}\""
    
    if [[ "$CFG_ENABLE_NVIDIA_DEVICES" == "true" ]]; then
        container_env+=",
    \"NVIDIA_VISIBLE_DEVICES\": \"all\",
    \"NVIDIA_DRIVER_CAPABILITIES\": \"compute,video,utility\",
    \"__NV_PRIME_RENDER_OFFLOAD\": \"1\",
    \"__GLX_VENDOR_LIBRARY_NAME\": \"nvidia\",
    \"WAYLAND_DISPLAY\": \"wayland-0\",
    \"XDG_RUNTIME_DIR\": \"/tmp\""
    fi
    
    # Build runArgs
    local run_args_block=""
    if [[ -n "$run_args" ]]; then
        run_args_block="\"runArgs\": [
    ${run_args}
  ],"
    fi
    
    # Add header comments for category images
    local header_comment=""
    local image_or_build=""
    
    if [[ -n "$use_image" ]]; then
        # Using pre-built image
        image_or_build="\"image\": \"$use_image\","
        if [[ -n "$category" ]]; then
            local github_ref="${CATEGORY_GITHUB_PATHS[$category]}"
            header_comment="  // ============================================================================
  // Category: $category
  // Base image: $use_image
  // ============================================================================
  // This devcontainer uses a pre-built dev-control category image.
  // 
  // Build source: $github_ref
  // Features: ${CATEGORY_FEATURES[$category]}
  // 
  // To build this base image locally:
  //   git clone https://github.com/xaostech/dev-control ~/.dev-control
  //   cd ~/.dev-control/.devcontainer/$category
  //   podman build -t $use_image .
  //
  // To use a local build instead of pulling from registry, ensure the image exists:
  //   podman images | grep ${use_image%%:*}
  // ============================================================================

"
        fi
    elif [[ -n "$category" ]]; then
        # Building from Dockerfile for a category
        image_or_build="\"build\": {
    \"dockerfile\": \"Dockerfile\"
  },"
        local image_tag="${BASE_IMAGE_CATEGORIES[$category]}"
        local github_ref="${CATEGORY_GITHUB_PATHS[$category]}"
        header_comment="  // ============================================================================
  // Category: $category
  // Image tag: $image_tag
  // ============================================================================
  // This devcontainer builds from the generated Dockerfile.
  // 
  // Build source: $github_ref
  // Features: ${CATEGORY_FEATURES[$category]}
  // 
  // After building, tag the image for reuse:
  //   podman tag \$(podman images  --filter \"label=devcontainer.local_folder=\$(pwd)\") $image_tag
  //
  // Then use --img --$category in other projects to reference this image.
  // ============================================================================

"
    else
        # Regular build mode
        image_or_build="\"build\": {
    \"dockerfile\": \"Dockerfile\"
  },"
    fi
    
    cat > "$devcontainer_file" << DEVCONTAINER_EOF
{
${header_comment}  "name": "${project_name^^}",
  ${image_or_build}
  "remoteUser": "${remote_user}",
  "workspaceMount": "source=\${localWorkspaceFolder},target=/workspaces/${project_name},type=bind,consistency=cached",
  "workspaceFolder": "/workspaces/${project_name}",
  ${run_args_block}
  "mounts": [
    ${mounts}
  ],
  "containerEnv": {
    ${container_env}
  },
  "postCreateCommand": "sudo chown -R ${remote_user}:${remote_user} . 2>/dev/null || true && sudo chmod 755 /home/${remote_user} 2>/dev/null || true && sudo chown -R ${remote_user}:${remote_user} /home/${remote_user}/.vscode-server 2>/dev/null || true && git config --global --add safe.directory '*' && sudo mkdir -p /run/user/${uid} && sudo chown ${remote_user}:${remote_user} /run/user/${uid} && ln -sf /tmp/wayland-0 /run/user/${uid}/wayland-0 2>/dev/null || true && gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true && sudo chown -R ${remote_user}:${remote_user} /run/user/${uid} 2>/dev/null || true",
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
# Base Image Building
################################################################################

# Generate Dockerfile for a category with all features baked in
generate_category_dockerfile() {
    local category="$1"
    local dockerfile_path="$2"
    
    cat > "$dockerfile_path" << 'DOCKERFILE_HEADER'
FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive

# Install core development tools and dependencies
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    git \
    build-essential \
    sudo \
    locales \
    lsb-release \
    curl \
    wget \
    ca-certificates \
    gnupg \
    libsecret-tools \
    nano \
    jq \
    && sed -i '/en_GB.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen en_GB.UTF-8 \
    && update-locale LANG=en_GB.UTF-8 LC_ALL=en_GB.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_GB.UTF-8 \
    LC_ALL=en_GB.UTF-8 \
    TZ=UTC \
    EDITOR=nano

RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*
DOCKERFILE_HEADER

    # Add category-specific features
    case "$category" in
        game-dev)
            cat >> "$dockerfile_path" << 'DOCKERFILE_GAMEDEV'

# ============================================================================
# GAME-DEV: Godot, Vulkan, SDL2, GLFW, CUDA
# ============================================================================

# Install Vulkan SDK and game development libraries
RUN apt-get update && apt-get install -y \
    cmake ninja-build scons pkg-config unzip \
    libx11-dev libxcursor-dev libxinerama-dev \
    libgl1-mesa-dev libglu1-mesa-dev \
    libasound2-dev libpulse-dev \
    libfreetype6-dev libssl-dev libudev-dev \
    libxi-dev libxrandr-dev \
    vulkan-tools libvulkan-dev \
    vulkan-utility-libraries-dev vulkan-validationlayers \
    spirv-tools glslang-tools glslang-dev \
    libshaderc-dev libshaderc1 \
    libsdl2-2.0-0 libsdl2-dev libglm-dev \
    libstb-dev libpng-dev libjpeg-dev \
    libwayland-dev libxkbcommon-dev wayland-protocols \
    libdecor-0-dev \
    && rm -rf /var/lib/apt/lists/*

# Build GLFW 3.4 from source with native Wayland support
RUN git clone --depth 1 --branch 3.4 https://github.com/glfw/glfw.git /tmp/glfw \
    && cd /tmp/glfw \
    && cmake -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DGLFW_BUILD_WAYLAND=ON \
        -DGLFW_BUILD_X11=OFF \
        -DBUILD_SHARED_LIBS=ON \
    && cmake --build build \
    && cmake --install build \
    && rm -rf /tmp/glfw \
    && ldconfig

# Install CUDA Toolkit 13.1
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb -O /tmp/cuda-keyring.deb \
    && dpkg -i /tmp/cuda-keyring.deb && rm /tmp/cuda-keyring.deb \
    && apt-get update && apt-get install -y \
        cuda-toolkit-13-1 cuda-nvcc-13-1 \
        cuda-libraries-dev-13-1 cuda-cudart-dev-13-1 \
    && rm -rf /var/lib/apt/lists/*

ENV PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH} \
    CUDA_HOME=/usr/local/cuda

# Install Godot Engine
RUN GODOT_VERSION=$(curl -s https://api.github.com/repos/godotengine/godot/releases/latest | jq -r '.tag_name' | sed 's/-stable//') \
    && curl -fsSL "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -o /tmp/godot.zip \
    && unzip  /tmp/godot.zip -d /tmp \
    && mv /tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm /tmp/godot.zip
DOCKERFILE_GAMEDEV
            ;;
        
        art)
            cat >> "$dockerfile_path" << 'DOCKERFILE_ART'

# ============================================================================
# ART: 2D/3D art tools, design software
# ============================================================================

RUN apt-get update && apt-get install -y \
    imagemagick \
    gimp \
    inkscape \
    blender \
    krita \
    graphicsmagick \
    optipng \
    pngquant \
    jpegoptim \
    libheif-examples \
    && rm -rf /var/lib/apt/lists/*

# Install pastel (colour tool) from GitHub releases
RUN PASTEL_VERSION=$(curl -s https://api.github.com/repos/sharkdp/pastel/releases/latest | grep -oP '"tag_name": "\K[^"]+') \
    && curl -fsSL "https://github.com/sharkdp/pastel/releases/download/${PASTEL_VERSION}/pastel-${PASTEL_VERSION}-x86_64-unknown-linux-musl.tar.gz" | tar xz -C /tmp \
    && sudo mv /tmp/pastel-${PASTEL_VERSION}-x86_64-unknown-linux-musl/pastel /usr/local/bin/ \
    && sudo chmod +x /usr/local/bin/pastel \
    && rm -rf /tmp/pastel-*
DOCKERFILE_ART
            ;;
        
        data-science)
            cat >> "$dockerfile_path" << 'DOCKERFILE_DATASCIENCE'

# ============================================================================
# DATA-SCIENCE: CUDA, Jupyter, Scientific Computing, Bioinformatics
# ============================================================================

# Switch to root for package installation
USER root

# Install CUDA Toolkit 13.1
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb -O /tmp/cuda-keyring.deb \
    && dpkg -i /tmp/cuda-keyring.deb && rm /tmp/cuda-keyring.deb \
    && apt-get update && apt-get install -y \
        cuda-toolkit-13-1 cuda-nvcc-13-1 \
        cuda-libraries-dev-13-1 cuda-cudart-dev-13-1 \
    && rm -rf /var/lib/apt/lists/*

# Install CUDA 12.6 runtime libraries for PyTorch/TensorFlow compatibility
RUN apt-get update && apt-get install -y --no-install-recommends \
        cuda-cudart-12-6 cuda-nvrtc-12-6 \
        libcublas-12-6 libcufft-12-6 libcurand-12-6 \
        libcusparse-12-6 libcusolver-12-6 \
        libnvjitlink-12-6 libcudnn9-cuda-12 \
    && rm -rf /var/lib/apt/lists/*

# Install scientific computing, bioinformatics, and data science dependencies
RUN apt-get update && apt-get install -y \
    libopenblas-dev liblapack-dev libgomp1 \
    libhdf5-dev libnetcdf-dev \
    graphviz ghostscript \
    emboss ncbi-blast+ \
    bowtie2 samtools bcftools \
    bedtools bioperl \
    && rm -rf /var/lib/apt/lists/*

# Install R for statistical computing
RUN apt-get update && apt-get install -y \
    r-base r-base-dev r-recommended \
    && rm -rf /var/lib/apt/lists/*

ENV PATH=/usr/local/cuda/bin:${PATH}:/usr/local/bin:/usr/bin:/bin \
    LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:/usr/local/cuda/lib64:${LD_LIBRARY_PATH} \
    CUDA_HOME=/usr/local/cuda

RUN apt-get update && apt-get install -y \
    python3 python3-pip python3-dev python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Install R packages for bioinformatics (phyloseq, etc.) - must be root
RUN R --vanilla -e "install.packages(c('BiocManager', 'tidyverse', 'ggplot2', 'ggmap', 'plotly'), repos='http://cran.r-project.org')" \
    && R --vanilla -e "BiocManager::install(c('phyloseq', 'dada2', 'DESeq2', 'limma', 'edgeR', 'igraph'), ask=FALSE)" \
    && R --vanilla -e "install.packages('vegan', repos='http://cran.r-project.org')"

# Install Miniforge (lightweight conda) as root
RUN wget https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh -O /tmp/miniforge.sh && \
    bash /tmp/miniforge.sh -b -p /opt/conda && \
    rm /tmp/miniforge.sh && \
    /opt/conda/bin/conda clean -afy

ENV PATH="/opt/conda/bin:$PATH"

# Create conda environment with scientific and bioinformatics stack (as root)
RUN conda create -y -n datasci python=3.11 && \
    conda run -n datasci conda install -y -c conda-forge \
    numpy scipy scikit-learn scikit-image \
    pandas polars dask \
    matplotlib seaborn plotly bokeh altair \
    jupyter jupyterlab jupyter-book \
    notebook ipykernel ipywidgets \
    statsmodels sympy networkx \
    nltk gensim spacy \
    biopython pysam pybedtools HTSeq \
    bioconda::samtools bioconda::bcftools bioconda::bedtools \
    && conda clean -afy

# Install PyTorch and TensorFlow in conda env (separate to manage dependencies)
RUN conda run -n datasci pip install --no-cache-dir \
    torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu124 \
    tensorflow[and-cuda] pytorch-lightning \
    transformers huggingface-hub

# Install spacy model (use direct conda env paths to avoid activation issues)
RUN /opt/conda/envs/datasci/bin/python -m spacy download en_core_web_sm

# Install Jupyter extensions (use direct conda env paths)
RUN /opt/conda/envs/datasci/bin/pip install --no-cache-dir jupyter-lsp python-lsp-server jupyterlab-lsp jupyterlab-git jupyterlab-execute-time

# Enable conda env on shell startup
RUN echo "conda activate datasci" >> ~/.bashrc

# Switch to user
USER ${base_user}

# Activate conda env by default in shells
RUN echo 'source /opt/conda/etc/profile.d/conda.sh && conda activate datasci' >> ~/.bashrc

# Create Jupyter config directory
RUN mkdir -p ~/.jupyter && touch ~/.hushlogin

# Switch back to root for final setup
USER root
DOCKERFILE_DATASCIENCE
            ;;
        
        streaming)
            cat >> "$dockerfile_path" << 'DOCKERFILE_STREAMING'

# ============================================================================
# STREAMING: FFmpeg+NVENC, NGINX-RTMP, SRT, ONNX Runtime GPU, YOLOv8
# ============================================================================

# Install CUDA Toolkit 13.1
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb -O /tmp/cuda-keyring.deb \
    && dpkg -i /tmp/cuda-keyring.deb && rm /tmp/cuda-keyring.deb \
    && apt-get update && apt-get install -y \
        cuda-toolkit-13-1 cuda-nvcc-13-1 \
        cuda-libraries-dev-13-1 cuda-cudart-dev-13-1 \
    && rm -rf /var/lib/apt/lists/*

# Install CUDA 12.6 runtime libraries for ONNX Runtime 1.20.x compatibility
RUN apt-get update && apt-get install -y --no-install-recommends \
        cuda-cudart-12-6 cuda-nvrtc-12-6 \
        libcublas-12-6 libcufft-12-6 libcurand-12-6 \
        libcusparse-12-6 libcusolver-12-6 \
        libnvjitlink-12-6 libcudnn9-cuda-12 \
    && rm -rf /var/lib/apt/lists/*

ENV PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:/usr/local/cuda/lib64:${LD_LIBRARY_PATH} \
    CUDA_HOME=/usr/local/cuda

# Install FFmpeg build dependencies
RUN apt-get update && apt-get install -y \
    nasm yasm pkg-config gpg dirmngr libmd0 cmake \
    libx264-dev libx265-dev libvpx-dev \
    libfdk-aac-dev libmp3lame-dev libopus-dev \
    libass-dev libfreetype6-dev libvorbis-dev \
    libwebp-dev libaom-dev libdav1d-dev \
    librist-dev libssl-dev libzmq3-dev libsdl2-dev \
    && rm -rf /var/lib/apt/lists/*

# Build SRT from source
RUN git clone --depth 1 --branch v1.5.4 https://github.com/Haivision/srt.git /tmp/srt \
    && cd /tmp/srt && cmake -B build -DCMAKE_INSTALL_PREFIX=/usr/local \
    && cmake --build build -j$(nproc) && cmake --install build \
    && rm -rf /tmp/srt && ldconfig

# Install nv-codec-headers for NVENC/NVDEC
RUN git clone --depth 1 https://github.com/FFmpeg/nv-codec-headers.git /tmp/nv-codec-headers \
    && cd /tmp/nv-codec-headers && make install \
    && rm -rf /tmp/nv-codec-headers

# Build FFmpeg from master with NVENC/NVDEC
RUN git clone --depth 1 https://git.ffmpeg.org/ffmpeg.git /tmp/ffmpeg \
    && cd /tmp/ffmpeg && ./configure \
        --prefix=/usr/local --enable-gpl --enable-nonfree \
        --enable-cuvid --enable-nvenc --enable-nvdec \
        --enable-libx264 --enable-libx265 --enable-libvpx \
        --enable-libfdk-aac --enable-libmp3lame --enable-libopus \
        --enable-libass --enable-libfreetype --enable-libwebp \
        --enable-libaom --enable-libdav1d --enable-libsrt \
        --enable-librist --enable-libzmq \
    && make -j$(nproc) && make install \
    && rm -rf /tmp/ffmpeg && ldconfig

# Build NGINX with RTMP module
RUN apt-get update && apt-get install -y libpcre3-dev libssl-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/* \
    && git clone --depth 1 https://github.com/arut/nginx-rtmp-module.git /tmp/nginx-rtmp \
    && curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --import \
    && curl -sLO https://nginx.org/download/nginx-1.27.3.tar.gz \
    && tar -xzf nginx-1.27.3.tar.gz -C /tmp && rm nginx-1.27.3.tar.gz \
    && cd /tmp/nginx-1.27.3 && ./configure \
        --prefix=/usr/local/nginx \
        --with-http_ssl_module --with-http_v2_module \
        --with-http_realip_module --with-http_stub_status_module \
        --with-stream --with-stream_ssl_module \
        --add-module=/tmp/nginx-rtmp \
    && make -j$(nproc) && make install \
    && rm -rf /tmp/nginx-* \
    && ln -sf /usr/local/nginx/sbin/nginx /usr/local/bin/nginx

# Install streaming utilities
RUN apt-get update && apt-get install -y mediainfo && rm -rf /var/lib/apt/lists/*
RUN apt-get update && apt-get install -y sox libsox-fmt-all && rm -rf /var/lib/apt/lists/*
RUN apt-get update && apt-get install -y v4l-utils && rm -rf /var/lib/apt/lists/*

# Install FFmpeg development headers
RUN apt-get update && apt-get install -y \
    libavformat-dev libavcodec-dev libavutil-dev libswscale-dev \
    && rm -rf /var/lib/apt/lists/*

# Install yt-dlp
RUN YT_DLP_VERSION=$(curl -s https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest | jq -r '.tag_name') \
    && curl -fsSL "https://github.com/yt-dlp/yt-dlp/releases/download/${YT_DLP_VERSION}/yt-dlp" -o /usr/local/bin/yt-dlp \
    && chmod a+rx /usr/local/bin/yt-dlp

# Install TensorRT
RUN apt-get update && apt-get install -y \
    libnvinfer-lean10 libnvinfer-vc-plugin10 \
    libnvinfer-dispatch10 libnvinfer-headers-dev \
    bc sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Install ONNX Runtime 1.20.1 GPU
RUN ONNX_VERSION="1.20.1" \
    && curl -fsSL "https://github.com/microsoft/onnxruntime/releases/download/v${ONNX_VERSION}/onnxruntime-linux-x64-gpu-${ONNX_VERSION}.tgz" -o /tmp/onnxruntime.tgz \
    && tar -xzf /tmp/onnxruntime.tgz -C /opt \
    && mv /opt/onnxruntime-linux-x64-gpu-${ONNX_VERSION} /opt/onnxruntime \
    && ln -sf /opt/onnxruntime/include/* /usr/local/include/ \
    && ln -sf /opt/onnxruntime/lib/libonnxruntime.so* /usr/local/lib/ \
    && ln -sf /opt/onnxruntime/lib/libonnxruntime_providers_cuda.so /usr/local/lib/ \
    && ln -sf /opt/onnxruntime/lib/libonnxruntime_providers_shared.so /usr/local/lib/ \
    && ldconfig && rm -f /tmp/onnxruntime.tgz

ENV ONNXRUNTIME_DIR=/opt/onnxruntime \
    LD_LIBRARY_PATH=/opt/onnxruntime/lib:${LD_LIBRARY_PATH}

# Export YOLOv8n to ONNX format
RUN apt-get update && apt-get install -y --no-install-recommends python3-pip python3-venv \
    && python3 -m venv /tmp/yolo-export \
    && /tmp/yolo-export/bin/pip install ultralytics onnx onnxslim onnxruntime \
    && cd /tmp/yolo-export \
    && /tmp/yolo-export/bin/python -c "from ultralytics import YOLO; model = YOLO('yolov8n.pt'); model.export(format='onnx', imgsz=640, opset=17, simplify=True)" \
    && mkdir -p /opt/models \
    && mv /tmp/yolo-export/yolov8n.onnx /opt/models/yolov8n.onnx \
    && chmod 644 /opt/models/yolov8n.* \
    && rm -rf /tmp/yolo-export ~/.config/Ultralytics /tmp/Ultralytics \
    && apt-get purge -y python3-pip python3-venv \
    && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

ENV PATH=/usr/local/nginx/sbin:$PATH
DOCKERFILE_STREAMING
            ;;
        
        web-dev)
            cat >> "$dockerfile_path" << 'DOCKERFILE_WEBDEV'

# ============================================================================
# WEB-DEV: Node.js, npm, modern web frameworks, Wrangler
# ============================================================================

# Web development tools
RUN apt-get update && apt-get install -y \
    && rm -rf /var/lib/apt/lists/*
DOCKERFILE_WEBDEV
            ;;
        
        dev-tools)
            cat >> "$dockerfile_path" << 'DOCKERFILE_DEVTOOLS'

# ============================================================================
# DEV-TOOLS: GCC, build-essential, common compilers
# ============================================================================

RUN apt-get update && apt-get install -y \
    clang llvm gdb valgrind \
    cmake ninja-build meson \
    pkg-config autoconf automake libtool \
    && rm -rf /var/lib/apt/lists/*
DOCKERFILE_DEVTOOLS
            ;;
    esac

    # Add common user setup at the end
    # Use CATEGORY name for the base image user (generic, reusable)
    local base_user="$category"
    cat >> "$dockerfile_path" << DOCKERFILE_USER

# ============================================================================
# User setup: ${base_user} (category-based generic user)
# ============================================================================

# Create user ${base_user} with sudo privileges
RUN if id ubuntu &>/dev/null; then \\
        groupmod -n ${base_user} ubuntu && \\
        usermod -l ${base_user} -d /home/${base_user} ubuntu && \\
        mkdir -p /home/${base_user} && \\
        chown -R ${base_user}:${base_user} /home/${base_user}; \\
    else \\
        useradd -m -s /bin/bash ${base_user}; \\
    fi && \\
    usermod -aG sudo ${base_user} && \\
    echo "${base_user} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \\
    mkdir -p /home/${base_user}/.config /home/${base_user}/.cache /home/${base_user}/.local/share && \\
    chown -R ${base_user}:${base_user} /home/${base_user}

USER ${base_user}
WORKDIR /home/${base_user}

RUN touch ~/.hushlogin

# Install nvm and Node.js
ENV NVM_DIR=/home/${base_user}/.config/nvm
ENV BASH_ENV=/home/${base_user}/.bashrc
RUN mkdir -p "\$NVM_DIR" && \\
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash && \\
    echo 'export NVM_DIR="\$HOME/.config/nvm"' >> ~/.bashrc && \\
    echo '[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"' >> ~/.bashrc && \\
    bash -c 'source \$NVM_DIR/nvm.sh && nvm install 22 && nvm alias default 22'

ENV PATH=\$NVM_DIR/versions/node/v22.13.1/bin:\$PATH

# Clean up GPG keyring (interferes with host GPG agent mount)
RUN rm -rf ~/.gnupg

# Pre-create .vscode-server directory with proper permissions (need root)
USER root
RUN mkdir -p /home/${base_user}/.vscode-server && chown ${base_user}:${base_user} /home/${base_user}/.vscode-server && chmod 775 /home/${base_user}/.vscode-server
USER ${base_user}

WORKDIR /workspaces
DOCKERFILE_USER
}

build_base_image() {
    local category="$1"
    local image_tag="${BASE_IMAGE_CATEGORIES[$category]}"
    local github_ref="${CATEGORY_GITHUB_PATHS[$category]}"
    
    if [[ -z "$image_tag" ]]; then
        print_error "Unknown category: $category"
        echo "Available: ${!BASE_IMAGE_CATEGORIES[*]}"
        exit 1
    fi
    
    local project_dir="$(pwd)"
    local project_name=$(basename "$project_dir")
    local devcontainer_dir="$project_dir/.devcontainer"
    
    print_header "Generating Base Image Config: $category"
    print_kv "Category" "$category"
    print_kv "Image tag" "$image_tag"
    print_kv "Features" "${CATEGORY_FEATURES[$category]}"
    print_kv "Source" "$github_ref"
    print_kv "Output" "$devcontainer_dir"
    print_kv "GitHub User" "$CFG_GITHUB_USER"
    print_kv "GPG Key" "$CFG_GPG_KEY_ID"
    print_kv "Mount GPG" "$CFG_MOUNT_GPG"
    print_kv "Mount GH Config" "$CFG_MOUNT_GH_CONFIG"
    print_kv "Mount Docker" "$CFG_MOUNT_DOCKER_SOCKET"
    echo ""
    
    # Create .devcontainer directory
    mkdir -p "$devcontainer_dir"
    
    # Generate Dockerfile with all category features
    print_info "Generating Dockerfile with $category features..."
    generate_category_dockerfile "$category" "$devcontainer_dir/Dockerfile"
    print_success "Created: $devcontainer_dir/Dockerfile"
    
    # Generate .dockerignore
    generate_dockerignore "$devcontainer_dir"
    
    # Generate devcontainer.json using the standard function
    PROJECT_PATH="$project_dir" generate_devcontainer_json "$devcontainer_dir" "" "$category"
    echo ""
    
    print_header_success "Base Image Config Generated!"
    echo ""
    print_kv "Dockerfile" "$devcontainer_dir/Dockerfile"
    print_kv "Config" "$devcontainer_dir/devcontainer.json"
    echo ""
    
    echo -e "${BOLD}Build now?${NC}"
    echo -e "  ${CYAN}Y${NC}) Build image with podman (may take 10-30 minutes)"
    echo -e "  ${CYAN}N${NC}) Skip - use 'Open in Container' in VS Code instead"
    echo ""
    
    if confirm "Build $image_tag now?"; then
        print_info "Building image (this may take several minutes)..."
        echo ""
        
        cd "$devcontainer_dir"
        if podman build -t "$image_tag" .; then
            echo ""
            print_header_success "Base Image Built Successfully!"
            print_kv "Image" "$image_tag"
            echo ""
            print_info "Verify: ${CYAN}podman images | grep ${image_tag%%:*}${NC}"
            print_info "Use in other projects: ${CYAN}dc-contain --img --$category${NC}"
        else
            echo ""
            print_error "Build failed"
            exit 1
        fi
    else
        echo ""
        print_info "Skipped building. To build later:"
        echo -e "  ${CYAN}cd $devcontainer_dir && podman build -t $image_tag .${NC}"
        echo ""
        print_info "Or open in VS Code and use 'Reopen in Container'"
    fi
}

################################################################################
# Image-based Devcontainer Generation
################################################################################

generate_image_devcontainer() {
    local category="$1"
    local image_tag="${BASE_IMAGE_CATEGORIES[$category]}"
    local github_ref="${CATEGORY_GITHUB_PATHS[$category]}"
    
    if [[ -z "$image_tag" ]]; then
        print_error "Unknown category: $category"
        echo "Available: ${!BASE_IMAGE_CATEGORIES[*]}"
        exit 1
    fi
    
    local project_name=$(basename "$(pwd)")
    local devcontainer_dir=".devcontainer"
    
    print_header "Generating Devcontainer: $project_name"
    print_kv "Category" "$category"
    print_kv "Base image" "$image_tag"
    print_kv "Features" "${CATEGORY_FEATURES[$category]}"
    print_kv "GitHub User" "$CFG_GITHUB_USER"
    print_kv "GPG Key" "$CFG_GPG_KEY_ID"
    print_kv "Mount GPG" "$CFG_MOUNT_GPG"
    print_kv "Mount GH Config" "$CFG_MOUNT_GH_CONFIG"
    print_kv "Mount Docker" "$CFG_MOUNT_DOCKER_SOCKET"
    echo ""
    
    # Check if image exists (podman adds localhost/ prefix)
    if ! podman images --format "{{.Repository}}:{{.Tag}}" | grep -E "(localhost/)?${image_tag}$"; then
        print_warning "Base image not found locally: $image_tag"
        echo ""
        echo "Build it first:"
        echo "  ${CYAN}cd ~/.dev-control/.devcontainer/$category${NC}"
        echo "  ${CYAN}dc-contain --base --$category${NC}"
        echo ""
        if ! confirm "Continue anyway (will fail when opening devcontainer)?"; then
            exit 1
        fi
    fi
    
    mkdir -p "$devcontainer_dir"
    
    # Generate devcontainer.json using the standard function
    PROJECT_PATH="$(pwd)" generate_devcontainer_json "$devcontainer_dir" "$image_tag" "$category"
    echo ""
    print_header_success "Devcontainer Generated!"
    echo ""
    print_section "Next Steps:"
    echo -e "  1. Open in VS Code: ${GREEN}code $(pwd)${NC}"
    echo -e "  2. Press ${CYAN}F1${NC} → ${CYAN}Dev Containers: Reopen in Container${NC}"
    echo ""
}

################################################################################
# Nest Mode - Recursively rebuild all base and img containers
################################################################################

run_nest_mode() {
    local start_dir="${1:-$(pwd)}"
    shift || true  # Remove first argument
    
    # Collect allowed categories from remaining args (--art, --game-dev, etc.)
    local allowed_cats=""
    for arg in "$@"; do
        case "$arg" in
            --game-dev|--art|--data-science|--streaming|--web-dev|--dev-tools)
                allowed_cats+="${arg#--}|"
                ;;
        esac
    done
    allowed_cats="${allowed_cats%|}"  # Remove trailing |
    
    local nest_json="$start_dir/.devcontainer/nest.json"
    
    print_header "Nest Mode: Scanning for containers"
    print_kv "Starting from" "$start_dir"
    if [[ -n "$allowed_cats" ]]; then
        print_kv "Filter to categories" "$allowed_cats"
    fi
    echo ""
    
    # Find all .devcontainer dirs and build projects list
    find "$start_dir" -type d -name ".devcontainer" 2>/dev/null | sort | while read -r devcontainer_dir; do
        local project_dir="$(dirname "$devcontainer_dir")"
        local rel_path="${project_dir#$start_dir/}"
        [[ "$rel_path" == "$project_dir" ]] && rel_path="."
        
        # Skip root
        [[ "$rel_path" == "." ]] && continue
        
        local dcjson="$devcontainer_dir/devcontainer.json"
        [[ ! -f "$dcjson" ]] && continue
        
        # Extract category and type
        local category=$(grep -oiP '//\s*category:\s*\K[a-z0-9-]+' "$dcjson" 2>/dev/null | head -1)
        category="${category:-unknown}"
        
        # Filter by allowed categories if specified
        if [[ -n "$allowed_cats" ]]; then
            local match=0
            for allowed in ${allowed_cats//|/ }; do
                [[ "$category" == "$allowed" ]] && match=1 && break
            done
            [[ $match -eq 0 ]] && continue
        fi
        
        local type=""
        [[ $(grep -c '"build"' "$dcjson" 2>/dev/null) -gt 0 ]] && type="BASE"
        [[ $(grep -c '"image"' "$dcjson" 2>/dev/null) -gt 0 ]] && type="IMG"
        [[ -z "$type" ]] && continue
        
        echo "$rel_path|$type|$category"
    done > "$nest_json.tmp"
    
    # Read results
    if [[ ! -f "$nest_json.tmp" ]] || [[ ! -s "$nest_json.tmp" ]]; then
        print_error "No valid projects detected"
        rm -f "$nest_json.tmp"
        return 1
    fi
    
    # Separate unknown and known categories
    local -a unknown_projects
    local -a known_projects
    
    while IFS='|' read -r path type category; do
        if [[ "$category" == "unknown" ]]; then
            unknown_projects+=("$path|$type|$category")
        else
            known_projects+=("$path|$type|$category")
        fi
    done < "$nest_json.tmp"
    
    # Display unknown projects first
    echo ""
    if [[ ${#unknown_projects[@]} -gt 0 ]]; then
        print_header "⚠️  Unknown Category (will NOT be regenerated)"
        echo ""
        local idx=1
        for proj in "${unknown_projects[@]}"; do
            IFS='|' read -r path type category <<< "$proj"
            printf "  ${CYAN}%d.${NC} %-30s ${YELLOW}%s${NC}\n" "$idx" "$path" "$type"
            ((idx++))
        done
        echo ""
    fi
    
    # Display recognized projects
    print_header "Recognized Projects (will be regenerated)"
    echo ""
    
    if [[ ${#known_projects[@]} -eq 0 ]]; then
        print_warning "No recognized category projects found"
        rm -f "$nest_json.tmp"
        return 1
    fi
    
    local idx=1
    for proj in "${known_projects[@]}"; do
        IFS='|' read -r path type category <<< "$proj"
        printf "  ${CYAN}%d.${NC} %-30s ${YELLOW}%s${NC} ${GREEN}(%s)${NC}\n" "$idx" "$path" "$type" "$category"
        ((idx++))
    done
    echo ""
    
    # Save to nest.json (only known projects)
    mkdir -p "$start_dir/.devcontainer"
    {
        echo "{"
        echo "  \"start_dir\": \"$start_dir\","
        echo "  \"detected_at\": \"$(date -Iseconds)\","
        echo "  \"projects\": ["
        local first=true
        for proj in "${known_projects[@]}"; do
            IFS='|' read -r path type category <<< "$proj"
            if [[ "$first" != true ]]; then echo ","; fi
            printf "    {\"path\": \"%s\", \"type\": \"%s\", \"category\": \"%s\"}" "$path" "$type" "$category"
            first=false
        done
        echo ""
        echo "  ]"
        echo "}"
    } > "$nest_json"
    
    print_success "Saved configuration to $nest_json"
    echo ""
    
    # ASK FOR CONFIRMATION FOR RECOGNIZED PROJECTS
    print_warning "Regenerate ${#known_projects[@]} recognized containers?"
    read -p "Proceed? [y/N] " -n 1 -r
    echo ""
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Aborted - no changes made"
        rm -f "$nest_json.tmp"
        return 0
    fi
    
    # Execute builds (only known projects)
    print_header "Building recognized containers"
    echo ""
    
    for proj in "${known_projects[@]}"; do
        IFS='|' read -r path type category <<< "$proj"
        local full_path="$start_dir/$path"
        [[ "$path" == "." ]] && full_path="$start_dir"
        
        if [[ -d "$full_path/.devcontainer" ]]; then
            echo ""
            print_info "$type: $path ($category)"
            (cd "$full_path" && "$SCRIPT_DIR/containerise.sh" --defaults --"${type,,}" --"$category" <<< y)
        fi
    done
    
    rm -f "$nest_json.tmp"
    echo ""
    print_header_success "Nest Mode Complete"
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
    
    # Always set project path first
    if [[ -z "$PROJECT_PATH" ]]; then
        PROJECT_PATH="$(pwd)"
    fi
    
    # Handle --nest mode early and exit
    if [[ "$NEST_MODE" == true ]]; then
        run_nest_mode "$PROJECT_PATH"
        exit 0
    fi
    
    # Always load user configuration (GPG, mounts, GitHub user, etc.)
    load_container_config
    
    # Ensure container name is set from folder if not in config
    if [[ -z "$CFG_CONTAINER_NAME" ]]; then
        CFG_CONTAINER_NAME=$(basename "$PROJECT_PATH")
    fi
    
    # Check if already in devcontainer
    if is_in_devcontainer; then
        print_warning "Already running inside a devcontainer"
        print_info "This script is meant to be run on the host machine"
        exit 0
    fi
    
    # Run interactive config unless using --defaults
    if [[ "$USE_DEFAULTS" != true ]]; then
        # Only run full interactive mode if no MODE specified
        if [[ -z "$MODE" ]]; then
            print_header "Dev-Control Containerisation"
            detect_project_path "$PROJECT_PATH"
            load_container_config  # Reload if path changed
        fi
        run_interactive_config
    else
        print_info "Using saved defaults from configuration"
    fi
    
    # Handle MODE-based workflows (--base or --img)
    if [[ -n "$MODE" ]]; then
        if [[ -z "$CATEGORY_FLAG" ]]; then
            print_error "Category required. Use --game-dev, --art, --streaming, etc."
            echo ""
            show_help
            exit 1
        fi
        
        # Auto-enable NVIDIA for categories that use CUDA
        case "$CATEGORY_FLAG" in
            streaming|data-science|game-dev|art)
                CFG_ENABLE_NVIDIA_DEVICES="true"
                ;;
        esac
        
        if [[ "$MODE" == "base" ]]; then
            build_base_image "$CATEGORY_FLAG"
            exit 0
        elif [[ "$MODE" == "image" ]]; then
            generate_image_devcontainer "$CATEGORY_FLAG"
            exit 0
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
