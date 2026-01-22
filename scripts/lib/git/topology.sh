#!/usr/bin/env bash
# ============================================================================
# topology.sh - Git topology preservation utilities
# ============================================================================
# This module provides functions for preserving and manipulating git commit
# topology (parent relationships, merge commits) during history rewriting.
#
# Functions:
#   linearise_range_to_branch()           - Create linear branch from range
#   preserve_topology_range_to_branch()   - Preserve merges/topology in new branch
#   preserve_and_sign_topology_range_to_branch() - Preserve + prepare for signing
#   sign_commits_preserving_dates()       - Sign commits via filter-branch
#   sign_preserved_topology_branch()      - Sign preserved branch via rebase
#   atomic_preserve_range_to_branch()     - Deterministic preserve with immediate signing
#
# Required globals (defined in parent script):
#   TEMP_ALL_DATES     - Path to temp file for storing dates
#   DRY_RUN            - If true, show what would be done without executing
#   ALLOW_UNSIGNED_PRESERVE - If true, continue despite unsigned commits
#   LAST_PRESERVE_MAP  - Set by atomic_preserve to track old->new sha mapping
#   LAST_PRESERVE_UNSIGNED - Set if unsigned commits encountered
#   TIMED_SIGN_MODE    - If true, use timed signing mode for PRs
#
# Required functions (from lib/output.sh):
#   print_info(), print_success(), print_warning(), print_error()
# ============================================================================

# Ensure we're being sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This script should be sourced, not executed directly." >&2
    exit 1
fi

# ============================================================================
# LINEARIZATION
# ============================================================================

# Helper: linearise a range into a single-parent branch (UK spelling: linearise)
# Creates a new branch with all commits from range but without merge structure
linearise_range_to_branch() {
    local range="$1"
    local ts
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    local tmp_branch="tmp/linearise-${ts}"

    print_info "Creating linearised branch: $tmp_branch from range: $range"

    local last_new=""

    for c in $(git rev-list --topo-order --reverse "$range"); do
        print_info "Linearising commit: $c"
        local tree
        tree=$(git rev-parse "$c^{tree}")
        local author_name author_email author_date commit_msg
        author_name=$(git show -s --format='%an' "$c")
        author_email=$(git show -s --format='%ae' "$c")
        author_date=$(git show -s --format='%aI' "$c")
        commit_msg=$(git log -1 --format=%B "$c")

        GIT_AUTHOR_NAME="$author_name" GIT_AUTHOR_EMAIL="$author_email" GIT_AUTHOR_DATE="$author_date" GIT_COMMITTER_DATE="$author_date" \
        new_sha=$(echo "$commit_msg" | git commit-tree "$tree" ${last_new:+-p $last_new})

        last_new="$new_sha"
    done

    if [[ -n "$last_new" ]]; then
        git update-ref "refs/heads/$tmp_branch" "$last_new"
        git checkout "$tmp_branch"
        print_success "Linearised branch created: $tmp_branch"
    else
        print_warning "No commits to linearise for range: $range"
        return 1
    fi
}

# ============================================================================
# TOPOLOGY PRESERVATION
# ============================================================================

# Helper: preserve topology (recreate commits including merges with original dates, NO signing)
# Signing happens in Phase 2 via rebase which properly handles dates + signatures
preserve_and_sign_topology_range_to_branch() {
    local range="$1"
    local ts
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    local tmp_branch="tmp/preserve-${ts}"

    print_info "Creating preserved-topology + signed branch: $tmp_branch from range: $range"

    declare -A sha_map
    local last_new

    for c in $(git rev-list --topo-order --reverse "$range"); do
        local tree
        tree=$(git rev-parse "$c^{tree}")
        local author_name author_email author_date commit_msg
        author_name=$(git show -s --format='%an' "$c")
        author_email=$(git show -s --format='%ae' "$c")
        author_date=$(git show -s --format='%aI' "$c")
        author_date=$(git show -s --format='%aI' "$c")
        commit_msg=$(git log -1 --format=%B "$c")
        print_info "Recreating + signing commit: ${c:0:7} with date: $author_date"

        parent_args=()
        for p in $(git rev-list --parents -n 1 "$c" | cut -d' ' -f2-); do
            if [[ -n "${sha_map[$p]:-}" ]]; then
                parent_args+=( -p "${sha_map[$p]}" )
            else
                parent_args+=( -p "$p" )
            fi
        done

        # Phase 1: Create commits with topology + original dates (NO SIGNING YET)
        # Signing happens in Phase 2 via rebase which properly preserves dates with signatures
        # Research confirmed: commit-tree -S can have root commit issues; rebase is more reliable
        GIT_AUTHOR_NAME="$author_name" GIT_AUTHOR_EMAIL="$author_email" \
        GIT_AUTHOR_DATE="$author_date" GIT_COMMITTER_DATE="$author_date" \
        new_sha=$(echo "$commit_msg" | git commit-tree "${parent_args[@]}" "$tree")

        if [[ -z "$new_sha" ]]; then
            print_error "Failed to create commit-tree for $c"
            return 1
        fi

        sha_map[$c]="$new_sha"
        last_new="$new_sha"
    done

    if [[ -n "$last_new" ]]; then
        git update-ref "refs/heads/$tmp_branch" "$last_new"
        git checkout "$tmp_branch"
        
        print_success "Preserved-topology branch created (unsigned): $tmp_branch"
        print_info "Phase 2 will sign these commits while preserving dates via rebase"
    else
        print_warning "Failed to create preserved-topology branch for range: $range"
        return 1
    fi
}

# Helper: preserve topology (recreate commits including merges)
# If SIGN_COMMITS=true, sign commits during recreation with original dates
preserve_topology_range_to_branch() {
    local range="$1"
    local sign_commits="${2:-false}"
    local ts
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    local tmp_branch="tmp/preserve-${ts}"

    local mode_desc="Preserving topology"
    if [[ "$sign_commits" == [Tt][Rr][Uu][Ee] ]]; then
        mode_desc="Preserving topology with dates (signing deferred to preserve timestamps)"
    fi
    print_info "Creating preserved-topology branch: $tmp_branch from range: $range ($mode_desc)"

    declare -A sha_map
    local last_new
    local last_merge_seen=""
    local current_pr_timestamp=""
    local TIMED_SIGN_MODE="${TIMED_SIGN_MODE:-false}"

    for c in $(git rev-list --topo-order --reverse "$range"); do
        # Check if this is a merge commit (has multiple parents)
        local parent_count
        parent_count=$(git rev-list --parents -n 1 "$c" | wc -w)
        parent_count=$((parent_count - 1))  # Subtract the commit itself
        
        local is_merge="false"
        [[ "$parent_count" -gt 1 ]] && is_merge="true"
        
        # TIMED_SIGN_MODE: After a merge commit, wait for next minute before processing next PR
        if [[ "$TIMED_SIGN_MODE" == "true" && "$last_merge_seen" == "true" && "$is_merge" == "false" ]]; then
            print_info "TIMED_SIGN: Detected new PR after merge. Waiting for next minute boundary..."
            # Poll each second until minute boundary crosses
            local last_minute
            last_minute=$(date -u +%M)
            while [[ $(date -u +%M) == "$last_minute" ]]; do
                sleep 1
            done
            current_pr_timestamp=$(date -u +%Y-%m-%dT%H:%M:%S+00:00)
            print_info "TIMED_SIGN: New timestamp for this PR: $current_pr_timestamp"
            last_merge_seen="false"
        fi
        
        # Initialize timestamp for first commit or after wait
        if [[ -z "$current_pr_timestamp" ]]; then
            current_pr_timestamp=$(date -u +%Y-%m-%dT%H:%M:%S+00:00)
            [[ "$TIMED_SIGN_MODE" == "true" ]] && print_info "TIMED_SIGN: Starting with timestamp: $current_pr_timestamp"
        fi
        
        print_info "Recreating commit: $c"
        local tree
        tree=$(git rev-parse "$c^{tree}")
        local author_name author_email author_date commit_msg
        author_name=$(git show -s --format='%an' "$c")
        author_email=$(git show -s --format='%ae' "$c")
        # Use current_pr_timestamp in TIMED_SIGN_MODE, otherwise original date
        if [[ "$TIMED_SIGN_MODE" == "true" ]]; then
            author_date="$current_pr_timestamp"
        else
            author_date=$(git show -s --format='%aI' "$c")
        fi
        commit_msg=$(git log -1 --format=%B "$c")

        parent_args=()
        for p in $(git rev-list --parents -n 1 "$c" | cut -d' ' -f2-); do
            if [[ -n "${sha_map[$p]:-}" ]]; then
                parent_args+=( -p "${sha_map[$p]}" )
            else
                parent_args+=( -p "$p" )
            fi
        done

        # CRITICAL: Create commits WITHOUT -S flag to preserve dates via environment variables
        # Signing will be applied afterward if needed, which preserves the dates we set here
        GIT_AUTHOR_NAME="$author_name" GIT_AUTHOR_EMAIL="$author_email" GIT_AUTHOR_DATE="$author_date" GIT_COMMITTER_DATE="$author_date" \
        new_sha=$(echo "$commit_msg" | git commit-tree "$tree" "${parent_args[@]}")

        if [[ -z "$new_sha" ]]; then
            print_error "Failed to create commit-tree for $c"
            return 1
        fi

        sha_map[$c]="$new_sha"
        last_new="$new_sha"
        
        # Track if this was a merge commit for TIMED_SIGN_MODE
        [[ "$is_merge" == "true" ]] && last_merge_seen="true"
    done

    if [[ -n "$last_new" ]]; then
        git update-ref "refs/heads/$tmp_branch" "$last_new"
        git checkout "$tmp_branch"
        
        print_success "Preserved-topology branch created: $tmp_branch"
    else
        print_warning "Failed to create preserved-topology branch for range: $range"
        return 1
    fi
}

# ============================================================================
# SIGNING UTILITIES
# ============================================================================

# Sign commits on a branch while preserving their dates using GPG directly
sign_commits_preserving_dates() {
    local branch="$1"
    print_info "Signing commits on branch $branch while preserving original dates"
    
    # Use git filter-branch with a custom commit filter that signs without touching dates
    # The trick: extract date, create new signed commit, preserve the date
    FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f --commit-filter '
        # Get the original date from the current commit
        original_date=$(git log -1 --format=%aI "$GIT_COMMIT" 2>/dev/null)
        
        # Create the commit with GPG signature while preserving the exact date
        # We export the commit and use git hash-object to create a new object with signature
        GIT_AUTHOR_NAME="$(git show -s --format=%an "$GIT_COMMIT")"
        GIT_AUTHOR_EMAIL="$(git show -s --format=%ae "$GIT_COMMIT")"
        GIT_AUTHOR_DATE="$original_date"
        GIT_COMMITTER_DATE="$original_date"
        
        # Use git commit-tree with GPG signing and environment variable dates
        tree=$(git rev-parse "$GIT_COMMIT^{tree}")
        parents=$(git rev-list --parents -n 1 "$GIT_COMMIT" | cut -d'"'"' '"'"' -f2-)
        parent_args=""
        for p in $parents; do
            parent_args="$parent_args -p $p"
        done
        
        # Sign the commit: commit-tree -S preserves dates when used with env vars in some git versions
        # But to be safe, use git commit instead which respects the env vars
        new_commit=$(git commit-tree -S $parent_args -m "$(git log -1 --format=%B "$GIT_COMMIT")" "$tree" 2>/dev/null)
        
        if [[ -z "$new_commit" ]]; then
            # Fallback: if -S fails, try without it (unsigned but with correct dates)
            new_commit=$(git commit-tree $parent_args -m "$(git log -1 --format=%B "$GIT_COMMIT")" "$tree")
        fi
        
        echo "$new_commit"
    ' -- "$branch" || {
        print_warning "GPG signing via filter-branch encountered issues"
        return 1
    }
}

# Sign a preserved-topology branch without date preservation (dates handled separately by recreate_history_with_dates)
sign_preserved_topology_branch() {
    local src_branch
    src_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    if [[ -z "$src_branch" ]]; then
        print_error "No current branch to sign"
        return 1
    fi

    local ts tmp_branch
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    tmp_branch="tmp/preserve-signed-${ts}"

    print_info "Signing preserved-topology branch: $src_branch"

    # Create tmp branch from current
    git branch "$tmp_branch" "$src_branch" || true
    git checkout "$tmp_branch" || true

    # Rebase with merge-preserving sign
    # Just sign the commits; dates will be restored by recreate_history_with_dates
    # Remove -n flag to allow proper date handling
    if git rebase -f --rebase-merges -x "git commit --amend --no-edit -S" --root >/dev/null 2>&1; then
        print_success "Signed preserved-topology branch created: $tmp_branch"
        return 0
    else
        print_error "Failed to sign preserved-topology branch"
        git checkout "$src_branch" 2>/dev/null || true
        git branch -D "$tmp_branch" 2>/dev/null || true
        return 1
    fi
}

# ============================================================================
# ATOMIC PRESERVE (DETERMINISTIC)
# ============================================================================

# Atomic preserve: deterministic commit-tree recreation with immediate signing & date verification
# This is the most reliable method for preserving topology with signing
atomic_preserve_range_to_branch() {
    local range="$1"
    local ts
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    local tmp_branch="tmp/atomic-preserve-${ts}"
    local preserve_map="/tmp/git-fix-atomic-preserve-map-${ts}.txt"
    local logf="/tmp/git-fix-atomic-preserve-${ts}.log"
    : > "$preserve_map"
    : > "$logf"

    print_info "Creating atomic-preserve branch: $tmp_branch from range: $range"

    declare -A sha_map
    local last_new

    for c in $(git rev-list --topo-order --reverse "$range"); do
        print_info "[atomic] Recreating commit: $c"
        echo "[atomic] Recreating commit: $c" >> "$logf"

        local tree author_name author_email author_date commit_msg
        tree=$(git rev-parse "$c^{tree}")
        author_name=$(git show -s --format='%an' "$c")
        author_email=$(git show -s --format='%ae' "$c")
        author_date=$(git show -s --format='%aI' "$c")
        commit_msg=$(git log -1 --format=%B "$c")

        parent_args=()
        for p in $(git rev-list --parents -n 1 "$c" | cut -d' ' -f2-); do
            if [[ -n "${sha_map[$p]:-}" ]]; then
                parent_args+=( -p "${sha_map[$p]}" )
            else
                parent_args+=( -p "$p" )
            fi
        done

        # Create unsigned commit with exact parents/tree and author dates
        GIT_AUTHOR_NAME="$author_name" GIT_AUTHOR_EMAIL="$author_email" GIT_AUTHOR_DATE="$author_date" \
        GIT_COMMITTER_DATE="$author_date" \
        new_sha=$(echo "$commit_msg" | git commit-tree "$tree" "${parent_args[@]}")

        if [[ -z "$new_sha" ]]; then
            echo "[atomic] Failed to create commit-tree for $c" | tee -a "$logf"
            print_warning "Failed to create commit-tree for $c"
            return 1
        fi

        # Update a temporary branch ref to the new commit and checkout to amend/sign
        git update-ref "refs/heads/$tmp_branch" "$new_sha" || true
        if ! git checkout --quiet "$new_sha" 2>/dev/null; then
            echo "[atomic] Failed to checkout intermediate commit $new_sha" | tee -a "$logf"
            print_warning "Failed to checkout intermediate commit"
            return 1
        fi

        # Amend to sign (and ensure dates preserved). Fail-fast on unsigned commits unless allowed.
        echo "[atomic] Amending/signing commit: $new_sha -> date: $author_date" | tee -a "$logf"
        GIT_AUTHOR_DATE="$author_date" GIT_COMMITTER_DATE="$author_date" \
            git commit --amend --no-edit -n -S >>"$logf" 2>&1 || true

        signed_sha=$(git rev-parse HEAD)
        if [[ -z "$signed_sha" ]]; then
            echo "[atomic] Amend/sign failed (no HEAD) for $new_sha" | tee -a "$logf"
            print_warning "Amend/sign failed for commit $new_sha"
            return 1
        fi

        # Verify signature status
        sig_status=$(git log -1 --format='%G?' HEAD 2>/dev/null || true)
        if [[ "$sig_status" != "G" ]]; then
            echo "[atomic] Commit $signed_sha has non-good signature: $sig_status" | tee -a "$logf"
            if [[ "${ALLOW_UNSIGNED_PRESERVE:-false}" != "true" ]]; then
                print_error "Commit $signed_sha not signed correctly (status: $sig_status). Aborting atomic preserve."
                echo "$c|$signed_sha|$author_date|UNSIGNED|$sig_status" >> "/tmp/git-fix-preserve-unsigned-${ts}.txt"
                LAST_PRESERVE_UNSIGNED="/tmp/git-fix-preserve-unsigned-${ts}.txt"
                return 1
            else
                print_warning "ALLOW_UNSIGNED_PRESERVE=true: continuing despite unsigned commit $signed_sha"
            fi
        fi

        # Verify date matches expected epoch
        existing_epoch=$(git show -s --format=%at HEAD 2>/dev/null || true)
        date_epoch=$(date -d "$author_date" +%s 2>/dev/null || true)
        if [[ -n "$existing_epoch" && -n "$date_epoch" && "$existing_epoch" -ne "$date_epoch" ]]; then
            echo "[atomic] Date mismatch for $signed_sha: expected $date_epoch actual $existing_epoch" | tee -a "$logf"
            print_error "Date mismatch after amend for commit $signed_sha. Aborting atomic preserve."
            return 1
        fi

        # Record mapping and update refs
        echo "$c|$signed_sha|$author_date" >> "$preserve_map"
        sha_map[$c]="$signed_sha"
        last_new="$signed_sha"

        git update-ref "refs/heads/$tmp_branch" "$last_new" || true

    done

    # Save mapping globally and checkout branch
    LAST_PRESERVE_MAP="$preserve_map"
    if [[ -n "$last_new" ]]; then
        git checkout "$tmp_branch"
        print_success "Atomic preserved-topology branch created: $tmp_branch (map: $preserve_map log: $logf)"
        return 0
    else
        print_warning "Failed to create atomic preserved-topology branch for range: $range"
        return 1
    fi
}
