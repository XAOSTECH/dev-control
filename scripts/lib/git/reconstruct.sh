#!/usr/bin/env bash
#
# Dev-Control Shared Library: Reconstruct — date-restoration via rebase-exec
# helper, with cherry-pick reconstruction fallback for commits that fail to
# rebase (used by --amend, --drop and --sign flows).
#
# Public functions:
#   recreate_history_with_dates()         — main entry point (preferred:
#                                            rebase-based; fallback: dummy
#                                            edit + cherry-pick reconstruct).
#   try_reconstruct_with_strategies()     — wrapper that retries reconstruct
#                                            with 'ours' / 'theirs'.
#   show_reconstruction_state()           — diagnostic dump after failure.
#   prompt_override_same_branch()         — interactive force-replace prompt.
#   reconstruct_history_without_commit()  — cherry-pick replay onto parent.
#
# Required from the caller:
#   - print.sh / colours.sh sourced (print_info/print_success/print_warning/
#     print_error)
#   - apply_dates_from_preserve_map (lib/git/dates.sh)
#   - generate_apply_dates_helper_file (lib/git/dates.sh)
#   - auto_add_conflicted_files (lib/git/rewrite.sh)
#   - find_worktree_paths_for_branch / update_worktrees_to_remote
#     (lib/git/worktree.sh)
#   - Globals: SCRIPT_DIR, TEMP_ALL_DATES, REPORT_DIR, DRY_RUN,
#     PRESERVE_TOPOLOGY, LAST_PRESERVE_MAP, RECONSTRUCTION_COMPLETED,
#     LAST_RECONSTRUCT_BRANCH, LAST_RECONSTRUCT_REPORT,
#     LAST_RECONSTRUCT_FAILING_COMMIT, RECONSTRUCT_TARGET, RECONSTRUCT_AUTO,
#     ALLOW_OVERRIDE_SAME_BRANCH, UPDATE_WORKTREES, AUTO_RESOLVE,
#     ORIGINAL_BRANCH, HARNESS_MODE
#   - File descriptor 3 (interactive prompts)
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# ============================================================================
# RECREATE HISTORY WITH CAPTURED DATES
# ============================================================================

recreate_history_with_dates() {
    print_info "Restoring commit dates via rebase-based approach (preferred) with fallback to dummy-edit..."

    if [[ ! -f "$TEMP_ALL_DATES" ]]; then
        print_warning "No dates file found ($TEMP_ALL_DATES); skipping date restoration"
        return 0
    fi

    local total
    total=$(wc -l < "$TEMP_ALL_DATES" | tr -d ' ')
    if [[ "$total" -eq 0 ]]; then
        print_warning "Captured dates file empty; nothing to do"
        return 0
    fi
    
    # CRITICAL: Make a copy of TEMP_ALL_DATES before rebase-based restoration modifies it
    # This preserves the complete list for reconstruction fallback
    local DATES_FOR_RECONSTRUCTION
    DATES_FOR_RECONSTRUCTION=$(mktemp)
    cp "$TEMP_ALL_DATES" "$DATES_FOR_RECONSTRUCTION"

    # If we preserved topology and have a preserve map, prefer to apply dates using that map
    # BUT: only if we're NOT using reconstruction fallback (cherry-pick already preserved dates)
    if [[ "$total" -gt 1 && "${PRESERVE_TOPOLOGY:-}" == [Tt][Rr][Uu][Ee] && -n "${LAST_PRESERVE_MAP:-}" && -f "${LAST_PRESERVE_MAP}" && "${RECONSTRUCTION_COMPLETED:-false}" != "true" ]]; then
        print_info "Detected preserved-topology run; will try applying dates via preserve map: $LAST_PRESERVE_MAP"
        if apply_dates_from_preserve_map "$LAST_PRESERVE_MAP"; then
            return 0
        else
            print_warning "apply_dates_from_preserve_map failed; will continue to rebase-based method"
        fi
    fi

    # If multiple commits were captured, use a rebase-based method to apply each date
    if [[ "$total" -gt 1 ]]; then
        print_info "Attempting rebase-based application for $total commits"

        local oldest_commit
        oldest_commit=$(head -n1 "$TEMP_ALL_DATES" | cut -d'|' -f1)
        local parent
        parent=$(git rev-parse "${oldest_commit}~1" 2>/dev/null || true)

        # Use repository helper if present; otherwise generate a robust helper from this script
        local helper_script
        if [[ -f "$SCRIPT_DIR/helpers/apply-dates-helper.sh" ]]; then
            helper_script="$SCRIPT_DIR/helpers/apply-dates-helper.sh"
            chmod +x "$helper_script" || true
        else
            helper_script=$(generate_apply_dates_helper_file)
        fi

# preserve everything after first '|' (date may contain spaces)
date="\$(echo \"\${line}\" | cut -d'|' -f2-)"
# (removed) Inline date-apply log - date application delegated to helper script
# (removed) Inline commit amend - helper will perform amend/sign/verification per commit
# The helper script is responsible for removing applied lines from the dates file
# helper file ready (either repo helper or generated helper)

        local rebase_base
        if [[ -z "$parent" ]]; then
            rebase_base="--root"
        else
            rebase_base="$parent"
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "DRY-RUN: would run: export GIT_SEQUENCE_EDITOR=\"sed -i '/^pick /a exec /bin/bash $helper_script \"$TEMP_ALL_DATES\"'\" and git rebase -i $rebase_base"
            print_info "DRY-RUN: helper script: $helper_script"
            return 0
        fi

        # Insert exec that runs the helper with the dates file as an argument (use /bin/bash to avoid exec path issues)
        export GIT_SEQUENCE_EDITOR="sed -i -e '/^pick /a exec /bin/bash $helper_script \"$TEMP_ALL_DATES\"' -e '/^merge /a exec /bin/bash $helper_script \"$TEMP_ALL_DATES\"'"
        export GIT_EDITOR=:

        print_info "Running rebase to apply captured dates (may take a while)"
        if [[ "$rebase_base" == "--root" ]]; then
            git rebase -i --root || print_warning "Rebase-based date application failed; will fallback to dummy amend"
        else
            git rebase -i "$rebase_base" || print_warning "Rebase-based date application failed; will fallback to dummy amend"
        fi

        # Cleanup helper
        rm -f "$helper_script"

        # If there are remaining lines, the rebase did not finish applying all dates
        if [[ -s "$TEMP_ALL_DATES" ]]; then
            print_warning "Rebase-based method did not apply all dates; falling back to dummy amend"
        else
            print_success "Rebase-based date application finished"
            return 0
        fi
    fi

    # For PRESERVE_TOPOLOGY mode, dates and signatures were already applied in rebase --exec phase
    if [[ "${PRESERVE_TOPOLOGY:-}" == [Tt][Rr][Uu][Ee] ]]; then
        print_info "PRESERVE_TOPOLOGY=true: Dates and signatures preserved during rebase-sign phase"
        return 0
    fi

    # Fallback: dummy-edit (existing behaviour) - only for non-preserved-topology runs
    print_info "Performing fallback dummy-edit date restore for HEAD"

    local head_new_date
    head_new_date=$(tail -1 "$TEMP_ALL_DATES" | cut -d'|' -f2-)
    if [[ -z "$head_new_date" ]]; then
        print_warning "No HEAD date available; skipping fallback"
        return 0
    fi

    local dummy_file=".tmp-date-fix-$$"
    echo "Temporary file for date restoration - will be removed" > "$dummy_file"
    git add "$dummy_file"

    print_info "Step 1/3: Adding dummy file to trigger commit rewrite..."
    print_info "Step 2/3: Amending HEAD with date: $head_new_date"
    GIT_AUTHOR_DATE="$head_new_date" \
    GIT_COMMITTER_DATE="$head_new_date" \
    git commit --amend --no-edit || { print_error "Failed to amend HEAD for date restoration"; rm -f "$dummy_file"; return 1; }

    print_info "Step 3/3: Removing dummy file and finalising amend"
    rm -f "$dummy_file"
    git rm -f "$dummy_file" 2>/dev/null || true
    GIT_AUTHOR_DATE="$head_new_date" \
    GIT_COMMITTER_DATE="$head_new_date" \
    git commit --amend --no-edit || print_warning "Final amend failed"

    print_success "Fallback date restoration complete"

    # If there are still lines remaining in the dates file, attempt reconstruction fallback
    if [[ -s "$TEMP_ALL_DATES" ]]; then
        print_warning "Some captured dates remain; attempting reconstruction fallback (cherry-pick replay)"
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "DRY-RUN: would run reconstruction fallback for remaining commits"
        else
            # CRITICAL: Restore the complete list from copy before rebase-based phase modified it
            cp "$DATES_FOR_RECONSTRUCTION" "$TEMP_ALL_DATES"
            
            # Try reconstruction, optionally with auto strategies
            try_reconstruct_with_strategies "${RECONSTRUCT_TARGET:-$oldest_commit}" || {
                print_warning "Reconstruction fallback failed"
                show_reconstruction_state "$LAST_RECONSTRUCT_BRANCH" "$LAST_RECONSTRUCT_REPORT" "$LAST_RECONSTRUCT_FAILING_COMMIT"
                # If user set ALLOW_OVERRIDE_SAME_BRANCH, auto-confirm replacement with preserved branch
                if [[ "${ALLOW_OVERRIDE_SAME_BRANCH}" == "true" && -n "${LAST_RECONSTRUCT_BRANCH}" ]]; then
                    print_info "ALLOW_OVERRIDE_SAME_BRANCH=true: attempting to override $ORIGINAL_BRANCH with $LAST_RECONSTRUCT_BRANCH"
                    prompt_override_same_branch "$LAST_RECONSTRUCT_BRANCH" "$ORIGINAL_BRANCH"
                fi
            }
        fi
    fi
    
    # Cleanup reconstruction copy
    rm -f "$DATES_FOR_RECONSTRUCTION"
} 

# ============================================================================
# RECONSTRUCTION STRATEGIES
# ============================================================================

# Try reconstruction with multiple strategies if requested
try_reconstruct_with_strategies() {
    local target_hash="$1"
    local tried=""

    # First, try with whatever AUTO_RESOLVE is currently set to (could be empty)
    if reconstruct_history_without_commit "$target_hash"; then
        RECONSTRUCTION_COMPLETED="true"
        return 0
    fi

    if [[ "${RECONSTRUCT_AUTO}" == "true" ]]; then
        # Try 'ours' then 'theirs' unless already tried
        for strat in "ours" "theirs"; do
            if [[ "$AUTO_RESOLVE" == "$strat" ]]; then
                continue
            fi
            print_info "RECONSTRUCT_AUTO: retrying reconstruction with auto-resolve=$strat"
            AUTO_RESOLVE="$strat"
            if reconstruct_history_without_commit "$target_hash"; then
                RECONSTRUCTION_COMPLETED="true"
                return 0
            fi
        done
    fi

    return 1
}

# Display reconstruction branch/report/failing commit context to aid manual resolution
show_reconstruction_state() {
    local branch="$1"
    local report="$2"
    local failing="$3"

    print_info "Reconstruction branch: ${branch:-<none>}"
    if [[ -n "$branch" && $(git rev-parse --verify --quiet "$branch") ]]; then
        git checkout --quiet "$branch" || true
        print_info "Branch tip: $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
        print_info "Conflicted files (if any):"
        git diff --name-only --diff-filter=U || echo "(none)"
    fi

    if [[ -n "$report" && -f "$report" ]]; then
        print_info "Reconstruction report: $report"
        sed -n '1,200p' "$report" || true
    fi

    if [[ -n "$failing" ]]; then
        print_info "Failing commit: $failing"
        git show --stat --oneline "$failing" || true
        git show "$failing" | sed -n '1,200p' || true
    fi

    print_info "You can inspect '$branch' and resolve conflicts, then 'git cherry-pick --continue' to proceed."
}

# ============================================================================
# PROMPT-OVERRIDE — replace original branch with a tmp/* branch (destructive)
# ============================================================================

# Prompt user to optionally override the original branch with a tmp branch (destructive)
prompt_override_same_branch() {
    local src_branch="$1"
    local dest_branch="$2"
    local ts
    ts=$(date -u +%Y%m%dT%H%M%SZ)

    if [[ -z "$dest_branch" || -z "$src_branch" ]]; then
        print_warning "Missing branches for override prompt"
        return 1
    fi

    print_info "Comparison: $dest_branch .. $src_branch"
    local ahead behind
    ahead=$(git rev-list --count "${dest_branch}..${src_branch}")
    behind=$(git rev-list --count "${src_branch}..${dest_branch}")
    print_info "Commits: $src_branch is +${ahead}/-${behind} relative to $dest_branch"
    git --no-pager log --left-right --oneline "${dest_branch}...${src_branch}" | sed -n '1,40p'

    # Quick pre-push verification: if we have a preserve map for the source branch,
    # verify that the signed commits there have the expected dates. If dates are
    # mismatched, require an explicit override confirmation (or ALLOW_OVERRIDE_SAME_BRANCH=true).
    if [[ -n "${LAST_PRESERVE_MAP:-}" && -f "${LAST_PRESERVE_MAP}" && "${src_branch}" == tmp/preserve* ]]; then
        local total_dates=0 matched_dates=0 missing_dates=0
        while IFS='|' read -r orig signed date; do
            if [[ -z "$signed" || -z "$date" ]]; then continue; fi
            total_dates=$((total_dates+1))
            # Compare by epoch
            existing_epoch=$(git show -s --format=%aI "$signed" 2>/dev/null || true)
            if [[ -n "$existing_epoch" ]]; then
                existing_epoch_s=$(date -d "$existing_epoch" +%s 2>/dev/null || true)
                date_epoch=$(date -d "$date" +%s 2>/dev/null || true)
                if [[ -n "$existing_epoch_s" && -n "$date_epoch" && "$existing_epoch_s" -eq "$date_epoch" ]]; then
                    matched_dates=$((matched_dates+1))
                fi
            fi
        done < "$LAST_PRESERVE_MAP"
        missing_dates=$((total_dates-matched_dates))
        if [[ "$total_dates" -gt 0 && "$missing_dates" -gt 0 ]]; then
            print_warning "Preserved branch '$src_branch' has $missing_dates/$total_dates commits with mismatched dates. Overwriting remote will lose reconstructed date fixes."
            if [[ "${ALLOW_OVERRIDE_SAME_BRANCH:-}" != "true" ]]; then
                echo "To proceed anyway, type 'override' (case-sensitive), or re-run with ALLOW_OVERRIDE_SAME_BRANCH=true to auto-accept." 
                read -rp "Type 'override' to confirm replacement: " _confirm
                if [[ "$_confirm" != "override" ]]; then
                    print_info "Override not confirmed; aborting replace to avoid losing reconstructed dates."
                    return 0
                fi
                _ans=y
            else
                print_info "ALLOW_OVERRIDE_SAME_BRANCH=true: proceeding despite missing dates"
            fi
        fi
    fi

    # If we previously applied a reconstruction to the remote branch, detect
    # whether origin/$dest_branch already points at the reconstruction result.
    if [[ -n "${LAST_RECONSTRUCT_BRANCH:-}" && $(git rev-parse --verify --quiet "$LAST_RECONSTRUCT_BRANCH" >/dev/null; echo $?) -eq 0 ]]; then
        remote_sha=$(git ls-remote origin "refs/heads/$dest_branch" | cut -f1 || true)
        recon_sha=$(git rev-parse --verify "$LAST_RECONSTRUCT_BRANCH" 2>/dev/null || true)
        if [[ -n "$remote_sha" && -n "$recon_sha" && "$remote_sha" == "$recon_sha" ]]; then
            print_warning "Remote $dest_branch currently points at reconstructed branch $LAST_RECONSTRUCT_BRANCH (sha: ${recon_sha:0:8})."
            print_warning "Force-pushing $src_branch will overwrite the reconstruction result."
            if [[ "${ALLOW_OVERRIDE_SAME_BRANCH:-}" == "true" ]]; then
                print_info "ALLOW_OVERRIDE_SAME_BRANCH=true: continuing with override"
            else
                echo "Options:" 
                echo "  1) Continue and replace remote with $src_branch (may lose reconstructed dates)"
                echo "  2) Keep reconstructed branch ($LAST_RECONSTRUCT_BRANCH) as remote (recommended)"
                echo "  3) Cancel"
                read -rp "Choose [1/2/3]: " _choice2
                case "${_choice2:-2}" in
                    1)
                        _ans=y
                        ;;
                    2)
                        print_info "Keeping reconstructed branch on remote. Aborting override."
                        return 0
                        ;;
                    *)
                        print_info "User chose to cancel override"
                        return 0
                        ;;
                esac
            fi
        fi
    fi

    local _ans

    # If we previously ran a reconstruction fallback that applied dates (and the
    # preserve branch still has remaining captured dates), prefer the reconstructed
    # branch and let the user choose explicitly to avoid accidentally overwriting
    # the reconstruction with an incomplete preserved branch.
    if [[ -n "${LAST_RECONSTRUCT_BRANCH:-}" && -n "$TEMP_ALL_DATES" && -s "$TEMP_ALL_DATES" ]]; then
        # Ensure the reconstruct branch actually exists
        if git rev-parse --verify --quiet "$LAST_RECONSTRUCT_BRANCH" >/dev/null; then
            print_warning "Detected reconstruction branch available: $LAST_RECONSTRUCT_BRANCH"
            print_warning "Captured dates remain; source branch '$src_branch' did not apply all dates."

            if [[ "${ALLOW_OVERRIDE_SAME_BRANCH:-}" == "true" ]]; then
                print_info "ALLOW_OVERRIDE_SAME_BRANCH=true: preferring reconstruction branch $LAST_RECONSTRUCT_BRANCH"
                src_branch="$LAST_RECONSTRUCT_BRANCH"
                _ans=y
            else
                echo "Choose replacement source:" 
                echo "  1) Use preserved branch: $src_branch (may have missing dates)"
                echo "  2) Use reconstructed branch: $LAST_RECONSTRUCT_BRANCH (dates applied via reconstruction)"
                echo "  3) Cancel"
                read -rp "Choose [1/2/3]: " _choice
                case "${_choice:-3}" in
                    1)
                        _ans=y
                        ;;
                    2)
                        src_branch="$LAST_RECONSTRUCT_BRANCH"
                        _ans=y
                        ;;
                    *)
                        print_info "User chose to cancel override"
                        return 0
                        ;;
                esac
            fi
        fi
    fi

    if [[ "${_ans:-}" == "" ]]; then
        if [[ "${ALLOW_OVERRIDE_SAME_BRANCH:-}" == "true" ]]; then
            print_info "ALLOW_OVERRIDE_SAME_BRANCH=true: auto-confirming override"
            _ans=y
        elif [[ "$HARNESS_MODE" == "true" ]]; then
            print_info "Harness mode: skipping destructive override prompt"
            return 0
        else
            read -rp "Replace remote branch '$dest_branch' with '$src_branch' (force push)? This will rewrite remote history. Continue? [y/N]: " _ans
        fi
    fi

    if [[ "${_ans,,}" == "y" || "${_ans,,}" == "yes" ]]; then
        # create backup tag
        local tag="backup/${dest_branch}-pre-override-${ts}"
        print_info "Creating backup tag: $tag -> $dest_branch"
        git tag -f "$tag" "$dest_branch" || true
        print_info "Pushing backup tag to origin"
        git push origin "refs/tags/$tag" || print_warning "Failed to push backup tag to origin"

        # create bundle
        local bundle="/tmp/git-fix-history-backup-override-${ts}.bundle"
        print_info "Creating bundle: $bundle"
        git bundle create "$bundle" "refs/heads/$dest_branch" || print_warning "Bundle creation failed"

        print_info "Force-pushing $src_branch to origin/$dest_branch"
        if git push origin +refs/heads/"$src_branch":refs/heads/"$dest_branch" --force-with-lease; then
            print_success "Successfully replaced origin/$dest_branch with $src_branch"

            # If any worktrees have this branch checked out, either update them (if allowed)
            # or warn the user and skip updating local refs to avoid "used by worktree" errors.
            local worktree_paths
            worktree_paths=$(find_worktree_paths_for_branch "$dest_branch")
            if [[ -n "$worktree_paths" ]]; then
                if [[ "${UPDATE_WORKTREES}" == "true" ]]; then
                    print_info "Worktrees detected for branch $dest_branch; updating them to origin/$dest_branch"
                    update_worktrees_to_remote "$dest_branch"
                else
                    print_warning "Branch '$dest_branch' is checked out in one or more worktrees; not updating local refs. Set UPDATE_WORKTREES=true to auto-update them (will create backups)."
                fi
            else
                # No worktrees reference this branch: safe to update local branch ref
                git branch -f "$dest_branch" "refs/heads/$src_branch" || true
            fi
        else
            print_error "Failed to force-push $src_branch to origin/$dest_branch"
            return 1
        fi
    else
        print_info "User declined override; leaving branches as-is"
    fi
}

# ============================================================================
# RECONSTRUCT — cherry-pick replay onto parent of target commit
# ============================================================================

# Reconstruction fallback: cherry-pick remaining captured commits onto parent branch
reconstruct_history_without_commit() {
    local target_hash="$1"
    local ts
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    local tmp_branch="tmp/remove-${target_hash:0:8}-${ts}"

    # Record metadata about this reconstruction attempt
    LAST_RECONSTRUCT_BRANCH="$tmp_branch"
    LAST_RECONSTRUCT_REPORT="$REPORT_DIR/reconstruct-${target_hash:0:8}-${ts}.txt"
    LAST_RECONSTRUCT_FAILING_COMMIT=""

    if [[ ! -f "$TEMP_ALL_DATES" || ! -s "$TEMP_ALL_DATES" ]]; then
        print_warning "No remaining captured dates found for reconstruction"
        return 1
    fi

    local parent
    parent=$(git rev-parse "${target_hash}~1" 2>/dev/null || true)
    if [[ -z "$parent" ]]; then
        print_error "Cannot reconstruct: parent of $target_hash not found"
        return 1
    fi

    print_info "Starting reconstruction fallback on branch: $tmp_branch (based on $parent)"
    git checkout -b "$tmp_branch" "$parent"

    local report_file="$REPORT_DIR/reconstruct-${target_hash:0:8}-${ts}.txt"
    echo "Reconstruction report: $report_file" > "$report_file"
    echo "Starting reconstruction of commits after $target_hash" | tee -a "$report_file"

    # Read remaining commits from the dates file in order (oldest first)
    local commit
    local status=0
    declare -A new_sha_map

    # Iterate through a copy of the dates file to allow in-loop modifications
    local dates_tmp
    dates_tmp=$(mktemp)
    cp "$TEMP_ALL_DATES" "$dates_tmp"

    while IFS='|' read -r commit commit_date; do
        # Skip empty lines
        if [[ -z "$commit" ]]; then
            continue
        fi

        echo "Processing $commit (date: $commit_date)" | tee -a "$report_file"

        # If commit already present in the current branch (ancestor of HEAD), skip
        if git merge-base --is-ancestor "$commit" HEAD 2>/dev/null; then
            echo "SKIP: $commit already present in the current branch" | tee -a "$report_file"
            # remove the line from the master dates file
            grep -v -F -- "${commit}|${commit_date}" "$TEMP_ALL_DATES" > "${TEMP_ALL_DATES}.tmp" && mv "${TEMP_ALL_DATES}.tmp" "$TEMP_ALL_DATES"
            continue
        fi

        # Attempt to recreate merge commits deterministically first (commit-tree)
        local parents
        parents=$(git rev-list --parents -n 1 "$commit" | cut -d' ' -f2-)
        local parent_count
        parent_count=$(echo "$parents" | wc -w)

        if [[ "$parent_count" -gt 1 ]]; then
            echo "INFO: Recreating merge commit $commit with parents: $parents" | tee -a "$report_file"
            local tree
            tree=$(git rev-parse "$commit^{tree}")
            local orig_author_name orig_author_email commit_msg
            orig_author_name=$(git show -s --format='%an' "$commit" 2>/dev/null || true)
            orig_author_email=$(git show -s --format='%ae' "$commit" 2>/dev/null || true)
            commit_msg=$(git log -1 --format=%B "$commit")

            parent_args=()
            for p in $parents; do
                if [[ -n "${new_sha_map[$p]:-}" ]]; then
                    parent_args+=( -p "${new_sha_map[$p]}" )
                else
                    parent_args+=( -p "$p" )
                fi
            done

            if new_sha=$(GIT_AUTHOR_NAME="$orig_author_name" GIT_AUTHOR_EMAIL="$orig_author_email" \
                GIT_AUTHOR_DATE="$commit_date" GIT_COMMITTER_DATE="$commit_date" \
                echo "$commit_msg" | git commit-tree "$tree" "${parent_args[@]}" 2>/dev/null); then
                new_sha_map[$commit]="$new_sha"
                echo "OK: Recreated merge commit $commit -> $new_sha" | tee -a "$report_file"
                grep -v -F -- "${commit}|${commit_date}" "$TEMP_ALL_DATES" > "${TEMP_ALL_DATES}.tmp" && mv "${TEMP_ALL_DATES}.tmp" "$TEMP_ALL_DATES"
                continue
            else
                echo "WARN: Failed to recreate merge commit $commit; attempting cherry-pick fallback" | tee -a "$report_file"
            fi
        fi

        # Attempt cherry-pick (non-merge or fallback)
        if git cherry-pick --allow-empty --strategy=recursive --strategy-option=theirs "$commit" >/dev/null 2>&1; then
            # Capture new sha of cherry-picked commit
            local new_sha
            new_sha=$(git rev-parse --verify HEAD 2>/dev/null || true)

            # Amend to set author and dates
            local orig_author_name
            local orig_author_email
            orig_author_name=$(git show -s --format='%an' "$commit" 2>/dev/null || true)
            orig_author_email=$(git show -s --format='%ae' "$commit" 2>/dev/null || true)
            if [[ -n "$orig_author_name" && -n "$orig_author_email" && -n "$commit_date" ]]; then
                GIT_AUTHOR_NAME="$orig_author_name" GIT_AUTHOR_EMAIL="$orig_author_email" \
                GIT_AUTHOR_DATE="$commit_date" GIT_COMMITTER_DATE="$commit_date" \
                git commit --amend --no-edit --no-verify >/dev/null 2>&1 || true
            fi

            # Map original -> new sha for future merge recreation
            if [[ -n "$new_sha" ]]; then
                new_sha_map[$commit]="$new_sha"
            fi

            echo "OK: Cherry-picked $commit" | tee -a "$report_file"
            # remove the line
            grep -v -F -- "${commit}|${commit_date}" "$TEMP_ALL_DATES" > "${TEMP_ALL_DATES}.tmp" && mv "${TEMP_ALL_DATES}.tmp" "$TEMP_ALL_DATES"
            continue
        fi

        # If cherry-pick failed, try auto-resolve if configured
        if [[ -n "$AUTO_RESOLVE" ]]; then
            echo "Conflict during cherry-pick of $commit; attempting auto-resolve ($AUTO_RESOLVE)" | tee -a "$report_file"
            if auto_add_conflicted_files "$AUTO_RESOLVE"; then
                # Try to continue cherry-pick
                if git cherry-pick --continue >/dev/null 2>&1; then
                    # Capture and map new sha
                    local new_sha
                    new_sha=$(git rev-parse --verify HEAD 2>/dev/null || true)

                    # Amend dates as above
                    local orig_author_name
                    local orig_author_email
                    orig_author_name=$(git show -s --format='%an' "$commit" 2>/dev/null || true)
                    orig_author_email=$(git show -s --format='%ae' "$commit" 2>/dev/null || true)
                    if [[ -n "$orig_author_name" && -n "$orig_author_email" && -n "$commit_date" ]]; then
                        GIT_AUTHOR_NAME="$orig_author_name" GIT_AUTHOR_EMAIL="$orig_author_email" \
                        GIT_AUTHOR_DATE="$commit_date" GIT_COMMITTER_DATE="$commit_date" \
                        git commit --amend --no-edit --no-verify >/dev/null 2>&1 || true
                    fi

                    # Map original -> new sha
                    if [[ -n "$new_sha" ]]; then
                        new_sha_map[$commit]="$new_sha"
                    fi

                    echo "OK: Cherry-picked $commit with auto-resolve" | tee -a "$report_file"
                    grep -v -F -- "${commit}|${commit_date}" "$TEMP_ALL_DATES" > "${TEMP_ALL_DATES}.tmp" && mv "${TEMP_ALL_DATES}.tmp" "$TEMP_ALL_DATES"
                    continue
                else
                    # If the cherry-pick ended empty, skip it
                    if git status --porcelain | grep -q '^$'; then
                        echo "SKIP: Cherry-pick of $commit resulted in empty commit; skipping" | tee -a "$report_file"
                        git cherry-pick --skip >/dev/null 2>&1 || true
                        grep -v -F -- "${commit}|${commit_date}" "$TEMP_ALL_DATES" > "${TEMP_ALL_DATES}.tmp" && mv "${TEMP_ALL_DATES}.tmp" "$TEMP_ALL_DATES"
                        continue
                    fi
                fi
            else
                echo "FAIL: Auto-resolve failed for $commit" | tee -a "$report_file"
                status=1
                break
            fi
        else
            echo "FAIL: Conflict during cherry-pick of $commit and AUTO_RESOLVE unset" | tee -a "$report_file"
            status=1
            break
        fi
    done < "$dates_tmp"

    # Cleanup temp copy
    rm -f "$dates_tmp"

    if [[ $status -eq 0 ]]; then
        echo "Reconstruction completed successfully onto $tmp_branch" | tee -a "$report_file"
        echo "Remaining dates file:" >> "$report_file"
        [[ -f "$TEMP_ALL_DATES" ]] && sed -n '1,200p' "$TEMP_ALL_DATES" >> "$report_file"
        echo "You can inspect branch: $tmp_branch" | tee -a "$report_file"

        # Prompt whether to replace the original branch with this reconstructed branch (destructive)
        local confirm_replace
        read -u 3 -rp "Replace branch '$ORIGINAL_BRANCH' with reconstructed branch '$tmp_branch' and force-push to origin? [y/N]: " confirm_replace
        if [[ "$confirm_replace" =~ ^[Yy] ]]; then
            echo "Creating backup tag for $ORIGINAL_BRANCH and force-updating it to $tmp_branch" | tee -a "$report_file"
            TAG=backup/${ORIGINAL_BRANCH}-pre-drop-$(date -u +%Y%m%dT%H%M%SZ)
            if git show-ref --verify --quiet "refs/heads/$ORIGINAL_BRANCH"; then
                git tag -f "$TAG" "refs/heads/$ORIGINAL_BRANCH" 2>/dev/null || git tag -f "$TAG" "$(git rev-parse HEAD)" 2>/dev/null || true
            else
                git tag -f "$TAG" "$(git rev-parse HEAD)" 2>/dev/null || true
            fi
            git push origin "refs/tags/$TAG" || true

            # Reset original branch to reconstructed branch and push
            git checkout "$ORIGINAL_BRANCH" 2>/dev/null || git checkout -b "$ORIGINAL_BRANCH"
            git reset --hard "$tmp_branch"
            if git push --force-with-lease origin "$ORIGINAL_BRANCH"; then
                echo "SUCCESS: $ORIGINAL_BRANCH reset to $tmp_branch and pushed" | tee -a "$report_file"
                # Delete the tmp branch locally
                git branch -D "$tmp_branch" 2>/dev/null || true
                # Clean up any other leftover tmp/remove-* branches from previous failed attempts
                print_info "Cleaning up leftover reconstruction branches..."
                git branch -l | grep "tmp/remove-${target_hash:0:8}-" | xargs -r git branch -D 2>/dev/null || true
                echo "Cleanup complete" | tee -a "$report_file"
            else
                echo "ERROR: Failed to push $ORIGINAL_BRANCH to origin" | tee -a "$report_file"
            fi
        else
            echo "Left reconstructed branch $tmp_branch in place for inspection" | tee -a "$report_file"
        fi

        return 0
    else
        # Try to extract the failing commit for easier inspection
        LAST_RECONSTRUCT_FAILING_COMMIT=$(grep -E "FAIL: (Auto-resolve failed for|Conflict during cherry-pick of)" "$report_file" | tail -n1 | sed -E 's/.* ([0-9a-f]{7,40}).*/\1/' || true)
        if [[ -n "$LAST_RECONSTRUCT_FAILING_COMMIT" ]]; then
            echo "Reconstruction failed at commit: $LAST_RECONSTRUCT_FAILING_COMMIT" | tee -a "$report_file"
        fi
        echo "Reconstruction failed; leaving branch $tmp_branch for manual inspection" | tee -a "$report_file"
        return 1
    fi
} 
