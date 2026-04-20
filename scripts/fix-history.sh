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
source "$SCRIPT_DIR/lib/colours.sh"
source "$SCRIPT_DIR/lib/print.sh"
source "$SCRIPT_DIR/lib/git/cleanup.sh"
source "$SCRIPT_DIR/lib/git/worktree.sh"
source "$SCRIPT_DIR/lib/git/dates.sh"
source "$SCRIPT_DIR/lib/git/topology.sh"
source "$SCRIPT_DIR/lib/git/harness.sh"
source "$SCRIPT_DIR/lib/git/rewrite.sh"
source "$SCRIPT_DIR/lib/git/reconstruct.sh"
source "$SCRIPT_DIR/lib/git/amend.sh"
source "$SCRIPT_DIR/lib/git/sign.sh"
source "$SCRIPT_DIR/lib/git/drop.sh"
source "$SCRIPT_DIR/lib/git/restore.sh"
source "$SCRIPT_DIR/lib/git/blossom.sh"

# Configuration
RANGE="HEAD=10"
INTERACTIVE=true
DRY_RUN=false
STASH_NUM=""
STASH_MODE=false
AMEND_MODE=false
AMEND_COMMIT=""
# Blossom mode: surgical amend of a non-tip commit via interactive rebase,
# preserving later commits.  Optional COMMIT may be supplied via --blossom <commit>;
# if omitted, the user is prompted.
BLOSSOM_MODE=false
BLOSSOM_COMMIT=""
NO_EDIT_MODE=false
NO_CLEANUP=false
CLEANUP_ONLY=false
SIGN_MODE=false
TIMED_SIGN_MODE=false  # Space out PR signing by minute boundaries
RESIGN_MODE=false       # Force re-sign even if already signed
AUTO_SIGN_MODE=false    # Auto-sign: detect unsigned commits, confirm, then auto-configure flags
REAUTHOR_MODE=false
REAUTHOR_TARGET=""
DROP_COMMIT=""
# Auto-resolve strategy: empty|ours|theirs
# Can be set via environment (AUTO_RESOLVE=ours|theirs|OURS|THEIRS) or via --auto-resolve <mode|=mode>
AUTO_RESOLVE="${AUTO_RESOLVE:-}"
AUTO_RESOLVE="${AUTO_RESOLVE,,}"  # normalise to lowercase
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
# Accepts: --auto-resolve <ours|theirs>  OR  --auto-resolve=<ours|theirs>  (case-insensitive)
ARGS=("$@")
for ((i=0;i<${#ARGS[@]};i++)); do
    _arg="${ARGS[$i]}"
    if [[ "$_arg" == "--auto-resolve" ]]; then
        if [[ $((i+1)) -lt ${#ARGS[@]} ]]; then
            AUTO_RESOLVE="${ARGS[$((i+1))],,}"
            if [[ "$AUTO_RESOLVE" != "ours" && "$AUTO_RESOLVE" != "theirs" ]]; then
                echo "[WARNING] Invalid value for --auto-resolve: $AUTO_RESOLVE (allowed: ours|theirs). Ignoring." >&2
                AUTO_RESOLVE=""
            else
                echo "[INFO] Auto-resolve strategy set to: $AUTO_RESOLVE" >&2
            fi
        fi
    elif [[ "$_arg" == --auto-resolve=* ]]; then
        AUTO_RESOLVE="${_arg#--auto-resolve=}"
        AUTO_RESOLVE="${AUTO_RESOLVE,,}"
        if [[ "$AUTO_RESOLVE" != "ours" && "$AUTO_RESOLVE" != "theirs" ]]; then
            echo "[WARNING] Invalid value for --auto-resolve: $AUTO_RESOLVE (allowed: ours|theirs). Ignoring." >&2
            AUTO_RESOLVE=""
        else
            echo "[INFO] Auto-resolve strategy set to: $AUTO_RESOLVE" >&2
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
      --blossom [COMMIT]     Surgical amend of a non-tip commit, preserving later commits
                             Drives `git rebase -i <commit>^` with auto-edit setup, offers
                             interactive sub-actions (edit message, sed/regex file replace,
                             arbitrary shell), cleans stale CHERRY_PICK_HEAD, runs
                             `git commit --amend` then `git rebase --continue`, and finally
                             prompts for `git push --force-with-lease`.  On any failure,
                             offers `git rebase --abort` to return to the pre-rebase HEAD.
                             Example: --blossom abc1234
  --sign                     Re-sign commits in the selected range (requires GPG)
                             Rewrites history to apply signatures and preserves dates
                             Automatically force-pushes to remote after signing (atomic)
    --resign                   Force re-sign commits even if already signed (use with --sign)
    --auto-sign                Detect unverified commits and auto-configure secure signing
                               (Automatically sets: --sign, PRESERVE_TOPOLOGY, AUTO_RESOLVE=ours, NO_EDIT_MODE)
                               Prompts for confirmation before proceeding
    --reauthor <commit|range>  Reset author to current git user for a commit or range
                                                         If a single commit is provided, rewrites from that commit to HEAD
  --atomic-preserve          Deterministic preserve: recreate commits (including merges) with
                             `git commit-tree`, immediately sign and set author/committer dates (atomic)
  --drop COMMIT              Drop (remove) a single non-root commit from history
                             Example: --drop 181cab0 (dropping commit by hash)

  --harness-drop <commit>    Run a minimal harness that drops a commit in a temporary branch,
                             creates a backup bundle and performs post-checks (safe wrapper)
  --harness-sign <range>     Run a minimal harness that re-signs commits in a range (requires GPG)
                             (Honours global ${CYAN}--dry-run${NC} flag)
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
                             (Creates a restore branch and optionally resets the target branch) ${CYAN}(Honours global --dry-run flag)${NC}

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
  ./scripts/fix-history.sh --blossom abc1234         # Surgical amend of non-tip commit (preserves later commits)
  ./scripts/fix-history.sh --blossom                 # Same, but prompts for the target commit
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
            --blossom)
                BLOSSOM_MODE=true
                # Optional positional argument; if next token is not a flag, take it
                if [[ -n "$2" && "$2" != -* ]]; then
                    BLOSSOM_COMMIT="$2"
                    shift 2
                else
                    BLOSSOM_COMMIT=""
                    shift
                fi
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
            --auto-sign)
                AUTO_SIGN_MODE=true
                shift
                ;;
            --resign)
                RESIGN_MODE=true
                SIGN_MODE=true
                shift
                ;;
            --reauthor)
                REAUTHOR_MODE=true
                REAUTHOR_TARGET="$2"
                shift 2
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
                AUTO_RESOLVE="${2,,}"
                if [[ "$AUTO_RESOLVE" != "ours" && "$AUTO_RESOLVE" != "theirs" ]]; then
                    print_error "Invalid value for --auto-resolve: $2 (allowed: ours|theirs)"
                    exit 1
                fi
                shift 2
                ;;
            --auto-resolve=*)
                AUTO_RESOLVE="${1#--auto-resolve=}"
                AUTO_RESOLVE="${AUTO_RESOLVE,,}"
                if [[ "$AUTO_RESOLVE" != "ours" && "$AUTO_RESOLVE" != "theirs" ]]; then
                    print_error "Invalid value for --auto-resolve: ${1#--auto-resolve=} (allowed: ours|theirs)"
                    exit 1
                fi
                shift
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
    local skip_uncommitted_check="${1:-false}"
    
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Not a git repository."
        exit 1
    fi
    
    # Skip uncommitted changes check if requested (e.g., for cleanup-only mode)
    if [[ "$skip_uncommitted_check" == "true" ]]; then
        return 0
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
    echo -e "  After applying, will automatically:"
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
# Amend functions moved to lib/git/amend.sh:
#   backup_repo(), amend_single_commit(), amend_mode()
# Date-restore + reconstruction moved to lib/git/reconstruct.sh:
#   recreate_history_with_dates(), try_reconstruct_with_strategies(),
#   show_reconstruction_state(), prompt_override_same_branch(),
#   reconstruct_history_without_commit()

# ---------------------------------------------------------------------------
# Note: sign_preserved_topology_branch() and atomic_preserve_range_to_branch()
# moved to lib/git/topology.sh

# apply_dates_from_preserve_map() moved to lib/git/dates.sh

# ---------------------------------------------------------------------------
# Drop a single commit (non-last) from history using rebase -i
# ---------------------------------------------------------------------------

# Conflict resolution functions moved to lib/git/rewrite.sh:
#   auto_add_conflicted_files(), auto_resolve_all_conflicts()

# Drop / push moved to lib/git/drop.sh:
#   prompt_and_push_branch(), drop_single_commit()


# ---------------------------------------------------------------------------
# Harness functions moved to lib/git/harness.sh:
#   harness_post_checks(), harness_finish_success(), harness_restore_backup(), harness_run()
# ---------------------------------------------------------------------------

# Restore moved to lib/git/restore.sh:
#   list_restore_candidates(), restore_candidate(), list_backups_and_restore()

# harness_run() moved to lib/git/harness.sh
# blossom_mode() and helpers moved to lib/git/blossom.sh


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
        check_git_repo true  # Skip uncommitted changes check - not needed for cleanup
        cleanup_tmp_and_backup_refs
        exit 0
    fi

    # Normalise RANGE syntax EARLY: support 'HEAD=all' and 'HEAD=N' forms
    # This must happen before any function (like sign_mode) uses RANGE
    if [[ -n "$RANGE" ]]; then
        # If user used HEAD=all or HEAD~all (case-insensitive), map to full history
        if [[ "${RANGE,,}" =~ ^head[=~]all$ ]]; then
            ROOT_COMMIT=$(git rev-list --max-parents=0 HEAD 2>/dev/null || true)
            if [[ -n "$ROOT_COMMIT" ]]; then
                RANGE="$ROOT_COMMIT..HEAD"
                print_info "Normalised RANGE to full history: $RANGE"
            fi
        else
            # Convert HEAD=N (digits) to HEAD~N to preserve existing behaviour
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
            print_info "Argument '$RESTORE_ARG' not recognised; showing interactive list"
            list_backups_and_restore
            exit 0
        else
            list_backups_and_restore
            exit 0
        fi
    fi

    # Handle auto-sign mode (detect unsigned commits and auto-configure)
    if [[ "$AUTO_SIGN_MODE" == "true" ]]; then
        auto_sign_detect
        # After auto_sign_detect returns, SIGN_MODE is set to true
        # Fall through to sign_mode below
    fi

    # Handle sign mode (re-sign commits in a range)
    if [[ "$SIGN_MODE" == "true" || "$REAUTHOR_MODE" == "true" ]]; then
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

    # Handle blossom mode (surgical non-tip amend via interactive rebase)
    if [[ "$BLOSSOM_MODE" == "true" ]]; then
        blossom_mode
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
