# ============================================================================
# WEB-DEV: Node.js, npm, modern web frameworks, Wrangler
# ============================================================================
#
# Category-specific layer appended after common.Dockerfile
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# Install nvm and Node.js system-wide (required for npx-dependent MCP servers like firecrawl)
ENV NVM_DIR=/opt/nvm
RUN mkdir -p /opt/nvm \
    && curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)/install.sh | bash \
    && bash -c 'source /opt/nvm/nvm.sh && nvm install --lts && nvm alias default lts/* && nvm use default && node_path="$(nvm which default)" && node_dir="$(dirname "$node_path")" && node_prefix="$(dirname "$node_dir")" && ln -sfn "$node_prefix" /opt/nvm/versions/node/default && nvm cache clear' \
    && chmod -R a+rx /opt/nvm

# Dynamically set PATH to latest installed Node version (supports nvm updates without rebuilds)
RUN echo 'export NVM_DIR=/opt/nvm && [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh" && export PATH=$(ls -d $NVM_DIR/versions/node/*/bin 2>/dev/null | head -1):$PATH' >> /etc/profile.d/load-nvm.sh \
    && chmod +x /etc/profile.d/load-nvm.sh

ENV PATH=/opt/nvm/versions/node/default/bin:${PATH}

# Install Wrangler globally (Cloudflare Workers CLI)
RUN bash -c 'source /opt/nvm/nvm.sh && nvm use default && npm install -g wrangler'

# Verify installation
RUN bash -c 'source /opt/nvm/nvm.sh && nvm use default && wrangler --version'
