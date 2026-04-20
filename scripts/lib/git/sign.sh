#!/usr/bin/env bash
#
# Dev-Control Shared Library: Sign — re-sign commits across a range, with
# auto-detection of unsigned commits and topology-preserving rebase strategy.
#
# Required from the caller:
#   - print.sh / colours.sh sourced (print_info/print_success/print_warning/
#     print_error/print_header)
#   - check_git_repo, backup_repo (lib/git/amend.sh), confirm_changes
#   - capture_dates_for_range / recreate_history_with_dates
#     (lib/git/dates.sh, lib/git/reconstruct.sh)
#   - linearise_range_to_branch / preserve_topology_range_to_branch
#     (lib/git/topology.sh)
#   - prompt_override_same_branch (lib/git/reconstruct.sh)
#   - Globals: RANGE, SIGN_MODE, RESIGN_MODE, REAUTHOR_MODE, REAUTHOR_TARGET,
#     PRESERVE_TOPOLOGY, AUTO_FIX_REBASE, NO_EDIT_MODE, DRY_RUN, HARNESS_MODE,
#     ORIGINAL_BRANCH, SIGNATURES_ALREADY_APPLIED, REBASE_BASE
#   - File descriptor 3 (interactive prompts)
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# ============================================================================
# AUTO-SIGN — detect unsigned commits and auto-configure secure signing
# ============================================================================

auto_sign_detect() {
    print_header
    check_git_repo
    
    print_info "Scanning repository for unverified commits..."
    
    # Normalise RANGE (same as sign_mode does)
    if [[ -n "$RANGE" ]]; then
        if [[ "${RANGE,,}" =~ ^head[=~]all$ ]]; then
            ROOT_COMMIT=$(git rev-list --max-parents=0 HEAD 2>/dev/null || true)
            if [[ -n "$ROOT_COMMIT" ]]; then
                RANGE="$ROOT_COMMIT..HEAD"
            fi
        elif [[ "$RANGE" =~ ^HEAD=([0-9]+)$ ]]; then
            RANGE="HEAD~${BASH_REMATCH[1]}"
        fi
    fi
    
    # Normalise to ..HEAD format
    if [[ "$RANGE" != *".."* ]]; then
        RANGE="$RANGE..HEAD"
    fi
    
    # Check for unsigned commits
    local commit_info
    commit_info=$(git log --reverse --format="%h %G? %s" "$RANGE" 2>/dev/null || true)
    
    if [[ -z "$commit_info" ]]; then
        print_error "No commits found in range: $RANGE"
        exit 1
    fi
    
    local unsigned_commits
    unsigned_commits=$(echo "$commit_info" | grep -E ' [NE] ' || true)
    local unsigned_count
    unsigned_count=$(echo "$unsigned_commits" | grep -c . || echo 0)
    
    if [[ "$unsigned_count" -eq 0 ]]; then
        print_success "All commits in range $RANGE are already signed (verified)"
        echo "No action needed."
        exit 0
    fi
    
    # Show unsigned commits to user
    echo ""
    print_warning "Found $unsigned_count unsigned/unverified commit(s) in range: $RANGE"
    echo ""
    echo "Unsigned commits:"
    echo "$unsigned_commits" | sed 's/^/  /'
    echo ""
    
    # Explain what auto-sign will do
    echo "${BOLD}Auto-sign will:${NC}"
    echo "  • Enable commit signing (GPG required)"
    echo "  • Preserve merge topology (retain branch structure)"
    echo "  • Auto-resolve conflicts using 'ours' strategy"
    echo "  • Skip interactive menus (fully automated)"
    echo "  • Sign only unsigned commits (skip already-signed)"
    echo ""
    
    # Confirm with user
    local confirm
    read -rp "Proceed with auto-sign? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        print_info "Auto-sign cancelled by user"
        exit 0
    fi
    
    # Auto-configure flags for secure, non-interactive signing
    print_info "Configuring auto-sign flags..."
    SIGN_MODE=true
    export PRESERVE_TOPOLOGY=true
    AUTO_RESOLVE=ours
    NO_EDIT_MODE=true
    ATOMIC_PRESERVE=true
    
    print_success "Auto-sign configured:"
    echo "  SIGN_MODE=true"
    echo "  PRESERVE_TOPOLOGY=true"
    echo "  AUTO_RESOLVE=ours"
    echo "  NO_EDIT_MODE=true"
    echo "  ATOMIC_PRESERVE=true"
    echo ""
    
    # Now proceed to sign_mode which will do the actual work
    print_info "Proceeding to sign commits..."
}

# ============================================================================
# SIGN MODE — re-sign commits across a range and restore dates
# ============================================================================

sign_mode() {
    print_header
    check_git_repo
    backup_repo

    # Remember the original branch so we can offer to override it after creating tmp branches
    ORIGINAL_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    print_info "Original branch recorded: $ORIGINAL_BRANCH"

    # Validate GPG setup (only required when signing)
    if [[ "$SIGN_MODE" == "true" ]]; then
        local signingkey
        signingkey="$(git config user.signingkey 2>/dev/null || echo '')"
        if ! command -v gpg &>/dev/null || [[ -z "$signingkey" ]] || [[ "$signingkey" == "none" ]]; then
            print_warning "GPG not found or signing key not configured properly. Aborting sign operation."
            if [[ "$signingkey" == "none" ]]; then
                print_error "Signing key is set to 'none'. Check: git config --list | grep user.signingkey"
            fi
            exit 1
        fi
    fi

    # If --reauthor provided a target, include that commit in range to ensure merges are rewritten
    if [[ "$REAUTHOR_MODE" == "true" && -n "$REAUTHOR_TARGET" ]]; then
        if [[ "$REAUTHOR_TARGET" == *".."* ]]; then
            RANGE="$REAUTHOR_TARGET"
        else
            RANGE="$REAUTHOR_TARGET^..HEAD"
        fi
    fi

    # Normalise simple ranges like HEAD=5 into HEAD=5..HEAD for clarity
    if [[ "$RANGE" != *".."* ]]; then
        RANGE="$RANGE..HEAD"
    fi

    echo -e "${BOLD}Sign/Author Mode${NC}"
    echo -e "Range: ${CYAN}$RANGE${NC}"

    # In harness mode we auto-confirm to allow non-interactive testing (especially with --dry-run)
    if [[ "$HARNESS_MODE" == "true" ]]; then
        print_info "Harness mode: auto-confirming sign operation"
    else
        if ! confirm_changes; then
            print_info "Cancelled"
            exit 0
        fi
    fi

    # Capture original dates for commits in the specified range - CRITICAL for Phase 2
    # Store as COMMIT_SHA|AUTHOR_DATE|COMMITTER_DATE in a temp file for reference during signing
    local original_dates_file="/tmp/git-original-dates-$$.txt"
    git log --format="%H|%aI|%cI" "$RANGE" > "$original_dates_file"
    capture_dates_for_range "$RANGE"

    # Determine the oldest commit and its parent so we can rebase from parent (or --root)
    local oldest
    oldest=$(git rev-list --reverse "$RANGE" | head -n1)
    if [[ -z "$oldest" ]]; then
        print_error "Invalid range: $RANGE"
        exit 1
    fi
    local parent
    parent=$(git rev-parse "${oldest}~1" 2>/dev/null || true)

    if [[ -z "$parent" ]]; then
        REBASE_BASE="--root"
    else
        REBASE_BASE="$parent"
    fi

    # Check for merge commits; rebase -i with merges is risky for automated operations
    if git rev-list --merges "$RANGE" | grep -q .; then
        # If PRESERVE_TOPOLOGY is already set, skip the menu
        if [[ "${PRESERVE_TOPOLOGY:-}" == [Tt][Rr][Uu][Ee] && "$REAUTHOR_MODE" != "true" ]]; then
            print_info "PRESERVE_TOPOLOGY=true; retaining merge topology and signing directly via rebase"
            
            # DEFAULT: Skip leading signed commits, rebase from first unsigned onwards
            # This minimises history rewriting by not touching already-signed commits
            local commit_info
            commit_info=$(git log --reverse --format="%h %G?" "$RANGE" 2>/dev/null)
            
            if [[ -n "$commit_info" ]] && ! echo "$commit_info" | grep -q '[NE]' && "$RESIGN_MODE" != "true" ]]; then
                # All commits in range are already signed
                local total
                total=$(echo "$commit_info" | wc -l)
                print_success "All $total commits in range already signed - no rebasing needed"
                return 0
            fi
            
            # Find first unsigned commit
            local first_unsigned=""
            local leading_signed_count=0
            if [[ -n "$commit_info" ]]; then
                if [[ "$RESIGN_MODE" == "true" ]]; then
                    first_unsigned=$(echo "$commit_info" | head -n1 | awk '{print $1}')
                else
                    first_unsigned=$(echo "$commit_info" | grep -m1 '[NE]' | awk '{print $1}')
                fi
                if [[ -n "$first_unsigned" ]]; then
                    leading_signed_count=$(echo "$commit_info" | grep -B999 "^${first_unsigned}" | grep "^[^ ]* G" | wc -l)
                fi
            fi
            
            # Determine rebase base: skip leading signed commits, start from parent of first unsigned
            local rebase_base="--root"
            if [[ -n "$first_unsigned" ]]; then
                rebase_base="${first_unsigned}^"
                print_info "Found $leading_signed_count leading signed commits - skipping them"
                print_info "Rebasing from first unsigned commit ($first_unsigned) onwards"
            else
                print_info "No unsigned commits found - all signed already"
                return 0
            fi
            
            # Clean up any stale rebase-merge directory
            if [[ -d ".git/rebase-merge" ]]; then
                rm -rf .git/rebase-merge
            fi
            
            # Apply rebase with proven flags
            if git rebase "$rebase_base" --rebase-merges --gpg-sign --committer-date-is-author-date; then
                print_success "Unsigned commits signed; $leading_signed_count leading signed commits remain untouched"
                
                # Auto-push if AUTO_FIX_REBASE is set
                if [[ "${AUTO_FIX_REBASE:-}" == "true" ]]; then
                    print_info "AUTO_FIX_REBASE: Force-pushing signed commits to origin/$(git rev-parse --abbrev-ref HEAD)"
                    if git push --force-with-lease; then
                        print_success "Successfully pushed signed commits"
                    else
                        print_warning "Force-push failed; you may need to push manually with: git push --force-with-lease"
                    fi
                fi
                # Skip the normal Phase 2 rebase since we just did it above
                SIGNATURES_ALREADY_APPLIED="true"
            else
                print_error "Failed to sign commits while preserving topology."
                git rebase --abort || true
                exit 1
            fi
            return 0
        else
            print_warning "Range contains merge commits. Rewriting with merges directly is risky."
            echo "Options:"
            echo "  1) Linearise the range (merge topology will be flattened)."
            echo "  2) Retain merge topology (experimental - preserves merges)."
            echo "  3) Abort."
            if read -u 3 -rp "Choose [1/2/3]: " _choice; then
                :
            else
                read -rp "Choose [1/2/3]: " _choice
            fi
            case "${_choice:-1}" in
                1)
                    print_info "User chose: Linearise range (will create tmp/linear-<ts>)"
                    linearise_range_to_branch "$RANGE"
                    # After creation, set RANGE to new branch
                    RANGE="$(git rev-parse --abbrev-ref HEAD)"
                    ;;
                2)
                    print_info "User chose: Retain merge topology (experimental) - creating tmp/preserve-<ts>"
                    PRESERVE_TOPOLOGY=true
                    preserve_topology_range_to_branch "$RANGE" "false"
                    RANGE="$(git rev-parse --abbrev-ref HEAD)"
                    # Do NOT set SIGNATURES_ALREADY_APPLIED - rebase-sign will handle signing after topology is set
                    ;;
                *)
                    print_error "Operation aborted by user due to merge commits present"
                    return 1
                    ;;
            esac
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: would re-sign commits in range: $RANGE"
        return 0
    fi

    # Prepare sequence editor to insert an exec to re-sign after each pick and merge
    local amend_cmd="git commit --amend --no-edit -n"
    if [[ "$REAUTHOR_MODE" == "true" ]]; then
        amend_cmd+=" --reset-author"
    fi
    if [[ "$SIGN_MODE" == "true" ]]; then
        amend_cmd+=" -S"
    fi
    local seq_editor_cmd="sed -i -e '/^pick /a exec ${amend_cmd}' -e '/^merge /a exec ${amend_cmd}'"

    # Clean up any stale rebase state from previous failures
    if [[ -d ".git/rebase-merge" || -d ".git/rebase-apply" ]]; then
        print_warning "Found stale rebase state; cleaning up..."
        git rebase --abort 2>/dev/null || true
    fi

    print_info "Running interactive rebase to re-sign commits (no user interaction expected)"
    
    # Skip rebase if signatures were already applied during preserved-topology creation
    if [[ "${SIGNATURES_ALREADY_APPLIED:-}" != "true" ]]; then
        # Only run rebase if signatures weren't already applied
        if [[ "$REBASE_BASE" == "--root" ]]; then
            if [[ "${PRESERVE_TOPOLOGY:-}" != [Tt][Rr][Uu][Ee] ]]; then
                # Non-PRESERVE_TOPOLOGY: run normal rebase-sign
                if GIT_SEQUENCE_EDITOR="$seq_editor_cmd" git rebase -i --root; then
                    print_success "Rebase/Resign completed"
                else
                    print_error "Rebase failed during re-sign. Please inspect and resolve conflicts."
                    git rebase --abort || true
                    exit 1
                fi
            else
                # PRESERVE_TOPOLOGY=true: Sign commits while preserving ORIGINAL dates and merge topology
                # Uses proven method: Sebastian Rollén (Apr 2022) --gpg-sign --committer-date-is-author-date
                print_info "PRESERVE_TOPOLOGY=true: Signing commits while preserving ORIGINAL dates, author, and merge topology"
                print_info "Using proven rebase method: --gpg-sign --committer-date-is-author-date (signature timestamp = now, commit date = original)"
                
                if git rebase --root --rebase-merges --gpg-sign --committer-date-is-author-date; then
                    print_success "Rebase/Resign with ORIGINAL date and topology preservation completed"
                else
                    print_error "Rebase with signature and date preservation failed."
                    git rebase --abort || true
                    exit 1
                fi
            fi
        else
            if [[ "${PRESERVE_TOPOLOGY:-}" != [Tt][Rr][Uu][Ee] ]]; then
                # Non-PRESERVE_TOPOLOGY: run normal rebase-sign
                if GIT_SEQUENCE_EDITOR="$seq_editor_cmd" git rebase -i "$REBASE_BASE"; then
                    print_success "Rebase/Resign completed"
                else
                    print_error "Rebase failed during re-sign. Please inspect and resolve conflicts."
                    git rebase --abort || true
                    exit 1
                fi
            else
                # PRESERVE_TOPOLOGY=true: Sign commits while preserving ORIGINAL dates (non-root)
                # Uses proven method: Sebastian Rollén (Apr 2022) --gpg-sign --committer-date-is-author-date
                print_info "PRESERVE_TOPOLOGY=true: Signing commits while preserving ORIGINAL dates, author, and merge structure"
                print_info "Using proven rebase method: --gpg-sign --committer-date-is-author-date (signature timestamp = now, commit date = original)"
                
                if git rebase "$REBASE_BASE" --rebase-merges --gpg-sign --committer-date-is-author-date; then
                    print_success "Rebase/Resign with ORIGINAL date and topology preservation completed"
                else
                    print_error "Rebase with signature and date preservation failed."
                    git rebase --abort || true
                    exit 1
                fi
            fi
        fi
    else
        print_info "Signatures already applied during preserved-topology branch creation; skipping rebase-sign"
    fi

    # Dates are already preserved during Phase 1 (preserve_and_sign_topology_range_to_branch)
    # Verify dates are correct and skip expensive filter-branch operation
    if [[ "${PRESERVE_TOPOLOGY:-}" == [Tt][Rr][Uu][Ee] ]]; then
        # Phase 1 (commit-tree with env vars) already preserves dates correctly
        # No additional date restoration needed
        local sample_sha
        sample_sha=$(git rev-parse HEAD)
        local sample_date
        sample_date=$(git log -1 --format=%aI "$sample_sha" 2>/dev/null || true)
        
        if [[ -n "$sample_date" ]]; then
            print_success "PRESERVE_TOPOLOGY phase complete: Dates and signatures already preserved in Phase 1"
            print_info "Sample commit date: $sample_date"
        fi
    else
        # For non-preserved topology, use original method
        recreate_history_with_dates
    fi
    print_success "Resigning done"

    # CRITICAL: Before auto-pushing, verify that dates were actually preserved during Phase 2 signing
    # Since Phase 1 creates new SHAs, we verify by checking the CURRENT branch's commit dates
    if [[ "${PRESERVE_TOPOLOGY:-}" == [Tt][Rr][Uu][Ee] ]]; then
        print_info "CRITICAL VERIFICATION: Checking that signed commits have ORIGINAL dates (not current 2025-12-27 timestamp)..."
        
        # Sample the first, middle, and last commits from current branch
        local sample_commits
        mapfile -t sample_commits < <(git rev-list --reverse HEAD | awk 'NR==1 || NR==NF || NR%20==0')
        local sample_count=0
        local date_mismatch_count=0
        local sample_found=0
        
        for commit_sha in "${sample_commits[@]}"; do
            [[ -z "$commit_sha" ]] && continue
            sample_count=$((sample_count + 1))
            sample_found=$((sample_found + 1))
            
            current_date=$(git log -1 --format=%aI "$commit_sha" 2>/dev/null || true)
            
            if [[ -z "$current_date" ]]; then
                continue
            fi
            
            # Extract date component (YYYY-MM-DD) and check if it's 2025-12-23
            date_component=$(echo "$current_date" | cut -d'T' -f1)
            
            # Expected original date from the session start (2025-12-23)
            # If we see 2025-12-27, it means dates were reset to current signing time
            if [[ "$date_component" == "2025-12-27" ]]; then
                print_error "WRONG DATE DETECTED on $commit_sha: $current_date (current signing time, not original 2025-12-23)"
                date_mismatch_count=$((date_mismatch_count + 1))
            fi
        done
        
        if [[ $sample_found -eq 0 ]]; then
            print_warning "Could not sample any commits for verification"
        elif [[ $date_mismatch_count -gt 0 ]]; then
            print_error "CRITICAL: $date_mismatch_count sample commit(s) have current timestamps instead of original dates"
            print_error "This means the signing script in Phase 2 did NOT preserve original dates"
            print_error "The external dates file approach failed (SHA lookups don't work after Phase 1 rewrite)"
            print_error "ABORTING PUSH to prevent pushing incorrectly-dated commits"
            print_info ""
            print_info "Root cause: Phase 1 creates NEW SHAs, but the dates file contains OLD SHAs"
            print_info "The grep lookup in signing script fails, falling back to current dates"
            print_info ""
            print_info "Solution: The signing script should read dates from the commit being amended,"
            print_info "          not from an external file with old SHAs."
            exit 1
        else
            print_success "Date verification PASSED: Sampled $sample_found commits all have correct dates (not 2025-12-27)"
        fi
    fi

    # Auto-push after signing (atomic commit + push)
    # Only push if we're still on the original branch (not a tmp branch that needs to be merged back)
    # AND signatures weren't already pushed during PRESERVE_TOPOLOGY rebase
    if [[ "${RANGE}" != tmp/* && "${SIGNATURES_ALREADY_APPLIED:-}" != "true" ]]; then
        local current_branch
        current_branch=$(git rev-parse --abbrev-ref HEAD)
        
        print_info "Auto-pushing signed commits to origin/${current_branch}"
        if git push --force-with-lease origin "$current_branch"; then
            print_success "Successfully pushed signed commits to origin/${current_branch}"
        else
            print_warning "Force-push failed; you may need to push manually with: git push --force-with-lease"
            print_warning "This is normal if the remote has been updated since you started signing"
        fi
    fi

    # If we created a tmp branch (linearise/preserve), auto-override the original branch without prompting
    if [[ -n "${ORIGINAL_BRANCH:-}" && "${RANGE}" == tmp/* ]]; then
        local final_branch
        final_branch=$(git rev-parse --abbrev-ref HEAD)
        
        if [[ "$NO_EDIT_MODE" == "true" || "$AUTO_FIX_REBASE" == "true" ]]; then
            # Auto-confirm: force-push and checkout original branch
            print_info "AUTO_FIX: Force-pushing $final_branch to origin/${ORIGINAL_BRANCH}"
            git push origin "$final_branch:${ORIGINAL_BRANCH}" --force-with-lease 2>/dev/null || \
                git push origin "$final_branch:${ORIGINAL_BRANCH}" --force
            
            print_info "AUTO_FIX: Checking out original branch ${ORIGINAL_BRANCH}"
            git checkout "${ORIGINAL_BRANCH}" 2>/dev/null || true
            
            print_success "Automatically returned to ${ORIGINAL_BRANCH} after signing"
        else
            # Interactive mode: prompt user
            prompt_override_same_branch "${RANGE}" "${ORIGINAL_BRANCH}"
        fi
    fi
}
