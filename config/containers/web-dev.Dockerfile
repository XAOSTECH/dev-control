# ============================================================================
# WEB-DEV: Node.js, npm, modern web frameworks, Wrangler
# ============================================================================
#
# Category-specific layer appended after common-base.Dockerfile
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# Install nvm and Node.js (needed for wrangler, also in common-footer for freshness)
ENV NVM_DIR=/opt/nvm
RUN mkdir -p /opt/nvm \
    && curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)/install.sh | bash \
    && bash -c 'source /opt/nvm/nvm.sh && nvm install --lts && nvm alias default lts/* && nvm cache clear' \
    && chmod -R a+rx /opt/nvm

ENV PATH=/opt/nvm/versions/node/default/bin:${PATH}

# Install Wrangler globally (Cloudflare Workers CLI)
RUN bash -c 'source /opt/nvm/nvm.sh && npm install -g wrangler'

# Verify installation
RUN bash -c 'source /opt/nvm/nvm.sh && wrangler --version'
