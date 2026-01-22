#!/usr/bin/env bash
#
# Dev-Control Shared Library: Git Worktree Utilities
# Functions for managing and synchronizing git worktrees
#
# Usage:
#   source "${SCRIPT_DIR}/lib/git/worktree.sh"
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

# Ensure print functions are available (source print.sh before this)
# shellcheck disable=SC2034

# ============================================================================
# WORKTREE DISCOVERY
# ============================================================================

# Find worktree paths which have the given branch checked out
# Usage: find_worktree_paths_for_branch "branch-name"
# Returns: Newline-separated list of worktree paths
find_worktree_paths_for_branch() {
    local branch="$1"
    local out
    out=$(git worktree list --porcelain 2>/dev/null || true)
    local paths=()
    
    if [[ -z "$out" ]]; then
        echo ""
        return 0
    fi

    local path=""
    while IFS= read -r line; do
        if [[ "$line" == worktree* ]]; then
            path="${line#worktree }"
        elif [[ "$line" == branch* ]]; then
            local bref=${line#branch }
            # Normalize to refs/heads/<branch>
            if [[ "$bref" == "refs/heads/$branch" || "$bref" == "$branch" ]]; then
                paths+=("$path")
            fi
        fi
    done <<< "$out"

    # Print newline-separated paths
    (for p in "${paths[@]}"; do echo "$p"; done)
}

# List all worktree paths
# Usage: list_all_worktrees
# Returns: Newline-separated list of worktree paths
list_all_worktrees() {
    git worktree list --porcelain 2>/dev/null | grep '^worktree ' | cut -d' ' -f2-
}

# Get the branch name for a specific worktree path
# Usage: get_worktree_branch "/path/to/worktree"
# Returns: Branch name or empty if detached/not found
get_worktree_branch() {
    local worktree_path="$1"
    local out
    out=$(git worktree list --porcelain 2>/dev/null || true)
    
    local current_path="" in_target=false
    while IFS= read -r line; do
        if [[ "$line" == worktree* ]]; then
            current_path="${line#worktree }"
            if [[ "$current_path" == "$worktree_path" ]]; then
                in_target=true
            else
                in_target=false
            fi
        elif [[ "$in_target" == true && "$line" == branch* ]]; then
            local bref=${line#branch }
            # Strip refs/heads/ prefix if present
            echo "${bref#refs/heads/}"
            return 0
        fi
    done <<< "$out"
    
    echo ""
}

# ============================================================================
# WORKTREE SYNCHRONIZATION
# ============================================================================

# Update worktrees which have the branch checked out to match origin/branch
# Usage: update_worktrees_to_remote "branch-name"
# Creates backup bundles before updating
update_worktrees_to_remote() {
    local branch="$1"
    local ts
    ts=$(date -u +%Y%m%dT%H%M%SZ)

    local paths
    paths=$(find_worktree_paths_for_branch "$branch")
    if [[ -z "$paths" ]]; then
        print_info "No worktrees found using branch: $branch"
        return 0
    fi

    print_info "Found worktrees using '$branch', updating them to origin/$branch"
    for p in $paths; do
        print_info "Updating worktree at: $p"
        # Make a bundle backup of the branch as it appears in the worktree
        local bundle="/tmp/git-fix-worktree-backup-${branch//\//-}-${ts}.bundle"
        git -C "$p" bundle create "$bundle" "refs/heads/$branch" || print_warning "Failed to create worktree bundle for $p"

        # Fetch origin
        git -C "$p" fetch origin || print_warning "Failed to fetch in $p"

        if ! git -C "$p" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
            print_warning "origin/$branch not found; skipping update for $p"
            continue
        fi

        # Determine current branch in that worktree
        local curr_branch
        curr_branch=$(git -C "$p" symbolic-ref --quiet --short HEAD 2>/dev/null || true)

        if [[ "$curr_branch" == "$branch" ]]; then
            # Detach HEAD so we can safely update the branch ref even though it was checked out
            print_info "Branch $branch is currently checked out in $p; detaching HEAD, forcing update, and re-checking out"
            git -C "$p" checkout --detach HEAD || print_warning "Failed to detach HEAD in $p"

            # Force the branch to origin/<branch>
            git -C "$p" branch -f "$branch" "origin/$branch" || print_warning "Failed to force-update branch $branch in $p"

            # Re-checkout branch (now matches origin)
            git -C "$p" checkout "$branch" || print_warning "Failed to checkout $branch in $p"

            print_success "Safely updated checked-out branch $branch in worktree: $p (backup: $bundle)"
        else
            # Branch not checked out in this worktree: update local ref to match origin
            git -C "$p" update-ref "refs/heads/$branch" "refs/remotes/origin/$branch" || print_warning "Failed to update local ref for $branch in $p"
            print_success "Updated branch ref $branch in worktree: $p (backup: $bundle)"
        fi
    done
}

# Safely reset a worktree to match a specific ref
# Usage: reset_worktree_to_ref "/path/to/worktree" "ref"
# Creates backup bundle before resetting
reset_worktree_to_ref() {
    local worktree_path="$1"
    local target_ref="$2"
    local ts
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    
    if [[ ! -d "$worktree_path" ]]; then
        print_error "Worktree path does not exist: $worktree_path"
        return 1
    fi
    
    local curr_branch
    curr_branch=$(git -C "$worktree_path" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "HEAD")
    
    # Create backup
    local bundle="/tmp/git-fix-worktree-backup-${curr_branch//\//-}-${ts}.bundle"
    if git -C "$worktree_path" bundle create "$bundle" HEAD 2>/dev/null; then
        print_info "Created backup: $bundle"
    fi
    
    # Reset to target ref
    if git -C "$worktree_path" reset --hard "$target_ref"; then
        print_success "Reset worktree $worktree_path to $target_ref"
    else
        print_error "Failed to reset worktree to $target_ref"
        return 1
    fi
}
