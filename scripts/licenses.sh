#!/usr/bin/env bash
#
# Dev-Control License Auditor
# Detect, display, and manage licenses across repositories and submodules
#
# Usage:
#   ./licenses.sh                     # Detect and display licenses
#   ./licenses.sh --deep              # Include submodules recursively
#   ./licenses.sh --json              # Output as JSON
#   ./licenses.sh --check GPL-3.0     # Check compatibility
#   ./licenses.sh --apply MIT         # Apply license template
#   ./licenses.sh --help              # Show help
#
# Aliases: dc-licenses, dc-lic
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"
export DEV_CONTROL_DIR  # Used by sourced libraries

# Source shared libraries
source "$SCRIPT_DIR/lib/colours.sh"
source "$SCRIPT_DIR/lib/print.sh"
source "$SCRIPT_DIR/lib/git/license.sh"
source "$SCRIPT_DIR/lib/git/utils.sh"

# CLI options
DEEP_SCAN=false
JSON_OUTPUT=false
CHECK_COMPAT=""
APPLY_LICENSE=""
SHOW_HELP=false
TARGET_DIR="."
REFRESH=false

# ============================================================================
# CLI ARGUMENT PARSING
# ============================================================================

show_help() {
    cat << 'EOF'
Dev-Control License Auditor - Detect and manage repository licenses

USAGE:
  licenses.sh [OPTIONS] [DIRECTORY]

OPTIONS:
  -d, --deep              Scan submodules recursively
  -j, --json              Output results as JSON
  -c, --check LICENSE     Check compatibility with specified license
  -a, --apply LICENSE     Apply a license template (MIT, Apache-2.0, GPL-3.0, BSD-3-Clause)
  -r, --refresh           Force re-detection (ignore cache)
  -h, --help              Show this help message

EXAMPLES:
  licenses.sh                           # Show license for current repo
  licenses.sh --deep                    # Include all submodules
  licenses.sh --json --deep             # JSON output with submodules
  licenses.sh --check GPL-3.0           # Check if deps are compatible with GPL-3.0
  licenses.sh --apply MIT               # Apply MIT license template
  licenses.sh /path/to/repo --deep      # Scan specific directory

OUTPUT:
  Default output shows a table with:
  - Repository/submodule path
  - Detected SPDX license identifier
  - Detection source (file, github-api, cache)
  - License category (permissive, copyleft-weak, copyleft-strong)

SUPPORTED LICENSES:
  MIT, Apache-2.0, GPL-3.0, GPL-2.0, LGPL-3.0, LGPL-2.1,
  BSD-3-Clause, BSD-2-Clause, ISC, MPL-2.0, AGPL-3.0,
  Unlicense, CC0-1.0, CC-BY-4.0, Zlib, WTFPL

ALIASES:
  dc-licenses, dc-lic

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--deep)
                DEEP_SCAN=true
                shift
                ;;
            -j|--json)
                JSON_OUTPUT=true
                shift
                ;;
            -c|--check)
                CHECK_COMPAT="$2"
                shift 2
                ;;
            -a|--apply)
                APPLY_LICENSE="$2"
                shift 2
                ;;
            -r|--refresh)
                REFRESH=true
                shift
                ;;
            -h|--help)
                SHOW_HELP=true
                shift
                ;;
            -*)
                echo "Unknown option: $1" >&2
                echo "Use --help for usage information" >&2
                exit 1
                ;;
            *)
                TARGET_DIR="$1"
                shift
                ;;
        esac
    done
}

# ============================================================================
# DISPLAY FUNCTIONS
# ============================================================================

print_license_header() {
    print_header "Dev-Control License Auditor"
}

print_license_table() {
    local root_license="$1"
    local submodule_licenses="$2"
    
    # Table header
    printf "${BOLD}%-40s %-15s %-18s %-15s${NC}\n" "Repository" "License" "Source" "Category"
    print_separator 90
    
    # Root repository
    local root_spdx root_source root_category
    root_spdx=$(echo "$root_license" | jq -r '.spdx_id' 2>/dev/null)
    root_source=$(echo "$root_license" | jq -r '.source' 2>/dev/null)
    root_category=$(echo "$root_license" | jq -r '.category' 2>/dev/null)
    
    local colour="$GREEN"
    [[ "$root_category" == "copyleft-strong" ]] && colour="$YELLOW"
    [[ "$root_spdx" == "NOASSERTION" ]] && colour="$RED"
    
    printf "%-40s ${colour}%-15s${NC} %-18s %-15s\n" \
        "$(basename "$TARGET_DIR") (root)" "$root_spdx" "$root_source" "$root_category"
    
    # Submodules
    if [[ -n "$submodule_licenses" && "$submodule_licenses" != "[]" ]]; then
        echo "$submodule_licenses" | jq -c '.[]' 2>/dev/null | while read -r sub; do
            local sub_path sub_spdx sub_source sub_category
            sub_path=$(echo "$sub" | jq -r '.path' 2>/dev/null)
            sub_spdx=$(echo "$sub" | jq -r '.spdx_id' 2>/dev/null)
            sub_source=$(echo "$sub" | jq -r '.source' 2>/dev/null)
            sub_category=$(echo "$sub" | jq -r '.category' 2>/dev/null)
            
            local sub_color="$GREEN"
            [[ "$sub_category" == "copyleft-strong" ]] && sub_color="$YELLOW"
            [[ "$sub_spdx" == "NOASSERTION" ]] && sub_color="$RED"
            
            # Indent based on depth
            local indent="└── "
            local display_path
            display_path=$(basename "$sub_path")
            
            printf "  ${indent}%-36s ${sub_color}%-15s${NC} %-18s %-15s\n" \
                "$display_path" "$sub_spdx" "$sub_source" "$sub_category"
        done
    fi
    
    echo ""
}

print_json_output() {
    local root_license="$1"
    local submodule_licenses="$2"
    
    cat <<EOF
{
  "root": $root_license,
  "submodules": $submodule_licenses,
  "scan_date": "$(date -Iseconds)",
  "deep_scan": $DEEP_SCAN
}
EOF
}

print_compatibility_check() {
    local target_license="$1"
    local root_license="$2"
    local submodule_licenses="$3"
    
    print_section "Compatibility Check: $target_license"
    
    # Collect all licenses
    local all_licenses=()
    local root_spdx
    root_spdx=$(echo "$root_license" | jq -r '.spdx_id' 2>/dev/null)
    all_licenses+=("$root_spdx")
    
    if [[ -n "$submodule_licenses" && "$submodule_licenses" != "[]" ]]; then
        while read -r spdx; do
            all_licenses+=("$spdx")
        done < <(echo "$submodule_licenses" | jq -r '.[].spdx_id' 2>/dev/null)
    fi
    
    # Check compatibility
    local issues
    if issues=$(check_license_compatibility "$target_license" "${all_licenses[@]}" 2>&1); then
        print_success "All detected licenses are compatible with ${BOLD}$target_license${NC}"
    else
        print_error "Compatibility issues found:"
        echo "$issues" | while read -r issue; do
            print_warning "$issue"
        done
    fi
    echo ""
}

# ============================================================================
# LICENSE APPLICATION
# ============================================================================

apply_license_template() {
    local license="$1"
    local target="$TARGET_DIR"
    local template_dir="$DEV_CONTROL_DIR/license-templates"
    
    # Normalise license name
    local template_file="$template_dir/$license"
    
    if [[ ! -f "$template_file" ]]; then
        print_error "License template not found: $license"
        echo "Available templates:"
        for f in "$template_dir"/*; do
            [[ -f "$f" ]] && print_list_item "$(basename "$f")"
        done
        exit 1
    fi
    
    # Get current year and org
    local current_year
    current_year=$(date +%Y)
    local org_name=""
    
    if command -v gh &>/dev/null; then
        org_name=$(gh api user --jq '.login' 2>/dev/null || echo "")
    fi
    
    if [[ -z "$org_name" ]]; then
        org_name=$(git config --get user.name 2>/dev/null || echo "Your Name")
    fi
    
    # Apply template
    local dest="$target/LICENSE"
    sed -e "s|{{CURRENT_YEAR}}|$current_year|g" \
        -e "s|{{ORG_NAME}}|$org_name|g" \
        "$template_file" > "$dest"
    
    print_success "Applied $license license to $dest"
    
    # Cache the license
    if [[ -d "$target/.git" ]]; then
        git -C "$target" config --local dc-init.license-type "$license"
        git -C "$target" config --local dc-init.license-source "file:LICENSE"
        print_info "Cached license metadata in git config"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    parse_args "$@"
    
    if [[ "$SHOW_HELP" == "true" ]]; then
        show_help
        exit 0
    fi
    
    # Normalise target directory
    TARGET_DIR=$(cd "$TARGET_DIR" 2>/dev/null && pwd)
    
    if [[ ! -d "$TARGET_DIR" ]]; then
        print_error "Directory not found: $TARGET_DIR"
        exit 1
    fi
    
    # Apply license if requested
    if [[ -n "$APPLY_LICENSE" ]]; then
        apply_license_template "$APPLY_LICENSE"
        exit 0
    fi
    
    # Detect licenses
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        print_license_header
    fi
    
    # Get root license
    local root_license
    root_license=$(detect_license "$TARGET_DIR")
    
    # Get submodule licenses if deep scan
    local submodule_licenses="[]"
    if [[ "$DEEP_SCAN" == "true" ]]; then
        submodule_licenses=$(scan_submodule_licenses "$TARGET_DIR" "true")
    fi
    
    # Output
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        print_json_output "$root_license" "$submodule_licenses"
    else
        print_license_table "$root_license" "$submodule_licenses"
    fi
    
    # Compatibility check
    if [[ -n "$CHECK_COMPAT" ]]; then
        print_compatibility_check "$CHECK_COMPAT" "$root_license" "$submodule_licenses"
    fi
}

main "$@"
