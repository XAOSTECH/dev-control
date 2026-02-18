#!/usr/bin/env bash
#
# Version management library for Dev-Control
#
# Provides:
#   - Version information
#   - Update checking
#   - Changelog parsing
#   - Version comparison utilities
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# Get script directory
_VERSION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# VERSION INFORMATION
# ============================================================================

# Current version
DC_VERSION="2.0.0"
DC_VERSION_DATE="2025-01-20"
DC_REPO="xaoscience/dev-control"
DC_BRANCH="Main"

# Get full version string
# Usage: gc_version_string
gc_version_string() {
    echo "dev-control v${DC_VERSION} (${DC_VERSION_DATE})"
}

# Get version number only
# Usage: gc_version
gc_version() {
    echo "$DC_VERSION"
}

# Get installation info
# Usage: gc_install_info
gc_install_info() {
    local install_dir="${DC_INSTALL_DIR:-$(cd "$_VERSION_LIB_DIR/../.." && pwd)}"
    
    if [[ -d "$install_dir/.git" ]]; then
        local commit
        commit=$(git -C "$install_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")
        local branch
        branch=$(git -C "$install_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        echo "Installed from: git ($branch @ $commit)"
        echo "Location: $install_dir"
    elif [[ -f "$install_dir/.version" ]]; then
        echo "Installed from: release"
        echo "Location: $install_dir"
    else
        echo "Installed from: unknown"
        echo "Location: $install_dir"
    fi
}

# ============================================================================
# VERSION COMPARISON
# ============================================================================

# Compare semantic versions
# Usage: version_compare "1.0.0" "2.0.0"
# Returns: -1 (less), 0 (equal), 1 (greater)
version_compare() {
    local v1="$1"
    local v2="$2"
    
    if [[ "$v1" == "$v2" ]]; then
        echo "0"
        return 0
    fi
    
    local IFS=.
    local i
    local -a v1_parts
    local -a v2_parts
    # SC2206: Use read -a or mapfile instead of word splitting
    read -ra v1_parts <<< "$v1"
    read -ra v2_parts <<< "$v2"
    
    # Fill empty positions with zeros
    for ((i=${#v1_parts[@]}; i<${#v2_parts[@]}; i++)); do
        v1_parts[i]=0
    done
    for ((i=${#v2_parts[@]}; i<${#v1_parts[@]}; i++)); do
        v2_parts[i]=0
    done
    
    # Compare parts
    for ((i=0; i<${#v1_parts[@]}; i++)); do
        # Remove any non-numeric suffix (e.g., 1.0.0-beta)
        local p1=${v1_parts[i]%%[!0-9]*}
        local p2=${v2_parts[i]%%[!0-9]*}
        
        if ((p1 > p2)); then
            echo "1"
            return 0
        fi
        if ((p1 < p2)); then
            echo "-1"
            return 0
        fi
    done
    
    echo "0"
}

# Check if version is greater than or equal
# Usage: version_gte "2.0.0" "1.5.0" && echo "yes"
version_gte() {
    local result
    result=$(version_compare "$1" "$2")
    [[ "$result" != "-1" ]]
}

# Check if version is greater than
# Usage: version_gt "2.0.0" "1.5.0" && echo "yes"
version_gt() {
    local result
    result=$(version_compare "$1" "$2")
    [[ "$result" == "1" ]]
}

# ============================================================================
# UPDATE CHECKING
# ============================================================================

# Check for updates from GitHub
# Usage: gc_check_update
gc_check_update() {
    local current="$DC_VERSION"
    local latest
    local update_url="https://api.github.com/repos/${DC_REPO}/releases/latest"
    
    # Try to get latest version
    if command -v curl &>/dev/null; then
        latest=$(curl -s "$update_url" 2>/dev/null | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')
    elif command -v wget &>/dev/null; then
        latest=$(wget -qO- "$update_url" 2>/dev/null | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')
    fi
    
    if [[ -z "$latest" ]]; then
        echo "Could not check for updates"
        return 1
    fi
    
    if version_gt "$latest" "$current"; then
        echo "Update available: v$current -> v$latest"
        echo "Run: gc update"
        return 0
    else
        echo "Already at latest version: v$current"
        return 0
    fi
}

# Perform update
# Usage: gc_update
gc_update() {
    local install_dir="${DC_INSTALL_DIR:-$(cd "$_VERSION_LIB_DIR/../.." && pwd)}"
    
    if [[ ! -d "$install_dir/.git" ]]; then
        echo "Cannot update: not a git installation"
        echo "Reinstall with: curl -sSL https://raw.githubusercontent.com/${DC_REPO}/${DC_BRANCH}/install.sh | bash"
        return 1
    fi
    
    echo "Updating Dev-Control..."
    git -C "$install_dir" fetch origin
    git -C "$install_dir" reset --hard "origin/${DC_BRANCH}"
    
    echo "Updated to: $(gc_version_string)"
}

# ============================================================================
# CHANGELOG
# ============================================================================

# Get changelog for version
# Usage: gc_changelog [version]
gc_changelog() {
    local version="${1:-$DC_VERSION}"
    local changelog_file="${DC_INSTALL_DIR:-$(cd "$_VERSION_LIB_DIR/../.." && pwd)}/CHANGELOG.md"
    
    if [[ ! -f "$changelog_file" ]]; then
        echo "No changelog found"
        return 1
    fi
    
    # Extract section for version
    awk -v ver="$version" '
        /^## \[/ {
            if (found) exit
            if (index($0, ver)) found=1
        }
        found { print }
    ' "$changelog_file"
}

# Get recent changes
# Usage: gc_recent_changes [count]
gc_recent_changes() {
    local count="${1:-5}"
    local changelog_file="${DC_INSTALL_DIR:-$(cd "$_VERSION_LIB_DIR/../.." && pwd)}/CHANGELOG.md"
    
    if [[ ! -f "$changelog_file" ]]; then
        echo "No changelog found"
        return 1
    fi
    
    # Get first N version entries
    awk -v count="$count" '
        /^## \[/ { found++; if (found > count) exit }
        found { print }
    ' "$changelog_file"
}
