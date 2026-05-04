# ============================================================================
# Common footer: User setup, dev-control (appended to all categories)
# ============================================================================
#
# Expects: CATEGORY variable set by build process
# Creates: Generic category-named user for base image reusability
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# Note: CATEGORY, CFG_GITHUB_USER, CFG_GITHUB_USER_EMAIL, CFG_GPG_KEY_ID
# are replaced by containerise.sh during generation

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
    touch /home/${CATEGORY}/.hushlogin /home/${CATEGORY}/.bashrc && \
    chmod 755 /home/${CATEGORY} && \
    rm -rf /root/.gnupg /home/${CATEGORY}/.gnupg

# Configure nvm for user shell and GPG_TTY (run as root with explicit path — avoids
# UID name resolution instability in rootless podman layer snapshots)
RUN echo 'export NVM_DIR="/opt/nvm"' >> /home/${CATEGORY}/.bashrc && \
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> /home/${CATEGORY}/.bashrc && \
    echo 'export GPG_TTY=$(tty)' >> /home/${CATEGORY}/.bashrc

USER ${CATEGORY}
WORKDIR /home/${CATEGORY}

# Install dev-control system-wide to /opt
USER root
RUN mkdir -p /opt/dev-control && \
    wget -O- https://github.com/XAOSTECH/dev-control/archive/refs/tags/latest.tar.gz | tar -xz --strip-components=1 -C /opt/dev-control && \
    chmod +x /opt/dev-control/scripts/*.sh /opt/dev-control/lib/*.sh /opt/dev-control/lib/git/*.sh 2>/dev/null || true && \
    echo 'export PATH=/opt/dev-control/scripts:$PATH' >> /etc/profile.d/dev-control.sh && \
    chmod 644 /etc/profile.d/dev-control.sh

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

# Pre-create directories so VS Code never creates them as root before postCreate runs.
# All of these are also mounted as named volumes at runtime, so fuse-overlayfs xattr
# failures on NTFS-backed graphRoot cannot affect writability — but having them in the
# image prevents any fallback path that would create them root-owned.
# No ARG BUILD_DATE cache-buster: all affected dirs are named volumes, so runtime
# permissions are correct regardless of image layer cache age.
RUN mkdir -p \
        /home/${CATEGORY}/.vscode-server \
        /home/${CATEGORY}/.bash_backups \
        /home/${CATEGORY}/.gnupg \
        /home/${CATEGORY}/.ssh \
        /home/${CATEGORY}/.cache \
        /home/${CATEGORY}/.config \
        /home/${CATEGORY}/.devcontainer && \
    chmod 777 /home/${CATEGORY}/.vscode-server && \
    chmod 700 /home/${CATEGORY}/.bash_backups && \
    chmod 700 /home/${CATEGORY}/.gnupg && \
    chmod 700 /home/${CATEGORY}/.ssh && \
    chmod 755 /home/${CATEGORY}/.cache && \
    chmod 755 /home/${CATEGORY}/.config && \
    chmod 700 /home/${CATEGORY}/.devcontainer

# Root entrypoint: repairs filesystem bits stripped by fuse-overlayfs on
# NTFS-backed graphRoot (loses setuid + ownership across layer commits).
# Runs once at container start, then exec's the original command (VS Code's
# overrideCommand sleep loop). VS Code's exec sessions still attach as
# remoteUser=${CATEGORY} per devcontainer.json — only the long-running PID 1
# is root, which is required to restore the bits below.
RUN printf '%s\n' \
    '#!/bin/sh' \
    'set -e' \
    'chmod u+s /usr/bin/sudo 2>/dev/null || true' \
    'chown 1000:1000 /home/${CATEGORY} 2>/dev/null || true' \
    'chmod 755 /home/${CATEGORY} 2>/dev/null || true' \
    'chmod 700 /home/${CATEGORY}/.gnupg /home/${CATEGORY}/.ssh 2>/dev/null || true' \
    'exec "$@"' \
    > /usr/local/bin/dc-entrypoint.sh && \
    chmod 755 /usr/local/bin/dc-entrypoint.sh

# Metadata label for container discovery and category identification
LABEL dev-control.category="${CATEGORY}" \
      dev-control.type="base-image" \
      dev-control.source="https://github.com/xaostech/dev-control"

# NOTE: No final `USER ${CATEGORY}` directive. The container's PID 1 must run
# as root so the ENTRYPOINT can restore setuid on /usr/bin/sudo and ownership
# of /home/${CATEGORY} (both lost by fuse-overlayfs on NTFS). VS Code's
# remoteUser=${CATEGORY} setting in devcontainer.json controls who interactive
# shells run as — independent of the container's PID 1 user.
ENTRYPOINT ["/usr/local/bin/dc-entrypoint.sh"]
CMD ["sleep", "infinity"]

WORKDIR /workspaces
