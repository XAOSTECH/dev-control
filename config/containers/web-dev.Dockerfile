# ============================================================================
# WEB-DEV: Node.js, npm, modern web frameworks, Wrangler
# ============================================================================
#
# Category-specific layer appended after common-tools.Dockerfile
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# Install Wrangler globally (Cloudflare Workers CLI)
# Note: nvm/Node.js installed system-wide in common-tools.Dockerfile
RUN bash -c 'source /opt/nvm/nvm.sh && nvm use --lts && npm install -g wrangler'

# Verify installation
RUN bash -c 'source /opt/nvm/nvm.sh && nvm use --lts && wrangler --version'
