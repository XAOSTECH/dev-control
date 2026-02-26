#!/usr/bin/env bash
#
# Dev-Control Shared Library: Licence Detection
# Comprehensive licence detection and SPDX mapping
#
# Usage:
#   source "${SCRIPT_DIR}/lib/licence.sh"
#
# Features:
#   - Detect licence from local file content
#   - SPDX licence identifier header detection
#   - GitHub API licence fetching
#   - Submodule licence aggregation
#   - Licence compatibility checking
#

# Common licence file patterns
LICENSE_FILE_PATTERNS=(
    "LICENSE"
    "LICENSE.txt"
    "LICENSE.md"
    "LICENCE"
    "LICENCE.txt"
    "LICENCE.md"
    "COPYING"
    "COPYING.txt"
    "licence"
    "licence.txt"
    "licence.md"
    "Licence"
    "Licence.txt"
    "Licence.md"
)

# SPDX ID to display name mapping
declare -A SPDX_NAMES=(
    ["MIT"]="MIT Licence"
    ["Apache-2.0"]="Apache Licence 2.0"
    ["GPL-3.0"]="GNU General Public Licence v3.0"
    ["GPL-3.0-only"]="GNU General Public Licence v3.0 only"
    ["GPL-3.0-or-later"]="GNU General Public Licence v3.0 or later"
    ["GPL-2.0"]="GNU General Public Licence v2.0"
    ["GPL-2.0-only"]="GNU General Public Licence v2.0 only"
    ["LGPL-3.0"]="GNU Lesser General Public Licence v3.0"
    ["LGPL-2.1"]="GNU Lesser General Public Licence v2.1"
    ["BSD-3-Clause"]="BSD 3-Clause Licence"
    ["BSD-2-Clause"]="BSD 2-Clause Licence"
    ["ISC"]="ISC Licence"
    ["MPL-2.0"]="Mozilla Public Licence 2.0"
    ["AGPL-3.0"]="GNU Affero General Public Licence v3.0"
    ["Unlicence"]="The Unlicence"
    ["CC0-1.0"]="Creative Commons Zero v1.0 Universal"
    ["CC-BY-4.0"]="Creative Commons Attribution 4.0"
    ["WTFPL"]="Do What The F*ck You Want To Public Licence"
    ["Zlib"]="zlib Licence"
    ["NOASSERTION"]="No licence detected"
)

# Licence compatibility matrix (simplified)
# Permissive licences are generally compatible with copyleft
declare -A LICENSE_COMPATIBILITY=(
    ["MIT"]="permissive"
    ["Apache-2.0"]="permissive"
    ["BSD-3-Clause"]="permissive"
    ["BSD-2-Clause"]="permissive"
    ["ISC"]="permissive"
    ["Unlicence"]="permissive"
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

# Find licence file in a directory
# Usage: find_licence_file "/path/to/repo"
# Returns: path to licence file or empty string
find_licence_file() {
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
    
    # First, check for explicit SPDX-Licence-Identifier header
    local spdx_header
    spdx_header=$(grep -oP 'SPDX-Licence-Identifier:\s*\K[^\s]+' "$file" 2>/dev/null | head -1)
    if [[ -n "$spdx_header" ]]; then
        echo "$spdx_header"
        return 0
    fi
    
    # Pattern matching for common licences
    # Note: Content is already read as single string, use separate checks for multi-line patterns
    if echo "$content" | grep -qiE "MIT Licence|Permission is hereby granted.*MIT"; then
        echo "MIT"
    elif echo "$content" | grep -qiE "Apache Licence.*Version 2\.0|Licenced under the Apache Licence"; then
        echo "Apache-2.0"
    elif echo "$content" | grep -qiE "GNU GENERAL PUBLIC LICENSE" && echo "$content" | grep -qE "Version 3"; then
        echo "GPL-3.0"
    elif echo "$content" | grep -qiE "GNU GENERAL PUBLIC LICENSE" && echo "$content" | grep -qE "Version 2[^.]"; then
        echo "GPL-2.0"
    elif echo "$content" | grep -qiE "GNU LESSER GENERAL PUBLIC LICENSE" && echo "$content" | grep -qE "Version 3"; then
        echo "LGPL-3.0"
    elif echo "$content" | grep -qiE "GNU LESSER GENERAL PUBLIC LICENSE.*Version 2\.1|LGPLv2\.1"; then
        echo "LGPL-2.1"
    elif echo "$content" | grep -qiE "GNU AFFERO GENERAL PUBLIC LICENSE.*Version 3|AGPLv3"; then
        echo "AGPL-3.0"
    elif echo "$content" | grep -qiE "BSD 3-Clause|Redistribution and use.*three conditions"; then
        echo "BSD-3-Clause"
    elif echo "$content" | grep -qiE "BSD 2-Clause|Simplified BSD"; then
        echo "BSD-2-Clause"
    elif echo "$content" | grep -qiE "ISC Licence|ISC licence"; then
        echo "ISC"
    elif echo "$content" | grep -qiE "Mozilla Public Licence.*2\.0|MPL-2\.0"; then
        echo "MPL-2.0"
    elif echo "$content" | grep -qiE "The Unlicence|unlicence\.org"; then
        echo "Unlicence"
    elif echo "$content" | grep -qiE "CC0 1\.0|Creative Commons Zero"; then
        echo "CC0-1.0"
    elif echo "$content" | grep -qiE "Creative Commons Attribution 4\.0|CC BY 4\.0"; then
        echo "CC-BY-4.0"
    elif echo "$content" | grep -qiE "zlib Licence|zlib/libpng"; then
        echo "Zlib"
    elif echo "$content" | grep -qiE "WTFPL|Do What The.*You Want"; then
        echo "WTFPL"
    else
        echo "NOASSERTION"
        return 1
    fi
    
    return 0
}

# Detect licence from a local directory
# Usage: detect_local_licence "/path/to/repo"
# Returns: SPDX ID
detect_local_licence() {
    local dir="${1:-.}"
    local licence_file
    
    licence_file=$(find_licence_file "$dir")
    if [[ -n "$licence_file" ]]; then
        detect_spdx_from_content "$licence_file"
    else
        echo "NOASSERTION"
        return 1
    fi
}

# Detect licence from GitHub API
# Usage: detect_github_licence "owner" "repo"
# Returns: SPDX ID or "NOASSERTION"
detect_github_licence() {
    local owner="$1"
    local repo="$2"
    
    if ! command -v gh &>/dev/null; then
        echo "NOASSERTION"
        return 1
    fi
    
    local licence_info
    licence_info=$(gh repo view "${owner}/${repo}" --json licenceInfo --jq '.licenceInfo.spdxId' 2>/dev/null)
    
    if [[ -n "$licence_info" && "$licence_info" != "null" ]]; then
        echo "$licence_info"
        return 0
    fi
    
    echo "NOASSERTION"
    return 1
}

# Detect licence from remote URL
# Usage: detect_remote_licence "https://github.com/owner/repo.git"
# Returns: SPDX ID
detect_remote_licence() {
    local url="$1"
    
    if [[ "$url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
        local owner="${BASH_REMATCH[1]}"
        local repo="${BASH_REMATCH[2]%.git}"
        detect_github_licence "$owner" "$repo"
    else
        echo "NOASSERTION"
        return 1
    fi
}

# Detect licence for a repository (tries local first, then remote)
# Usage: detect_licence "/path/to/repo"
# Returns: JSON object with licence info
detect_licence() {
    local dir="${1:-.}"
    local spdx_id="NOASSERTION"
    local source="none"
    local licence_file=""
    
    # Try local file detection first
    licence_file=$(find_licence_file "$dir" 2>/dev/null || echo "")
    if [[ -n "$licence_file" ]]; then
        spdx_id=$(detect_spdx_from_content "$licence_file")
        source="file:$(basename "$licence_file")"
    fi
    
    # If still no assertion, try GitHub API
    if [[ "$spdx_id" == "NOASSERTION" ]]; then
        local remote_url
        remote_url=$(git -C "$dir" config --get remote.origin.url 2>/dev/null || echo "")
        if [[ -n "$remote_url" ]]; then
            spdx_id=$(detect_remote_licence "$remote_url")
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

# Scan submodules for licences
# Usage: scan_submodule_licences "/path/to/repo" [recursive]
# Returns: JSON array of licence info
scan_submodule_licences() {
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
            local licence_info
            licence_info=$(detect_licence "$full_path")
            
            if [[ "$first" == "true" ]]; then
                first=false
            else
                results+=","
            fi
            results+="$licence_info"
            
            # Recursive scan
            if [[ "$recursive" == "true" && -f "$full_path/.gitmodules" ]]; then
                local nested
                nested=$(scan_submodule_licences "$full_path" "true")
                if [[ "$nested" != "[]" ]]; then
                    results+=",${nested:1:-1}"  # Remove outer brackets
                fi
            fi
        fi
    done < <(git config --file "$root_dir/.gitmodules" --get-regexp 'submodule\..*\.path' 2>/dev/null | awk '{print $2}')
    
    results+="]"
    echo "$results"
}

# Check licence compatibility
# Usage: check_licence_compatibility "GPL-3.0" "MIT" "Apache-2.0"
# Returns: 0 if compatible, 1 if not
check_licence_compatibility() {
    local root_licence="$1"
    shift
    local dep_licences=("$@")
    local root_category="${LICENSE_COMPATIBILITY[$root_licence]:-unknown}"
    local issues=()
    
    for dep_licence in "${dep_licences[@]}"; do
        local dep_category="${LICENSE_COMPATIBILITY[$dep_licence]:-unknown}"
        
        # Strong copyleft can't be used in permissive projects
        if [[ "$root_category" == "permissive" && "$dep_category" == "copyleft-strong" ]]; then
            issues+=("$dep_licence (copyleft) incompatible with $root_licence (permissive)")
        fi
    done
    
    if [[ ${#issues[@]} -gt 0 ]]; then
        printf '%s\n' "${issues[@]}"
        return 1
    fi
    
    return 0
}

# Get licence display name
# Usage: get_licence_name "MIT"
get_licence_name() {
    local spdx_id="$1"
    echo "${SPDX_NAMES[$spdx_id]:-$spdx_id}"
}

# Get licence category
# Usage: get_licence_category "GPL-3.0"
get_licence_category() {
    local spdx_id="$1"
    echo "${LICENSE_COMPATIBILITY[$spdx_id]:-unknown}"
}

# Cache licence detection result in git config
# Usage: cache_licence "MIT" "file:LICENSE"
cache_licence() {
    local spdx_id="$1"
    local source="$2"
    
    if [[ -d ".git" ]]; then
        git config --local dc-init.licence-type "$spdx_id"
        git config --local dc-init.licence-source "$source"
    fi
}

# Load cached licence from git config
# Usage: load_cached_licence
# Returns: SPDX ID or empty
load_cached_licence() {
    git config --local dc-init.licence-type 2>/dev/null || echo ""
}
