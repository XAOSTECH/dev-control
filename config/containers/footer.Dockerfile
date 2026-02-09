# ============================================================================
# Common footer: User setup, nvm, dev-control (appended to all categories)
# ============================================================================
#
# Expects: CATEGORY variable set by build process
# Creates: Generic category-named user for base image reusability
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

# Note: CATEGORY, CFG_GITHUB_USER, CFG_GITHUB_USER_EMAIL, CFG_GPG_KEY_ID
# are replaced by containerise.sh during generation

# Create user ${CATEGORY} with sudo privileges
RUN if id ubuntu &>/dev/null; then \
        groupmod -n ${CATEGORY} ubuntu && \
        usermod -l ${CATEGORY} -d /home/${CATEGORY} ubuntu && \
        mkdir -p /home/${CATEGORY} && \
        chown -R ${CATEGORY}:${CATEGORY} /home/${CATEGORY}; \
    else \
        useradd -m -s /bin/bash ${CATEGORY}; \
    fi && \
    usermod -aG sudo ${CATEGORY} && \
    echo "${CATEGORY} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    mkdir -p /home/${CATEGORY}/.config /home/${CATEGORY}/.cache /home/${CATEGORY}/.local/share && \
    chown -R ${CATEGORY}:${CATEGORY} /home/${CATEGORY} && \
    rm -rf /root/.gnupg /home/${CATEGORY}/.gnupg

USER ${CATEGORY}
WORKDIR /home/${CATEGORY}

RUN touch ~/.hushlogin

# Configure nvm for user shell (installed system-wide in common layer)
RUN echo 'export NVM_DIR="/opt/nvm"' >> ~/.bashrc && \
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc

# Install dev-control system-wide to /opt
USER root
RUN mkdir -p /opt/dev-control && \
    curl -fsSL https://github.com/xaostech/dev-control/archive/refs/tags/latest.tar.gz | tar -xz --strip-components=1 -C /opt/dev-control && \
    chmod +x /opt/dev-control/scripts/*.sh /opt/dev-control/lib/*.sh /opt/dev-control/lib/git/*.sh 2>/dev/null || true && \
    echo 'export PATH=/opt/dev-control/scripts:$PATH' >> /etc/profile.d/dev-control.sh && \
    chmod 644 /etc/profile.d/dev-control.sh

# Pre-create .vscode-server, .gnupg, and .bash_backups directories with proper permissions
RUN mkdir -p /home/${CATEGORY}/.vscode-server /home/${CATEGORY}/.gnupg /home/${CATEGORY}/.bash_backups && \
    chown ${CATEGORY}:${CATEGORY} /home/${CATEGORY}/.vscode-server /home/${CATEGORY}/.gnupg /home/${CATEGORY}/.bash_backups && \
    chmod 775 /home/${CATEGORY}/.vscode-server && \
    chmod 700 /home/${CATEGORY}/.gnupg && \
    chmod 700 /home/${CATEGORY}/.bash_backups

# Set git config as root for the user's home
RUN ${GIT_CONFIG_CMD}

USER root

# Load dev-control aliases into bashrc as root, then fix permissions
RUN HOME=/home/${CATEGORY} bash -c 'bash /opt/dev-control/scripts/alias-loading.sh <<< A' && \
    chown ${CATEGORY}:${CATEGORY} /home/${CATEGORY}/.bash_aliases /home/${CATEGORY}/.bashrc

# Final permission enforcement (survives --userns remapping)
RUN chmod -R u+w /home/${CATEGORY}/.gnupg /home/${CATEGORY}/.ssh /home/${CATEGORY}/.cache 2>/dev/null || true && \
    chmod 700 /home/${CATEGORY}/.gnupg 2>/dev/null || true && \
    chown -R ${CATEGORY}:${CATEGORY} /home/${CATEGORY}/.gnupg /home/${CATEGORY}/.ssh /home/${CATEGORY}/.cache 2>/dev/null || true

USER ${CATEGORY}

WORKDIR /workspaces
