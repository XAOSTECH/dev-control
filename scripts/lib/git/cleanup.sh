#!/usr/bin/env bash
#
# Dev-Control Shared Library: Git Cleanup Utilities
# Functions for cleaning up temporary branches, tags, and merged branches
#
# Usage:
#   source "${SCRIPT_DIR}/lib/git/cleanup.sh"
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

# Ensure print functions are available (source print.sh before this)
# shellcheck disable=SC2034

# ============================================================================
# REFERENCE DISCOVERY
# ============================================================================

# Get local tags matching tmp/backup/restore patterns
# Usage: local_tags=$(get_tmp_backup_tags)
get_tmp_backup_tags() {
    git tag -l 2>/dev/null | grep -iE 'tmp|backup|restore' || true
}

# Get local branches matching tmp/backup/restore patterns (excluding current)
# Usage: local_branches=$(get_tmp_backup_branches)
get_tmp_backup_branches() {
    git branch --list 2>/dev/null | grep -iE 'tmp|backup|restore' | sed 's/^[* ]*//' || true
}

# Get remote tags matching tmp/backup/restore patterns
# Usage: remote_tags=$(get_remote_tmp_backup_tags [remote])
get_remote_tmp_backup_tags() {
    local remote="${1:-origin}"
    git ls-remote --tags "$remote" 2>/dev/null | \
        grep -iE 'tmp|backup|restore' | \
        sed 's/.*refs\/tags\///' | \
        sed 's/\^{}//' | \
        sort -u || true
}

# Get remote branches matching tmp/backup/restore patterns
# Usage: remote_branches=$(get_remote_tmp_backup_branches [remote])
get_remote_tmp_backup_branches() {
    local remote="${1:-origin}"
    git branch -r 2>/dev/null | \
        grep -iE 'tmp|backup|restore' | \
        grep "$remote/" | \
        sed "s/.*$remote\///" || true
}

# ============================================================================
# MERGED BRANCH DETECTION
# ============================================================================

# Get the base/default branch name (Main/main/master/develop)
# Usage: base=$(get_base_branch)
get_base_branch() {
    local candidate
    for candidate in Main main master develop; do
        if git show-ref --verify --quiet "refs/heads/$candidate"; then
            echo "$candidate"
            return 0
        fi
    done
    echo ""
}

# Get local branches that are fully merged into base branch
# Usage: merged=$(get_merged_local_branches [base_branch])
get_merged_local_branches() {
    local base_branch="${1:-$(get_base_branch)}"
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    
    [[ -z "$base_branch" ]] && return 0
    
    git branch --merged "$base_branch" 2>/dev/null | \
        sed 's/^[* ]*//' | \
        grep -vE "^($current_branch|$base_branch|Main|main|master|develop)$" | \
        grep -viE 'tmp|backup|restore' || true
}

# Get remote branches that are fully merged into base branch
# Usage: merged=$(get_merged_remote_branches [base_branch] [remote])
get_merged_remote_branches() {
    local base_branch="${1:-$(get_base_branch)}"
    local remote="${2:-origin}"
    
    [[ -z "$base_branch" ]] && return 0
    
    git branch -r --merged "$base_branch" 2>/dev/null | \
        grep "$remote/" | \
        sed "s/.*$remote\///" | \
        grep -vE "^($base_branch|Main|main|master|develop|HEAD)$" | \
        grep -viE 'tmp|backup|restore' || true
}

# ============================================================================
# COUNT UTILITIES
# ============================================================================

# Count non-empty lines in a string
# Usage: count=$(count_lines "$string")
count_lines() {
    local input="$1"
    if [[ -z "$input" ]]; then
        echo 0
    else
        echo "$input" | wc -l
    fi
}

# ============================================================================
# DELETION OPERATIONS
# ============================================================================

# Delete local tags from a list
# Usage: delete_local_tags "$tags_list"
delete_local_tags() {
    local tags="$1"
    [[ -z "$tags" ]] && return 0
    echo "$tags" | xargs -r git tag -d 2>/dev/null || true
}

# Delete local branches from a list (force delete)
# Usage: delete_local_branches "$branches_list" [force]
delete_local_branches() {
    local branches="$1"
    local force="${2:-true}"
    local flag="-d"
    [[ "$force" == "true" ]] && flag="-D"
    
    [[ -z "$branches" ]] && return 0
    echo "$branches" | xargs -r -I{} git branch "$flag" {} 2>/dev/null || true
}

# Delete remote tags
# Usage: delete_remote_tags "$tags_list" [remote]
delete_remote_tags() {
    local tags="$1"
    local remote="${2:-origin}"
    [[ -z "$tags" ]] && return 0
    echo "$tags" | xargs -r -I{} git push "$remote" --delete "refs/tags/{}" 2>/dev/null || true
}

# Delete remote branches
# Usage: delete_remote_branches "$branches_list" [remote]
delete_remote_branches() {
    local branches="$1"
    local remote="${2:-origin}"
    [[ -z "$branches" ]] && return 0
    echo "$branches" | xargs -r -I{} git push "$remote" --delete {} 2>/dev/null || true
}

# ============================================================================
# INTERACTIVE CLEANUP FUNCTIONS
# ============================================================================

# Cleanup temporary and backup refs interactively
# Usage: cleanup_tmp_backup_refs [fd]
# Args:
#   fd: File descriptor for input (default: 3, use 0 for stdin)
cleanup_tmp_backup_refs() {
    local input_fd="${1:-3}"
    
    # Ensure print functions exist
    if ! declare -f print_info &>/dev/null; then
        print_info() { echo "[INFO] $*"; }
        print_success() { echo "[SUCCESS] $*"; }
    fi
    
    print_info "Scanning for temporary and backup references..."
    
    local local_tags local_branches remote_tags remote_branches
    local_tags=$(get_tmp_backup_tags)
    local_branches=$(get_tmp_backup_branches)
    remote_tags=$(get_remote_tmp_backup_tags)
    remote_branches=$(get_remote_tmp_backup_branches)
    
    local local_tag_count local_branch_count remote_tag_count remote_branch_count
    local_tag_count=$(count_lines "$local_tags")
    local_branch_count=$(count_lines "$local_branches")
    remote_tag_count=$(count_lines "$remote_tags")
    remote_branch_count=$(count_lines "$remote_branches")
    
    if [[ $local_tag_count -eq 0 && $local_branch_count -eq 0 && \
          $remote_tag_count -eq 0 && $remote_branch_count -eq 0 ]]; then
        print_success "No temporary or backup references found"
        return 0
    fi
    
    echo ""
    [[ $local_tag_count -gt 0 ]] && {
        echo "Found $local_tag_count local backup/tmp tags:"
        echo "$local_tags" | sed 's/^/  - /'
    }
    [[ $local_branch_count -gt 0 ]] && {
        echo "Found $local_branch_count local backup/tmp branches:"
        echo "$local_branches" | sed 's/^/  - /'
    }
    [[ $remote_tag_count -gt 0 ]] && {
        echo "Found $remote_tag_count remote backup/tmp tags:"
        echo "$remote_tags" | sed 's/^/  - /'
    }
    [[ $remote_branch_count -gt 0 ]] && {
        echo "Found $remote_branch_count remote backup/tmp branches:"
        echo "$remote_branches" | sed 's/^/  - /'
    }
    echo ""
    
    local confirm_cleanup
    read -u "$input_fd" -rp "Delete these tmp/backup references? [y/N]: " confirm_cleanup
    
    if [[ "$confirm_cleanup" =~ ^[Yy] ]]; then
        [[ $local_tag_count -gt 0 ]] && {
            delete_local_tags "$local_tags"
            print_success "Deleted $local_tag_count local tags"
        }
        [[ $local_branch_count -gt 0 ]] && {
            delete_local_branches "$local_branches" true
            print_success "Deleted $local_branch_count local branches"
        }
        [[ $remote_tag_count -gt 0 ]] && {
            delete_remote_tags "$remote_tags"
            print_success "Deleted $remote_tag_count remote tags"
        }
        [[ $remote_branch_count -gt 0 ]] && {
            delete_remote_branches "$remote_branches"
            print_success "Deleted $remote_branch_count remote branches"
        }
    else
        print_info "Tmp/backup cleanup cancelled"
    fi
}

# Cleanup merged branches interactively
# Usage: cleanup_merged_branches_interactive [fd]
# Args:
#   fd: File descriptor for input (default: 3, use 0 for stdin)
cleanup_merged_branches_interactive() {
    local input_fd="${1:-3}"
    
    # Ensure print functions exist
    if ! declare -f print_info &>/dev/null; then
        print_info() { echo "[INFO] $*"; }
        print_success() { echo "[SUCCESS] $*"; }
    fi
    
    print_info "Scanning for merged branches..."
    
    local base_branch
    base_branch=$(get_base_branch)
    
    if [[ -z "$base_branch" ]]; then
        print_info "No base branch (Main/main/master/develop) found, skipping merged branch cleanup"
        return 0
    fi
    
    print_info "Using base branch: $base_branch"
    
    local merged_local merged_remote
    merged_local=$(get_merged_local_branches "$base_branch")
    merged_remote=$(get_merged_remote_branches "$base_branch")
    
    local merged_local_count merged_remote_count
    merged_local_count=$(count_lines "$merged_local")
    merged_remote_count=$(count_lines "$merged_remote")
    
    if [[ $merged_local_count -eq 0 && $merged_remote_count -eq 0 ]]; then
        print_success "No merged branches found (all clean!)"
        return 0
    fi
    
    # Colours (use defaults if not set)
    local BOLD="${BOLD:-\033[1m}"
    local CYAN="${CYAN:-\033[36m}"
    local YELLOW="${YELLOW:-\033[33m}"
    local NC="${NC:-\033[0m}"
    
    echo ""
    echo -e "${BOLD}Found branches fully merged into ${CYAN}$base_branch${NC}${BOLD}:${NC}"
    
    [[ $merged_local_count -gt 0 ]] && {
        echo ""
        echo -e "${BOLD}Local merged branches ($merged_local_count):${NC}"
        echo "$merged_local" | sed 's/^/  - /'
    }
    [[ $merged_remote_count -gt 0 ]] && {
        echo ""
        echo -e "${BOLD}Remote merged branches ($merged_remote_count):${NC}"
        echo "$merged_remote" | sed 's/^/  - /'
    }
    echo ""
    echo -e "${YELLOW}Note: These branches have been fully merged and are safe to delete${NC}"
    echo ""
    
    local confirm_cleanup
    read -u "$input_fd" -rp "Delete merged branches? [y/N]: " confirm_cleanup
    
    if [[ "$confirm_cleanup" =~ ^[Yy] ]]; then
        [[ $merged_local_count -gt 0 ]] && {
            delete_local_branches "$merged_local" false  # Use -d not -D for safety
            print_success "Deleted $merged_local_count local merged branches"
        }
        [[ $merged_remote_count -gt 0 ]] && {
            delete_remote_branches "$merged_remote"
            print_success "Deleted $merged_remote_count remote merged branches"
        }
    else
        print_info "Merged branch cleanup cancelled"
    fi
}

# Full cleanup: tmp/backup refs + optionally merged branches
# Usage: cleanup_all_refs [cleanup_merged] [fd]
cleanup_all_refs() {
    local cleanup_merged="${1:-false}"
    local input_fd="${2:-3}"
    
    cleanup_tmp_backup_refs "$input_fd"
    
    if [[ "$cleanup_merged" == "true" ]]; then
        cleanup_merged_branches_interactive "$input_fd"
    fi
}
