#!/usr/bin/env bash
#
# Version management library for git-control
#
# Provides:
#   - Version information
#   - Update checking
#   - Changelog parsing
#   - Version comparison utilities
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

# Get script directory
_VERSION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# VERSION INFORMATION
# ============================================================================

# Current version
GC_VERSION="2.0.0"
GC_VERSION_DATE="2025-01-20"
GC_REPO="xaoscience/git-control"
GC_BRANCH="Main"

# Get full version string
# Usage: gc_version_string
gc_version_string() {
    echo "git-control v${GC_VERSION} (${GC_VERSION_DATE})"
}

# Get version number only
# Usage: gc_version
gc_version() {
    echo "$GC_VERSION"
}

# Get installation info
# Usage: gc_install_info
gc_install_info() {
    local install_dir="${GC_INSTALL_DIR:-$(cd "$_VERSION_LIB_DIR/../.." && pwd)}"
    local install_type="source"
    
    if [[ -d "$install_dir/.git" ]]; then
        local commit
        commit=$(git -C "$install_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")
        local branch
        branch=$(git -C "$install_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        echo "Installed from: git ($branch @ $commit)"
        echo "Location: $install_dir"
    elif [[ -f "$install_dir/.version" ]]; then
        install_type="release"
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
    local v1_parts=($v1)
    local v2_parts=($v2)
    
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
    local current="$GC_VERSION"
    local latest
    local update_url="https://api.github.com/repos/${GC_REPO}/releases/latest"
    
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
    local install_dir="${GC_INSTALL_DIR:-$(cd "$_VERSION_LIB_DIR/../.." && pwd)}"
    
    if [[ ! -d "$install_dir/.git" ]]; then
        echo "Cannot update: not a git installation"
        echo "Reinstall with: curl -sSL https://raw.githubusercontent.com/${GC_REPO}/${GC_BRANCH}/install.sh | bash"
        return 1
    fi
    
    echo "Updating git-control..."
    git -C "$install_dir" fetch origin
    git -C "$install_dir" reset --hard "origin/${GC_BRANCH}"
    
    echo "Updated to: $(gc_version_string)"
}

# ============================================================================
# CHANGELOG
# ============================================================================

# Get changelog for version
# Usage: gc_changelog [version]
gc_changelog() {
    local version="${1:-$GC_VERSION}"
    local changelog_file="${GC_INSTALL_DIR:-$(cd "$_VERSION_LIB_DIR/../.." && pwd)}/CHANGELOG.md"
    
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
    local changelog_file="${GC_INSTALL_DIR:-$(cd "$_VERSION_LIB_DIR/../.." && pwd)}/CHANGELOG.md"
    
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
