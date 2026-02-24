# ============================================================================
# WEB-DEV: Node.js, npm, modern web frameworks, Wrangler
# ============================================================================
#
# Category-specific layer appended after common.Dockerfile
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# Install Wrangler globally (Cloudflare Workers CLI)
<<<<<<< HEAD
# Note: nvm/Node.js installed system-wide in common.Dockerfile
=======
# Note: nvm/Node.js installed system-wide in common-footer.Dockerfile
>>>>>>> parent of a262514 (fix: add nvm to web-dev category for wrangler dependency)
RUN bash -c 'source /opt/nvm/nvm.sh && npm install -g wrangler'

# Verify installation
RUN bash -c 'source /opt/nvm/nvm.sh && wrangler --version'
