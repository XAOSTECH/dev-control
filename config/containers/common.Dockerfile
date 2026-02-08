# Common base layer for all dev-control category images
# Sourced by containerise.sh generate_category_dockerfile()
#
# Provides: core dev tools, locale, timezone, GitHub CLI, nvm/Node.js
# Used by: --base builds (all categories), concatenated with category Dockerfiles
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

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
    && sed -i '/${LOCALE%.*}/s/^# //g' /etc/locale.gen \
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
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash \
    && bash -c 'source /opt/nvm/nvm.sh && nvm install 22 && nvm alias default 22' \
    && chmod -R a+rx /opt/nvm

# Set PATH for npx/npm to work in non-shell contexts (MCP servers, IDE integrations)
ENV PATH=/opt/nvm/versions/node/v22.13.1/bin:${PATH}
