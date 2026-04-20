#!/usr/bin/env bash
#
# Dev-Control Shared Library: Blossom — surgical non-tip commit amend
#
# Drives `git rebase -i <target>^` paused on the target commit and exposes
# interactive sub-actions (sed/regex replace, message edit, arbitrary shell)
# before amending and continuing the rebase.  Cleans stale CHERRY_PICK_HEAD
# leftovers, offers `git rebase --abort` on failure, and prompts for
# `git push --force-with-lease`.
#
# Required from the caller:
#   - print.sh / colours.sh sourced (print_info/print_success/print_warning/
#     print_error/print_header, BOLD/CYAN/GREEN/YELLOW/NC)
#   - check_git_repo function
#   - BLOSSOM_COMMIT (optional; if empty, prompted for)
#
# Usage:
#   source "${SCRIPT_DIR}/lib/git/blossom.sh"
#   blossom_mode
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# ============================================================================
# BLOSSOM MODE — surgical amend of a non-tip commit, preserving later commits
# ============================================================================
#
# Workflow:
#   1. GIT_SEQUENCE_EDITOR="sed -i '1s/^pick/edit/'" git rebase -i <target>^
#      → pauses at <target> with the working tree at that commit
#   2. User chooses sub-action(s): edit message, sed/regex replace in a file,
#      run an arbitrary shell command, or stop and let the caller drive
#   3. Stale .git/CHERRY_PICK_HEAD (left by aborted prior amends) is cleaned
#      so `git commit --amend` does not refuse with "in the middle of a cherry-pick"
#   4. git commit --amend (with optional new message)
#   5. git rebase --continue
#   6. Prompt for `git push --force-with-lease`
#   7. On any error, offer `git rebase --abort` to return to pre-rebase HEAD
#
# All git operations are automated; all *values* (commit, message, sed pattern,
# file path, shell command, push confirmation) are prompted for.

# Clean up stale rebase/cherry-pick state markers that can block `commit --amend`.
# Returns 0 if cleanup happened, 1 otherwise.
blossom_clean_stale_markers() {
    local git_dir
    git_dir=$(git rev-parse --git-dir 2>/dev/null) || return 1
    local cleaned=1
    if [[ -f "$git_dir/CHERRY_PICK_HEAD" ]]; then
        print_warning "Stale CHERRY_PICK_HEAD detected — removing"
        rm -f "$git_dir/CHERRY_PICK_HEAD"
        cleaned=0
    fi
    if [[ -f "$git_dir/MERGE_HEAD" ]] && ! git status --porcelain | grep -q '^UU '; then
        # Stale MERGE_HEAD without unmerged paths: also a leftover marker
        print_warning "Stale MERGE_HEAD detected — removing"
        rm -f "$git_dir/MERGE_HEAD"
        cleaned=0
    fi
    return "$cleaned"
}

# Prompt user to abort rebase; returns 0 if aborted, 1 if user declined.
blossom_offer_abort() {
    local reply
    if read -u 3 -rp "Abort rebase and return to pre-rebase HEAD? [Y/n]: " reply; then :; else
        read -rp "Abort rebase and return to pre-rebase HEAD? [Y/n]: " reply
    fi
    if [[ ! "$reply" =~ ^[Nn] ]]; then
        git rebase --abort 2>/dev/null || true
        print_info "Rebase aborted; HEAD restored"
        return 0
    fi
    print_info "Rebase left in progress; resolve manually then run: ${CYAN}git rebase --continue${NC}"
    return 1
}

# Apply a sed-style substitution to a single file, prompting for path and pattern.
# Pattern is a full sed script (e.g. 's/foo/bar/g').  Always uses an in-place edit
# with a backup and shows a unified diff for confirmation before staging.
blossom_sed_replace() {
    local file pattern reply
    if read -u 3 -rp "File to edit (relative path): " file; then :; else
        read -rp "File to edit (relative path): " file
    fi
    if [[ -z "$file" ]]; then
        print_warning "No file given; skipping"
        return 1
    fi
    if [[ ! -f "$file" ]]; then
        print_error "File not found: $file"
        return 1
    fi
    if read -u 3 -rp "sed pattern (e.g. s/old/new/g): " pattern; then :; else
        read -rp "sed pattern (e.g. s/old/new/g): " pattern
    fi
    if [[ -z "$pattern" ]]; then
        print_warning "No pattern given; skipping"
        return 1
    fi

    local tmp
    tmp=$(mktemp)
    if ! sed "$pattern" "$file" > "$tmp"; then
        print_error "sed failed; aborting replacement"
        rm -f "$tmp"
        return 1
    fi

    if cmp -s "$file" "$tmp"; then
        print_info "Pattern matched no changes in $file"
        rm -f "$tmp"
        return 1
    fi

    echo ""
    echo -e "${BOLD}Diff preview:${NC}"
    diff -u "$file" "$tmp" || true
    echo ""

    if read -u 3 -rp "Apply this change to $file? [y/N]: " reply; then :; else
        read -rp "Apply this change to $file? [y/N]: " reply
    fi
    if [[ ! "$reply" =~ ^[Yy] ]]; then
        print_info "Change discarded"
        rm -f "$tmp"
        return 1
    fi

    mv "$tmp" "$file"
    git add "$file"
    print_success "Updated and staged: $file"
    return 0
}

# Prompt user for an arbitrary shell command (one-liner) to run in the repo root.
# Output is shown; staging is left to the user (or a follow-up sub-action).
blossom_shell_action() {
    local cmd reply
    if read -u 3 -rp "Shell command to run (cwd=repo root): " cmd; then :; else
        read -rp "Shell command to run (cwd=repo root): " cmd
    fi
    [[ -z "$cmd" ]] && { print_warning "No command given; skipping"; return 1; }

    if read -u 3 -rp "Run: ${CYAN}${cmd}${NC} ? [y/N]: " reply; then :; else
        read -rp "Run: ${cmd} ? [y/N]: " reply
    fi
    [[ ! "$reply" =~ ^[Yy] ]] && { print_info "Command not run"; return 1; }

    if bash -c "$cmd"; then
        print_success "Command finished"
        echo -e "${YELLOW}Tip:${NC} stage any resulting changes with ${CYAN}git add <paths>${NC} before continuing"
        return 0
    fi
    print_error "Command exited non-zero"
    return 1
}

# Prompt for a new commit message (single line; empty keeps existing).
blossom_prompt_message() {
    local current new
    current=$(git log -1 --format=%B HEAD 2>/dev/null)
    echo ""
    echo -e "${BOLD}Current message:${NC}"
    echo "$current" | sed 's/^/    /'
    echo ""
    if read -u 3 -rp "New commit message (blank to keep existing): " new; then :; else
        read -rp "New commit message (blank to keep existing): " new
    fi
    BLOSSOM_NEW_MSG="$new"
}

blossom_mode() {
    print_header "Blossom: surgical non-tip amend"
    check_git_repo

    # Refuse to start if a rebase is already in progress
    local git_dir
    git_dir=$(git rev-parse --git-dir 2>/dev/null) || { print_error "Not a git repository"; exit 1; }
    if [[ -d "$git_dir/rebase-merge" || -d "$git_dir/rebase-apply" ]]; then
        print_error "A rebase is already in progress; resolve or abort it first"
        echo "  ${CYAN}git rebase --continue${NC}   or   ${CYAN}git rebase --abort${NC}"
        exit 1
    fi

    # Resolve target commit
    local target="$BLOSSOM_COMMIT"
    if [[ -z "$target" ]]; then
        echo ""
        echo -e "${BOLD}Recent commits:${NC}"
        git --no-pager log --oneline -n 15
        echo ""
        if read -u 3 -rp "Target commit to amend (hash, HEAD~N, etc.): " target; then :; else
            read -rp "Target commit to amend (hash, HEAD~N, etc.): " target
        fi
    fi
    [[ -z "$target" ]] && { print_error "No target commit given"; exit 1; }

    local target_hash
    target_hash=$(git rev-parse --verify "$target^{commit}" 2>/dev/null) || {
        print_error "Invalid commit: $target"
        exit 1
    }
    local head_hash
    head_hash=$(git rev-parse HEAD)
    if [[ "$target_hash" == "$head_hash" ]]; then
        print_warning "Target IS HEAD; use plain ${CYAN}git commit --amend${NC} instead"
        exit 1
    fi

    # Ensure target has a parent (cannot rebase root with -i <root>^)
    if ! git rev-parse --verify "${target_hash}^" >/dev/null 2>&1; then
        print_error "Target commit has no parent (root commit); --blossom cannot rewrite the root"
        exit 1
    fi

    echo ""
    echo -e "${BOLD}Target:${NC} $(git log -1 --format='%h %s (%an, %ar)' "$target_hash")"
    echo -e "${BOLD}Will rewrite:${NC} $(git rev-list --count "${target_hash}..HEAD") commit(s) on top"
    echo ""
    local confirm
    if read -u 3 -rp "Proceed with interactive rebase at ${target_hash:0:7}? [y/N]: " confirm; then :; else
        read -rp "Proceed with interactive rebase at ${target_hash:0:7}? [y/N]: " confirm
    fi
    [[ ! "$confirm" =~ ^[Yy] ]] && { print_info "Cancelled"; exit 0; }

    # Stash any uncommitted work (separate from the rebase machinery)
    local had_stash=false
    if ! git diff --quiet || ! git diff --cached --quiet; then
        print_info "Stashing uncommitted changes"
        if git stash push -u -m "blossom-pre-rebase-$(date +%s)" --quiet; then
            had_stash=true
        else
            print_error "Stash failed; aborting"
            exit 1
        fi
    fi

    # Save HEAD as a backup tag for safety
    local backup_tag="backup/blossom-pre-$(date -u +%Y%m%dT%H%M%SZ)"
    git tag -f "$backup_tag" HEAD >/dev/null 2>&1 || true
    print_info "Backup tag: ${CYAN}${backup_tag}${NC}"

    # Step 1: launch the rebase, auto-flipping pick→edit on the first line (the target)
    print_info "Starting interactive rebase at ${target_hash:0:7}^"
    if ! GIT_SEQUENCE_EDITOR="sed -i '1s/^pick/edit/'" git rebase -i "${target_hash}^"; then
        print_error "Rebase failed to start (or stopped on a conflict)"
        blossom_offer_abort || true
        [[ "$had_stash" == "true" ]] && git stash pop --quiet 2>/dev/null || true
        exit 1
    fi

    # Step 2: interactive sub-action loop
    BLOSSOM_NEW_MSG=""
    local done_editing=false
    while [[ "$done_editing" != "true" ]]; do
        echo ""
        echo -e "${BOLD}Blossom sub-actions${NC} (paused at ${CYAN}$(git log -1 --format='%h %s')${NC})"
        echo -e "  ${CYAN}1)${NC} Edit a file (sed/regex replace)"
        echo -e "  ${CYAN}2)${NC} Set new commit message"
        echo -e "  ${CYAN}3)${NC} Run an arbitrary shell command"
        echo -e "  ${CYAN}4)${NC} Show ${CYAN}git status${NC}"
        echo -e "  ${CYAN}5)${NC} Show ${CYAN}git diff${NC} (working tree)"
        echo -e "  ${CYAN}6)${NC} Stage all changes (${CYAN}git add -A${NC})"
        echo -e "  ${GREEN}c)${NC} Commit amend and continue"
        echo -e "  ${YELLOW}a)${NC} Abort rebase"
        local choice
        if read -u 3 -rp "> " choice; then :; else read -rp "> " choice; fi
        case "$choice" in
            1) blossom_sed_replace ;;
            2) blossom_prompt_message ;;
            3) blossom_shell_action ;;
            4) git status ;;
            5) git --no-pager diff ;;
            6) git add -A && print_success "All changes staged" ;;
            c|C) done_editing=true ;;
            a|A)
                if blossom_offer_abort; then
                    [[ "$had_stash" == "true" ]] && git stash pop --quiet 2>/dev/null || true
                    exit 0
                fi
                ;;
            *) print_warning "Unknown choice: $choice" ;;
        esac
    done

    # Step 3: clean stale markers before amending
    blossom_clean_stale_markers || true

    # Step 4: amend.  If nothing staged AND no message change, allow --no-edit fast path.
    local amend_args=(--no-verify)
    if [[ -n "$BLOSSOM_NEW_MSG" ]]; then
        amend_args+=(-m "$BLOSSOM_NEW_MSG")
    else
        amend_args+=(--no-edit)
    fi

    if ! git diff --cached --quiet || [[ -n "$BLOSSOM_NEW_MSG" ]]; then
        print_info "Amending commit"
        if ! git commit --amend "${amend_args[@]}"; then
            print_error "Amend failed"
            blossom_offer_abort || true
            [[ "$had_stash" == "true" ]] && git stash pop --quiet 2>/dev/null || true
            exit 1
        fi
    else
        print_info "Nothing to amend (no staged changes, no message change) — continuing rebase"
    fi

    # Step 5: continue the rebase to replay later commits
    print_info "Continuing rebase to replay later commits"
    if ! git rebase --continue; then
        print_error "Rebase --continue failed (likely a conflict in a replayed commit)"
        echo "Resolve conflicts, then run: ${CYAN}git rebase --continue${NC}"
        echo "Or to undo everything: ${CYAN}git rebase --abort && git reset --hard ${backup_tag}${NC}"
        [[ "$had_stash" == "true" ]] && print_info "Note: pre-rebase stash still present (stash@{0})"
        exit 1
    fi

    print_success "Rebase complete"

    # Step 6: restore stash
    if [[ "$had_stash" == "true" ]]; then
        print_info "Restoring pre-rebase stash"
        git stash pop --quiet 2>/dev/null || print_warning "Stash pop conflicted; resolve manually (stash@{0})"
    fi

    # Step 7: prompt for push
    echo ""
    local should_push
    if read -u 3 -rp "Push to remote with --force-with-lease? [y/N]: " should_push; then :; else
        read -rp "Push to remote with --force-with-lease? [y/N]: " should_push
    fi
    if [[ "$should_push" =~ ^[Yy] ]]; then
        if git push --force-with-lease; then
            print_success "Pushed"
        else
            print_error "Push failed; backup tag remains: ${backup_tag}"
            exit 1
        fi
    else
        print_info "Ready to push when you are: ${CYAN}git push --force-with-lease${NC}"
        print_info "Backup tag: ${CYAN}${backup_tag}${NC} (delete with: git tag -d ${backup_tag})"
    fi
}
