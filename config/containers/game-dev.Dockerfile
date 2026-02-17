# ============================================================================
# GAME-DEV: Godot, Vulkan, SDL2, GLFW, CUDA
# ============================================================================
#
# Category-specific layer appended after common.Dockerfile
#
# SPDX-License-Identifier: GPL-3.0-or-later
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
