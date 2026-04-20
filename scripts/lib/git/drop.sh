#!/usr/bin/env bash
#
# Dev-Control Shared Library: Drop — surgically remove a non-root commit
# from history (rebase -i with sed swapping pick→drop), with conflict
# auto-resolution, stale-rebase recovery, and reconstruction fallback.
#
# Also exposes prompt_and_push_branch — the shared interactive helper for
# offering a `git push --force-with-lease` after a destructive rewrite,
# with backup-tag creation and detached-HEAD handling.
#
# Required from the caller:
#   - print.sh / colours.sh sourced (print_info/print_success/print_warning/
#     print_error)
#   - check_git_repo function
#   - backup_repo            (lib/git/amend.sh)
#   - capture_dates_for_range (lib/git/dates.sh)
#   - recreate_history_with_dates / auto_resolve_all_conflicts
#     (lib/git/reconstruct.sh, lib/git/rewrite.sh)
#   - Globals: AUTO_RESOLVE, AUTO_FIX_REBASE, NO_EDIT_MODE, DRY_RUN,
#     ORIGINAL_BRANCH, RECONSTRUCT_TARGET, TEMP_ALL_DATES
#   - File descriptor 3 (interactive prompts)
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# ============================================================================
# PROMPT-AND-PUSH — shared post-rewrite push helper
# ============================================================================

# Prompt the user to push the currently checked-out branch (or an alternate branch)
# Called without arguments to use current branch (default), or with branch name
# shellcheck disable=SC2120  # Function intentionally uses default when no args passed
prompt_and_push_branch() {
    local branch="${1:-$(git rev-parse --abbrev-ref HEAD)}"
    local detached=false
    local current_sha
    if [[ "$branch" == "HEAD" ]]; then
        detached=true
        current_sha=$(git rev-parse HEAD)
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ "$detached" == "true" ]]; then
            print_info "DRY-RUN: detached HEAD detected - would create tag backup/${current_sha}-pre-drop-$(date -u +%Y%m%dT%H%M%SZ) and optionally create a tmp branch to push"
        else
            print_info "DRY-RUN: would create tag backup/${branch}-pre-drop-$(date -u +%Y%m%dT%H%M%SZ) and push it; then git push --force-with-lease origin ${branch}"
        fi
        return 0
    fi

    read -u 3 -rp "Push ${branch} to origin with force and create backup tag? [y/N]: " CONFIRM_PUSH_OR_ALT

    # If user typed a non-yes string without spaces, treat it as alternate branch name
    if [[ ! "$CONFIRM_PUSH_OR_ALT" =~ ^[Yy] ]]; then
        if [[ -n "$CONFIRM_PUSH_OR_ALT" && ! "$CONFIRM_PUSH_OR_ALT" =~ [[:space:]] ]]; then
            branch="$CONFIRM_PUSH_OR_ALT"
            read -u 3 -rp "Confirm: push branch '$branch' to origin with force and create backup tag? [y/N]: " CONFIRM_PUSH
        else
            print_info "Push cancelled by user"
            return 0
        fi
    else
        CONFIRM_PUSH="$CONFIRM_PUSH_OR_ALT"
    fi

    if [[ "$CONFIRM_PUSH" =~ ^[Yy] ]]; then
        if [[ "$detached" == "true" ]]; then
            TAG=backup/${current_sha}-pre-drop-$(date -u +%Y%m%dT%H%M%SZ)
            print_info "Detached HEAD: creating tag $TAG pointing to $current_sha"
            git tag -f "$TAG" "$current_sha" 2>/dev/null || true
            git push origin "refs/tags/$TAG" || true

            if [[ "$NO_EDIT_MODE" == "true" ]]; then
                TMP_BRANCH="tmp/repair-${current_sha:0:8}-$(date -u +%Y%m%dT%H%M%SZ)"
                git branch -f "$TMP_BRANCH" "$current_sha"
                if git push --force-with-lease origin "$TMP_BRANCH"; then
                    print_success "Detached HEAD pushed as $TMP_BRANCH (force)"
                    return 0
                else
                    print_error "Failed to push temporary branch $TMP_BRANCH to origin"
                    return 1
                fi
            else
                read -u 3 -rp "You are on a detached HEAD. Enter a branch name to push this HEAD to (or blank to cancel): " USER_BRANCH
                if [[ -n "$USER_BRANCH" ]]; then
                    git branch -f "$USER_BRANCH" "$current_sha"
                    if git push --force-with-lease origin "$USER_BRANCH"; then
                        print_success "$USER_BRANCH pushed to origin (force)"
                        return 0
                    else
                        print_error "Failed to push $USER_BRANCH to origin"
                        return 1
                    fi
                else
                    print_info "Push cancelled by user"
                    return 0
                fi
            fi
        else
            TAG=backup/${branch}-pre-drop-$(date -u +%Y%m%dT%H%M%SZ)
            git tag -f "$TAG" refs/heads/$branch 2>/dev/null || true
            git push origin "refs/tags/$TAG" || true

            git checkout "$branch" || git checkout -b "$branch"
            if git push --force-with-lease origin "$branch"; then
                print_success "$branch pushed to origin (force)"
                return 0
            else
                print_error "Failed to push $branch to origin"
                return 1
            fi
        fi
    else
        print_info "Push cancelled by user"
    fi
}

# ============================================================================
# DROP — surgically remove a single non-root commit via rebase -i
# ============================================================================

drop_single_commit() {
    local target_hash="$1"
    check_git_repo
    backup_repo

    # Remember the branch we started on so reconstructed branches can replace it
    ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)

    if ! git cat-file -e "$target_hash" 2>/dev/null; then
        print_error "Commit not found: $target_hash"
        exit 1
    fi

    # We'll attempt up to one automatic retry if a stale rebase state is found
    local attempt=0
    local max_attempts=2

    while true; do
        attempt=$((attempt + 1))

        local parent
        parent=$(git rev-parse "${target_hash}~1" 2>/dev/null || true)
        if [[ -z "$parent" ]]; then
            print_error "Cannot drop root commit"
            exit 1
        fi

        local short
        short=$(git rev-parse --short "$target_hash")
        # Match both 'pick' and 'merge' commands - the target might be a merge commit
        export GIT_SEQUENCE_EDITOR="sed -i -e '/^pick .*${short}/s/^pick/drop/' -e '/^merge .*${short}/s/^merge/drop/'"

        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "DRY RUN: would drop commit ${short}"
            return 0
        fi

        # Capture dates for commits after the target so we can restore them later
        # IMPORTANT: Capture ALL commits from target..HEAD BEFORE rebase, as rebase will change topology
        print_info "Capturing original dates for commits after ${short}"
        capture_dates_for_range "${target_hash}..HEAD"
        local captured_commits_count
        captured_commits_count=$(wc -l < "$TEMP_ALL_DATES" 2>/dev/null || echo 0)
        print_info "Captured $captured_commits_count commits for potential reconstruction"

        # Reset possible REBASE_EXIT flag
        unset REBASE_EXIT

        # If NO_EDIT_MODE is enabled (user passed --no-edit), set GIT_EDITOR to ':' to prevent editor prompts
        if [[ "$NO_EDIT_MODE" == "true" ]]; then
            print_info "NO_EDIT_MODE enabled: running rebase with GIT_EDITOR=':' to skip editor prompts"
            if GIT_EDITOR=':' git rebase -i --rebase-merges "$parent"; then
                print_success "Dropped commit ${short}"
                
                # CRITICAL FIX: After rebase, filter TEMP_ALL_DATES to only commits NOT already in HEAD
                print_info "Filtering out commits already present in rebased branch..."
                local temp_filtered
                temp_filtered=$(mktemp)
                while IFS='|' read -r commit commit_date; do
                    if [[ -n "$commit" ]] && ! git merge-base --is-ancestor "$commit" HEAD 2>/dev/null; then
                        echo "$commit|$commit_date" >> "$temp_filtered"
                    fi
                done < "$TEMP_ALL_DATES"
                mv "$temp_filtered" "$TEMP_ALL_DATES"
                local remaining
                remaining=$(wc -l < "$TEMP_ALL_DATES" 2>/dev/null || echo 0)
                print_info "After filtering: $remaining commits need reconstruction"
                
                # Record target for potential reconstruction fallback and restore original commit dates if available
                RECONSTRUCT_TARGET="$target_hash"
                recreate_history_with_dates || print_warning "Failed to restore original dates"
            else
                REBASE_EXIT=1
            fi
        else
            if git rebase -i --rebase-merges "$parent"; then
                print_success "Dropped commit ${short}"
                
                # CRITICAL FIX: After rebase, filter TEMP_ALL_DATES to only commits NOT already in HEAD
                print_info "Filtering out commits already present in rebased branch..."
                local temp_filtered
                temp_filtered=$(mktemp)
                while IFS='|' read -r commit commit_date; do
                    if [[ -n "$commit" ]] && ! git merge-base --is-ancestor "$commit" HEAD 2>/dev/null; then
                        echo "$commit|$commit_date" >> "$temp_filtered"
                    fi
                done < "$TEMP_ALL_DATES"
                mv "$temp_filtered" "$TEMP_ALL_DATES"
                local remaining
                remaining=$(wc -l < "$TEMP_ALL_DATES" 2>/dev/null || echo 0)
                print_info "After filtering: $remaining commits need reconstruction"
                
                # Record target for potential reconstruction fallback and restore original commit dates if available
                RECONSTRUCT_TARGET="$target_hash"
                recreate_history_with_dates || print_warning "Failed to restore original dates"
            else
                REBASE_EXIT=1
            fi
        fi

        # If rebase succeeded (no REBASE_EXIT), attempt to restore original commit dates
        if [[ -z "${REBASE_EXIT:-}" ]]; then
            if [[ -f "$TEMP_ALL_DATES" ]]; then
                print_info "Restoring original commit dates saved before drop"
                if recreate_history_with_dates; then
                    print_success "Original commit dates restored"
                else
                    print_warning "Failed to fully restore original commit dates"
                fi
            fi

            # Offer to push the branch (create a backup tag first)
            prompt_and_push_branch || print_warning "Automatic push failed or was cancelled"
            break
        fi

        # Rebase failed. Check for conflicted files and handle accordingly.
        local conflicts
        conflicts=$(git diff --name-only --diff-filter=U || true)
        if [[ -n "$conflicts" ]]; then
            print_warning "Rebase stopped due to conflicts in the following files:"
            echo "$conflicts" | sed 's/^/  - /'

            if [[ -n "$AUTO_RESOLVE" ]]; then
                print_info "AUTO_RESOLVE set to '$AUTO_RESOLVE' - attempting automated resolution loop"
                if auto_resolve_all_conflicts "$AUTO_RESOLVE"; then
                    # After auto-resolution loop completes, verify that the target commit was removed from current branch
                    if git merge-base --is-ancestor "$target_hash" HEAD 2>/dev/null; then
                        print_error "Target commit ${short} still present in current branch after auto-resolution"
                        exit 1
                    else
                        print_success "Conflicts auto-resolved and commit ${short} dropped from branch"
                        
                        # CRITICAL FIX: After auto-resolution, filter TEMP_ALL_DATES to only commits NOT already in HEAD
                        print_info "Filtering out commits already present in rebased branch..."
                        local temp_filtered
                        temp_filtered=$(mktemp)
                        while IFS='|' read -r commit commit_date; do
                            if [[ -n "$commit" ]] && ! git merge-base --is-ancestor "$commit" HEAD 2>/dev/null; then
                                echo "$commit|$commit_date" >> "$temp_filtered"
                            fi
                        done < "$TEMP_ALL_DATES"
                        mv "$temp_filtered" "$TEMP_ALL_DATES"
                        local remaining
                        remaining=$(wc -l < "$TEMP_ALL_DATES" 2>/dev/null || echo 0)
                        print_info "After filtering: $remaining commits need reconstruction"
                        
                        # Record target for potential reconstruction fallback and restore original commit dates for rewritten commits
                        RECONSTRUCT_TARGET="$target_hash"
                        if recreate_history_with_dates; then
                            print_success "Original commit dates restored"
                        else
                            print_warning "Failed to restore original dates"
                        fi

                        # Offer to push the branch (create a backup tag first)
                        prompt_and_push_branch || print_warning "Automatic push failed or was cancelled"
                        return 0
                    fi
                else
                    print_error "Auto-resolution loop failed; leaving rebase stopped for manual resolution"
                    exit 2
                fi
            else
                print_error "Rebase stopped. Please run: git add/rm <conflicted_files> then git rebase --continue"
                exit 2
            fi
        else
            # No conflicts - check whether a stale rebase state is blocking us
            if [[ -d .git/rebase-merge || -d .git/rebase-apply ]]; then
                print_warning "Detected existing rebase state (.git/rebase-merge or .git/rebase-apply)"

                # If user configured AUTO_FIX_REBASE, proceed automatically; otherwise prompt via FD 3
                if [[ "${AUTO_FIX_REBASE:-false}" == "true" ]]; then
                    print_info "AUTO_FIX_REBASE=true: removing stale rebase state and retrying (attempt ${attempt}/${max_attempts})"
                    rm -fr .git/rebase-merge .git/rebase-apply || true
                else
                    read -u 3 -rp "Remove stale rebase state at .git/rebase-merge and retry? [y/N]: " _CONF
                    if [[ "$_CONF" =~ ^[Yy] ]]; then
                        rm -fr .git/rebase-merge .git/rebase-apply || true
                    else
                        print_error "Rebase failed while dropping commit and no conflicts detected. Aborting."
                        git rebase --abort || true
                        exit 1
                    fi
                fi

                # Retry once after removing stale state
                if [[ $attempt -lt $max_attempts ]]; then
                    print_info "Retrying drop operation (attempt $((attempt+1))/$max_attempts)"
                    unset REBASE_EXIT
                    continue
                else
                    print_error "Exceeded retry attempts after removing stale rebase state. Aborting."
                    git rebase --abort || true
                    exit 1
                fi
            else
                print_error "Rebase failed while dropping commit and no conflicts detected. Aborting."
                git rebase --abort || true
                exit 1
            fi
        fi
    done
}
