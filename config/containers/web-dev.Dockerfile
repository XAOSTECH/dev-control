# ============================================================================
# WEB-DEV: Node.js, npm, modern web frameworks, Wrangler
# ============================================================================
#
# Category-specific layer appended after common.Dockerfile
# Note: nvm/Node.js is installed in the common footer section
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

# Web development tools (minimal - most tools installed via npm/nvm in footer)
RUN apt-get update && apt-get install -y \
    python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*
