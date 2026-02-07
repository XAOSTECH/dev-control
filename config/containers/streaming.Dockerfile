# ============================================================================
# STREAMING: FFmpeg+NVENC, NGINX-RTMP, SRT, ONNX Runtime GPU, YOLOv8
# ============================================================================
#
# Category-specific layer appended after common.Dockerfile
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

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

# ============================================================================
# Streaming: Create video and render groups for DRI/KMS device access
# ============================================================================

RUN groupadd -f -g 44 video && groupadd -f -g 109 render
