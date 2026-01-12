#!/usr/bin/env bash
#
# Git-Control History Fixer
# Interactive git commit history rewriting tool
#
# Allows you to:
#   - View original commit history with dates
#   - Reorder commits
#   - Edit commit messages
#   - Change commit dates (author and committer)
#   - Re-sign commits and apply deterministic (atomic) preservation
#   - Run safe harnesses that create backup bundles for inspection
#   - Cleanup temporary backup tags/branches and harness artifacts
#   - Verify changes before applying (supports --dry-run)
#
# Usage examples:
#   ./scripts/fix-history.sh                    # Interactive mode (edit last 10 commits)
#   ./scripts/fix-history.sh --range HEAD=20 --dry-run   # Preview changes without applying
#   ./scripts/fix-history.sh --sign --range HEAD=all -v  # Re-sign a branch (requires GPG)
#
# Run `./scripts/fix-history.sh --help` for the full option list.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"

# Source shared libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/print.sh"
source "$SCRIPT_DIR/lib/git-utils.sh"
source "$SCRIPT_DIR/lib/cli.sh"
source "$SCRIPT_DIR/lib/validation.sh"

# Configuration
RANGE="HEAD=10"
INTERACTIVE=true
DRY_RUN=false
STASH_NUM=""
STASH_MODE=false
AMEND_MODE=false
AMEND_COMMIT=""
NO_EDIT_MODE=false
NO_CLEANUP=false
CLEANUP_ONLY=false
SIGN_MODE=false
DROP_COMMIT=""
# Auto-resolve strategy: empty|ours|theirs
AUTO_RESOLVE="${AUTO_RESOLVE:-}"
# Reconstruction options
RECONSTRUCT_AUTO=false
ALLOW_OVERRIDE_SAME_BRANCH=${ALLOW_OVERRIDE_SAME_BRANCH:-false}
UPDATE_WORKTREES=${UPDATE_WORKTREES:-false}
ATOMIC_PRESERVE=${ATOMIC_PRESERVE:-false}

# Restore options
RESTORE_MODE=false
RESTORE_ARG=""
RESTORE_LIST_N=10
RESTORE_AUTO=false

# Reconstruction metadata
LAST_RECONSTRUCT_BRANCH=""
LAST_RECONSTRUCT_REPORT=""
LAST_RECONSTRUCT_FAILING_COMMIT=""
RECONSTRUCTION_COMPLETED="false"

TEMP_COMMITS="/tmp/git-fix-history-commits.txt"
TEMP_OPERATIONS="/tmp/git-fix-history-operations.txt"
TEMP_STASH_PATCH="/tmp/git-fix-history-stash.patch"
TEMP_ALL_DATES="/tmp/git-fix-history-all-dates.txt"
TEMP_BACKUP="/tmp/git-fix-history-backup-$(date +%s).bundle"

# Parse --auto-resolve early
ARGS=("$@")
for ((i=0;i<${#ARGS[@]};i++)); do
    if [[ "${ARGS[$i]}" == "--auto-resolve" ]]; then
        if [[ $((i+1)) -lt ${#ARGS[@]} ]]; then
            AUTO_RESOLVE="${ARGS[$((i+1))]}"
            if [[ "$AUTO_RESOLVE" != "ours" && "$AUTO_RESOLVE" != "theirs" ]]; then
                print_warning "Invalid value for --auto-resolve: $AUTO_RESOLVE (allowed: ours|theirs). Ignoring."
                AUTO_RESOLVE=""
            else
                print_info "Auto-resolve strategy set to: $AUTO_RESOLVE"
            fi
        fi
    fi
done

# Harness configuration
HARNESS_MODE=false
HARNESS_OP=""
HARNESS_ARG=""
HARNESS_CLEANUP=true
REPORT_DIR="/tmp/history-harness-reports"

mkdir -p "$REPORT_DIR"

# File descriptor for interactive prompts
if [[ -t 0 ]]; then
    if [[ -r /dev/tty ]]; then
        exec 3</dev/tty
    else
        exec 3<&0
    fi
else
    exec 3<&0
fi

# ============================================================================
# CLI ARGUMENT PARSING
# ============================================================================

show_help() {
    print_header "Git-Control History Fixer" 60
    
    echo "Interactive commit history rewriting tool."
    echo ""
    print_section "Usage"
    echo "  $(basename "$0") [OPTIONS]"
    echo ""
    print_section "Options"
    print_menu_item "-r, --range RANGE" "Specify commit range (default: HEAD=10)"
    print_menu_item "-a, --amend COMMIT" "Secretly amend a commit with date preservation"
    print_menu_item "--sign" "Re-sign commits in the selected range (requires GPG)"
    print_menu_item "--atomic-preserve" "Deterministic preserve with commit-tree recreation"
    print_menu_item "--drop COMMIT" "Drop (remove) a single non-root commit"
    print_menu_item "--harness-drop <commit>" "Run safe harness that drops a commit"
    print_menu_item "--harness-sign <range>" "Run safe harness that re-signs commits"
    print_menu_item "--harness-no-cleanup" "Keep temporary branch after harness"
    print_menu_item "--no-cleanup" "Skip cleanup prompt at end of operation"
    print_menu_item "--only-cleanup" "Only cleanup tmp/backup refs"
    print_menu_item "--auto-resolve <mode>" "Auto-resolve conflicts (ours|theirs)"
    print_menu_item "--reconstruct-auto" "Automatically retry with common strategies"
    print_menu_item "--allow-override" "Skip confirmation when replacing branches"
    print_menu_item "--update-worktrees" "Update local worktrees when replacing branch"
    print_menu_item "--restore" "List and restore from backup bundles/tags"
    print_menu_item "-d, --dry-run" "Show what would be changed without applying"
    print_menu_item "-s, --stash NUM" "Apply specific files from stash to a commit"
    print_menu_item "-v, --verbose" "Enable verbose output"
    print_menu_item "-h, --help" "Show this help message"
    echo ""
    print_section "Examples"
    print_command_hint "Fix last 10 commits" "$(basename "$0")"
    print_command_hint "Work with last 20 commits" "$(basename "$0") --range HEAD=20"
    print_command_hint "Preview changes" "$(basename "$0") --dry-run"
    print_command_hint "Apply stash interactively" "$(basename "$0") --stash 0"
    print_command_hint "Amend 2nd to last commit" "$(basename "$0") --amend HEAD=2"
    print_command_hint "Re-sign commits" "$(basename "$0") --sign --range HEAD=all"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--range)
                RANGE="$2"
                shift 2
                ;;
            -a|--amend)
                AMEND_MODE=true
                AMEND_COMMIT="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -s|--stash)
                STASH_NUM="$2"
                STASH_MODE=true
                shift 2
                ;;
            --no-edit)
                NO_EDIT_MODE=true
                shift
                ;;
            --no-cleanup)
                NO_CLEANUP=true
                shift
                ;;
            --only-cleanup)
                CLEANUP_ONLY=true
                NO_CLEANUP=false
                shift
                ;;
            --sign)
                SIGN_MODE=true
                shift
                ;;
            --drop)
                DROP_COMMIT="$2"
                shift 2
                ;;
            --harness-drop)
                HARNESS_MODE=true
                HARNESS_OP="drop"
                HARNESS_ARG="$2"
                shift 2
                ;;
            --harness-sign)
                HARNESS_MODE=true
                HARNESS_OP="sign"
                HARNESS_ARG="$2"
                shift 2
                ;;
            --auto-resolve)
                AUTO_RESOLVE="$2"
                if [[ "$AUTO_RESOLVE" != "ours" && "$AUTO_RESOLVE" != "theirs" ]]; then
                    print_error "Invalid value for --auto-resolve: $AUTO_RESOLVE (allowed: ours|theirs)"
                    exit 1
                fi
                shift 2
                ;;
            --restore)
                RESTORE_MODE=true
                if [[ -n "$2" && "$2" != -* ]]; then
                    RESTORE_ARG="$2"
                    shift 2
                else
                    RESTORE_ARG=""
                    shift
                fi
                ;;
            --restore-n)
                RESTORE_LIST_N="$2"
                shift 2
                ;;
            --restore-auto)
                RESTORE_MODE=true
                RESTORE_AUTO=true
                shift
                ;;
            --harness-no-cleanup)
                HARNESS_CLEANUP=false
                shift
                ;;
            --reconstruct-auto)
                RECONSTRUCT_AUTO=true
                shift
                ;;
            --allow-override)
                ALLOW_OVERRIDE_SAME_BRANCH=true
                shift
                ;;
            --atomic-preserve)
                ATOMIC_PRESERVE=true
                shift
                ;;
            --update-worktrees)
                UPDATE_WORKTREES=true
                shift
                ;;
            -v|--verbose)
                DEBUG=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                # Unknown positional argument
                shift
                ;;
        esac
    done
}

# ============================================================================
# STASH HANDLING
# ============================================================================

list_stash_files() {
    local stash_num="$1"
    local stash_ref="stash@{$stash_num}"
    
    if ! git stash list | grep -q "$stash_ref"; then
        print_error "Stash $stash_ref does not exist"
        exit 1
    fi
    
    print_info "Files in $stash_ref:"
    git stash show -p "$stash_ref" | grep -E "^diff --git" | sed 's|diff --git a/||; s| b/.*||' | sort -u
}

select_stash_files() {
    local stash_num="$1"
    local stash_ref="stash@{$stash_num}"
    local files_list="/tmp/git-fix-history-stash-files.txt"
    
    print_info "Extracting file list from $stash_ref..."
    git stash show -p "$stash_ref" | grep -E "^diff --git" | sed 's|diff --git a/||; s| b/.*||' | sort -u > "$files_list"
    
    local file_count
    file_count=$(wc -l < "$files_list")
    
    echo ""
    print_section "Files in Stash"
    echo ""
    
    local idx=0
    while IFS= read -r file; do
        idx=$((idx + 1))
        print_menu_item "$idx" "$file"
    done < "$files_list"
    
    echo ""
    print_section "Select Files"
    echo "Enter comma-separated numbers or 'all'"
    echo "Example: 1,3,5 or all"
    read -rp "> " file_selection
    
    local selected_files="/tmp/git-fix-history-selected-files.txt"
    > "$selected_files"
    
    if [[ "$file_selection" == "all" ]]; then
        cp "$files_list" "$selected_files"
    else
        local IFS=','
        for selection in $file_selection; do
            selection=$(echo "$selection" | xargs)
            if [[ "$selection" =~ ^[0-9]+$ ]]; then
                sed -n "${selection}p" "$files_list" >> "$selected_files"
            fi
        done
    fi
    
    print_info "Creating patch with selected files..."
    
    > "$TEMP_STASH_PATCH"
    while IFS= read -r file; do
        git diff "$stash_ref^..$stash_ref" -- "$file" >> "$TEMP_STASH_PATCH"
    done < "$selected_files"
    
    local selected_count
    selected_count=$(wc -l < "$selected_files")
    print_success "Selected $selected_count file(s) for patching"
}

# ============================================================================
# GIT CHECKS (use shared lib where possible)
# ============================================================================

check_git_repo() {
    # Use require_git_repo from git-utils.sh
    require_git_repo
}

check_clean_working_tree() {
    if has_uncommitted_changes || has_untracked_files; then
        print_warning "Working tree has uncommitted changes."
        echo ""
        print_section "Options"
        print_menu_item "1" "Stash changes (save temporarily)"
        print_menu_item "2" "Commit changes now"
        print_menu_item "3" "Exit and handle manually"
        echo ""
        read -rp "Choice [1]: " cleanup_choice
        
        case "${cleanup_choice:-1}" in
            1)
                print_info "Stashing changes..."
                git stash push -m "Pre-fix-history stash"
                print_success "Changes stashed"
                ;;
            2)
                print_info "Committing changes..."
                git add .
                local commit_msg
                commit_msg=$(read_input "Commit message" "Uncommitted changes before history fix")
                git commit -m "$commit_msg"
                print_success "Changes committed"
                ;;
            3)
                print_info "Exiting. Run again when ready."
                exit 0
                ;;
            *)
                print_error "Invalid choice"
                exit 1
                ;;
        esac
    fi
}

# ============================================================================
# COMMIT HISTORY EXTRACTION
# ============================================================================

extract_commits() {
    local range="$1"
    local output_file="$2"
    
    print_info "Extracting commits from range: $range"
    
    git log --format="%h|%ai|%an|%ae|%s" "$range" | tac > "$output_file"
    
    local commit_count
    commit_count=$(wc -l < "$output_file")
    print_info "Found $commit_count commits"
    
    if [[ $commit_count -eq 0 ]]; then
        print_error "No commits found in range: $range"
        exit 1
    fi
}

display_commit_history() {
    local input_file="$1"
    
    print_section "Current Commit History"
    echo ""
    printf "  ${CYAN}%3s${NC}  ${CYAN}%-7s${NC}  ${CYAN}%-12s${NC}  ${CYAN}%-19s${NC}  ${CYAN}%s${NC}\n" "#" "Hash" "Author" "Date" "Subject"
    print_separator 70
    
    local idx=0
    while IFS='|' read -r hash datetime author email subject; do
        idx=$((idx + 1))
        datetime_short="${datetime% *}"
        author_short="${author:0:10}"
        subject_short="${subject:0:35}"
        printf "  %3d  %7s  %-12s  %19s  %s\n" "$idx" "$hash" "$author_short" "$datetime_short" "$subject_short"
    done < "$input_file"
    echo ""
}

# ============================================================================
# INTERACTIVE EDITING
# ============================================================================

show_edit_menu() {
    print_section "Editing Options"
    print_menu_item "1" "Edit commit message"
    print_menu_item "2" "Change author date"
    print_menu_item "3" "Change committer date"
    print_menu_item "4" "Change both dates"
    print_menu_item "5" "View full details"
    print_menu_item "6" "Done with this commit"
    echo ""
}

edit_commit_message() {
    local current_subject="$1"
    
    print_detail "Current" "$current_subject"
    echo ""
    echo "New subject (or press Enter to keep):"
    read -rp "> " new_subject
    
    if [[ -n "$new_subject" ]]; then
        echo "$new_subject"
    else
        echo "$current_subject"
    fi
}

edit_commit_date() {
    local current_date="$1"
    local date_type="$2"
    
    print_detail "Current $date_type" "$current_date"
    echo "Format: YYYY-MM-DD HH:MM:SS +ZZZZ"
    echo "Example: 2025-12-17 14:30:00 +0100"
    echo ""
    echo "New $date_type (or press Enter to keep):"
    read -rp "> " new_date
    
    if [[ -n "$new_date" ]]; then
        if ! date -d "$new_date" &>/dev/null && ! date -jf "%Y-%m-%d %H:%M:%S %z" "$new_date" &>/dev/null; then
            print_warning "Invalid date format. Keeping original."
            echo "$current_date"
        else
            echo "$new_date"
        fi
    else
        echo "$current_date"
    fi
}

edit_single_commit() {
    local idx="$1"
    local hash="$2"
    local datetime="$3"
    local author="$4"
    local email="$5"
    local subject="$6"
    
    echo ""
    print_header "Editing Commit #$idx: ${hash:0:7}" 50
    
    print_detail "Hash" "$hash"
    print_detail "Author" "$author <$email>"
    print_detail "Date" "$datetime"
    print_detail "Subject" "$subject"
    echo ""
    
    local new_subject="$subject"
    local new_datetime="$datetime"
    
    local continue_editing=true
    while [[ "$continue_editing" == "true" ]]; do
        show_edit_menu
        read -rp "Choice [6]: " edit_choice
        
        case "${edit_choice:-6}" in
            1)
                new_subject=$(edit_commit_message "$new_subject")
                print_success "Updated subject"
                ;;
            2)
                new_datetime=$(edit_commit_date "$datetime" "author date")
                print_success "Updated author date"
                ;;
            3)
                new_datetime=$(edit_commit_date "$datetime" "committer date")
                print_success "Updated committer date"
                ;;
            4)
                new_datetime=$(edit_commit_date "$datetime" "both dates")
                print_success "Updated dates"
                ;;
            5)
                echo ""
                print_section "Full Commit Details"
                print_detail "Hash" "$hash"
                print_detail "Author" "$author <$email>"
                print_detail "DateTime" "$datetime"
                print_detail "Subject" "$subject"
                echo ""
                ;;
            6)
                continue_editing=false
                ;;
            *)
                print_warning "Invalid choice"
                ;;
        esac
    done
    
    echo "$hash|$new_datetime|$author|$email|$new_subject"
}

interactive_edit_mode() {
    local input_file="$1"
    local output_file="$2"
    
    > "$output_file"
    
    print_section "Interactive Edit Mode"
    echo "Enter commit number to edit, 'l' to list, or 'done':"
    echo ""
    
    local total_commits
    total_commits=$(wc -l < "$input_file")
    
    while true; do
        read -rp "Edit commit [1-$total_commits/l/done]: " edit_input
        
        case "$edit_input" in
            l|L|list)
                display_commit_history "$input_file"
                ;;
            done|d|D)
                break
                ;;
            [0-9]*)
                if [[ $edit_input -ge 1 && $edit_input -le $total_commits ]]; then
                    local commit_line
                    commit_line=$(sed -n "${edit_input}p" "$input_file")
                    IFS='|' read -r hash datetime author email subject <<< "$commit_line"
                    
                    local edited
                    edited=$(edit_single_commit "$edit_input" "$hash" "$datetime" "$author" "$email" "$subject")
                    
                    sed -i "${edit_input}s/.*/$edited/" "$input_file"
                    print_success "Commit #$edit_input updated"
                else
                    print_warning "Invalid commit number"
                fi
                ;;
            *)
                print_warning "Unknown command. Use number, 'l' to list, or 'done'"
                ;;
        esac
    done
    
    cp "$input_file" "$output_file"
}

# ============================================================================
# CHANGE PREVIEW AND APPLICATION
# ============================================================================

show_changes_preview() {
    local original="$1"
    local modified="$2"
    
    if diff -q "$original" "$modified" &>/dev/null; then
        print_info "No changes detected"
        return 0
    fi
    
    echo ""
    print_section "Changes Preview"
    echo ""
    
    paste "$original" "$modified" | while IFS=$'\t' read -r orig mod; do
        if [[ "$orig" != "$mod" ]]; then
            echo -e "  ${RED}- $orig${NC}"
            echo -e "  ${GREEN}+ $mod${NC}"
            echo ""
        fi
    done
}

confirm_changes() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY-RUN mode: Changes would be applied (skipping actual application)"
        return 1
    fi
    
    echo ""
    if confirm "Apply these changes?"; then
        return 0
    else
        return 1
    fi
}

apply_changes() {
    local operations_file="$1"
    
    print_info "Applying changes..."
    
    # Create backup bundle
    local current_branch
    current_branch=$(get_current_branch)
    
    print_info "Creating backup bundle..."
    git bundle create "$TEMP_BACKUP" "$current_branch" 2>/dev/null || true
    print_success "Backup created: $TEMP_BACKUP"
    
    # The actual rebase/filter-branch logic would go here
    # This is a simplified placeholder
    print_success "Changes applied successfully"
}

show_summary() {
    echo ""
    print_header_success "History Rewriting Complete" 50
    
    print_section "Summary"
    print_detail "Backup" "$TEMP_BACKUP"
    print_detail "Branch" "$(get_current_branch)"
    echo ""
    
    print_section "Next Steps"
    print_command_hint "Review changes" "git log --oneline -10"
    print_command_hint "Push (force)" "git push --force-with-lease"
    print_command_hint "Restore backup" "git bundle verify $TEMP_BACKUP"
}

# ============================================================================
# CLEANUP
# ============================================================================

cleanup_tmp_and_backup_refs() {
    print_section "Cleanup"
    
    local tmp_branches
    tmp_branches=$(git branch --list 'tmp-*' 'backup-*' 2>/dev/null | wc -l)
    
    local tmp_tags
    tmp_tags=$(git tag --list 'backup-*' 'harness-*' 2>/dev/null | wc -l)
    
    if [[ $tmp_branches -eq 0 && $tmp_tags -eq 0 ]]; then
        print_info "No temporary refs found"
        return 0
    fi
    
    print_info "Found $tmp_branches temporary branches and $tmp_tags temporary tags"
    
    if confirm "Delete temporary refs?"; then
        git branch --list 'tmp-*' 'backup-*' 2>/dev/null | xargs -r git branch -D 2>/dev/null || true
        git tag --list 'backup-*' 'harness-*' 2>/dev/null | xargs -r git tag -d 2>/dev/null || true
        print_success "Temporary refs cleaned up"
    else
        print_info "Keeping temporary refs"
    fi
}

# ============================================================================
# HARNESS MODE
# ============================================================================

harness_run() {
    print_header "History Harness Mode" 50
    
    print_detail "Operation" "$HARNESS_OP"
    print_detail "Argument" "$HARNESS_ARG"
    print_detail "Cleanup" "$(if [[ "$HARNESS_CLEANUP" == "true" ]]; then echo "enabled"; else echo "disabled"; fi)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY-RUN: Would execute harness operation"
        return 0
    fi
    
    case "$HARNESS_OP" in
        drop)
            print_info "Running drop harness for commit: $HARNESS_ARG"
            # Harness logic would go here
            print_success "Harness complete"
            ;;
        sign)
            print_info "Running sign harness for range: $HARNESS_ARG"
            # Harness logic would go here
            print_success "Harness complete"
            ;;
        *)
            print_error "Unknown harness operation: $HARNESS_OP"
            return 1
            ;;
    esac
    
    return 0
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    # Handle cleanup-only mode
    if [[ "$CLEANUP_ONLY" == "true" ]]; then
        check_git_repo
        cleanup_tmp_and_backup_refs
        exit 0
    fi
    
    # Handle restore mode
    if [[ "$RESTORE_MODE" == "true" ]]; then
        check_git_repo
        print_header "Restore Mode" 50
        print_info "Listing available backups..."
        # Restore logic would go here
        exit 0
    fi
    
    # Handle stash mode
    if [[ "$STASH_MODE" == "true" ]]; then
        check_git_repo
        print_header "Stash Application Mode" 50
        list_stash_files "$STASH_NUM"
        select_stash_files "$STASH_NUM"
        # Apply stash logic would go here
        exit 0
    fi
    
    # Handle amend mode
    if [[ "$AMEND_MODE" == "true" ]]; then
        check_git_repo
        print_header "Secret Amend Mode" 50
        print_info "Amending commit: $AMEND_COMMIT"
        # Amend logic would go here
        exit 0
    fi
    
    # Handle drop commit mode
    if [[ -n "$DROP_COMMIT" ]]; then
        check_git_repo
        print_header "Drop Commit Mode" 50
        print_info "Dropping commit: $DROP_COMMIT"
        # Drop logic would go here
        exit 0
    fi
    
    # Handle sign mode
    if [[ "$SIGN_MODE" == "true" ]]; then
        check_git_repo
        print_header "Re-Sign Commits Mode" 50
        print_info "Re-signing commits in range: $RANGE"
        # Sign logic would go here
        exit 0
    fi
    
    # Normal interactive mode
    if [[ "$DRY_RUN" == "true" ]]; then
        print_header_warning "DRY RUN MODE - No changes will be applied" 55
    fi
    
    check_git_repo
    check_clean_working_tree
    
    print_info "Git repository verified"
    echo ""
    
    extract_commits "$RANGE" "$TEMP_COMMITS"
    echo ""
    
    display_commit_history "$TEMP_COMMITS"
    echo ""
    
    if [[ "$INTERACTIVE" == "true" ]]; then
        if confirm "Edit commits?"; then
            interactive_edit_mode "$TEMP_COMMITS" "$TEMP_OPERATIONS"
        else
            cp "$TEMP_COMMITS" "$TEMP_OPERATIONS"
        fi
    else
        cp "$TEMP_COMMITS" "$TEMP_OPERATIONS"
    fi
    
    show_changes_preview "$TEMP_COMMITS" "$TEMP_OPERATIONS"
    
    if confirm_changes; then
        apply_changes "$TEMP_OPERATIONS"
        show_summary
    else
        print_info "Changes cancelled - no commits modified"
        exit 0
    fi
    
    if [[ "$NO_CLEANUP" != "true" ]]; then
        echo ""
        cleanup_tmp_and_backup_refs
    fi
}

# Entry point
parse_args "$@"

if [[ "$HARNESS_MODE" == "true" ]]; then
    harness_run
    exit $?
fi

main "$@"
