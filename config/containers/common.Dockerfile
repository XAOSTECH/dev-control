# Common base layer for all dev-control category images
# Sourced by containerise.sh generate_category_dockerfile()
#
# Provides: core dev tools, locale, timezone, GitHub CLI, nvm/Node.js
# Used by: --base builds (all categories), concatenated with category Dockerfiles
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive

# Install core development tools and dependencies
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    git \
    build-essential \
    sudo \
    locales \
    lsb-release \
    curl \
    wget \
    ca-certificates \
    gnupg \
    libsecret-tools \
    nano \
    jq \
    && sed -i '/${LOCALE}/s/^# //g' /etc/locale.gen \
    && locale-gen ${LOCALE} \
    && update-locale LANG=${LOCALE} LC_ALL=${LOCALE} \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=${LOCALE} \
    LC_ALL=${LOCALE} \
    TZ=${TZ} \
    EDITOR=nano

RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone

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
