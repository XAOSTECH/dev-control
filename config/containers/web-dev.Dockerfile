# ============================================================================
# WEB-DEV: Node.js, npm, modern web frameworks, Wrangler
# ============================================================================
#
# Category-specific layer appended after common.Dockerfile
# Note: nvm/Node.js is installed in the common footer section
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

# Web development tools
RUN apt-get update && apt-get install -y \
    && rm -rf /var/lib/apt/lists/*
