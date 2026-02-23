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
#   ✓ Generates _example and _minimal config variants
#   ✓ Adds personal config files to .gitignore
#
# Usage:
#   ./containerise.sh [PROJECT_PATH] [OPTIONS]
#   ./containerise.sh                    # Interactive mode
#   ./containerise.sh --defaults         # Use saved defaults (one-click)
#   ./containerise.sh --config FILE      # Use specific config file
#   ./containerise.sh --help             # Show help
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience
################################################################################

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"
export DEV_CONTROL_DIR  # Export to avoid SC2034 warning

# Source shared libraries
source "$SCRIPT_DIR/lib/colours.sh"
source "$SCRIPT_DIR/lib/print.sh"
source "$SCRIPT_DIR/lib/validation.sh"
source "$SCRIPT_DIR/lib/container.sh"

# CLI options
MODE=""  # "base" or "image"
CATEGORY_FLAG=""
BARE_MODE=false
USE_DEFAULTS=false
CONFIG_FILE=""
PROJECT_PATH=""
SHOW_HELP=false
NEST_MODE=false
NEST_REGEN=false
NO_CACHE=false

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
  --bare    Generate minimal devcontainer (no category, custom base image)
  --nest    Recursively rebuild all base and img containers in subdirectories
            Use --nest . to include the root directory itself
  --regen   Delete all .devcontainer dirs before nest rebuild (forces regeneration)
  --no-cache  Build base images without layer cache (force full image rebuild)

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

  # Rebuild current directory as root + all subdirectories
  cd ~/PRO/ART && containerise.sh --nest .

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
            --bare)
                BARE_MODE=true
                shift
                ;;
            --nest)
                NEST_MODE=true
                USE_DEFAULTS=true
                shift
                ;;
            --regen)
                NEST_REGEN=true
                shift
                ;;
            --no-cache)
                NO_CACHE=true
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
        usermod -u 1000 -l ${CFG_CONTAINER_NAME} -d /home/${CFG_CONTAINER_NAME} ubuntu && \\
        if [ ! -d /home/${CFG_CONTAINER_NAME} ]; then mkdir -p /home/${CFG_CONTAINER_NAME}; fi && \\
        if [ -d /home/ubuntu ] && [ ! -d /home/${CFG_CONTAINER_NAME} ]; then \\
            mv /home/ubuntu /home/${CFG_CONTAINER_NAME}; \\
        fi; \\
    else \\
        useradd -m -s /bin/bash -u 1000 ${CFG_CONTAINER_NAME}; \\
    fi && \\
    usermod -aG sudo ${CFG_CONTAINER_NAME} && \\
    echo "${CFG_CONTAINER_NAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \\
    mkdir -p /home/${CFG_CONTAINER_NAME}/.config /home/${CFG_CONTAINER_NAME}/.cache /home/${CFG_CONTAINER_NAME}/.local/share /home/${CFG_CONTAINER_NAME}/.vscode-server /home/${CFG_CONTAINER_NAME}/.bash_backups && \\
    chown -R ${CFG_CONTAINER_NAME}:${CFG_CONTAINER_NAME} /home/${CFG_CONTAINER_NAME} && \\
    chmod 775 /home/${CFG_CONTAINER_NAME}/.vscode-server && \\
    chmod 700 /home/${CFG_CONTAINER_NAME}/.bash_backups && \\
    rm -rf /root/.gnupg /home/${CFG_CONTAINER_NAME}/.gnupg.old

USER ${CFG_CONTAINER_NAME}
WORKDIR /home/${CFG_CONTAINER_NAME}
DOCKERFILE_EOF

        # Add hush login if enabled
        if [[ "$CFG_HUSH_LOGIN" == "true" ]]; then
            cat >> "$dockerfile_path" << DOCKERFILE_EOF

RUN touch ~/.hushlogin
DOCKERFILE_EOF
        fi

        # Install nvm and Node.js (required for npx-dependent MCP servers)
        cat >> "$dockerfile_path" << DOCKERFILE_EOF

# Install nvm and Node.js (required for npx-dependent MCP servers like firecrawl)
# System-wide installation (consistent with common-base/common-footer templates)
ENV NVM_DIR=/opt/nvm
RUN mkdir -p "$NVM_DIR" && \\
    curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/\$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)/install.sh | bash && \\
    bash -c 'source /opt/nvm/nvm.sh && nvm install --lts && nvm alias default lts/* && nvm cache clear' && \\
    chmod -R a+rx $NVM_DIR

# Dynamically load nvm and set PATH to latest installed Node (supports updates without rebuilds)
RUN echo 'export NVM_DIR=/opt/nvm && [ -s "\$NVM_DIR/nvm.sh" ] && source "\$NVM_DIR/nvm.sh"' >> ~/.bashrc && \\
    echo 'export PATH=\$(ls -d \$NVM_DIR/versions/node/*/bin 2>/dev/null | head -1):\$PATH' >> ~/.bashrc
DOCKERFILE_EOF

        # Add git configuration (always include safe.directory and defaultBranch, user/email/gpg if provided)
        local git_config_cmd=$(generate_git_config_dockerfile "$CFG_GITHUB_USER" "$CFG_GITHUB_USER_EMAIL" "$CFG_GPG_KEY_ID")
        
        cat >> "$dockerfile_path" << DOCKERFILE_EOF

# Bake git config into image
RUN $git_config_cmd
DOCKERFILE_EOF

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
        # VS Code's Remote Containers extension automatically forwards the host gpg-agent
        # socket into the container at ~/.gnupg/S.gpg-agent via its built-in forwarding.
        # Mounting the raw socket file here would create a second competing path and
        # also fails hard at container start if the host gpg-agent socket does not exist.
        : # GPG agent forwarding is handled by VS Code's built-in mechanism
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
    
    # Streaming category: Add NVENC encoding library mount
    if [[ "$category" == "streaming" ]]; then
        if [[ -n "$mounts" ]]; then mounts+=","; fi
        mounts+="\"source=/usr/lib/x86_64-linux-gnu/libnvidia-encode.so.1,target=/usr/lib/x86_64-linux-gnu/libnvidia-encode.so.1,type=bind,readonly\""
    fi
    
    # Build NVIDIA device mounts if enabled.
    # Note: --userns=keep-id is intentionally omitted here.
    # VS Code Dev Containers automatically adds it for Podman when the container
    # user UID matches the host UID, so including it in runArgs causes duplication
    # (podman run --userns=keep-id --userns=keep-id) which breaks user namespace
    # mapping and produces EACCES errors on .gnupg / .ssh / .cache at runtime.
    local run_args=""
    if [[ "$CFG_ENABLE_NVIDIA_DEVICES" == "true" ]]; then
        run_args="\"--shm-size=1g\",\"--device=/dev/dri\",\"--device=/dev/nvidia0\",\"--device=/dev/nvidiactl\",\"--device=/dev/nvidia-modeset\",\"--device=/dev/nvidia-uvm\",\"--device=/dev/nvidia-uvm-tools\""
    fi
    
    # Streaming category: Always enable NVIDIA devices, DRI/KMS access, and USB capture device
    if [[ "$category" == "streaming" ]]; then
        run_args="\"--shm-size=1g\",\"--device=/dev/dri\",\"--device=/dev/nvidia0\",\"--device=/dev/nvidiactl\",\"--device=/dev/nvidia-modeset\",\"--device=/dev/nvidia-uvm\",\"--device=/dev/nvidia-uvm-tools\",\"--group-add=video\",\"--group-add=render\",\"--security-opt=label=disable\",\"--device=/dev/usb-video-capture1\""
    fi
    
    # Build extensions array (default + category-specific)
    local extensions=""
    IFS=',' read -ra ext_array <<< "$CFG_VSCODE_EXTENSIONS"
    for ext in "${ext_array[@]}"; do
        if [[ -n "$extensions" ]]; then extensions+=","; fi
        extensions+="\"${ext}\""
    done
    
    # Add category-specific extensions if available
    if [[ -n "$category" && -n "${CATEGORY_EXTENSIONS[$category]:-}" ]]; then
        for ext in ${CATEGORY_EXTENSIONS[$category]}; do
            if [[ -n "$extensions" ]]; then extensions+=","; fi
            extensions+="\"${ext}\""
        done
    fi
    
    # Build container environment vars
    # Note: GPG_TTY cannot be set here (tty is not known at JSON generation time).
    # It is set correctly at shell startup via postCreateCommand or terminal init.
    local container_env="\"GPG_KEY_ID\": \"${CFG_GPG_KEY_ID}\",
    \"GITHUB_USER\": \"${CFG_GITHUB_USER}\",
    \"DOCKER_HOST\": \"unix:///var/run/docker.sock\",
    \"DISPLAY\": \"\${localEnv:DISPLAY}\",
    \"TZ\": \"${CFG_TIMEZONE}\""
    
    if [[ "$CFG_ENABLE_NVIDIA_DEVICES" == "true" || "$category" == "streaming" ]]; then
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
    
    # Build git config line from saved YAML configuration (always include safe.directory and defaultBranch)
    local git_config_line=" && $(generate_git_config_postcreate "$CFG_GITHUB_USER" "$CFG_GITHUB_USER_EMAIL" "$CFG_GPG_KEY_ID")"
    
    # Determine image_or_build and store category metadata for README
    local image_or_build=""
    local category_metadata=""
    
    if [[ -n "$use_image" ]]; then
        # Using pre-built image
        image_or_build="\"image\": \"$use_image\","
        if [[ -n "$category" ]]; then
            local github_ref="${CATEGORY_GITHUB_PATHS[$category]}"
            category_metadata="{\"type\":\"image\",\"category\":\"$category\",\"base_image\":\"$use_image\",\"source\":\"$github_ref\",\"features\":\"${CATEGORY_FEATURES[$category]}\"}"
        fi
    elif [[ -n "$category" ]]; then
        # Building from Dockerfile for a category
        image_or_build="\"build\": {
    \"dockerfile\": \"Dockerfile\"
  },"
        local image_tag="${BASE_IMAGE_CATEGORIES[$category]}"
        local github_ref="${CATEGORY_GITHUB_PATHS[$category]}"
        category_metadata="{\"type\":\"build\",\"category\":\"$category\",\"image_tag\":\"$image_tag\",\"source\":\"$github_ref\",\"features\":\"${CATEGORY_FEATURES[$category]}\"}"
    else
        # Regular build mode
        image_or_build="\"build\": {
    \"dockerfile\": \"Dockerfile\"
  },"
    fi
    
    cat > "$devcontainer_file" << DEVCONTAINER_EOF
{
  "name": "${project_name^^}",
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
  "postCreateCommand": "sudo chown -R ${uid}:${uid} . 2>/dev/null || true && sudo chmod 755 /home/${remote_user} 2>/dev/null || true && sudo chown -R ${uid}:${uid} /home/${remote_user}/.vscode-server 2>/dev/null || true && sudo mkdir -p /home/${remote_user}/.gnupg /home/${remote_user}/.ssh /home/${remote_user}/.cache /home/${remote_user}/.config && sudo chown ${uid}:${uid} /home/${remote_user}/.gnupg /home/${remote_user}/.ssh /home/${remote_user}/.cache /home/${remote_user}/.config && sudo chmod 700 /home/${remote_user}/.gnupg /home/${remote_user}/.ssh && sudo chmod 755 /home/${remote_user}/.cache /home/${remote_user}/.config && sudo mkdir -p /run/user/${uid}/gnupg && sudo chown -R ${uid}:${uid} /run/user/${uid} 2>/dev/null || true && ln -sf /tmp/wayland-0 /run/user/${uid}/wayland-0 2>/dev/null || true${git_config_line} && bash -c 'bash /opt/dev-control/scripts/alias-loading.sh <<< A'",
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

    # Generate category documentation as README if applicable
    if [[ -n "$category_metadata" ]]; then
        generate_category_readme "$devcontainer_dir" "$category_metadata"
    fi
    
    print_success "Created: $devcontainer_file"
}

# Generate category README documentation
generate_category_readme() {
    local devcontainer_dir="$1"
    local metadata="$2"
    
    # Parse metadata JSON (simple extraction without jq)
    local category=$(echo "$metadata" | grep -oP '(?<="category":")[^"]*')
    local type=$(echo "$metadata" | grep -oP '(?<="type":")[^"]*')
    local base_image=$(echo "$metadata" | grep -oP '(?<="base_image":")[^"]*')
    local image_tag=$(echo "$metadata" | grep -oP '(?<="image_tag":")[^"]*')
    local source=$(echo "$metadata" | grep -oP '(?<="source":")[^"]*')
    local features=$(echo "$metadata" | grep -oP '(?<="features":")[^"]*')
    
    local readme_file="$devcontainer_dir/README.md"
    local project_dir
    project_dir="$(dirname "$devcontainer_dir")"
    local container_name
    container_name="$(basename "$project_dir")"
    
    write_devcontainer_readme \
        "$readme_file" \
        "$category" \
        "$type" \
        "$base_image" \
        "$image_tag" \
        "$source" \
        "$features" \
        "$container_name"
}

# Generate all devcontainer files
generate_devcontainer() {
    local devcontainer_dir="$PROJECT_PATH/.devcontainer"
    
    print_info "Generating devcontainer configuration..."
    
    mkdir -p "$devcontainer_dir"
    
    generate_dockerignore "$devcontainer_dir"
    generate_dockerfile "$devcontainer_dir"
    generate_devcontainer_json "$devcontainer_dir"
    generate_container_readme "$devcontainer_dir"
    generate_config_variants "$devcontainer_dir" "" "" ""
    add_devcontainer_to_gitignore "$PROJECT_PATH"
}

################################################################################
# Output
################################################################################

generate_container_readme() {
    local devcontainer_dir="$1"
    local readme_file="$devcontainer_dir/README.md"
    
    # Determine container type from devcontainer.json
    local container_type="custom"
    if [[ -f "$devcontainer_dir/devcontainer.json" ]]; then
        grep -q '"build"' "$devcontainer_dir/devcontainer.json" && container_type="build"
        grep -q '"image"' "$devcontainer_dir/devcontainer.json" && container_type="image"
    fi
    
    # Determine category - check if we're in base/image mode
    local category="custom"
    [[ -n "$CATEGORY_FLAG" ]] && category="$CATEGORY_FLAG"
    
    local container_name
    container_name=$(basename "$PROJECT_PATH")
    
    write_devcontainer_readme \
        "$readme_file" \
        "$category" \
        "$container_type" \
        "" \
        "" \
        "" \
        "" \
        "$container_name"
}

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
    echo -e "  1. Download dev-control with: ${GREEN}gh release download latest --repo xaoscience/dev-control${NC}"
    echo -e "  2. Load aliases: ${GREEN}source ./scripts/alias-loading.sh${NC}"
    echo -e "  3. Open the project in VS Code: ${GREEN}code $PROJECT_PATH${NC}"
    echo -e "  4. Press ${CYAN}F1${NC} and run: ${CYAN}Dev Containers: Reopen in Container${NC}"
    echo ""
    
    print_section "One-Click Mode:"
    echo -e "  Next time, run: ${GREEN}dc-container --defaults${NC}"
    echo ""
}



################################################################################
# Config Variant Generation (_example and _minimal)
################################################################################

# Generate _example and _minimal config variants alongside personal config files
# _example: tracked reference with placeholder values (YOUR_GITHUB_USER, etc.)
# _minimal: tracked reference with all dependencies but no personal config
#
# Personal files (Dockerfile, devcontainer.json) are gitignored.
# Variant files (Dockerfile_example, devcontainer_example.json, etc.) are tracked.
generate_config_variants() {
    local devcontainer_dir="$1"
    local mode="${2:-}"       # "base", "image", or "" (no-flag)
    local category="${3:-}"
    local image_tag="${4:-}"

    # Save original config
    local orig_user="$CFG_GITHUB_USER"
    local orig_email="${CFG_GITHUB_USER_EMAIL:-}"
    local orig_gpg="${CFG_GPG_KEY_ID:-}"
    local orig_mount_gpg="${CFG_MOUNT_GPG:-true}"
    local orig_mount_gh="${CFG_MOUNT_GH_CONFIG:-true}"
    local orig_mount_wrangler="${CFG_MOUNT_WRANGLER:-false}"

    # ─── EXAMPLE VARIANT (placeholder credentials) ───
    print_info "Generating _example variant (placeholder values)..."
    CFG_GITHUB_USER="YOUR_GITHUB_USER"
    CFG_GITHUB_USER_EMAIL="YOUR_GITHUB_EMAIL"
    CFG_GPG_KEY_ID="YOUR_GPG_KEY_ID"
    _generate_variant "$devcontainer_dir" "$mode" "$category" "$image_tag" "_example"

    # ─── MINIMAL VARIANT (no personal config) ───
    print_info "Generating _minimal variant (no personal config)..."
    CFG_GITHUB_USER=""
    CFG_GITHUB_USER_EMAIL=""
    CFG_GPG_KEY_ID=""
    CFG_MOUNT_GPG="false"
    CFG_MOUNT_GH_CONFIG="false"
    CFG_MOUNT_WRANGLER="false"
    _generate_variant "$devcontainer_dir" "$mode" "$category" "$image_tag" "_minimal"

    # ─── RESTORE original config ───
    CFG_GITHUB_USER="$orig_user"
    CFG_GITHUB_USER_EMAIL="$orig_email"
    CFG_GPG_KEY_ID="$orig_gpg"
    CFG_MOUNT_GPG="$orig_mount_gpg"
    CFG_MOUNT_GH_CONFIG="$orig_mount_gh"
    CFG_MOUNT_WRANGLER="$orig_mount_wrangler"

    # Regenerate personal files (overwritten during no-flag variant generation)
    if [[ "$mode" != "base" && "$mode" != "image" ]]; then
        generate_dockerfile "$devcontainer_dir"
    fi
    if [[ "$mode" == "image" ]]; then
        generate_devcontainer_json "$devcontainer_dir" "$image_tag" "$category"
    elif [[ "$mode" == "base" ]]; then
        generate_devcontainer_json "$devcontainer_dir" "" "$category"
    else
        generate_devcontainer_json "$devcontainer_dir"
    fi

    print_success "Config variants generated (_example + _minimal)"
}

# Internal helper: generate one variant (Dockerfile + devcontainer.json) with current config
_generate_variant() {
    local devcontainer_dir="$1"
    local mode="$2"
    local category="$3"
    local image_tag="$4"
    local suffix="$5"  # "_example" or "_minimal"

    local variant_label=""
    if [[ "$suffix" == "_example" ]]; then
        variant_label="EXAMPLE: Replace YOUR_GITHUB_USER, YOUR_GITHUB_EMAIL, YOUR_GPG_KEY_ID with your values"
    elif [[ "$suffix" == "_minimal" ]]; then
        variant_label="MINIMAL: All dependencies, no personal config (git identity, GPG, host mounts)"
    fi

    # Generate Dockerfile variant (not needed for --img mode which uses pre-built image)
    if [[ "$mode" != "image" ]]; then
        if [[ "$mode" == "base" ]]; then
            # generate_category_dockerfile accepts output path directly
            generate_category_dockerfile "$category" "$devcontainer_dir/Dockerfile${suffix}"
        else
            # generate_dockerfile writes to Dockerfile, then rename
            generate_dockerfile "$devcontainer_dir"
            mv "$devcontainer_dir/Dockerfile" "$devcontainer_dir/Dockerfile${suffix}"
        fi
        # Prepend variant header
        {
            echo "# ${variant_label}"
            echo "# This is a tracked reference file. Personal config (Dockerfile) is gitignored."
            echo "#"
            cat "$devcontainer_dir/Dockerfile${suffix}"
        } > "$devcontainer_dir/Dockerfile${suffix}.tmp"
        mv "$devcontainer_dir/Dockerfile${suffix}.tmp" "$devcontainer_dir/Dockerfile${suffix}"
        print_success "Created: Dockerfile${suffix}"
    fi

    # Generate devcontainer.json variant
    if [[ "$mode" == "image" ]]; then
        generate_devcontainer_json "$devcontainer_dir" "$image_tag" "$category"
    elif [[ "$mode" == "base" ]]; then
        generate_devcontainer_json "$devcontainer_dir" "" "$category"
    else
        generate_devcontainer_json "$devcontainer_dir"
    fi
    mv "$devcontainer_dir/devcontainer.json" "$devcontainer_dir/devcontainer${suffix}.json"
    print_success "Created: devcontainer${suffix}.json"
}

################################################################################
# Base Image Building
################################################################################

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
    
    # Add personal config to .gitignore
    add_devcontainer_to_gitignore "$project_dir"

    # Generate tracked config variants (_example + _minimal)
    PROJECT_PATH="$project_dir" generate_config_variants "$devcontainer_dir" "base" "$category" ""
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
        local build_args=()
        [[ "$NO_CACHE" == "true" ]] && build_args+=("--no-cache")
        build_args+=("--build-arg" "BUILD_DATE=$(date +%Y%m%d)")
        if podman build "${build_args[@]}" -t "$image_tag" .; then
            echo ""
            print_header_success "Base Image Built Successfully!"
            print_kv "Image" "$image_tag"
            echo ""
            print_info "Verify: ${CYAN}podman images | grep ${image_tag%%:*}${NC}"
            print_info "Use in other projects: ${CYAN}dc-contain --img --$category${NC}"
            echo ""
            # Prune stale VS Code UID-wrapper images (vsc-*-uid).
            # VS Code names these by a hash of devcontainer.json content, not the
            # image digest. Podman's layer cache resolves the FROM mutable tag to
            # the OLD digest when rebuilding, so the wrapper is silently built from
            # the pre-fix base image. Pruning forces VS Code to rebuild the wrapper
            # transparently from the new base on next container open (~5s rebuild).
            local stale_wrappers=()
            mapfile -t stale_wrappers < <(
                podman images --format "{{.Repository}}" 2>/dev/null \
                    | grep "^localhost/vsc-" || true
            )
            if [[ ${#stale_wrappers[@]} -gt 0 ]]; then
                print_info "Pruning ${#stale_wrappers[@]} stale VS Code UID-wrapper image(s)..."
                for wrapper in "${stale_wrappers[@]}"; do
                    podman rmi --force "$wrapper" 2>/dev/null || true
                done
                print_success "Pruned. VS Code will rebuild wrappers from the new base on next open."
            fi
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
    
    # Add personal config to .gitignore
    add_devcontainer_to_gitignore "$(pwd)"

    # Generate tracked config variants (_example + _minimal)
    PROJECT_PATH="$(pwd)" generate_config_variants "$devcontainer_dir" "image" "$category" "$image_tag"
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
    local include_root=false
    shift || true  # Remove first argument
    
    # Check if first arg is "." to include root directory
    if [[ "$start_dir" == "." ]]; then
        include_root=true
        start_dir="$(pwd)"
    fi
    
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
    [[ "$include_root" == true ]] && print_kv "Include root" "yes"
    echo ""
    
    # Check if nest.json exists - use it as source of truth
    if [[ -f "$nest_json" ]]; then
        print_info "Using existing nest.json as source of truth"
        echo ""
        
        # Extract projects from nest.json using grep/sed
        # Each line: {"path": "...", "type": "...", "category": "..."}
        grep -oP '\{"path"[^}]+\}' "$nest_json" | while read -r project_obj; do
            # Extract values from JSON object
            local path=$(echo "$project_obj" | grep -oP '"path":\s*"\K[^"]+')
            local type=$(echo "$project_obj" | grep -oP '"type":\s*"\K[^"]+')
            local category=$(echo "$project_obj" | grep -oP '"category":\s*"\K[^"]+')
            
            [[ -z "$path" || -z "$type" || -z "$category" ]] && continue
            
            # Filter by allowed categories if specified
            if [[ -n "$allowed_cats" ]]; then
                local match=0
                for allowed in ${allowed_cats//|/ }; do
                    [[ "$category" == "$allowed" ]] && match=1 && break
                done
                [[ $match -eq 0 ]] && continue
            fi
            
            echo "$path|$type|$category"
        done > "$nest_json.tmp"
    else
        # No nest.json - scan for .devcontainer dirs and extract categories from README.md
        print_info "No nest.json found. Scanning for containers..."
        echo ""
        
        # Find all .devcontainer dirs and build projects list (exclude .tmp and .bak)
        find "$start_dir" \( -name ".tmp" -o -name ".bak" -o -name "*.tmp" -o -name "*.bak" \) -prune -o -type d -name ".devcontainer" -print 2>/dev/null | sort | while read -r devcontainer_dir; do
            local project_dir="$(dirname "$devcontainer_dir")"
            local rel_path="${project_dir#$start_dir/}"
            [[ "$rel_path" == "$project_dir" ]] && rel_path="."
            
            # Skip root unless explicitly included with "."
            if [[ "$rel_path" == "." && "$include_root" != true ]]; then
                continue
            fi
            
            local dcjson="$devcontainer_dir/devcontainer.json"
            [[ ! -f "$dcjson" ]] && continue
            
            # Extract category from README.md first
            local category="unknown"
            local readme_file="$devcontainer_dir/README.md"
            if [[ -f "$readme_file" ]]; then
                category=$(grep -oP '(?<=^- \*\*Category\*\*: `)[^`]*' "$readme_file" 2>/dev/null | head -1)
                category="${category:-unknown}"
            fi
            
            # Fallback: try comment in devcontainer.json
            if [[ "$category" == "unknown" ]]; then
                category=$(grep -oiP '//\s*category:\s*\K[a-z0-9-]+' "$dcjson" 2>/dev/null | head -1)
                category="${category:-unknown}"
            fi
            
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
    fi

    
    # Handle --regen: delete existing .devcontainer directories (except root)
    if [[ "$NEST_REGEN" == true ]]; then
        print_kv "Regenerate mode" "DELETE existing containers and .devcontainer dirs (keeping root)"
        echo ""
        print_warning "This will DELETE all dev-control containers and .devcontainer directories under $start_dir (except root)"

        # First, delete any matching containers
        local -a container_ids
        mapfile -t container_ids < <(
            docker ps -q -a --filter "label=devcontainer.local_folder" 2>/dev/null | grep -v "^$" || true
        )
        
        if [[ ${#container_ids[@]} -gt 0 ]]; then
            echo ""
            print_info "Found ${#container_ids[@]} dev-control containers to delete:"
            local container_id
            for container_id in "${container_ids[@]}"; do
                local folder=$(docker inspect "$container_id" --format='{{.Config.Labels.devcontainer.local_folder}}' 2>/dev/null || echo "unknown")
                echo "  - $folder (${container_id:0:12})"
            done
            echo ""
            
            if confirm "Delete these containers?"; then
                echo ""
                for container_id in "${container_ids[@]}"; do
                    print_info "Stopping container ${container_id:0:12}..."
                    docker stop "$container_id" 2>/dev/null || true
                    print_info "Removing container ${container_id:0:12}..."
                    docker rm "$container_id" 2>/dev/null || true
                    print_success "Removed container ${container_id:0:12}"
                done
                echo ""
                print_success "Deleted ${#container_ids[@]} containers"
            else
                print_info "Skipped container deletion"
            fi
        fi

        local -a regen_dirs
        mapfile -t regen_dirs < <(
            find "$start_dir" -type d -name ".devcontainer" 2>/dev/null \
                | grep -v "^$start_dir/.devcontainer$" \
                | grep -vE '/(\.tmp|\.bak)/' \
                | sort
        )

        if [[ ${#regen_dirs[@]} -eq 0 ]]; then
            print_info "No .devcontainer directories found to delete"
            echo ""
        else
            print_info "Found ${#regen_dirs[@]} .devcontainer directories to delete:"
            local dc_dir
            for dc_dir in "${regen_dirs[@]}"; do
                echo "  - ${dc_dir#$start_dir/}"
            done
            echo ""
        fi

        if confirm "Are you ABSOLUTELY sure?"; then
            local count=0
            local dc_dir
            echo ""
            
            # Temporarily disable set -e for deletion loop (rm might fail on some dirs)
            set +e
            for dc_dir in "${regen_dirs[@]}"; do
                print_info "Deleting: ${dc_dir#$start_dir/}"
                rm -rf "$dc_dir"
                if [[ $? -eq 0 ]]; then
                    print_success "Deleted: ${dc_dir#$start_dir/}"
                else
                    print_warning "Failed to delete: ${dc_dir#$start_dir/}"
                fi
                ((count++))
            done
            set -e
            
            echo ""
            print_success "Deleted $count .devcontainer directories"
            echo ""
            print_info "Continuing with rebuild of recognised projects..."
            echo ""
        else
            print_info "Aborted"
            rm -f "$nest_json.tmp"
            return 0
        fi
    fi
    
    echo ""

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
        print_section "To regenerate these containers:"
        echo -e "  1. Cd into each project directory"
        echo -e "  2. Run: ${GREEN}containerise.sh --${type,,} --CATEGORY${NC}"
        echo -e "     (where CATEGORY is one of: art, game-dev, data-science, streaming, web-dev, dev-tools)"
        echo -e "  3. Or add them to ${CYAN}$nest_json${NC} manually"
        echo ""
    fi
    
    # Display recognised projects
    print_header "Recognised Projects (will be regenerated)"
    echo ""
    
    if [[ ${#known_projects[@]} -eq 0 ]]; then
        print_warning "No recognised category projects found"
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
    
    # ASK FOR CONFIRMATION FOR RECOGNISED PROJECTS
    # Skip if --regen was used (user already confirmed delete operation)
    if [[ "$NEST_REGEN" != true ]]; then
        print_warning "Regenerate ${#known_projects[@]} recognised containers?"
        read -p "Proceed? [y/N] " -n 1 -r
        echo ""
        echo ""
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Aborted - no changes made"
            rm -f "$nest_json.tmp"
            return 0
        fi
    else
        # With --regen, auto-proceed after deletion confirmation
        print_info "Auto-proceeding with rebuild of ${#known_projects[@]} containers..."
        echo ""
    fi
    
    # During --regen, prune all stale VS Code UID-wrapper images (vsc-*-uid) upfront
    # BEFORE any base images are built. This makes the prune order-independent and
    # predictable: it fires once here, not after whichever base happened to build first.
    # (The per-build prune in build_base_image() remains for standalone --base runs.)
    if [[ "$NEST_REGEN" == true ]]; then
        local stale_wrappers=()
        mapfile -t stale_wrappers < <(
            podman images --format "{{.Repository}}" 2>/dev/null \
                | grep "^localhost/vsc-" || true
        )
        if [[ ${#stale_wrappers[@]} -gt 0 ]]; then
            print_info "Pruning ${#stale_wrappers[@]} stale VS Code UID-wrapper image(s) before rebuild..."
            for wrapper in "${stale_wrappers[@]}"; do
                podman rmi --force "$wrapper" 2>/dev/null || true
            done
            print_success "Pruned. VS Code will rebuild wrappers from new base images."
            echo ""
        fi
    fi

    # Execute builds (only known projects)
    print_header "Building recognised containers"
    echo ""
    
    for proj in "${known_projects[@]}"; do
        IFS='|' read -r path type category <<< "$proj"
        local full_path="$start_dir/$path"
        [[ "$path" == "." ]] && full_path="$start_dir"
        
        # Verify project directory exists
        [[ ! -d "$full_path" ]] && continue
        
        echo ""
        print_info "$type: $path ($category)"
        (cd "$full_path" && "$SCRIPT_DIR/containerise.sh" --defaults --"${type,,}" --"$category" <<< y)
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
    
    # Load categories from YAML
    load_categories
    
    # Handle --nest mode early and exit
    if [[ "$NEST_MODE" == true ]]; then
        run_nest_mode "$PROJECT_PATH"
        exit 0
    fi
    
    # Handle --bare mode
    if [[ "$BARE_MODE" == true ]]; then
        print_header "Dev-Control Containerisation (Bare Mode)"
        print_info "Setting up minimal devcontainer (custom base image only)"
        # Bare mode: don't require defaults, continue to interactive config
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
    
    # Bare mode requires defaults or will use interactive config
    if [[ "$BARE_MODE" == true ]]; then
        if [[ "$USE_DEFAULTS" != true ]]; then
            print_warning "Bare mode with interactive config not fully supported"
            print_info "Use --defaults flag with --bare for one-shot setup"
            exit 1
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
