# ============================================================================
# Common footer: System tools + user setup + dev-control (appended to all categories)
# ============================================================================
#
# Expects: CATEGORY variable set by build process
# Creates: Generic category-named user for base image reusability
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# Note: CATEGORY, CFG_GITHUB_USER, CFG_GITHUB_USER_EMAIL, CFG_GPG_KEY_ID
# are replaced by containerise.sh during generation

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install nvm and Node.js system-wide (required for npx-dependent MCP servers like firecrawl)
ENV NVM_DIR=/opt/nvm
RUN mkdir -p /opt/nvm \
    && curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)/install.sh | bash \
    && bash -c 'source /opt/nvm/nvm.sh && nvm install --lts && nvm alias default lts/* && nvm cache clear' \
    && chmod -R a+rx /opt/nvm

# Dynamically set PATH to latest installed Node version (supports nvm updates without rebuilds)
RUN echo 'export NVM_DIR=/opt/nvm && [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh" && export PATH=$(ls -d $NVM_DIR/versions/node/*/bin 2>/dev/null | head -1):$PATH' >> /etc/profile.d/load-nvm.sh \
    && chmod +x /etc/profile.d/load-nvm.sh

ENV PATH=/opt/nvm/versions/node/default/bin:${PATH}

# Create user ${CATEGORY} with sudo privileges
RUN if id ubuntu &>/dev/null; then \
        groupmod -n ${CATEGORY} ubuntu && \
        usermod -l ${CATEGORY} -d /home/${CATEGORY} -m ubuntu; \
    else \
        useradd -m -s /bin/bash -u 1000 ${CATEGORY}; \
    fi && \
    usermod -aG sudo ${CATEGORY} && \
    echo "${CATEGORY} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    mkdir -p /home/${CATEGORY}/.config /home/${CATEGORY}/.cache /home/${CATEGORY}/.local/share && \
    chown -R ${CATEGORY}:${CATEGORY} /home/${CATEGORY} && \
    chmod 755 /home/${CATEGORY} && \
    rm -rf /root/.gnupg /home/${CATEGORY}/.gnupg

USER ${CATEGORY}
WORKDIR /home/${CATEGORY}

RUN touch ~/.hushlogin ~/.bashrc

# Configure nvm for user shell (installed system-wide in common layer)
# Set GPG_TTY correctly for interactive shells (must be evaluated at runtime, not baked in).
RUN echo 'export NVM_DIR="/opt/nvm"' >> ~/.bashrc && \
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc && \
    echo 'export GPG_TTY=$(tty)' >> ~/.bashrc

# Install dev-control system-wide to /opt
USER root
RUN mkdir -p /opt/dev-control && \
    wget -O- https://github.com/XAOSTECH/dev-control/archive/refs/tags/latest.tar.gz | tar -xz --strip-components=1 -C /opt/dev-control && \
    chmod +x /opt/dev-control/scripts/*.sh /opt/dev-control/lib/*.sh /opt/dev-control/lib/git/*.sh 2>/dev/null || true && \
    echo 'export PATH=/opt/dev-control/scripts:$PATH' >> /etc/profile.d/dev-control.sh && \
    chmod 644 /etc/profile.d/dev-control.sh

# Pre-create directories with proper permissions before VS Code init runs.
# VS Code's container setup (pre-postCreateCommand) creates missing dirs as root,
# which permanently breaks writability for the container user.
# Pre-creating here with correct ownership prevents that race condition.
# BUILD_DATE busts this layer's cache on each build so permissions are always applied fresh.
ARG BUILD_DATE
RUN mkdir -p \
        /home/${CATEGORY}/.vscode-server \
        /home/${CATEGORY}/.bash_backups \
        /home/${CATEGORY}/.gnupg \
        /home/${CATEGORY}/.ssh \
        /home/${CATEGORY}/.cache \
        /home/${CATEGORY}/.config \
        /home/${CATEGORY}/.devcontainer && \
    chown -R ${CATEGORY}:${CATEGORY} \
        /home/${CATEGORY}/.vscode-server \
        /home/${CATEGORY}/.bash_backups \
        /home/${CATEGORY}/.gnupg \
        /home/${CATEGORY}/.ssh \
        /home/${CATEGORY}/.cache \
        /home/${CATEGORY}/.config \
        /home/${CATEGORY}/.devcontainer && \
    chmod 775 /home/${CATEGORY}/.vscode-server && \
    chmod 700 /home/${CATEGORY}/.bash_backups && \
    chmod 700 /home/${CATEGORY}/.gnupg && \
    chmod 700 /home/${CATEGORY}/.ssh && \
    chmod 755 /home/${CATEGORY}/.cache && \
    chmod 755 /home/${CATEGORY}/.config && \
    chmod 700 /home/${CATEGORY}/.devcontainer

# Metadata label for container discovery and category identification
LABEL dev-control.category="${CATEGORY}" \
      dev-control.type="base-image" \
      dev-control.source="https://github.com/xaostech/dev-control"

USER ${CATEGORY}

WORKDIR /workspaces
