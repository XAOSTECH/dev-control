#!/usr/bin/env bash
#
# Dev-Control Shared Library: Configuration
# Manages Dev-Control configuration from multiple sources
#
# Configuration hierarchy (highest priority first):
#   1. Environment variables (DC_*)
#   2. Project config (.dc-init.yaml in repo root)
#   3. Global config (~/.config/dev-control/config.yaml)
#   4. Built-in defaults
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# ============================================================================
# CONFIGURATION PATHS
# ============================================================================

DC_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dev-control"
DC_GLOBAL_CONFIG="$DC_CONFIG_DIR/config.yaml"
DC_PROJECT_CONFIG=".dc-init.yaml"
DC_LEGACY_PROJECT_CONFIG=".dc-init.yml"
DC_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dev-control"

# ============================================================================
# DEFAULT VALUES
# ============================================================================

declare -A DC_DEFAULTS=(
    ["default_licence"]="MIT"
    ["default_branch"]="main"
    ["auto_sign_commits"]="true"
    ["auto_push_after_fix"]="false"
    ["licence_deep_scan"]="false"
    ["interactive_mode"]="true"
    ["color_output"]="auto"
    ["editor"]="${EDITOR:-nano}"
    ["github_org"]=""
    ["template_set"]="default"
)

# ============================================================================
# YAML PARSING (Pure Bash - no dependencies)
# ============================================================================

# Simple YAML parser for flat key: value files
parse_yaml() {
    local file="$1"
    local prefix="${2:-}"
    local line key value
    
    [[ ! -f "$file" ]] && return 1
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        
        # Match key: value
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_-]*)[[:space:]]*:[[:space:]]*(.*)[[:space:]]*$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            
            # Remove quotes
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            
            # Replace hyphens with underscores
            key="${key//-/_}"
            
            printf '%s%s=%q\n' "$prefix" "$key" "$value"
        fi
    done < "$file"
}

# ============================================================================
# CONFIGURATION LOADING
# ============================================================================

load_gc_config() {
    local key value
    
    # Start with defaults
    for key in "${!DC_DEFAULTS[@]}"; do
        eval "DC_CONFIG_${key}=\"${DC_DEFAULTS[$key]}\""
    done
    
    # Load global config
    if [[ -f "$DC_GLOBAL_CONFIG" ]]; then
        eval "$(parse_yaml "$DC_GLOBAL_CONFIG" "DC_CONFIG_")"
    fi
    
    # Find project root and load project config
    local project_root
    if project_root=$(git rev-parse --show-toplevel 2>/dev/null); then
        if [[ -f "$project_root/$DC_PROJECT_CONFIG" ]]; then
            eval "$(parse_yaml "$project_root/$DC_PROJECT_CONFIG" "DC_CONFIG_")"
        elif [[ -f "$project_root/$DC_LEGACY_PROJECT_CONFIG" ]]; then
            eval "$(parse_yaml "$project_root/$DC_LEGACY_PROJECT_CONFIG" "DC_CONFIG_")"
        fi
    fi
    
    return 0
}

gc_config() {
    local key="$1"
    local default="${2:-}"
    local var_name
    
    # Replace dots and dashes with underscores for variable name
    var_name="DC_CONFIG_${key//./_}"
    var_name="${var_name//-/_}"
    
    if [[ -n "${!var_name+x}" ]]; then
        echo "${!var_name}"
    else
        echo "$default"
    fi
}

gc_config_set() {
    local key="$1"
    local value="$2"
    local scope="${3:-project}"
    local config_file
    local var_name
    
    # Replace dots and dashes with underscores for variable name
    var_name="DC_CONFIG_${key//./_}"
    var_name="${var_name//-/_}"
    
    if [[ "$scope" == "global" ]]; then
        config_file="$DC_GLOBAL_CONFIG"
        mkdir -p "$(dirname "$config_file")"
    else
        local project_root
        project_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
        config_file="$project_root/$DC_PROJECT_CONFIG"
    fi
    
    if [[ ! -f "$config_file" ]]; then
        echo "# Dev-Control configuration" > "$config_file"
    fi
    
    if grep -q "^${key}:" "$config_file" 2>/dev/null; then
        sed -i "s|^${key}:.*|${key}: ${value}|" "$config_file"
    else
        echo "${key}: ${value}" >> "$config_file"
    fi
    
    printf -v "$var_name" '%s' "$value"
}

gc_config_show() {
    local format="${1:-text}"
    local key var
    
    if [[ "$format" == "json" ]]; then
        echo "{"
        local first=true
        for var in $(compgen -v | grep ^DC_CONFIG_ | sort); do
            key="${var#DC_CONFIG_}"
            $first || echo ","
            first=false
            printf '  "%s": "%s"' "$key" "${!var}"
        done
        echo ""
        echo "}"
    else
        for var in $(compgen -v | grep ^DC_CONFIG_ | sort); do
            key="${var#DC_CONFIG_}"
            printf "%-25s %s\n" "${key}:" "${!var}"
        done
    fi
}

# ============================================================================
# LEGACY GC-INIT CONFIG
# ============================================================================

# Load Dev-Control metadata from git config
# Note: These variables are intended for use by caller scripts
load_gc_metadata() {
    git rev-parse --git-dir &>/dev/null || return 1
    
    PROJECT_NAME=$(git config --local --get dc-init.project-name 2>/dev/null || echo "")
    REPO_SLUG=$(git config --local --get dc-init.repo-slug 2>/dev/null || echo "")
    LICENSE_TYPE=$(git config --local --get dc-init.licence-type 2>/dev/null || echo "")
    DESCRIPTION=$(git config --local --get dc-init.description 2>/dev/null || echo "")
    ORG_NAME=$(git config --local --get dc-init.org-name 2>/dev/null || echo "")
    TOPICS=$(git config --local --get dc-init.topics 2>/dev/null || echo "")
    VISIBILITY=$(git config --local --get dc-init.visibility 2>/dev/null || echo "")
    TEMPLATE_SET=$(git config --local --get dc-init.template-set 2>/dev/null || echo "")
    WEBSITE_URL=$(git config --local --get dc-init.website-url 2>/dev/null || echo "")
    
    return 0
}

save_gc_metadata() {
    local key="$1"
    local value="$2"
    git config --local "dc-init.${key}" "$value"
}

has_gc_metadata() {
    git config --local --get-regexp '^dc-init\.' &>/dev/null
}

init_gc_config_dir() {
    mkdir -p "$DC_CONFIG_DIR"
    mkdir -p "$DC_CACHE_DIR"
}
