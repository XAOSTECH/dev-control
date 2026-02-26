#!/usr/bin/env bash
#
# Dev-Control Shared Library: Git Tree Visualization Data Extraction
# Functions for extracting git data for fractal tree visualization
#
# Usage:
#   source "${SCRIPT_DIR}/lib/git/tree-viz.sh"
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# ============================================================================
# GIT DATA EXTRACTION
# ============================================================================

# Extract all commits with metadata for visualization
# Output: JSON array of commits with sha, parents, author, date, message, refs
extract_commits_json() {
    local branch="${1:-HEAD}"
    local max_commits="${2:-500}"  # Limit for performance
    
    # Get commits with all needed data - use jq to properly escape subject
    git log "$branch" \
        --all \
        --max-count="$max_commits" \
        --date=iso-strict \
        --pretty=format:'%H%n%h%n%P%n%an%n%ae%n%ad%n%at%n%s%n%D' \
        2>/dev/null | \
        paste -d'|' - - - - - - - - - | \
        awk -F'|' '{print}' | \
        jq -R 'split("|") | {sha: .[0], short: .[1], parents: .[2], author: .[3], email: .[4], date: .[5], timestamp: (.[6] | tonumber), subject: .[7], refs: .[8]}' | \
        jq -s '.' || echo '[]'
}

# Extract branch information
# Output: JSON array of branches with name, sha, is_current, is_merged
extract_branches_json() {
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    
    local base_branch
    base_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
    
    echo "["
    local first=true
    while IFS= read -r line; do
        local branch_name sha is_merged is_current
        sha=$(echo "$line" | awk '{print $1}')
        branch_name=$(echo "$line" | sed 's/^[* ]*//' | awk '{$1=""; print $0}' | sed 's/^ //')
        
        is_current="false"
        [[ "$branch_name" == "$current_branch" ]] && is_current="true"
        
        is_merged="false"
        if git merge-base --is-ancestor "$sha" "$base_branch" 2>/dev/null; then
            is_merged="true"
        fi
        
        [[ "$first" == "false" ]] && echo ","
        first=false
        
        printf '  {"name":"%s","sha":"%s","current":%s,"merged":%s}' \
            "$branch_name" "$sha" "$is_current" "$is_merged"
    done < <(git branch -v --no-abbrev 2>/dev/null)
    echo ""
    echo "]"
}

# Extract tag information
# Output: JSON array of tags with name, sha, date
extract_tags_json() {
    echo "["
    local first=true
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        local tag_name sha
        tag_name=$(echo "$line" | awk '{print $2}' | sed 's/refs\/tags\///')
        sha=$(echo "$line" | awk '{print $1}')
        
        [[ "$first" == "false" ]] && echo ","
        first=false
        
        printf '  {"name":"%s","sha":"%s"}' "$tag_name" "$sha"
    done < <(git show-ref --tags 2>/dev/null)
    echo ""
    echo "]"
}

# Generate complete tree data JSON
# Output: JSON object with commits, branches, tags, metadata
generate_tree_data_json() {
    local output_file="${1:-/tmp/git-tree-data.json}"
    local max_commits="${2:-500}"
    
    local repo_name
    repo_name=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" || echo "repository")
    
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    
    cat > "$output_file" <<-EOF
{
  "metadata": {
    "repository": "$repo_name",
    "current_branch": "$current_branch",
    "generated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "max_commits": $max_commits
  },
  "commits": $(extract_commits_json "$current_branch" "$max_commits"),
  "branches": $(extract_branches_json),
  "tags": $(extract_tags_json)
}
EOF
    
    echo "$output_file"
}

# ============================================================================
# TREE LAYOUT CALCULATION
# ============================================================================

# Calculate fractal tree positions for commits
# Uses a mandelbrot-esque circular branch pattern
# Output: Enhanced JSON with x, y, angle, radius for each commit
calculate_tree_positions() {
    local input_json="$1"
    local output_file="${2:-/tmp/git-tree-positions.json}"
    
    # Source the pure bash layout calculator
    source "$(dirname "${BASH_SOURCE[0]}")/tree-layout.sh"
    
    # Use jq-based fractal layout (pure bash/jq, no python)
    if command -v jq &>/dev/null; then
        calculate_tree_positions_bash "$input_json" "$output_file" >/dev/null
    else
        # Fallback: simple vertical layout without jq
        calculate_tree_positions_simple "$input_json" "$output_file" >/dev/null
    fi
    
    echo "$output_file"
}

# ============================================================================
# VISUALIZATION METRICS
# ============================================================================

# Get repository statistics for visualization sizing
get_repo_stats() {
    local commit_count
    commit_count=$(git rev-list --count HEAD 2>/dev/null || echo 0)
    
    local branch_count
    branch_count=$(git branch | wc -l || echo 0)
    
    local merge_count
    merge_count=$(git log --merges --oneline | wc -l || echo 0)
    
    cat <<-EOF
{
  "commits": $commit_count,
  "branches": $branch_count,
  "merges": $merge_count,
  "suggested_width": $((800 + branch_count * 50)),
  "suggested_height": $((600 + commit_count * 2))
}
EOF
}
