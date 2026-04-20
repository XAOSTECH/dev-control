#!/usr/bin/env bash
#
# Dev-Control Shared Library: Amend — capture-all-dates, amend one commit,
# recreate history.
#
# Workflow ("secret amend"):
#   1. Snapshot every author/committer date in the current branch.
#   2. Drive `git rebase -i <target>^` with sed to flip the target to `edit`.
#   3. Optionally apply selected stash files to the working tree, stage,
#      `git commit --amend`, then `git rebase --continue`.
#   4. Re-apply the captured dates so the surrounding history looks
#      untouched.
#
# Required from the caller:
#   - print.sh / colours.sh sourced (print_info/print_success/print_warning/
#     print_error/print_header/print_header_success, BOLD/CYAN/GREEN/YELLOW/NC)
#   - check_git_repo function
#   - capture_all_dates / capture_dates_for_range / display_and_edit_dates
#     (lib/git/dates.sh)
#   - recreate_history_with_dates (lib/git/reconstruct.sh)
#   - select_stash_files (in fix-history.sh)
#   - Globals: AMEND_COMMIT, STASH_NUM, TEMP_BACKUP, TEMP_ALL_DATES,
#     TEMP_STASH_PATCH
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# ============================================================================
# AMEND MODE - CAPTURE ALL DATES, AMEND ONE COMMIT, RECREATE HISTORY
# ============================================================================

backup_repo() {
    print_info "Creating backup bundle..."
    git bundle create "$TEMP_BACKUP" --all
    print_success "Backup saved: $TEMP_BACKUP"
}

amend_single_commit() {
    local target_hash="$1"
    local stash_patch="$2"
    
    print_info "Preparing to amend commit: ${CYAN}$(git rev-parse --short $target_hash)${NC}"
    
    local parent
    parent=$(git rev-parse "${target_hash}~1")
    
    print_info "Starting interactive rebase..."
    echo ""
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "Commit to amend: ${CYAN}$(git log -1 --oneline $target_hash)${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Use git rebase -i with GIT_EDITOR to auto-mark as edit
    EDITOR="sed -i '0,/^pick ${target_hash:0:7}/s/^pick/edit/'" GIT_SEQUENCE_EDITOR="sed -i '0,/^pick ${target_hash:0:7}/s/^pick/edit/'" \
    git rebase -i "$parent" || true
    
    echo ""
    echo -e "${BOLD}Make your edits to the commit files.${NC}"
    
    # If stash patch provided, apply it
    if [[ -n "$stash_patch" ]] && [[ -f "$stash_patch" ]]; then
        echo -e "${YELLOW}Applying stash files...${NC}"
        # Use git apply with --whitespace=nowarn and force overwrite
        if git apply --reject "$stash_patch" 2>&1 | grep -v "^hint:" | grep -v "^checking patch"; then
            git add -A
            print_success "Stash files applied and staged"
        else
            print_warning "Applying stash with conflicts - staging available changes"
            git add -A 2>/dev/null || true
        fi
    fi
    
    # Auto-continue rebase without waiting for user input
    print_info "Auto-continuing rebase..."
    git rebase --continue || {
        print_error "Rebase continue failed"
        return 1
    }
    
    print_success "Rebase completed"
}

amend_mode() {
    print_header
    
    check_git_repo
    backup_repo
    
    # Resolve the commit to amend
    local target_hash
    target_hash=$(git rev-parse "$AMEND_COMMIT") || {
        print_error "Invalid commit: $AMEND_COMMIT"
        exit 1
    }
    
    # Check it's not the last commit
    local head_hash
    head_hash=$(git rev-parse HEAD)
    if [[ "$target_hash" == "$head_hash" ]]; then
        print_warning "Target is the last commit. Use normal git amend for that."
        exit 1
    fi
    
    echo ""
    echo -e "${BOLD}Amend Mode${NC}"
    echo -e "Target commit: ${CYAN}$(git log -1 --oneline $target_hash)${NC}"
    echo -e "Backup saved: ${CYAN}$TEMP_BACKUP${NC}"
    echo ""
    
    # Optional: apply stash files to this commit
    local stash_patch_to_apply=""
    if [[ -n "$STASH_NUM" ]] && [[ "$STASH_NUM" != "false" ]]; then
        echo -e "${BOLD}Apply stash files to this commit? [y/N]:${NC}"
        if read -u 3 -rp "> " apply_stash; then :; else read -rp "> " apply_stash; fi
        
        if [[ "$apply_stash" =~ ^[Yy] ]]; then
            print_info "Selecting files from stash@{$STASH_NUM}..."
            select_stash_files "$STASH_NUM"
            stash_patch_to_apply="$TEMP_STASH_PATCH"
            echo -e "${GREEN}✓${NC} Stash files will be applied to amended commit"
        fi
    fi
    
    if read -u 3 -rp "Continue? [Y/n]: " confirm; then :; else read -rp "Continue? [Y/n]: " confirm; fi
    if [[ "$confirm" =~ ^[Nn] ]]; then
        print_info "Cancelled"
        exit 0
    fi
    
    # Step 1: Capture all original dates
    local base_commit
    base_commit=$(git rev-list --max-parents=0 HEAD)
    capture_all_dates "$base_commit"
    
    # Step 1b: Display and optionally edit dates
    display_and_edit_dates "$TEMP_ALL_DATES" "$target_hash"
    
    # Step 2: Amend the commit
    amend_single_commit "$target_hash" "$stash_patch_to_apply"
    
    # Step 3: Recreate history with all original dates
    recreate_history_with_dates
    
    print_header_success "Complete!"
    
    echo -e "History recreated as if nothing happened."
    echo -e "Backup available: ${CYAN}$TEMP_BACKUP${NC}"
    echo ""
    
    # Try to read from stdin, fallback to interactive if not available
    if read -t 1 -rp "Push to remote? [y/N]: " should_push 2>/dev/null; then
        true  # Input was provided
    else
        # No piped input available, ask interactively
        read -rp "Push to remote? [y/N]: " should_push
    fi
    
    if [[ "$should_push" =~ ^[Yy] ]]; then
        print_info "Pushing with force-with-lease..."
        git push --force-with-lease || {
            print_error "Push failed"
            return 1
        }
        print_success "Pushed"
    else
        print_info "Ready to push when you are: ${CYAN}git push --force-with-lease${NC}"
    fi
}
