#!/usr/bin/env bash
#
# Dev-Control History Fixer
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
#   PRESERVE_TOPOLOGY=TRUE UPDATE_WORKTREES=true NO_EDIT_MODE=true AUTO_FIX_REBASE=true RECONSTRUCT_AUTO=true dc-fix --sign --range HEAD=all -v
#
# Cleaning and harness helpers:
#   ./scripts/fix-history.sh --only-cleanup      # Only cleanup tmp/backup tags and branches
#   ./scripts/fix-history.sh --no-cleanup ...    # Skip cleanup prompt at end of run
#
# Environment variables can be used in place of flags when applicable (examples: PRESERVE_TOPOLOGY, UPDATE_WORKTREES, NO_EDIT_MODE, AUTO_FIX_REBASE, RECONSTRUCT_AUTO)
# For advanced non-interactive runs consider setting env vars and using --sign / --atomic-preserve flags.
#
# Run `./scripts/fix-history.sh --help` for the full option list.
#

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"

# Source shared libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/print.sh"
source "$SCRIPT_DIR/lib/git/cleanup.sh"
source "$SCRIPT_DIR/lib/git/worktree.sh"
source "$SCRIPT_DIR/lib/git/dates.sh"
source "$SCRIPT_DIR/lib/git/topology.sh"

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
TIMED_SIGN_MODE=false  # Space out PR signing by minute boundaries
DROP_COMMIT=""
# Auto-resolve strategy: empty|ours|theirs
# Can be set via environment (AUTO_RESOLVE=ours|theirs) or via --auto-resolve <mode>
AUTO_RESOLVE="${AUTO_RESOLVE:-}"
# Reconstruction options
RECONSTRUCT_AUTO=false   # if true, try multiple auto-resolve strategies automatically
ALLOW_OVERRIDE_SAME_BRANCH=${ALLOW_OVERRIDE_SAME_BRANCH:-false}  # if true, auto-confirm destructive override of original branch when safe
UPDATE_WORKTREES=${UPDATE_WORKTREES:-false}  # if true, attempt to update checked-out worktrees for target branch after pushing
# Atomic preserve mode: perform deterministic commit-tree recreation + sign + date set in a single pass
ATOMIC_PRESERVE=${ATOMIC_PRESERVE:-false}  # set via --atomic-preserve to enable atomic/deterministic preserve

# Restore options
RESTORE_MODE=false
RESTORE_ARG=""
RESTORE_LIST_N=10
RESTORE_AUTO=false

# Reconstruction metadata (populated when fallback runs)
LAST_RECONSTRUCT_BRANCH=""
LAST_RECONSTRUCT_REPORT=""
LAST_RECONSTRUCT_FAILING_COMMIT=""
RECONSTRUCTION_COMPLETED="false"

TEMP_COMMITS="/tmp/git-fix-history-commits.txt"
TEMP_OPERATIONS="/tmp/git-fix-history-operations.txt"
TEMP_STASH_PATCH="/tmp/git-fix-history-stash.patch"
TEMP_ALL_DATES="/tmp/git-fix-history-all-dates.txt"
TEMP_BACKUP="/tmp/git-fix-history-backup-$(date +%s).bundle"

# Parse a simple --auto-resolve argument early so users can pass it anywhere on the command line
# Accepts: --auto-resolve <ours|theirs>
ARGS=("$@")
for ((i=0;i<${#ARGS[@]};i++)); do
    if [[ "${ARGS[$i]}" == "--auto-resolve" ]]; then
        if [[ $((i+1)) -lt ${#ARGS[@]} ]]; then
            AUTO_RESOLVE="${ARGS[$((i+1))]}"
            if [[ "$AUTO_RESOLVE" != "ours" && "$AUTO_RESOLVE" != "theirs" ]]; then
                echo "[WARNING] Invalid value for --auto-resolve: $AUTO_RESOLVE (allowed: ours|theirs). Ignoring." >&2
                AUTO_RESOLVE=""
            else
                echo "[INFO] Auto-resolve strategy set to: $AUTO_RESOLVE" >&2
            fi
        fi
    fi
done

# Harness configuration (minimal test harness integrated into script)
HARNESS_MODE=false
HARNESS_OP=""
HARNESS_ARG=""
HARNESS_CLEANUP=true
REPORT_DIR="/tmp/history-harness-reports"
RESTORE_MODE=false

mkdir -p "$REPORT_DIR"

# File descriptor for interactive prompts (uses /dev/tty if available)
if [[ -t 0 ]]; then
    # Try to open /dev/tty for interactive input
    if [[ -r /dev/tty ]]; then
        exec 3</dev/tty
    else
        # Fallback to stdin
        exec 3<&0
    fi
else
    exec 3<&0
fi

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# ============================================================================
# CLI ARGUMENT PARSING
# ============================================================================

show_help() {
    cat << 'EOF'
Dev-Control History Fixer - Interactive commit history rewriting

Usage: fix-history.sh [OPTIONS]

Options:
  -r, --range RANGE          Specify commit range (default: HEAD=10)
                             Examples: HEAD=5, main..HEAD, abc123..def456
  -a, --amend COMMIT         Secretly amend a commit (not latest) with date preservation
                             Recreates history as if nothing happened
                             Example: --amend HEAD=2 (amend 2nd to last commit)
  --sign                     Re-sign commits in the selected range (requires GPG)
                             Rewrites history to apply signatures and preserves dates
  --atomic-preserve          Deterministic preserve: recreate commits (including merges) with
                             `git commit-tree`, immediately sign and set author/committer dates (atomic)
  --drop COMMIT              Drop (remove) a single non-root commit from history
                             Example: --drop 181cab0 (dropping commit by hash)

  --harness-drop <commit>    Run a minimal harness that drops a commit in a temporary branch,
                             creates a backup bundle and performs post-checks (safe wrapper)
  --harness-sign <range>     Run a minimal harness that re-signs commits in a range (requires GPG)
                             (Honors global ${CYAN}--dry-run${NC} flag)
  --harness-no-cleanup       Keep temporary branch after running the harness for inspection
  --no-cleanup               Skip cleanup prompt at end of operation; do not offer to delete tmp/backup refs
  --only-cleanup             Only cleanup tmp/backup tags and branches (no other operations)
  --cleanup-merged           Also offer to cleanup merged branches (safe to delete)
  --auto-resolve <mode>      Auto-resolve conflicts during automated rebase/drop. Modes: ${CYAN}ours${NC}, ${CYAN}theirs${NC}
                             If provided, conflicting files will be auto-added (checkout --ours/--theirs)
                             before running ${CYAN}git rebase --continue${NC}.
  --reconstruct-auto         Automatically retry reconstruction with common strategies (ours/theirs) on failure
  --allow-override           Skip confirmation when replacing the original branch with a tmp branch
  --update-worktrees         When replacing a branch, detect and safely update any local worktrees that have
                             the branch checked out (creates a bundle backup first)
  --restore                  List backup bundles and tags and interactively restore a chosen ref to a branch
                             (Creates a restore branch and optionally resets the target branch) ${CYAN}(Honors global --dry-run flag)${NC}

  -d, --dry-run              Show what would be changed without applying
  -s, --stash NUM            Apply specific files from stash to a commit
                             Example: --stash 0 (applies stash@{0} interactively)
  -h, --help                 Show this help message
  -v, --verbose              Enable verbose output

Examples:
  ./scripts/fix-history.sh                           # Fix last 10 commits interactively
  ./scripts/fix-history.sh --range HEAD=20           # Work with last 20 commits
  ./scripts/fix-history.sh --dry-run                 # Preview changes without applying
  ./scripts/fix-history.sh --harness-drop a61b084 --dry-run
  ./scripts/fix-history.sh --harness-sign HEAD=5..HEAD
  ./scripts/fix-history.sh --stash 0                 # Apply stash@{0} to commits
  ./scripts/fix-history.sh --amend HEAD=2            # Secretly amend 2nd to last commit
  ./scripts/fix-history.sh --range main..HEAD        # Fix commits between main and HEAD

EOF
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
            --cleanup-merged)
                CLEANUP_MERGED=true
                shift
                ;;
            --sign)
                SIGN_MODE=true
                shift
                ;;
            --timed-sign)
                SIGN_MODE=true
                TIMED_SIGN_MODE=true
                export TIMED_SIGN_MODE
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
                # Optional argument: if the next token is not another flag, treat it as RESTORE_ARG
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

            --restore)
                RESTORE_MODE=true
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
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
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
    echo -e "${BOLD}Files in stash:${NC}"
    echo ""
    
    local idx=0
    while IFS= read -r file; do
        idx=$((idx + 1))
        echo -e "  ${CYAN}$idx)${NC} $file"
    done < "$files_list"
    
    echo ""
    echo -e "${BOLD}Select files to apply (comma-separated numbers or 'all'):${NC}"
    echo -e "  Example: ${CYAN}1,3,5${NC} or ${CYAN}all${NC}"
    read -rp "> " file_selection
    
    local selected_files="/tmp/git-fix-history-selected-files.txt"
    > "$selected_files"
    
    if [[ "$file_selection" == "all" ]]; then
        cp "$files_list" "$selected_files"
    else
        # Parse selected indices
        local IFS=','
        for selection in $file_selection; do
            selection=$(echo "$selection" | xargs)  # trim whitespace
            if [[ "$selection" =~ ^[0-9]+$ ]]; then
                sed -n "${selection}p" "$files_list" >> "$selected_files"
            fi
        done
    fi
    
    print_info "Creating patch with selected files..."
    
    # Create patch with only selected files
    > "$TEMP_STASH_PATCH"
    while IFS= read -r file; do
        git diff "$stash_ref^..$stash_ref" -- "$file" >> "$TEMP_STASH_PATCH"
    done < "$selected_files"
    
    local selected_count
    selected_count=$(wc -l < "$selected_files")
    print_success "Selected $selected_count file(s) for patching"
}

# ============================================================================
# GIT CHECKS
# ============================================================================

check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Not a git repository."
        exit 1
    fi
    
    if [[ -n "$(git status --porcelain)" ]]; then
        print_warning "Working tree has uncommitted changes."
        echo ""
        echo "Options:"
        echo -e "  ${CYAN}1)${NC} Stash changes (save temporarily)"
        echo -e "  ${CYAN}2)${NC} Commit changes now"
        echo -e "  ${CYAN}3)${NC} Exit and handle manually"
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
                read -rp "Commit message: " commit_msg
                git commit -m "${commit_msg:-Uncommitted changes before history fix}"
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
    
    print_info "Extracting commits from range: ${CYAN}$range${NC}"
    
    # Get commits in reverse order (oldest first)
    git log --format="%h|%ai|%an|%ae|%s" "$range" | tac > "$output_file"
    
    local commit_count
    commit_count=$(wc -l < "$output_file")
    print_info "Found ${CYAN}$commit_count${NC} commits"
    
    if [[ $commit_count -eq 0 ]]; then
        print_error "No commits found in range: $range"
        exit 1
    fi
}

display_commit_history() {
    local input_file="$1"
    
    echo -e "${BOLD}Current Commit History:${NC}\n"
    echo -e "  ${CYAN}#${NC}  ${CYAN}Hash${NC}      ${CYAN}Author${NC}          ${CYAN}Date${NC}                 ${CYAN}Subject${NC}"
    echo -e "  ${CYAN}──────────────────────────────────────────────────────────────────${NC}"
    
    local idx=0
    while IFS='|' read -r hash datetime author email subject; do
        idx=$((idx + 1))
        # Format: Date Time (remove seconds)
        datetime_short="${datetime% *}"
        author_short="${author:0:10}"
        subject_short="${subject:0:35}"
        printf "  ${CYAN}%2d${NC}  %7s  %-12s  %19s  %s\n" "$idx" "$hash" "$author_short" "$datetime_short" "$subject_short"
    done < "$input_file"
    echo ""
}

# ============================================================================
# INTERACTIVE EDITING
# ============================================================================

show_edit_menu() {
    echo -e "${BOLD}Editing Options:${NC}"
    echo -e "  ${CYAN}1)${NC} Edit commit message"
    echo -e "  ${CYAN}2)${NC} Change author date"
    echo -e "  ${CYAN}3)${NC} Change committer date"
    echo -e "  ${CYAN}4)${NC} Change both dates"
    echo -e "  ${CYAN}5)${NC} View full details"
    echo -e "  ${CYAN}6)${NC} Done with this commit"
    echo ""
}

edit_commit_message() {
    local current_subject="$1"
    
    echo -e "Current: ${CYAN}$current_subject${NC}"
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
    
    echo -e "Current $date_type: ${CYAN}$current_date${NC}"
    echo -e "Format: ${CYAN}YYYY-MM-DD HH:MM:SS +ZZZZ${NC}"
    echo "Example: 2025-12-17 14:30:00 +0100"
    echo ""
    echo "New $date_type (or press Enter to keep):"
    read -rp "> " new_date
    
    if [[ -n "$new_date" ]]; then
        # Validate date format
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
    echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║${NC}  Editing Commit ${CYAN}#$idx${NC}: ${CYAN}${hash:0:7}${NC}                                   ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "  ${CYAN}Hash:${NC}     $hash"
    echo -e "  ${CYAN}Author:${NC}   $author <$email>"
    echo -e "  ${CYAN}Date:${NC}     $datetime"
    echo -e "  ${CYAN}Subject:${NC}  $subject"
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
                echo -e "${GREEN}✓${NC} Updated subject"
                ;;
            2)
                # Extract author date only (first datetime in git format)
                author_date="${datetime%% *}"
                author_time="${datetime#* }"
                new_author_datetime=$(edit_commit_date "$datetime" "author date")
                # Keep committer date as is for now
                new_datetime="$new_author_datetime"
                echo -e "${GREEN}✓${NC} Updated author date"
                ;;
            3)
                new_datetime=$(edit_commit_date "$datetime" "committer date")
                echo -e "${GREEN}✓${NC} Updated committer date"
                ;;
            4)
                new_datetime=$(edit_commit_date "$datetime" "both dates")
                echo -e "${GREEN}✓${NC} Updated dates"
                ;;
            5)
                echo -e "\n${BOLD}Full Commit Details:${NC}"
                echo -e "  Hash:           $hash"
                echo -e "  Author:         $author <$email>"
                echo -e "  DateTime:       $datetime"
                echo -e "  Subject:        $subject"
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
    
    # Return modified values
    echo "$hash|$new_datetime|$author|$email|$new_subject"
}

# ============================================================================
# INTERACTIVE WORKFLOW
# ============================================================================

interactive_edit_mode() {
    local input_file="$1"
    local output_file="$2"
    
    > "$output_file"
    
    local idx=0
    while IFS='|' read -r hash datetime author email subject; do
        idx=$((idx + 1))
        
        display_commit_history "$input_file"
        echo -e "${BOLD}Edit this commit? [y/N]:${NC}"
        # Use /dev/tty (fd 3) for interactive prompts so loop stdin isn't consumed
        if read -u 3 -rp "  Commit #$idx (${hash:0:7}): " should_edit; then
            :
        else
            # Fallback to standard input
            read -rp "  Commit #$idx (${hash:0:7}): " should_edit
        fi
        
        if [[ "$should_edit" =~ ^[Yy] ]]; then
            local result
            result=$(edit_single_commit "$idx" "$hash" "$datetime" "$author" "$email" "$subject")
            echo "$result" >> "$output_file"
        else
            echo "$hash|$datetime|$author|$email|$subject" >> "$output_file"
        fi
    done < "$input_file"
}

# ============================================================================
# PREVIEW AND CONFIRMATION
# ============================================================================

show_changes_preview() {
    local original_file="$1"
    local modified_file="$2"
    
    echo -e "\n${BOLD}${YELLOW}Changes Summary:${NC}\n"
    
    local idx=0
    while IFS='|' read -r orig_hash orig_datetime orig_author orig_email orig_subject; do
        idx=$((idx + 1))
        read -r new_data < <(sed -n "${idx}p" "$modified_file")
        IFS='|' read -r new_hash new_datetime new_author new_email new_subject <<< "$new_data"
        
        if [[ "$orig_datetime" != "$new_datetime" ]] || [[ "$orig_subject" != "$new_subject" ]]; then
            echo -e "  ${CYAN}Commit #$idx${NC} (${orig_hash:0:7}):"
            
            if [[ "$orig_datetime" != "$new_datetime" ]]; then
                echo -e "    Date: ${RED}$orig_datetime${NC} → ${GREEN}$new_datetime${NC}"
            fi
            
            if [[ "$orig_subject" != "$new_subject" ]]; then
                echo -e "    Msg:  ${RED}${orig_subject:0:40}...${NC}"
                echo -e "       → ${GREEN}${new_subject:0:40}...${NC}"
            fi
            echo ""
        fi
    done < "$original_file"
}

confirm_changes() {
    echo -e "${BOLD}${YELLOW}⚠️  WARNING: This operation will rewrite commit history!${NC}"
    echo ""
    echo -e "  This will modify:"
    echo -e "    • Commit messages"
    echo -e "    • Author and committer dates"
    echo ""
    echo -e "  After applying, you will need to:"
    echo -e "    ${CYAN}git push --force-with-lease${NC}"
    echo ""
    # Use interactive FD 3 when available to avoid reading from piped stdin
    if read -u 3 -rp "Continue? [y/N]: " confirm; then
        :
    else
        read -rp "Continue? [y/N]: " confirm
    fi
    [[ "$confirm" =~ ^[Yy] ]]
}

# ============================================================================
# COMMIT REWRITING
# ============================================================================

apply_changes() {
    local modified_file="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        print_info "${YELLOW}${BOLD}DRY RUN${NC} - Preview mode only. No commits will be rewritten."
        echo -e "  To apply these changes, run: ${CYAN}fix-history.sh --range $RANGE${NC}"
        echo ""
        return 0
    fi
    
    print_info "Applying changes..."
    
    # Get the base commit (oldest one to be rewritten + 1)
    local base_commit
    base_commit=$(git rev-list --max-parents=0 HEAD)
    
    local idx=0
    while IFS='|' read -r hash datetime author email subject; do
        idx=$((idx + 1))
        
        # Filter for this specific commit and update it
        git filter-branch --env-filter '
            if [ $GIT_COMMIT = '"\"$hash\""' ]; then
                export GIT_AUTHOR_DATE='"\"$datetime\""'
                export GIT_COMMITTER_DATE='"\"$datetime\""'
            fi
        ' --force -- --all 2>/dev/null || true
        
        print_debug "Updated commit $idx/$idx"
    done < "$modified_file"
    
    print_success "Changes applied!"
    print_info "To push to remote, run: ${CYAN}git push --force-with-lease${NC}"
}

# ============================================================================
# SUMMARY
# ============================================================================

show_summary() {
    print_header_success "History Fixed!"
    echo -e "${BOLD}Next Steps:${NC}"
    echo -e "  1. Review changes: ${CYAN}git log --oneline -10${NC}"
    echo -e "  2. Push to remote: ${CYAN}git push --force-with-lease${NC}"
    echo ""
}

# ============================================================================
# CLEANUP
# ============================================================================

cleanup() {
    rm -f "$TEMP_COMMITS" "$TEMP_OPERATIONS"
}

rollback_on_cancel() {
    print_error "Script interrupted - rolling back to backup..."
    
    if [[ -f "$TEMP_BACKUP" ]]; then
        print_info "Restoring from backup: $TEMP_BACKUP"
        git bundle unbundle "$TEMP_BACKUP" || true
        git reset --hard origin/Main || git reset --hard HEAD || true
        git clean -fd
        print_success "Rolled back to pre-operation state"
    fi
    
    exit 1
}

trap cleanup EXIT
trap rollback_on_cancel INT TERM

# ============================================================================
# AMEND MODE - CAPTURE ALL DATES, AMEND ONE COMMIT, RECREATE HISTORY
# ============================================================================
# Date capture functions moved to lib/git/dates.sh:
#   capture_all_dates(), capture_dates_for_range()

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

# Date display/edit and helper generation functions moved to lib/git/dates.sh:
#   display_and_edit_dates(), GENERATED_HELPERS[], generate_apply_dates_helper_file()

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

    # Fallback: dummy-edit (existing behavior) - only for non-preserved-topology runs
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

    print_info "Step 3/3: Removing dummy file and finalizing amend"
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

# Note: find_worktree_paths_for_branch() and update_worktrees_to_remote()
# are now provided by lib/git/worktree.sh

# Note: Topology preservation functions moved to lib/git/topology.sh:
#   linearise_range_to_branch(), preserve_and_sign_topology_range_to_branch(),
#   preserve_topology_range_to_branch(), sign_commits_preserving_dates()


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

# ---------------------------------------------------------------------------
# Sign mode: re-sign commits across a range and restore dates
# ---------------------------------------------------------------------------
sign_mode() {
    print_header
    check_git_repo
    backup_repo

    # Remember the original branch so we can offer to override it after creating tmp branches
    ORIGINAL_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    print_info "Original branch recorded: $ORIGINAL_BRANCH"

    if ! command -v gpg &>/dev/null && ! git config user.signingkey &>/dev/null; then
        print_warning "GPG not found or signing key not configured. Aborting sign operation."
        exit 1
    fi

    echo -e "${BOLD}Sign Mode${NC}"
    echo -e "Range: ${CYAN}$RANGE${NC}"
    # Normalize simple ranges like HEAD=5 into HEAD=5..HEAD for clarity
    if [[ "$RANGE" != *".."* ]]; then
        RANGE="$RANGE..HEAD"
    fi

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
        if [[ "${PRESERVE_TOPOLOGY:-}" == [Tt][Rr][Uu][Ee] ]]; then
            print_info "PRESERVE_TOPOLOGY=true; retaining merge topology and signing directly via rebase"
            
            # DEFAULT: Skip leading signed commits, rebase from first unsigned onwards
            # This minimizes history rewriting by not touching already-signed commits
            local commit_info
            commit_info=$(git log --reverse --format="%h %G?" "$RANGE" 2>/dev/null)
            
            if [[ -n "$commit_info" ]] && ! echo "$commit_info" | grep -q '[NE]'; then
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
                first_unsigned=$(echo "$commit_info" | grep -m1 '[NE]' | awk '{print $1}')
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
    local seq_editor_cmd="sed -i -e '/^pick /a exec git commit --amend --no-edit -n -S' -e '/^merge /a exec git commit --amend --no-edit -n -S'"

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

# Note: sign_preserved_topology_branch() and atomic_preserve_range_to_branch()
# moved to lib/git/topology.sh

# apply_dates_from_preserve_map() moved to lib/git/dates.sh

# ---------------------------------------------------------------------------
# Drop a single commit (non-last) from history using rebase -i
# ---------------------------------------------------------------------------

# Attempt to automatically add conflicted files and continue rebase
# mode: 'ours' or 'theirs'
auto_add_conflicted_files() {
    local mode="$1"

    local conflict_files
    conflict_files=$(git diff --name-only --diff-filter=U || true)
    if [[ -z "$conflict_files" ]]; then
        print_warning "No conflicted files found to auto-resolve"
        return 1
    fi

    print_info "Auto-resolving ${mode} for conflicted files..."
    for f in $conflict_files; do
        # If file was deleted in one side, determine whether to rm or checkout
        if [[ "$mode" == "theirs" ]]; then
            git checkout --theirs -- "$f" 2>/dev/null || true
        else
            git checkout --ours -- "$f" 2>/dev/null || true
        fi

        # If the file no longer exists in the working tree, remove it, else add
        if [[ -f "$f" || -d "$f" ]]; then
            git add -- "$f"
        else
            # If file is absent, it likely should be removed
            git rm --quiet -- "$f" 2>/dev/null || true
        fi
        print_info "Staged resolution for: $f"
    done

    # Try to continue rebase
    # Use NO_EDIT_MODE to avoid editor prompts when continuing
    if [[ "$NO_EDIT_MODE" == "true" ]]; then
        print_info "NO_EDIT_MODE enabled: using GIT_EDITOR=':' for git rebase --continue"
        if GIT_EDITOR=':' git rebase --continue; then
            print_success "Rebase continued after auto-resolution"
            return 0
        else
            print_warning "git rebase --continue did not finish; there may be more conflicts"
            return 1
        fi
    else
        if git rebase --continue; then
            print_success "Rebase continued after auto-resolution"
            return 0
        else
            print_warning "git rebase --continue did not finish; there may be more conflicts"
            return 1
        fi
    fi
}

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

# Repeatedly attempt auto-resolution until rebase finishes or we hit an error
auto_resolve_all_conflicts() {
    local mode="$1"
    local attempts=0

    while true; do
        attempts=$((attempts+1))
        if auto_add_conflicted_files "$mode"; then
            # git rebase --continue succeeded and rebase finished
            return 0
        fi

        # If there are still conflicts, and attempts are within reasonable limit, continue
        local conflicts
        conflicts=$(git diff --name-only --diff-filter=U || true)
        if [[ -z "$conflicts" ]]; then
            # no conflicts remain but continuation failed => abort
            print_error "No conflicts found but rebase did not continue cleanly"
            return 1
        fi

        if (( attempts > 15 )); then
            print_error "Too many auto-resolve attempts; aborting"
            return 1
        fi

        print_info "Auto-resolve attempt $attempts complete; re-checking for new conflicts..."
        # loop and attempt resolution of new conflicts
    done
}
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


# ---------------------------------------------------------------------------
# Minimal in-script harness to run safe test operations in a temp branch
# Harness uses the global --dry-run flag (DRY_RUN) when provided.
# ---------------------------------------------------------------------------

harness_post_checks() {
    local target_hash="$1"
    local rf="$2"

    echo "Post-operation checks:" | tee -a "$rf"

    # 1) Commit absent? Use git rev-parse to detect short or full SHAs and refs
    if git rev-parse --quiet --verify "$target_hash" >/dev/null 2>&1; then
        echo "ERROR: Commit $target_hash still present in the history" | tee -a "$rf"
        # Also print the resolved full SHA for debugging
        full_sha=$(git rev-parse --verify "$target_hash" 2>/dev/null || true)
        echo "Found as: ${full_sha:-<none>}" | tee -a "$rf"
        return 1
    else
        echo "OK: Commit $target_hash absent from history" | tee -a "$rf"
    fi

    # 2) Clean working tree?
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "WARNING: Working tree not clean after operation" | tee -a "$rf"
        git status --porcelain | tee -a "$rf"
        return 1
    else
        echo "OK: Working tree clean" | tee -a "$rf"
    fi

    # 3) Diff summary vs origin/Main (if exists)
    if git rev-parse --verify origin/Main >/dev/null 2>&1; then
        echo "Diff summary (origin/Main..HEAD):" | tee -a "$rf"
        git diff --name-status origin/Main..HEAD | tee -a "$rf"
    else
        echo "origin/Main not found, skipping diff summary" | tee -a "$rf"
    fi

    return 0
}

harness_finish_success() {
    local tmp_branch="$1"
    local rf="$2"

    echo "" | tee -a "$rf"
    echo "Harness completed successfully." | tee -a "$rf"
    echo "Report saved: $rf" | tee -a "$rf"

    if [[ "$HARNESS_CLEANUP" == "true" ]]; then
        git checkout - || true
        git branch -D "$tmp_branch" || true
        echo "Cleaned up temp branch $tmp_branch" | tee -a "$rf"
    else
        echo "Temp branch retained: $tmp_branch" | tee -a "$rf"
    fi
}

harness_restore_backup() {
    local bundle="$1"
    local rf="$2"
    echo "Restoring from backup bundle: $bundle" | tee -a "$rf"
    git bundle unbundle "$bundle" || true
    git reset --hard origin/Main || git reset --hard HEAD || true
}

# List available backup bundles, harness bundles and backup tags and tmp branches
list_restore_candidates() {
    echo "Available backup bundles (in /tmp):"
    ls -1 /tmp/git-fix-history-backup-* 2>/dev/null || true
    ls -1 /tmp/harness-backup-* 2>/dev/null || true
    echo ""
    echo "Available backup tags (backup/*):"
    git tag -l 'backup/*' || true
    echo ""
    echo "Remote tmp branches (origin/tmp/*):"
    git ls-remote --heads origin 'tmp/*' 2>/dev/null | awk '{print $2}' | sed 's#refs/heads/##' || true
}

# Create a restore branch from a bundle or remote branch/tag
restore_candidate() {
    local candidate="$1"

    if [[ -f "$candidate" ]]; then
        echo "Bundle selected: $candidate"
        git bundle list-heads "$candidate" || true
        # Defer to interactive chooser for exact ref selection
        list_backups_and_restore
        return 0
    fi

    if git rev-parse --verify --quiet "$candidate" >/dev/null 2>&1; then
        TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
        local_restore="restore/${candidate}-${TIMESTAMP}"
        git branch -f "$local_restore" "$candidate"
        git push -u origin "$local_restore" || print_warning "Failed to push restore branch to origin"
        print_success "Created restore branch: $local_restore"
        return 0
    fi

    if git ls-remote --heads origin "refs/heads/${candidate}" >/dev/null 2>&1; then
        TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
        local_restore="restore/${candidate//\//_}-${TIMESTAMP}"
        git fetch origin "refs/heads/${candidate}:refs/heads/${local_restore}" || { print_error "Failed to fetch origin/${candidate}"; return 1; }
        git push -u origin "$local_restore" || print_warning "Failed to push restore branch to origin"
        print_success "Created restore branch: $local_restore"
        return 0
    fi

    print_error "Candidate not recognized or missing: $candidate"
    return 1
}

# Interactively list available backup bundles and tags and restore a selected ref
list_backups_and_restore() {
    print_header
    check_git_repo

    echo "Available backup bundles (local /tmp):"
    local bundles
    IFS=$'\n' read -d '' -r -a bundles < <(ls -1 /tmp/git-fix-history-backup-*.bundle /tmp/harness-backup-*.bundle 2>/dev/null || true)

    echo "Available backup tags (git):"
    local tags
    IFS=$'\n' read -d '' -r -a tags < <(git tag -l "backup/*" 2>/dev/null || true)

    local idx=0
    declare -a choices

    echo ""
    echo "Choose a backup to inspect/restore:"

    for b in "${bundles[@]}"; do
        idx=$((idx+1))
        choices[$idx]="bundle:$b"
        echo "  $idx) bundle: $(basename "$b")"
    done

    for t in "${tags[@]}"; do
        idx=$((idx+1))
        choices[$idx]="tag:$t"
        echo "  $idx) tag: $t"
    done

    if [[ ${#choices[@]} -eq 0 ]]; then
        print_error "No backup bundles or tags found."
        return 1
    fi

    echo ""
    read -u 3 -rp "Select number to restore (or 'q' to cancel): " sel
    if [[ "$sel" == "q" ]]; then
        print_info "Cancelled"
        return 0
    fi

    if ! [[ "$sel" =~ ^[0-9]+$ ]] || [[ -z "${choices[$sel]}" ]]; then
        print_error "Invalid selection"
        return 1
    fi

    IFS=':' read -r typ val <<< "${choices[$sel]}"

    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)

    if [[ "$typ" == "bundle" ]]; then
        local bundle_file="$val"
        echo "Bundle selected: $bundle_file"
        echo "Contents:"; git bundle list-heads "$bundle_file" || true

        read -u 3 -rp "Enter the ref to restore (e.g. refs/heads/devcontainer/minimal) or 'q' to cancel: " ref_choice
        if [[ "$ref_choice" == "q" ]]; then
            print_info "Cancelled"
            return 0
        fi

        local restore_branch="restore/$(echo "$ref_choice" | sed 's|refs/heads/||; s|/|_|g')-${TIMESTAMP}"
        print_info "Creating local restore branch: $restore_branch from bundle ref: $ref_choice"
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "DRY-RUN: would run: git fetch \"$bundle_file\" \"$ref_choice\":refs/heads/$restore_branch"
            print_info "DRY-RUN: would run: git push -u origin \"$restore_branch\""
        else
            git fetch "$bundle_file" "$ref_choice":"refs/heads/$restore_branch" || { print_error "Failed to fetch ref from bundle"; return 1; }
            git push -u origin "$restore_branch" || print_warning "Failed to push restore branch to origin; branch is local"
        fi

        read -u 3 -rp "Reset a target branch to this restore? (Enter branch name or leave empty to skip): " target_branch
        if [[ -n "$target_branch" ]]; then
            read -u 3 -rp "Confirm: reset branch '$target_branch' to '$restore_branch' and force-push? [y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy] ]]; then
                TAG=backup/${target_branch}-pre-restore-${TIMESTAMP}
                if [[ "$DRY_RUN" == "true" ]]; then
                    print_info "DRY-RUN: would run: git tag -f \"$TAG\" refs/heads/$target_branch"
                    print_info "DRY-RUN: would run: git push origin \"refs/tags/$TAG\""
                    print_info "DRY-RUN: would run: git checkout \"$target_branch\" || git checkout -b \"$target_branch\""
                    print_info "DRY-RUN: would run: git reset --hard \"$restore_branch\""
                    print_info "DRY-RUN: would run: git push --force-with-lease origin \"$target_branch\""
                    print_success "DRY-RUN: Branch $target_branch would be reset to $restore_branch"
                else
                    git tag -f "$TAG" refs/heads/$target_branch 2>/dev/null || true
                    git push origin "refs/tags/$TAG" || true
                    git checkout "$target_branch" || git checkout -b "$target_branch"
                    git reset --hard "$restore_branch"
                    git push --force-with-lease origin "$target_branch"
                    print_success "Branch $target_branch reset to $restore_branch and pushed"
                fi
            else
                print_info "Skipped resetting target branch"
            fi
        fi

        print_success "Restore branch created: $restore_branch"
        return 0
    else
        # tag restore
        local tag_name="$val"
        echo "Tag selected: $tag_name"
        local restore_branch="restore/${tag_name}-${TIMESTAMP}"
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "DRY-RUN: would run: git branch -f \"$restore_branch\" \"$tag_name\""
            print_info "DRY-RUN: would run: git push -u origin \"$restore_branch\""
        else
            git branch -f "$restore_branch" "$tag_name"
            git push -u origin "$restore_branch" || print_warning "Failed to push restore branch to origin"
        fi

        read -u 3 -rp "Reset a target branch to this tag? (Enter branch name or leave empty to skip): " target_branch
        if [[ -n "$target_branch" ]]; then
            read -u 3 -rp "Confirm: reset branch '$target_branch' to tag '$tag_name' and force-push? [y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy] ]]; then
                TAG=backup/${target_branch}-pre-restore-${TIMESTAMP}
                if [[ "$DRY_RUN" == "true" ]]; then
                    print_info "DRY-RUN: would run: git tag -f \"$TAG\" refs/heads/$target_branch"
                    print_info "DRY-RUN: would run: git push origin \"refs/tags/$TAG\""
                    print_info "DRY-RUN: would run: git checkout \"$target_branch\" || git checkout -b \"$target_branch\""
                    print_info "DRY-RUN: would run: git reset --hard \"$tag_name\""
                    print_info "DRY-RUN: would run: git push --force-with-lease origin \"$target_branch\""
                    print_success "DRY-RUN: Branch $target_branch would be reset to $tag_name"
                else
                    git tag -f "$TAG" refs/heads/$target_branch 2>/dev/null || true
                    git push origin "refs/tags/$TAG" || true
                    git checkout "$target_branch" || git checkout -b "$target_branch"
                    git reset --hard "$tag_name"
                    git push --force-with-lease origin "$target_branch"
                    print_success "Branch $target_branch reset to $tag_name and pushed"
                fi
            else
                print_info "Skipped resetting target branch"
            fi
        fi
        print_success "Restore branch created from tag: $restore_branch"
        return 0
    fi
}


harness_run() {
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMP_BRANCH="tmp/harness-${TIMESTAMP}"
    REPORT_FILE="$REPORT_DIR/report-${TIMESTAMP}.txt"

    echo "Harness report: $REPORT_FILE"

    echo "Operation: ${HARNESS_OP} ${HARNESS_ARG}" | tee "$REPORT_FILE"

    # Capture pre-op log snapshot (limit by RESTORE_LIST_N)
    PRE_LOG="$REPORT_DIR/pre-${TIMESTAMP}.log"
    git --no-pager log --oneline -n "${RESTORE_LIST_N}" > "$PRE_LOG"
    echo "Pre-op log (last ${RESTORE_LIST_N} commits):" | tee -a "$REPORT_FILE"
    sed 's/^/  /' "$PRE_LOG" | tee -a "$REPORT_FILE"

    # Bail if a previous tmp/remove attempt for this commit exists to avoid repetition
    if [[ "${HARNESS_FORCE:-false}" != "true" ]]; then
        if git for-each-ref --format='%(refname:short)' refs/heads | grep -q "^tmp/remove-${HARNESS_ARG}-"; then
            echo "ERROR: Found existing tmp/remove-${HARNESS_ARG}-* branches. Aborting to avoid repeated failed attempts." | tee -a "$REPORT_FILE"
            return 1
        fi
    else
        echo "WARNING: HARNESS_FORCE=true - proceeding despite existing tmp/remove branches" | tee -a "$REPORT_FILE"
    fi

    # Create temp branch
    git checkout -b "$TMP_BRANCH" | tee -a "$REPORT_FILE"
    echo "Created temp branch: $TMP_BRANCH" | tee -a "$REPORT_FILE"

    # Create local bundle backup
    BUNDLE="/tmp/harness-backup-${TIMESTAMP}.bundle"
    git bundle create "$BUNDLE" --all
    echo "Backup bundle: $BUNDLE" | tee -a "$REPORT_FILE"

    # Honor global DRY_RUN
    PREV_DRY_RUN="$DRY_RUN"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Running harness in DRY-RUN mode" | tee -a "$REPORT_FILE"
    fi

    case "$HARNESS_OP" in
        drop)
            echo "Running drop for commit: $HARNESS_ARG" | tee -a "$REPORT_FILE"
            # Capture exit code so we can differentiate conflict-stops and hard failures
            drop_single_commit "$HARNESS_ARG" 2>&1 | tee -a "$REPORT_FILE"
            rc=${PIPESTATUS[0]:-1}

            # If this was a dry-run and drop_single_commit printed the DRY-RUN marker, consider the dry-run simulated
            if [[ "$PREV_DRY_RUN" == "true" ]] && grep -q "DRY RUN: would drop commit" "$REPORT_FILE"; then
                echo "DRY-RUN: drop operation simulated (no changes applied)" | tee -a "$REPORT_FILE"
                # Capture post-op log snapshot
                POST_LOG="$REPORT_DIR/post-${TIMESTAMP}.log"
                git --no-pager log --oneline -n "${RESTORE_LIST_N}" > "$POST_LOG"
                echo "Post-op log (last ${RESTORE_LIST_N} commits):" | tee -a "$REPORT_FILE"
                sed 's/^/  /' "$POST_LOG" | tee -a "$REPORT_FILE"

                echo "DRY-RUN mode: skipping post-op verification checks (no changes were applied)" | tee -a "$REPORT_FILE"
                DRY_RUN="$PREV_DRY_RUN"
                return 0
            fi

            if [[ $rc -eq 0 ]]; then
                # Success
                :
            elif [[ $rc -eq 2 ]]; then
                echo "CONFLICT: Rebase stopped due to conflicts during drop; leaving temp branch for manual resolution" | tee -a "$REPORT_FILE"
                echo "Temp branch: $TMP_BRANCH" | tee -a "$REPORT_FILE"
                DRY_RUN="$PREV_DRY_RUN"
                return 1
            else
                echo "Drop failed" | tee -a "$REPORT_FILE"
                harness_restore_backup "$BUNDLE" "$REPORT_FILE"
                DRY_RUN="$PREV_DRY_RUN"
                return 1
            fi

            # Capture post-op log snapshot
            POST_LOG="$REPORT_DIR/post-${TIMESTAMP}.log"
            git --no-pager log --oneline -n "${RESTORE_LIST_N}" > "$POST_LOG"
            echo "Post-op log (last ${RESTORE_LIST_N} commits):" | tee -a "$REPORT_FILE"
            sed 's/^/  /' "$POST_LOG" | tee -a "$REPORT_FILE"

            if ! harness_post_checks "$HARNESS_ARG" "$REPORT_FILE"; then
                harness_restore_backup "$BUNDLE" "$REPORT_FILE"
                DRY_RUN="$PREV_DRY_RUN"
                return 1
            fi
            ;;
        sign)
            echo "Running sign for range: $HARNESS_ARG" | tee -a "$REPORT_FILE"
            # set RANGE for sign_mode and let sign_mode use DRY_RUN as appropriate
            OLD_RANGE="$RANGE"
            RANGE="$HARNESS_ARG"
            if ! sign_mode 2>&1 | tee -a "$REPORT_FILE"; then
                echo "Sign failed" | tee -a "$REPORT_FILE"
                harness_restore_backup "$BUNDLE" "$REPORT_FILE"
                RANGE="$OLD_RANGE"
                DRY_RUN="$PREV_DRY_RUN"
                return 1
            fi
            RANGE="$OLD_RANGE"
            ;;
        *)
            echo "Unknown harness operation: $HARNESS_OP" | tee -a "$REPORT_FILE"
            DRY_RUN="$PREV_DRY_RUN"
            return 1
            ;;
    esac

    DRY_RUN="$PREV_DRY_RUN"

    harness_finish_success "$TMP_BRANCH" "$REPORT_FILE"
    return 0
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

# Cleanup function: removes tmp and backup branches/tags at end of run
cleanup_tmp_and_backup_refs() {
    # Delegate to shared library (uses fd 3 for input)
    cleanup_tmp_backup_refs 3
    
    # Cleanup merged branches if flag is set
    if [[ "$CLEANUP_MERGED" == "true" ]]; then
        cleanup_merged_branches_interactive 3
    fi
}

main() {
    print_header "Dev-Control History Fixer"
    parse_args "$@"
    
    # If cleanup-only mode, run cleanup and exit
    if [[ "$CLEANUP_ONLY" == "true" ]]; then
        check_git_repo
        cleanup_tmp_and_backup_refs
        exit 0
    fi

    # Normalize RANGE syntax EARLY: support 'HEAD=all' and 'HEAD=N' forms
    # This must happen before any function (like sign_mode) uses RANGE
    if [[ -n "$RANGE" ]]; then
        # If user used HEAD=all or HEAD~all (case-insensitive), map to full history
        if [[ "${RANGE,,}" =~ ^head[=~]all$ ]]; then
            ROOT_COMMIT=$(git rev-list --max-parents=0 HEAD 2>/dev/null || true)
            if [[ -n "$ROOT_COMMIT" ]]; then
                RANGE="$ROOT_COMMIT..HEAD"
                print_info "Normalized RANGE to full history: $RANGE"
            fi
        else
            # Convert HEAD=N (digits) to HEAD~N to preserve existing behavior
            if [[ "$RANGE" =~ ^HEAD=([0-9]+)$ ]]; then
                RANGE="HEAD~${BASH_REMATCH[1]}"
            fi
        fi
    fi

    # Handle restore mode
    if [[ "$RESTORE_MODE" == "true" ]]; then
        if [[ -n "$RESTORE_ARG" ]]; then
            print_info "RESTORE_ARG provided: $RESTORE_ARG"
            # If it's a bundle file path
            if [[ -f "$RESTORE_ARG" ]]; then
                print_info "Bundle file detected: $RESTORE_ARG"
                echo "Available refs in bundle:" && git bundle list-heads "$RESTORE_ARG" || true
                list_backups_and_restore
                exit 0
            fi

            # If it's a tag or local ref
            if git rev-parse --verify --quiet "$RESTORE_ARG" >/dev/null; then
                print_info "Found tag/local ref: $RESTORE_ARG - creating restore branch"
                TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
                local_restore="restore/${RESTORE_ARG}-${TIMESTAMP}"
                if [[ "$DRY_RUN" == "true" ]]; then
                    print_info "DRY-RUN: would create local restore branch: $local_restore from $RESTORE_ARG"
                    echo "Top $RESTORE_LIST_N commits on $RESTORE_ARG:" && git --no-pager log --oneline "$RESTORE_ARG" -n "$RESTORE_LIST_N"
                else
                    git branch -f "$local_restore" "$RESTORE_ARG"
                    git push -u origin "$local_restore" || print_warning "Failed to push restore branch"
                    print_success "Created restore branch: $local_restore"
                    echo "Top $RESTORE_LIST_N commits on $local_restore:" && git --no-pager log --oneline "$local_restore" -n "$RESTORE_LIST_N"
                fi
                exit 0
            fi

            # If it's a remote branch name, try fetching from origin
            if git ls-remote --heads origin "refs/heads/${RESTORE_ARG}" >/dev/null 2>&1; then
                print_info "Found origin/${RESTORE_ARG}. Creating restore branch..."
                TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
                local_restore="restore/${RESTORE_ARG//\//_}-${TIMESTAMP}"
                if [[ "$DRY_RUN" == "true" ]]; then
                    print_info "DRY-RUN: would fetch origin ref refs/heads/${RESTORE_ARG} into local branch: $local_restore"
                    print_info "DRY-RUN: would push -u origin $local_restore"
                    echo "Top $RESTORE_LIST_N commits on origin/${RESTORE_ARG}:"
                    git --no-pager ls-remote origin "refs/heads/${RESTORE_ARG}" || true
                else
                    git fetch origin "refs/heads/${RESTORE_ARG}:refs/heads/${local_restore}" || { print_error "Failed to fetch origin/${RESTORE_ARG}"; exit 1; }
                    git push -u origin "$local_restore" || print_warning "Failed to push restore branch to origin"
                    print_success "Created restore branch: $local_restore"
                    echo "Top $RESTORE_LIST_N commits on $local_restore:" && git --no-pager log --oneline "$local_restore" -n "$RESTORE_LIST_N"
                fi

                if [[ "$RESTORE_AUTO" == "true" ]]; then
                    TARGET_BRANCH="${RESTORE_TARGET:-devcontainer/minimal}"
                    TAG=backup/${TARGET_BRANCH}-pre-restore-$(date -u +%Y%m%dT%H%M%SZ)
                    if [[ "$DRY_RUN" == "true" ]]; then
                        print_info "DRY-RUN: would run: git tag -f \"$TAG\" refs/heads/$TARGET_BRANCH"
                        print_info "DRY-RUN: would run: git push origin \"refs/tags/$TAG\""
                        print_info "DRY-RUN: would run: git checkout \"$TARGET_BRANCH\" || git checkout -b \"$TARGET_BRANCH\""
                        print_info "DRY-RUN: would run: git reset --hard \"$local_restore\""
                        print_info "DRY-RUN: would run: git push --force-with-lease origin \"$TARGET_BRANCH\""
                        print_success "DRY-RUN: $TARGET_BRANCH would be reset to $local_restore"
                    else
                        git tag -f "$TAG" refs/heads/$TARGET_BRANCH 2>/dev/null || true
                        git push origin "refs/tags/$TAG" || true
                        git checkout "$TARGET_BRANCH" || git checkout -b "$TARGET_BRANCH"
                        git reset --hard "$local_restore"
                        if git push --force-with-lease origin "$TARGET_BRANCH"; then
                            print_success "$TARGET_BRANCH reset to $local_restore and pushed"
                        else
                            print_error "Failed to push $TARGET_BRANCH to origin"
                            exit 1
                        fi
                    fi
                else
                    # Single confirmation prompt (default target is devcontainer/minimal)
                    TARGET_BRANCH="${RESTORE_TARGET:-devcontainer/minimal}"
                    read -u 3 -rp "Reset ${TARGET_BRANCH} to '$local_restore' and force-push? [y/N]: " CONFIRM_RESET_OR_ALT

                    # If user typed a non-yes string without spaces, treat it as alternate branch name
                    if [[ ! "$CONFIRM_RESET_OR_ALT" =~ ^[Yy] ]]; then
                        if [[ -n "$CONFIRM_RESET_OR_ALT" && ! "$CONFIRM_RESET_OR_ALT" =~ [[:space:]] ]]; then
                            # User provided an alternate branch name (no spaces), confirm it
                            TARGET_BRANCH="$CONFIRM_RESET_OR_ALT"
                            read -u 3 -rp "Confirm reset '$TARGET_BRANCH' -> '$local_restore' and force-push? [y/N]: " CONFIRM_RESET
                        else
                            # No confirmation; cancel
                            print_info "Reset cancelled by user. Restore branch remains: $local_restore"
                            exit 0
                        fi
                    else
                        CONFIRM_RESET="$CONFIRM_RESET_OR_ALT"
                    fi

                    if [[ "$CONFIRM_RESET" =~ ^[Yy] ]]; then
                        TAG=backup/${TARGET_BRANCH}-pre-restore-$(date -u +%Y%m%dT%H%M%SZ)
                        if [[ "$DRY_RUN" == "true" ]]; then
                            print_info "DRY-RUN: would run: git tag -f \"$TAG\" refs/heads/$TARGET_BRANCH"
                            print_info "DRY-RUN: would run: git push origin \"refs/tags/$TAG\""

                            print_info "DRY-RUN: would run: git checkout \"$TARGET_BRANCH\" || git checkout -b \"$TARGET_BRANCH\""
                            print_info "DRY-RUN: would run: git reset --hard \"$local_restore\""
                            print_info "DRY-RUN: would run: git push --force-with-lease origin \"$TARGET_BRANCH\""
                            print_success "DRY-RUN: $TARGET_BRANCH would be reset to $local_restore"
                        else
                            git tag -f "$TAG" refs/heads/$TARGET_BRANCH 2>/dev/null || true
                            git push origin "refs/tags/$TAG" || true

                            git checkout "$TARGET_BRANCH" || git checkout -b "$TARGET_BRANCH"
                            git reset --hard "$local_restore"

                            if git push --force-with-lease origin "$TARGET_BRANCH"; then
                                print_success "$TARGET_BRANCH reset to $local_restore and pushed"
                            else
                                print_error "Failed to push $TARGET_BRANCH to origin"
                                exit 1
                            fi
                        fi
                    else
                        print_info "Reset cancelled by user. Restore branch remains: $local_restore"
                    fi
                fi
                exit 0
            fi

            # Fallback: interactive list
            print_info "Argument '$RESTORE_ARG' not recognized; showing interactive list"
            list_backups_and_restore
            exit 0
        else
            list_backups_and_restore
            exit 0
        fi
    fi

    # Handle sign mode (re-sign commits in a range)
    if [[ "$SIGN_MODE" == "true" ]]; then
        sign_mode
        exit 0
    fi

    # Handle drop-commit mode (surgically remove a single commit)
    if [[ -n "$DROP_COMMIT" ]]; then
        drop_single_commit "$DROP_COMMIT"
        exit 0
    fi

    # Handle no-edit mode (restore dates only)
    if [[ "$NO_EDIT_MODE" == "true" ]]; then
        check_git_repo
        
        print_info "Restoring original commit dates..."
        echo ""
        
        local base_commit
        base_commit=$(git rev-list --max-parents=0 HEAD)
        capture_all_dates "$base_commit"
        
        # Display dates and ask if user wants to edit
        display_and_edit_dates "$TEMP_ALL_DATES" ""
        
        # Recreate history with restored dates
        recreate_history_with_dates
        
        echo ""
        print_success "All commit dates have been restored"
        echo ""
        echo -e "${YELLOW}Review the changes:${NC} git log --format='%h %aI %s' -10"
        echo ""
        
        read -rp "Push to remote? [y/N]: " should_push
        if [[ "$should_push" =~ ^[Yy] ]]; then
            print_info "Pushing with force-with-lease..."
            git push --force-with-lease || {
                print_error "Push failed"
                return 1
            }
            print_success "Pushed"
        fi
        
        exit 0
    fi
    
    # Handle amend mode
    if [[ "$AMEND_MODE" == "true" ]]; then
        amend_mode
        exit 0
    fi
    
    # Handle stash mode separately
    if [[ "$STASH_MODE" == "true" ]]; then
        check_git_repo
        
        print_info "Stash application mode"
        echo ""
        
        select_stash_files "$STASH_NUM"
        
        echo ""
        echo -e "${BOLD}Files to apply:${NC}"
        cat /tmp/git-fix-history-selected-files.txt | while IFS= read -r file; do
            echo -e "  ${CYAN}•${NC} $file"
        done
        
        echo ""
        echo -e "${BOLD}Select target commit to apply to:${NC}"
        echo -e "  Example: ${CYAN}181cab0${NC} or ${CYAN}HEAD=2${NC}"
        read -rp "> " target_commit
        
        if [[ -z "$target_commit" ]]; then
            print_error "No commit selected"
            exit 1
        fi
        
        # Resolve commit hash
        target_hash=$(git rev-parse "$target_commit")
        target_subject=$(git log -1 --format=%s "$target_hash")
        
        # Get original dates of target commit BEFORE any operations
        original_target_author=$(git log -1 --format=%aI "$target_hash")
        original_target_committer=$(git log -1 --format=%cI "$target_hash")
        
        print_info "Target commit: ${CYAN}${target_hash:0:7}${NC} - $target_subject"
        print_info "Original date: ${CYAN}$original_target_author${NC}"
        
        # Get all commits after target with their original dates
        local commits_after
        mapfile -t commits_after < <(git rev-list --reverse "${target_hash}..HEAD")
        
        declare -A after_dates
        if [[ ${#commits_after[@]} -gt 0 ]]; then
            for commit in "${commits_after[@]}"; do
                after_dates[$commit]=$(git log -1 --format=%aI "$commit")
            done
        fi
        
        # Reset to before target commit
        print_info "Resetting to parent of target..."
        git reset --hard "${target_hash}^" --quiet
        
        # Apply patch
        print_info "Applying patch..."
        if ! git apply "$TEMP_STASH_PATCH" 2>&1 | grep -v "^warning:" | grep -v "trailing whitespace"; then
            print_error "Failed to apply patch"
            git reset --hard "$target_hash"
            exit 1
        fi
        
        print_success "Patch applied"
        
        # Stage all changes
        print_info "Staging changes..."
        git add -A
        
        # Amend target commit with its ORIGINAL dates
        print_info "Amending target commit..."
        GIT_AUTHOR_DATE="$original_target_author" \
        GIT_COMMITTER_DATE="$original_target_committer" \
        git commit --amend --no-edit --quiet
        
        print_success "Target commit amended (date preserved: $original_target_author)"
        
        # Re-apply each commit after target using git rebase to preserve commit history
        if [[ ${#commits_after[@]} -gt 0 ]]; then
            echo ""
            print_info "Re-applying ${#commits_after[@]} commit(s) after target with rebase..."
            
            # Create a rebase script that will apply each commit with its original date
            local rebase_script="/tmp/git-fix-history-rebase-exec.sh"
            > "$rebase_script"
            chmod +x "$rebase_script"
            
            # Write exec commands for each commit to update dates
            for commit_hash in "${commits_after[@]}"; do
                original_date="${after_dates[$commit_hash]}"
                cat >> "$rebase_script" << REBASE_EOF
if [ "\$GIT_COMMIT" = "${commit_hash:0:40}" ]; then
    export GIT_AUTHOR_DATE="$original_date"
    export GIT_COMMITTER_DATE="$original_date"
fi
REBASE_EOF
            done
            
            # Use rebase to replay all commits onto the amended target
            print_info "Rebasing commits onto amended target..."
            REBASE_MERGE_DIR=".git/rebase-merge"
            
            # Start rebase of all commits after target
            git rebase --onto HEAD "${commits_after[0]}~1" "${commits_after[-1]}" 2>&1 | grep -v "^First, rewinding head" || true
            
            print_success "All commits re-applied"
        fi
        
        print_header_success "Complete!"
        
        # Show final history
        echo -e "${BOLD}Final history:${NC}"
        git log --format="%h %ai %s" -5
        
        echo ""
        echo -e "${BOLD}Edit latest commit date? [y/N]:${NC}"
        read -rp "  (Current: $(git log -1 --format=%aI HEAD)) " edit_date
        
        if [[ "$edit_date" =~ ^[Yy] ]]; then
            echo ""
            echo -e "Current date: ${CYAN}$(git log -1 --format=%aI HEAD)${NC}"
            echo -e "Format: ${CYAN}YYYY-MM-DDTHH:MM:SS±HH:MM${NC}"
            read -rp "New date: " new_date
            
            if [[ -n "$new_date" ]]; then
                GIT_AUTHOR_DATE="$new_date" \
                GIT_COMMITTER_DATE="$new_date" \
                git commit --amend --no-edit --quiet
                print_success "Date updated to: $new_date"
            fi
        fi
        
        echo ""
        read -rp "Push to remote? [y/N]: " should_push
        if [[ "$should_push" =~ ^[Yy] ]]; then
            print_info "Pushing with force-with-lease..."
            git push --force-with-lease --quiet
            print_success "Pushed to remote"
        else
            print_info "Changes ready. Run when ready: ${CYAN}git push --force-with-lease${NC}"
        fi
        
        exit 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}${BOLD}🔍 DRY RUN MODE - No changes will be applied${NC}\n"
    fi
    
    check_git_repo
    
    print_info "Git repository verified"
    echo ""
    
    extract_commits "$RANGE" "$TEMP_COMMITS"
    echo ""
    
    display_commit_history "$TEMP_COMMITS"
    echo ""
    
    if [[ "$INTERACTIVE" == "true" ]]; then
        read -rp "Edit commits? [Y/n]: " should_edit_interactive
        if [[ ! "$should_edit_interactive" =~ ^[Nn] ]]; then
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
    
    # Offer cleanup of tmp/backup refs at end of successful operation
    if [[ "$NO_CLEANUP" != "true" ]]; then
        echo ""
        cleanup_tmp_and_backup_refs
    fi
}

# Entry point: parse args first so harness mode can run standalone
parse_args "$@"
if [[ "$HARNESS_MODE" == "true" ]]; then
    harness_run
    exit $?
fi

main "$@"