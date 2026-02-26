# Common base layer for all dev-control category images
# Sourced by containerise.sh generate_category_dockerfile()
#
# Provides: core dev tools, locale, timezone
# Used by: --base builds (all categories), concatenated with category Dockerfiles
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
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
