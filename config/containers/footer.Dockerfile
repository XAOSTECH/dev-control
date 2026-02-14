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
        usermod -u 1000 -l ${CATEGORY} -d /home/${CATEGORY} ubuntu && \
        mkdir -p /home/${CATEGORY} && \
        chown -R ${CATEGORY}:${CATEGORY} /home/${CATEGORY}; \
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

# Pre-create directories with proper permissions
# .gnupg must exist with correct permissions (700) so VS Code init doesn't fail trying to create it
# postCreateCommand will remove and recreate it fresh on each container start
RUN mkdir -p /home/${CATEGORY}/.vscode-server /home/${CATEGORY}/.bash_backups /home/${CATEGORY}/.gnupg && \
    chown ${CATEGORY}:${CATEGORY} /home/${CATEGORY}/.vscode-server /home/${CATEGORY}/.bash_backups /home/${CATEGORY}/.gnupg && \
    chmod 775 /home/${CATEGORY}/.vscode-server && \
    chmod 700 /home/${CATEGORY}/.bash_backups && \
    chmod 700 /home/${CATEGORY}/.gnupg

# Final permission enforcement (survives --userns remapping)
RUN chmod -R u+w /home/${CATEGORY}/.ssh /home/${CATEGORY}/.cache 2>/dev/null || true && \
    chown -R ${CATEGORY}:${CATEGORY} /home/${CATEGORY}/.ssh /home/${CATEGORY}/.cache 2>/dev/null || true

USER ${CATEGORY}

WORKDIR /workspaces
