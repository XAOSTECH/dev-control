# ============================================================================
# ART: 2D/3D art tools, design software
# ============================================================================
#
# Category-specific layer appended after common-base.Dockerfile
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

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
