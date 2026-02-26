#!/usr/bin/env bash
#
# Dev-Control Shared Library: Output Formatting
# Provides --json, --quiet, --verbose output mode support
#
# Usage:
#   source "$SCRIPT_DIR/lib/output.sh"
#   init_output_mode   # Call at script start
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# ============================================================================
# OUTPUT MODE DETECTION
# ============================================================================

# Output modes (set via environment or --flags)
# DC_QUIET, DC_VERBOSE, DC_JSON are set by gc entry point
# Scripts can also parse their own flags

init_output_mode() {
    # Inherit from environment
    OUTPUT_QUIET="${DC_QUIET:-false}"
    OUTPUT_VERBOSE="${DC_VERBOSE:-false}"
    OUTPUT_JSON="${DC_JSON:-false}"
    OUTPUT_DEBUG="${DC_DEBUG:-false}"
    
    # If JSON mode, suppress normal output
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        OUTPUT_QUIET=true
    fi
}

# ============================================================================
# CONDITIONAL OUTPUT
# ============================================================================

# Output only if not in quiet mode
# Usage: out "message"
out() {
    [[ "${OUTPUT_QUIET:-${DC_QUIET:-false}}" == "true" ]] && return 0
    echo "$*"
}

# Output only if not in quiet mode (with formatting)
# Usage: outf "format" args...
# Note: Caller is responsible for format string safety
outf() {
    [[ "$OUTPUT_QUIET" == "true" ]] && return 0
    # shellcheck disable=SC2059
    printf "$@"
}

# Output only in verbose mode
# Usage: verbose "message"
verbose() {
    [[ "$OUTPUT_VERBOSE" == "true" ]] && echo "$*"
    return 0
}

# Output only in debug mode
# Usage: debug "message"
debug() {
    [[ "$OUTPUT_DEBUG" == "true" ]] && echo "[DEBUG] $*" >&2
    return 0
}

# ============================================================================
# WRAPPED PRINT FUNCTIONS
# ============================================================================

# These wrap the print.sh functions but respect output modes

out_info() {
    [[ "$OUTPUT_QUIET" == "true" ]] && return 0
    print_info "$@"
}

out_success() {
    [[ "$OUTPUT_QUIET" == "true" ]] && return 0
    print_success "$@"
}

out_warning() {
    # Warnings always show unless JSON mode
    [[ "$OUTPUT_JSON" == "true" ]] && return 0
    print_warning "$@"
}

out_error() {
    # Errors always show (to stderr)
    print_error "$@"
}

out_header() {
    [[ "$OUTPUT_QUIET" == "true" ]] && return 0
    print_header "$@"
}

out_section() {
    [[ "$OUTPUT_QUIET" == "true" ]] && return 0
    print_section "$@"
}

# ============================================================================
# JSON OUTPUT HELPERS
# ============================================================================

# Start JSON object
json_start() {
    echo "{"
}

# End JSON object
json_end() {
    echo "}"
}

# Add JSON field (handles escaping)
# Usage: json_field "key" "value" [last]
json_field() {
    local key="$1"
    local value="$2"
    local last="${3:-false}"
    
    # Escape special characters in value
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\t'/\\t}"
    
    if [[ "$last" == "true" ]]; then
        printf '  "%s": "%s"\n' "$key" "$value"
    else
        printf '  "%s": "%s",\n' "$key" "$value"
    fi
}

# Add JSON number field
json_number() {
    local key="$1"
    local value="$2"
    local last="${3:-false}"
    
    if [[ "$last" == "true" ]]; then
        printf '  "%s": %s\n' "$key" "$value"
    else
        printf '  "%s": %s,\n' "$key" "$value"
    fi
}

# Add JSON boolean field
json_bool() {
    local key="$1"
    local value="$2"
    local last="${3:-false}"
    
    [[ "$value" == "true" || "$value" == "1" ]] && value="true" || value="false"
    
    if [[ "$last" == "true" ]]; then
        printf '  "%s": %s\n' "$key" "$value"
    else
        printf '  "%s": %s,\n' "$key" "$value"
    fi
}

# Add JSON array field
# Usage: json_array "key" "val1" "val2" "val3"
json_array() {
    local key="$1"
    shift
    local values=("$@")
    local last="${values[-1]}"
    
    # Check if last value is "true" (meaning it's the last field marker)
    if [[ "$last" == "true" || "$last" == "false" ]]; then
        unset 'values[-1]'
    else
        last="false"
    fi
    
    printf '  "%s": [' "$key"
    local first=true
    for val in "${values[@]}"; do
        $first || printf ', '
        first=false
        printf '"%s"' "$val"
    done
    
    if [[ "$last" == "true" ]]; then
        printf ']\n'
    else
        printf '],\n'
    fi
}

# Build and output JSON object
# Usage: json_output "key1=val1" "key2=val2" ...
json_output() {
    local fields=("$@")
    local count=${#fields[@]}
    local i=0
    
    echo "{"
    for field in "${fields[@]}"; do
        ((i++))
        local key="${field%%=*}"
        local value="${field#*=}"
        
        if [[ $i -eq $count ]]; then
            json_field "$key" "$value" "true"
        else
            json_field "$key" "$value"
        fi
    done
    echo "}"
}

# ============================================================================
# OUTPUT MODE FLAG PARSING
# ============================================================================

# Parse output-related flags from arguments
# Usage: parse_output_flags "$@"; set -- "${REMAINING_ARGS[@]}"
parse_output_flags() {
    REMAINING_ARGS=()
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -q|--quiet)
                OUTPUT_QUIET=true
                DC_QUIET=true
                shift
                ;;
            --verbose)
                OUTPUT_VERBOSE=true
                DC_VERBOSE=true
                shift
                ;;
            --json)
                OUTPUT_JSON=true
                OUTPUT_QUIET=true
                DC_JSON=true
                shift
                ;;
            --debug)
                OUTPUT_DEBUG=true
                DC_DEBUG=true
                shift
                ;;
            --no-colour)
                # Disable colours (these are used by sourcing scripts)
                NC="" RED="" GREEN="" YELLOW="" BLUE="" CYAN="" MAGENTA="" BOLD="" DIM=""
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
# INITIALISATION
# ============================================================================

# Auto-initialise if environment is set
init_output_mode
