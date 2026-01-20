#!/usr/bin/env bash
#
# Dev-Control Shared Library: Validation
# Input validation and sanitization helpers
#
# Usage:
#   source "${SCRIPT_DIR}/lib/validation.sh"
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

# ============================================================================
# STRING VALIDATION
# ============================================================================

# Check if a string is empty or whitespace only
# Usage: if is_empty "$var"; then ...
is_empty() {
    [[ -z "${1// /}" ]]
}

# Check if a string is a valid identifier (alphanumeric + underscore)
# Usage: if is_valid_identifier "my_var"; then ...
is_valid_identifier() {
    [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]
}

# Check if a string is a valid slug (lowercase, alphanumeric, hyphens)
# Usage: if is_valid_slug "my-repo"; then ...
is_valid_slug() {
    [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

# Convert string to slug
# Usage: slug=$(to_slug "My Project Name")
to_slug() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-' | sed 's/--*/-/g' | sed 's/^-//;s/-$//'
}

# ============================================================================
# PATH VALIDATION
# ============================================================================

# Check if a path exists and is a directory
# Usage: if is_directory "/path/to/dir"; then ...
is_directory() {
    [[ -d "$1" ]]
}

# Check if a path exists and is a file
# Usage: if is_file "/path/to/file"; then ...
is_file() {
    [[ -f "$1" ]]
}

# Check if a path is readable
# Usage: if is_readable "/path/to/file"; then ...
is_readable() {
    [[ -r "$1" ]]
}

# Check if a path is writable
# Usage: if is_writable "/path/to/file"; then ...
is_writable() {
    [[ -w "$1" ]]
}

# Resolve to absolute path
# Usage: abs_path=$(to_absolute_path "./relative/path")
to_absolute_path() {
    local path="$1"
    if [[ "$path" == /* ]]; then
        echo "$path"
    else
        echo "$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")"
    fi
}

# ============================================================================
# URL VALIDATION
# ============================================================================

# Check if a string looks like a URL
# Usage: if is_url "https://example.com"; then ...
is_url() {
    [[ "$1" =~ ^https?:// ]]
}

# Check if a string looks like a git URL
# Usage: if is_git_url "git@github.com:user/repo.git"; then ...
is_git_url() {
    [[ "$1" =~ ^(https?://|git@|git://|ssh://) ]]
}

# Check if a string looks like a GitHub URL
# Usage: if is_github_url "https://github.com/user/repo"; then ...
is_github_url() {
    [[ "$1" =~ github\.com ]]
}

# ============================================================================
# NUMBER VALIDATION
# ============================================================================

# Check if a string is a positive integer
# Usage: if is_positive_integer "42"; then ...
is_positive_integer() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

# Check if a string is a non-negative integer (including 0)
# Usage: if is_non_negative_integer "0"; then ...
is_non_negative_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

# Check if a value is within a range
# Usage: if in_range "5" "1" "10"; then ...
in_range() {
    local value="$1" min="$2" max="$3"
    [[ "$value" -ge "$min" && "$value" -le "$max" ]]
}

# ============================================================================
# DATE/TIME VALIDATION
# ============================================================================

# Check if a string is a valid ISO date (YYYY-MM-DD)
# Usage: if is_iso_date "2024-01-15"; then ...
is_iso_date() {
    [[ "$1" =~ ^[0-9]{4}-[0-1][0-9]-[0-3][0-9]$ ]]
}

# Check if a string is a valid ISO datetime
# Usage: if is_iso_datetime "2024-01-15T10:30:00"; then ...
is_iso_datetime() {
    [[ "$1" =~ ^[0-9]{4}-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9] ]]
}

# ============================================================================
# REQUIRED VALUE CHECKS
# ============================================================================

# Require a variable to be set and non-empty
# Usage: require_var "MY_VAR" "$MY_VAR"
require_var() {
    local name="$1"
    local value="$2"
    
    if is_empty "$value"; then
        print_error "Required variable '$name' is not set or empty."
        exit 1
    fi
}

# Require a file to exist
# Usage: require_file "/path/to/file"
require_file() {
    local path="$1"
    
    if [[ ! -f "$path" ]]; then
        print_error "Required file not found: $path"
        exit 1
    fi
}

# Require a directory to exist
# Usage: require_directory "/path/to/dir"
require_directory() {
    local path="$1"
    
    if [[ ! -d "$path" ]]; then
        print_error "Required directory not found: $path"
        exit 1
    fi
}

# Require a command to be available
# Usage: require_command "jq"
require_command() {
    local cmd="$1"
    
    if ! command -v "$cmd" &>/dev/null; then
        print_error "Required command not found: $cmd"
        exit 1
    fi
}
