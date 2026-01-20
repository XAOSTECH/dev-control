#!/usr/bin/env bash
#
# Dev-Control Shared Library: License Detection
# Comprehensive license detection and SPDX mapping
#
# Usage:
#   source "${SCRIPT_DIR}/lib/license.sh"
#
# Features:
#   - Detect license from local file content
#   - SPDX license identifier header detection
#   - GitHub API license fetching
#   - Submodule license aggregation
#   - License compatibility checking
#

# Common license file patterns
LICENSE_FILE_PATTERNS=(
    "LICENSE"
    "LICENSE.txt"
    "LICENSE.md"
    "LICENCE"
    "LICENCE.txt"
    "LICENCE.md"
    "COPYING"
    "COPYING.txt"
    "license"
    "license.txt"
    "license.md"
    "License"
    "License.txt"
    "License.md"
)

# SPDX ID to display name mapping
declare -A SPDX_NAMES=(
    ["MIT"]="MIT License"
    ["Apache-2.0"]="Apache License 2.0"
    ["GPL-3.0"]="GNU General Public License v3.0"
    ["GPL-3.0-only"]="GNU General Public License v3.0 only"
    ["GPL-3.0-or-later"]="GNU General Public License v3.0 or later"
    ["GPL-2.0"]="GNU General Public License v2.0"
    ["GPL-2.0-only"]="GNU General Public License v2.0 only"
    ["LGPL-3.0"]="GNU Lesser General Public License v3.0"
    ["LGPL-2.1"]="GNU Lesser General Public License v2.1"
    ["BSD-3-Clause"]="BSD 3-Clause License"
    ["BSD-2-Clause"]="BSD 2-Clause License"
    ["ISC"]="ISC License"
    ["MPL-2.0"]="Mozilla Public License 2.0"
    ["AGPL-3.0"]="GNU Affero General Public License v3.0"
    ["Unlicense"]="The Unlicense"
    ["CC0-1.0"]="Creative Commons Zero v1.0 Universal"
    ["CC-BY-4.0"]="Creative Commons Attribution 4.0"
    ["WTFPL"]="Do What The F*ck You Want To Public License"
    ["Zlib"]="zlib License"
    ["NOASSERTION"]="No license detected"
)

# License compatibility matrix (simplified)
# Permissive licenses are generally compatible with copyleft
declare -A LICENSE_COMPATIBILITY=(
    ["MIT"]="permissive"
    ["Apache-2.0"]="permissive"
    ["BSD-3-Clause"]="permissive"
    ["BSD-2-Clause"]="permissive"
    ["ISC"]="permissive"
    ["Unlicense"]="permissive"
    ["CC0-1.0"]="permissive"
    ["Zlib"]="permissive"
    ["GPL-3.0"]="copyleft-strong"
    ["GPL-3.0-only"]="copyleft-strong"
    ["GPL-3.0-or-later"]="copyleft-strong"
    ["GPL-2.0"]="copyleft-strong"
    ["GPL-2.0-only"]="copyleft-strong"
    ["AGPL-3.0"]="copyleft-strong"
    ["LGPL-3.0"]="copyleft-weak"
    ["LGPL-2.1"]="copyleft-weak"
    ["MPL-2.0"]="copyleft-weak"
)

# Find license file in a directory
# Usage: find_license_file "/path/to/repo"
# Returns: path to license file or empty string
find_license_file() {
    local dir="${1:-.}"
    
    for pattern in "${LICENSE_FILE_PATTERNS[@]}"; do
        if [[ -f "$dir/$pattern" ]]; then
            echo "$dir/$pattern"
            return 0
        fi
    done
    
    return 1
}

# Detect SPDX identifier from file content
# Usage: detect_spdx_from_content "/path/to/LICENSE"
# Returns: SPDX ID or "NOASSERTION"
detect_spdx_from_content() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        echo "NOASSERTION"
        return 1
    fi
    
    local content
    content=$(head -150 "$file" 2>/dev/null)
    
    # First, check for explicit SPDX-License-Identifier header
    local spdx_header
    spdx_header=$(grep -oP 'SPDX-License-Identifier:\s*\K[^\s]+' "$file" 2>/dev/null | head -1)
    if [[ -n "$spdx_header" ]]; then
        echo "$spdx_header"
        return 0
    fi
    
    # Pattern matching for common licenses
    if echo "$content" | grep -qiE "MIT License|Permission is hereby granted.*MIT"; then
        echo "MIT"
    elif echo "$content" | grep -qiE "Apache License.*Version 2\.0|Licensed under the Apache License"; then
        echo "Apache-2.0"
    elif echo "$content" | grep -qiE "GNU GENERAL PUBLIC LICENSE.*Version 3|GPLv3"; then
        echo "GPL-3.0"
    elif echo "$content" | grep -qiE "GNU GENERAL PUBLIC LICENSE.*Version 2|GPLv2"; then
        echo "GPL-2.0"
    elif echo "$content" | grep -qiE "GNU LESSER GENERAL PUBLIC LICENSE.*Version 3|LGPLv3"; then
        echo "LGPL-3.0"
    elif echo "$content" | grep -qiE "GNU LESSER GENERAL PUBLIC LICENSE.*Version 2\.1|LGPLv2\.1"; then
        echo "LGPL-2.1"
    elif echo "$content" | grep -qiE "GNU AFFERO GENERAL PUBLIC LICENSE.*Version 3|AGPLv3"; then
        echo "AGPL-3.0"
    elif echo "$content" | grep -qiE "BSD 3-Clause|Redistribution and use.*three conditions"; then
        echo "BSD-3-Clause"
    elif echo "$content" | grep -qiE "BSD 2-Clause|Simplified BSD"; then
        echo "BSD-2-Clause"
    elif echo "$content" | grep -qiE "ISC License|ISC license"; then
        echo "ISC"
    elif echo "$content" | grep -qiE "Mozilla Public License.*2\.0|MPL-2\.0"; then
        echo "MPL-2.0"
    elif echo "$content" | grep -qiE "The Unlicense|unlicense\.org"; then
        echo "Unlicense"
    elif echo "$content" | grep -qiE "CC0 1\.0|Creative Commons Zero"; then
        echo "CC0-1.0"
    elif echo "$content" | grep -qiE "Creative Commons Attribution 4\.0|CC BY 4\.0"; then
        echo "CC-BY-4.0"
    elif echo "$content" | grep -qiE "zlib License|zlib/libpng"; then
        echo "Zlib"
    elif echo "$content" | grep -qiE "WTFPL|Do What The.*You Want"; then
        echo "WTFPL"
    else
        echo "NOASSERTION"
        return 1
    fi
    
    return 0
}

# Detect license from a local directory
# Usage: detect_local_license "/path/to/repo"
# Returns: SPDX ID
detect_local_license() {
    local dir="${1:-.}"
    local license_file
    
    license_file=$(find_license_file "$dir")
    if [[ -n "$license_file" ]]; then
        detect_spdx_from_content "$license_file"
    else
        echo "NOASSERTION"
        return 1
    fi
}

# Detect license from GitHub API
# Usage: detect_github_license "owner" "repo"
# Returns: SPDX ID or "NOASSERTION"
detect_github_license() {
    local owner="$1"
    local repo="$2"
    
    if ! command -v gh &>/dev/null; then
        echo "NOASSERTION"
        return 1
    fi
    
    local license_info
    license_info=$(gh repo view "${owner}/${repo}" --json licenseInfo --jq '.licenseInfo.spdxId' 2>/dev/null)
    
    if [[ -n "$license_info" && "$license_info" != "null" ]]; then
        echo "$license_info"
        return 0
    fi
    
    echo "NOASSERTION"
    return 1
}

# Detect license from remote URL
# Usage: detect_remote_license "https://github.com/owner/repo.git"
# Returns: SPDX ID
detect_remote_license() {
    local url="$1"
    
    if [[ "$url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
        local owner="${BASH_REMATCH[1]}"
        local repo="${BASH_REMATCH[2]%.git}"
        detect_github_license "$owner" "$repo"
    else
        echo "NOASSERTION"
        return 1
    fi
}

# Detect license for a repository (tries local first, then remote)
# Usage: detect_license "/path/to/repo"
# Returns: JSON object with license info
detect_license() {
    local dir="${1:-.}"
    local spdx_id="NOASSERTION"
    local source="none"
    local license_file=""
    
    # Try local file detection first
    license_file=$(find_license_file "$dir" 2>/dev/null || echo "")
    if [[ -n "$license_file" ]]; then
        spdx_id=$(detect_spdx_from_content "$license_file")
        source="file:$(basename "$license_file")"
    fi
    
    # If still no assertion, try GitHub API
    if [[ "$spdx_id" == "NOASSERTION" ]]; then
        local remote_url
        remote_url=$(git -C "$dir" config --get remote.origin.url 2>/dev/null || echo "")
        if [[ -n "$remote_url" ]]; then
            spdx_id=$(detect_remote_license "$remote_url")
            if [[ "$spdx_id" != "NOASSERTION" ]]; then
                source="github-api"
            fi
        fi
    fi
    
    # Output JSON
    cat <<EOF
{
  "spdx_id": "$spdx_id",
  "name": "${SPDX_NAMES[$spdx_id]:-Unknown}",
  "source": "$source",
  "path": "$dir",
  "category": "${LICENSE_COMPATIBILITY[$spdx_id]:-unknown}"
}
EOF
}

# Scan submodules for licenses
# Usage: scan_submodule_licenses "/path/to/repo" [recursive]
# Returns: JSON array of license info
scan_submodule_licenses() {
    local root_dir="${1:-.}"
    local recursive="${2:-false}"
    local results="["
    local first=true
    
    # Read .gitmodules if it exists
    if [[ ! -f "$root_dir/.gitmodules" ]]; then
        echo "[]"
        return 0
    fi
    
    # Parse submodule paths
    while IFS= read -r subpath; do
        [[ -z "$subpath" ]] && continue
        
        local full_path="$root_dir/$subpath"
        if [[ -d "$full_path" ]]; then
            local license_info
            license_info=$(detect_license "$full_path")
            
            if [[ "$first" == "true" ]]; then
                first=false
            else
                results+=","
            fi
            results+="$license_info"
            
            # Recursive scan
            if [[ "$recursive" == "true" && -f "$full_path/.gitmodules" ]]; then
                local nested
                nested=$(scan_submodule_licenses "$full_path" "true")
                if [[ "$nested" != "[]" ]]; then
                    results+=",${nested:1:-1}"  # Remove outer brackets
                fi
            fi
        fi
    done < <(git config --file "$root_dir/.gitmodules" --get-regexp 'submodule\..*\.path' 2>/dev/null | awk '{print $2}')
    
    results+="]"
    echo "$results"
}

# Check license compatibility
# Usage: check_license_compatibility "GPL-3.0" "MIT" "Apache-2.0"
# Returns: 0 if compatible, 1 if not
check_license_compatibility() {
    local root_license="$1"
    shift
    local dep_licenses=("$@")
    local root_category="${LICENSE_COMPATIBILITY[$root_license]:-unknown}"
    local issues=()
    
    for dep_license in "${dep_licenses[@]}"; do
        local dep_category="${LICENSE_COMPATIBILITY[$dep_license]:-unknown}"
        
        # Strong copyleft can't be used in permissive projects
        if [[ "$root_category" == "permissive" && "$dep_category" == "copyleft-strong" ]]; then
            issues+=("$dep_license (copyleft) incompatible with $root_license (permissive)")
        fi
    done
    
    if [[ ${#issues[@]} -gt 0 ]]; then
        printf '%s\n' "${issues[@]}"
        return 1
    fi
    
    return 0
}

# Get license display name
# Usage: get_license_name "MIT"
get_license_name() {
    local spdx_id="$1"
    echo "${SPDX_NAMES[$spdx_id]:-$spdx_id}"
}

# Get license category
# Usage: get_license_category "GPL-3.0"
get_license_category() {
    local spdx_id="$1"
    echo "${LICENSE_COMPATIBILITY[$spdx_id]:-unknown}"
}

# Cache license detection result in git config
# Usage: cache_license "MIT" "file:LICENSE"
cache_license() {
    local spdx_id="$1"
    local source="$2"
    
    if [[ -d ".git" ]]; then
        git config --local dc-init.license-type "$spdx_id"
        git config --local dc-init.license-source "$source"
    fi
}

# Load cached license from git config
# Usage: load_cached_license
# Returns: SPDX ID or empty
load_cached_license() {
    git config --local dc-init.license-type 2>/dev/null || echo ""
}
