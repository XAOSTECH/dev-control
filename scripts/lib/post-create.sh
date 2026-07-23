#!/usr/bin/env bash
#
# Dev-Control Post-Create Command Script (for Dockerfile)
#
# This script is executed during the Docker build process.
# It handles permissions, ownership, and other setup tasks.
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

set -e

# Arguments passed from Dockerfile
REMOTE_USER="$1"
HOST_UID="$2"
GIT_CONFIG_COMMAND="$3"

# This script runs as root inside the container during build.

# Fix sudo permissions
chmod u+s /usr/bin/sudo

# Set up home directory ownership and permissions
# The user's home directory is created by the 'useradd' command in the base Dockerfile.
# We ensure the permissions are correct here.
chown "${HOST_UID}:${HOST_UID}" "/home/${REMOTE_USER}"
chmod 755 "/home/${REMOTE_USER}"
# The .gnupg and .ssh directories will be created by volume mounts later,
# but we can create them here to set initial permissions.
mkdir -p "/home/${REMOTE_USER}/.gnupg" "/home/${REMOTE_USER}/.ssh"
chown -R "${HOST_UID}:${HOST_UID}" "/home/${REMOTE_USER}/.gnupg" "/home/${REMOTE_USER}/.ssh"
chmod 700 "/home/${REMOTE_USER}/.gnupg" "/home/${REMOTE_USER}/.ssh"

# Ensure GPG directory exists for agent
mkdir -p "/run/user/${HOST_UID}/gnupg"
chown -R "${HOST_UID}:${HOST_UID}" "/run/user/${HOST_UID}"

# Apply Git configuration
if [[ -n "$GIT_CONFIG_COMMAND" ]]; then
    # Run the git config commands as the remote user
    su - "${REMOTE_USER}" -c "$GIT_CONFIG_COMMAND"
fi
