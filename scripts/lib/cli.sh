#!/usr/bin/env bash
#
# Dev-Control Shared Library: CLI Utilities
# Common argument parsing and CLI helper functions
#
# Usage:
#   source "${SCRIPT_DIR}/lib/cli.sh"
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

# ============================================================================
# SCRIPT METADATA
# ============================================================================

# Resolve the actual script path (handles symlinks)
# Usage: SCRIPT_PATH=$(resolve_script_path "${BASH_SOURCE[0]}")
resolve_script_path() {
    local path="$1"
    while [[ -L "$path" ]]; do
        local dir
        dir=$(dirname "$path")
        path=$(readlink "$path")
        [[ "$path" != /* ]] && path="$dir/$path"
    done
    echo "$path"
}

# Get the directory containing the script
# Usage: SCRIPT_DIR=$(get_script_dir "${BASH_SOURCE[0]}")
get_script_dir() {
    local path
    path=$(resolve_script_path "$1")
    cd "$(dirname "$path")" && pwd
}

# ============================================================================
# ARGUMENT PARSING HELPERS
# ============================================================================

# Check if an argument is a flag (starts with -)
# Usage: if is_flag "$arg"; then ...
is_flag() {
    [[ "$1" == -* ]]
}

# Check if a flag has a value (next arg doesn't start with -)
# Usage: if flag_has_value "$next_arg"; then ...
flag_has_value() {
    [[ -n "$1" && "$1" != -* ]]
}

# Parse common flags and return remaining args
# Sets: SHOW_HELP, VERBOSE, DEBUG, DRY_RUN
# Usage: parse_common_flags "$@"
#        set -- "${REMAINING_ARGS[@]}"
# Note: Sets SHOW_HELP, VERBOSE, DEBUG, DRY_RUN variables for caller scripts
parse_common_flags() {
    # These variables are used by caller scripts, not directly here
    SHOW_HELP=false
    VERBOSE=false
    DEBUG=false
    DRY_RUN=false
    REMAINING_ARGS=()
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                SHOW_HELP=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            *)
                REMAINING_ARGS+=("$1")
                shift
                ;;
        esac
    done
}

# ============================================================================
# COMMAND DISPATCH
# ============================================================================

# Run a subcommand based on first argument
# Usage: dispatch_command "$1" "${@:2}"
#        Functions should be named: cmd_<subcommand>
dispatch_command() {
    local cmd="$1"
    shift
    
    if [[ -z "$cmd" ]]; then
        cmd="help"
    fi
    
    local func="cmd_${cmd//-/_}"
    
    if declare -f "$func" > /dev/null; then
        "$func" "$@"
    else
        print_error "Unknown command: $cmd"
        echo "Use --help for usage information"
        exit 1
    fi
}

# ============================================================================
# ENVIRONMENT UTILITIES
# ============================================================================

# Check if running in a devcontainer
# Usage: if is_devcontainer; then ...
is_devcontainer() {
    [[ -f "/.dockerenv" ]] || [[ -n "$REMOTE_CONTAINERS" ]] || [[ -n "$CODESPACES" ]]
}

# Check if running interactively (has a TTY)
# Usage: if is_interactive; then ...
is_interactive() {
    [[ -t 0 && -t 1 ]]
}

# Check if colors should be enabled
# Usage: if should_use_colors; then source colors.sh
should_use_colors() {
    [[ -t 1 ]] && [[ "${NO_COLOR:-}" != "1" ]] && [[ "${TERM:-}" != "dumb" ]]
}

# ============================================================================
# VERSION HANDLING
# ============================================================================

# Compare semantic versions
# Usage: if version_gte "2.0.0" "1.5.0"; then ...
version_gte() {
    local v1="$1" v2="$2"
    [[ "$(printf '%s\n%s' "$v1" "$v2" | sort -V | head -n1)" == "$v2" ]]
}

# Get git version
# Usage: GIT_VERSION=$(get_git_version)
get_git_version() {
    git --version | grep -oP '\d+\.\d+\.\d+' | head -1
}

# Check if git version is at least a certain version
# Usage: if git_version_at_least "2.28.0"; then ...
git_version_at_least() {
    local required="$1"
    local current
    current=$(get_git_version)
    version_gte "$current" "$required"
}
