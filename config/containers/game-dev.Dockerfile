# ============================================================================
# GAME-DEV: Godot, Vulkan, SDL2, GLFW, CUDA
# ============================================================================
#
# Category-specific layer appended after common.Dockerfile
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

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

# Build GLFW (latest) from source with native Wayland support
RUN GLFW_VERSION=$(curl -s https://api.github.com/repos/glfw/glfw/releases/latest | jq -r '.tag_name') \
    && git clone --depth 1 --branch ${GLFW_VERSION} https://github.com/glfw/glfw.git /tmp/glfw \
    && cd /tmp/glfw \
    && cmake -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DGLFW_BUILD_WAYLAND=ON \
        -DGLFW_BUILD_X11=OFF \
        -DBUILD_SHARED_LIBS=ON \
    && cmake --build build \
    && cmake --install build \
    && cd / && rm -rf /tmp/glfw \
    && ldconfig

# Install the latest stable CUDA Toolkit from the NVIDIA Ubuntu repo
RUN CUDA_REPO_URL="$(. /etc/os-release 2>/dev/null || true; VERSION_ID="${VERSION_ID:-26.04}"; printf '%s' "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${VERSION_ID//.}/x86_64/")" \
    && CUDA_PACKAGE="$(curl -fsSL "$CUDA_REPO_URL" 2>/dev/null | grep -oE 'cuda-toolkit-[0-9]+-[0-9]+' | LC_ALL=C sort -V | tail -n 1 || echo 'cuda-toolkit-13-5')" \
    && [ -n "$CUDA_PACKAGE" ] \
    && CUDA_NVCC_PACKAGE="${CUDA_PACKAGE/cuda-toolkit-/cuda-nvcc-}" \
    && CUDA_LIBRARIES_PACKAGE="${CUDA_PACKAGE/cuda-toolkit-/cuda-libraries-dev-}" \
    && CUDA_CUDART_PACKAGE="${CUDA_PACKAGE/cuda-toolkit-/cuda-cudart-dev-}" \
    && wget "${CUDA_REPO_URL}cuda-keyring_1.1-1_all.deb" -O /tmp/cuda-keyring.deb \
    && dpkg -i /tmp/cuda-keyring.deb && rm /tmp/cuda-keyring.deb \
    && apt-get update && apt-get install -y \
        "$CUDA_PACKAGE" "$CUDA_NVCC_PACKAGE" \
        "$CUDA_LIBRARIES_PACKAGE" "$CUDA_CUDART_PACKAGE" \
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
