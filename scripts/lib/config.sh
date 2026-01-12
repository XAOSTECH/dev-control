#!/usr/bin/env bash
#
# Git-Control Shared Library: Configuration
# gc-init metadata loading and saving functions
#
# Usage:
#   source "${SCRIPT_DIR}/lib/config.sh"
#

# Configuration prefix for git config
GC_CONFIG_PREFIX="gc-init"

# Load all gc-init metadata from git config
# Usage: load_gc_metadata
# Sets global variables: PROJECT_NAME, REPO_SLUG, ORG_NAME, SHORT_DESCRIPTION, LICENSE_TYPE
load_gc_metadata() {
    if [[ ! -d ".git" ]]; then
        return 1
    fi
    
    PROJECT_NAME=$(git config --local ${GC_CONFIG_PREFIX}.project-name 2>/dev/null || echo "")
    REPO_SLUG=$(git config --local ${GC_CONFIG_PREFIX}.repo-slug 2>/dev/null || echo "")
    ORG_NAME=$(git config --local ${GC_CONFIG_PREFIX}.org-name 2>/dev/null || echo "")
    SHORT_DESCRIPTION=$(git config --local ${GC_CONFIG_PREFIX}.description 2>/dev/null || echo "")
    LICENSE_TYPE=$(git config --local ${GC_CONFIG_PREFIX}.license-type 2>/dev/null || echo "")
    LICENSE_SOURCE=$(git config --local ${GC_CONFIG_PREFIX}.license-source 2>/dev/null || echo "")
    STABILITY=$(git config --local ${GC_CONFIG_PREFIX}.stability 2>/dev/null || echo "")
    
    return 0
}

# Save gc-init metadata to git config
# Usage: save_gc_metadata "key" "value"
save_gc_metadata() {
    local key="$1"
    local value="$2"
    
    if [[ ! -d ".git" ]]; then
        return 1
    fi
    
    if [[ -n "$value" ]]; then
        git config --local "${GC_CONFIG_PREFIX}.${key}" "$value"
    fi
}

# Save all gc-init metadata at once
# Usage: save_all_gc_metadata
save_all_gc_metadata() {
    [[ -n "${PROJECT_NAME:-}" ]] && save_gc_metadata "project-name" "$PROJECT_NAME"
    [[ -n "${REPO_SLUG:-}" ]] && save_gc_metadata "repo-slug" "$REPO_SLUG"
    [[ -n "${ORG_NAME:-}" ]] && save_gc_metadata "org-name" "$ORG_NAME"
    [[ -n "${SHORT_DESCRIPTION:-}" ]] && save_gc_metadata "description" "$SHORT_DESCRIPTION"
    [[ -n "${LICENSE_TYPE:-}" ]] && save_gc_metadata "license-type" "$LICENSE_TYPE"
    [[ -n "${LICENSE_SOURCE:-}" ]] && save_gc_metadata "license-source" "$LICENSE_SOURCE"
    [[ -n "${STABILITY:-}" ]] && save_gc_metadata "stability" "$STABILITY"
}

# Clear all gc-init metadata
# Usage: clear_gc_metadata
clear_gc_metadata() {
    if [[ ! -d ".git" ]]; then
        return 1
    fi
    
    git config --local --remove-section "$GC_CONFIG_PREFIX" 2>/dev/null || true
}

# Get a specific gc-init metadata value
# Usage: get_gc_metadata "license-type"
get_gc_metadata() {
    local key="$1"
    git config --local "${GC_CONFIG_PREFIX}.${key}" 2>/dev/null || echo ""
}

# Check if gc-init metadata exists
# Usage: has_gc_metadata
has_gc_metadata() {
    [[ -n "$(git config --local --get-regexp "^${GC_CONFIG_PREFIX}\." 2>/dev/null)" ]]
}

# Display all gc-init metadata
# Usage: show_gc_metadata
show_gc_metadata() {
    if ! has_gc_metadata; then
        echo "No gc-init metadata found."
        return 1
    fi
    
    echo "gc-init metadata:"
    git config --local --get-regexp "^${GC_CONFIG_PREFIX}\." 2>/dev/null | \
        sed "s/^${GC_CONFIG_PREFIX}\./  /" | \
        column -t -s ' ' 2>/dev/null || cat
}
