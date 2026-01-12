#!/usr/bin/env bash
#
# Git-Control Shared Library: Configuration
# Manages git-control configuration from multiple sources
#
# Configuration hierarchy (highest priority first):
#   1. Environment variables (GC_*)
#   2. Project config (.gc-init.yaml in repo root)
#   3. Global config (~/.config/git-control/config.yaml)
#   4. Built-in defaults
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

# ============================================================================
# CONFIGURATION PATHS
# ============================================================================

GC_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/git-control"
GC_GLOBAL_CONFIG="$GC_CONFIG_DIR/config.yaml"
GC_PROJECT_CONFIG=".gc-init.yaml"
GC_LEGACY_PROJECT_CONFIG=".gc-init.yml"
GC_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/git-control"

# ============================================================================
# DEFAULT VALUES
# ============================================================================

declare -A GC_DEFAULTS=(
    ["default_license"]="MIT"
    ["default_branch"]="main"
    ["auto_sign_commits"]="true"
    ["auto_push_after_fix"]="false"
    ["license_deep_scan"]="false"
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
    for key in "${!GC_DEFAULTS[@]}"; do
        eval "GC_CONFIG_${key}=\"${GC_DEFAULTS[$key]}\""
    done
    
    # Load global config
    if [[ -f "$GC_GLOBAL_CONFIG" ]]; then
        eval "$(parse_yaml "$GC_GLOBAL_CONFIG" "GC_CONFIG_")"
    fi
    
    # Find project root and load project config
    local project_root
    if project_root=$(git rev-parse --show-toplevel 2>/dev/null); then
        if [[ -f "$project_root/$GC_PROJECT_CONFIG" ]]; then
            eval "$(parse_yaml "$project_root/$GC_PROJECT_CONFIG" "GC_CONFIG_")"
        elif [[ -f "$project_root/$GC_LEGACY_PROJECT_CONFIG" ]]; then
            eval "$(parse_yaml "$project_root/$GC_LEGACY_PROJECT_CONFIG" "GC_CONFIG_")"
        fi
    fi
    
    return 0
}

gc_config() {
    local key="$1"
    local default="${2:-}"
    local var="GC_CONFIG_${key}"
    
    if [[ -n "${!var+x}" ]]; then
        echo "${!var}"
    else
        echo "$default"
    fi
}

gc_config_set() {
    local key="$1"
    local value="$2"
    local scope="${3:-project}"
    local config_file
    
    if [[ "$scope" == "global" ]]; then
        config_file="$GC_GLOBAL_CONFIG"
        mkdir -p "$(dirname "$config_file")"
    else
        local project_root
        project_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
        config_file="$project_root/$GC_PROJECT_CONFIG"
    fi
    
    if [[ ! -f "$config_file" ]]; then
        echo "# git-control configuration" > "$config_file"
    fi
    
    if grep -q "^${key}:" "$config_file" 2>/dev/null; then
        sed -i "s|^${key}:.*|${key}: ${value}|" "$config_file"
    else
        echo "${key}: ${value}" >> "$config_file"
    fi
    
    eval "GC_CONFIG_${key//-/_}=\"$value\""
}

gc_config_show() {
    local format="${1:-text}"
    local key var
    
    if [[ "$format" == "json" ]]; then
        echo "{"
        local first=true
        for var in $(compgen -v | grep ^GC_CONFIG_ | sort); do
            key="${var#GC_CONFIG_}"
            $first || echo ","
            first=false
            printf '  "%s": "%s"' "$key" "${!var}"
        done
        echo ""
        echo "}"
    else
        for var in $(compgen -v | grep ^GC_CONFIG_ | sort); do
            key="${var#GC_CONFIG_}"
            printf "%-25s %s\n" "${key}:" "${!var}"
        done
    fi
}

# ============================================================================
# LEGACY GC-INIT CONFIG
# ============================================================================

load_gc_metadata() {
    git rev-parse --git-dir &>/dev/null || return 1
    
    PROJECT_NAME=$(git config --local --get gc-init.project-name 2>/dev/null || echo "")
    REPO_SLUG=$(git config --local --get gc-init.repo-slug 2>/dev/null || echo "")
    LICENSE_TYPE=$(git config --local --get gc-init.license-type 2>/dev/null || echo "")
    DESCRIPTION=$(git config --local --get gc-init.description 2>/dev/null || echo "")
    ORG_NAME=$(git config --local --get gc-init.org-name 2>/dev/null || echo "")
    TOPICS=$(git config --local --get gc-init.topics 2>/dev/null || echo "")
    VISIBILITY=$(git config --local --get gc-init.visibility 2>/dev/null || echo "")
    TEMPLATE_SET=$(git config --local --get gc-init.template-set 2>/dev/null || echo "")
    
    return 0
}

save_gc_metadata() {
    local key="$1"
    local value="$2"
    git config --local "gc-init.${key}" "$value"
}

has_gc_metadata() {
    git config --local --get-regexp '^gc-init\.' &>/dev/null
}

init_gc_config_dir() {
    mkdir -p "$GC_CONFIG_DIR"
    mkdir -p "$GC_CACHE_DIR"
}
