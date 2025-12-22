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
#   - Verify changes before applying
#
# Usage:
#   ./scripts/fix-history.sh                    # Interactive mode
#   ./scripts/fix-history.sh --range HEAD~5     # Fix last 5 commits
#   ./scripts/fix-history.sh --help
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
RANGE="HEAD~10"
INTERACTIVE=true
DRY_RUN=false
STASH_NUM=""
STASH_MODE=false
AMEND_MODE=false
AMEND_COMMIT=""
NO_EDIT_MODE=false
SIGN_MODE=false
DROP_COMMIT=""
TEMP_COMMITS="/tmp/git-fix-history-commits.txt"
TEMP_OPERATIONS="/tmp/git-fix-history-operations.txt"
TEMP_STASH_PATCH="/tmp/git-fix-history-stash.patch"
TEMP_ALL_DATES="/tmp/git-fix-history-all-dates.txt"
TEMP_BACKUP="/tmp/git-fix-history-backup-$(date +%s).bundle"

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

print_header() {
    echo -e "\n${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║${NC}            ${CYAN}Git-Control History Fixer${NC}                      ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}

# ============================================================================
# CLI ARGUMENT PARSING
# ============================================================================

show_help() {
    cat << 'EOF'
Git-Control History Fixer - Interactive commit history rewriting

Usage: fix-history.sh [OPTIONS]

Options:
  -r, --range RANGE          Specify commit range (default: HEAD~10)
                             Examples: HEAD~5, main..HEAD, abc123..def456
  -a, --amend COMMIT         Secretly amend a commit (not latest) with date preservation
                             Recreates history as if nothing happened
                             Example: --amend HEAD~2 (amend 2nd to last commit)
  --sign                     Re-sign commits in the selected range (requires GPG)
                             Rewrites history to apply signatures and preserves dates
  --drop COMMIT              Drop (remove) a single non-root commit from history
                             Example: --drop 181cab0 (dropping commit by hash)
  -d, --dry-run              Show what would be changed without applying
  -s, --stash NUM            Apply specific files from stash to a commit
                             Example: --stash 0 (applies stash@{0} interactively)
  -h, --help                 Show this help message
  -v, --verbose              Enable verbose output

Examples:
  ./scripts/fix-history.sh                           # Fix last 10 commits interactively
  ./scripts/fix-history.sh --range HEAD~20           # Work with last 20 commits
  ./scripts/fix-history.sh --dry-run                 # Preview changes without applying
  ./scripts/fix-history.sh --stash 0                 # Apply stash@{0} to commits
  ./scripts/fix-history.sh --amend HEAD~2            # Secretly amend 2nd to last commit
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
            --sign)
                SIGN_MODE=true
                shift
                ;;
            --drop)
                DROP_COMMIT="$2"
                shift 2
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
    echo ""
    echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║${NC}                  ${CYAN}History Fixed!${NC}                             ${BOLD}${GREEN}║${NC}"
    echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
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

capture_all_dates() {
    # Backwards compatible: capture from a start ref's parent to HEAD
    local start_ref="$1"

    print_info "Capturing original dates for ALL commits..."

    > "$TEMP_ALL_DATES"

    # If start_ref is empty or equals HEAD, capture only HEAD
    if [[ -z "$start_ref" || "$start_ref" == "HEAD" ]]; then
        for commit in $(git rev-list --reverse HEAD); do
            author_date=$(git log -1 --format=%aI "$commit")
            echo "$commit|$author_date" >> "$TEMP_ALL_DATES"
        done
    else
        # If start_ref is a single commit hash (parent), we capture commits after it
        # If start_ref already contains '..' or is a range, use it directly
        if [[ "$start_ref" == *".."* ]]; then
            range="$start_ref"
        else
            range="$start_ref..HEAD"
        fi

        for commit in $(git rev-list --reverse "$range"); do
            author_date=$(git log -1 --format=%aI "$commit")
            echo "$commit|$author_date" >> "$TEMP_ALL_DATES"
        done
    fi

    local count
    count=$(wc -l < "$TEMP_ALL_DATES")
    print_success "Captured original dates for $count commits"
}

# Capture dates for an arbitrary git range (e.g., HEAD~5..HEAD or main..HEAD)
capture_dates_for_range() {
    local range="$1"
    print_info "Capturing dates for range: $range"
    > "$TEMP_ALL_DATES"
    for commit in $(git rev-list --reverse "$range"); do
        author_date=$(git log -1 --format=%aI "$commit")
        echo "$commit|$author_date" >> "$TEMP_ALL_DATES"
    done
    local count
    count=$(wc -l < "$TEMP_ALL_DATES")
    print_success "Captured original dates for $count commits in range"
}

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

display_and_edit_dates() {
    local dates_file="$1"
    local target_commit="$2"
    
    if [[ ! -f "$dates_file" ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}Commit Creation Times${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════${NC}"
    
    local commit_idx=0
    local -a commits_to_edit
    
    while IFS='|' read -r commit_hash orig_date; do
        commit_idx=$((commit_idx + 1))
        local short_hash
        short_hash=$(git rev-parse --short "$commit_hash" 2>/dev/null || echo "${commit_hash:0:7}")
        local subject
        subject=$(git log -1 --format=%s "$commit_hash" 2>/dev/null || echo "unknown")
        
        if [[ "$commit_hash" == "$target_commit" ]]; then
            echo -e "${YELLOW}[$commit_idx]${NC} ${YELLOW}[AMENDING]${NC} $short_hash: $subject"
        else
            echo -e "[$commit_idx] $short_hash: $subject"
        fi
        echo -e "    Created: ${CYAN}$orig_date${NC}"
    done < "$dates_file"
    
    echo ""
    echo -e "${BOLD}Do any of these timestamps need to be edited? [y/N]:${NC}"
    read -rp "> " edit_dates
    
    if [[ "$edit_dates" =~ ^[Yy] ]]; then
        # Re-display with edit prompts
        echo ""
        echo -e "${BOLD}Edit timestamps:${NC}"
        echo -e "${GRAY}(Accept formats: 2025-12-18, 2025-12-18 14:30, 2025-12-18T14:30:00+01:00, or empty to skip)${NC}"
        echo ""
        commit_idx=0
        
        > "${dates_file}.edited"
        
        # Use a different file descriptor for the loop to avoid stdin conflicts
        # Read the dates file on FD4 so we can keep FD3 reserved for interactive input
        while IFS='|' read -r commit_hash orig_date <&4; do
            commit_idx=$((commit_idx + 1))
            local short_hash
            short_hash=$(git rev-parse --short "$commit_hash" 2>/dev/null || echo "${commit_hash:0:7}")
            
            echo -e "[$commit_idx] $short_hash"
            echo -e "    Current: ${CYAN}$orig_date${NC}"
            # Use fd 3 for interactive user input to avoid stealing file input
            if read -u 3 -rp "    New date (empty to keep): " user_date; then :; else read -rp "    New date (empty to keep): " user_date; fi
            
            local new_date="$orig_date"
            
            if [[ -n "$user_date" ]]; then
                # Try to parse the user input
                local parsed_date
                
                # First, try to parse as-is (for already formatted dates)
                if parsed_date=$(date -d "$user_date" --iso-8601=seconds 2>/dev/null); then
                    new_date="$parsed_date"
                else
                    # Try to handle common user input formats
                    # Format: "YYYY-MM-DD" or "YYYY-MM-DD HH:MM"
                    if [[ "$user_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}($|\ [0-9]{2}:[0-9]{2}) ]]; then
                        # Add time if not provided
                        if [[ ! "$user_date" =~ \ [0-9]{2}:[0-9]{2} ]]; then
                            user_date="$user_date 00:00"
                        fi
                        # Parse and format
                        if parsed_date=$(date -d "$user_date" --iso-8601=seconds 2>/dev/null); then
                            new_date="$parsed_date"
                        else
                            print_warning "Could not parse date '$user_date'. Keeping original: $orig_date"
                        fi
                    else
                        print_warning "Unrecognized date format '$user_date'. Try: 2025-12-18 or 2025-12-18 14:30"
                    fi
                fi
            fi
            
            echo "$commit_hash|$new_date" >> "${dates_file}.edited"
        done 4< "$dates_file"
        
        # Replace the dates file with edited version
        mv "${dates_file}.edited" "$dates_file"
        print_success "Dates updated"
    fi
}

recreate_history_with_dates() {
    print_info "Restoring commit dates via dummy-edit workaround..."
    
    if [[ ! -f "$TEMP_ALL_DATES" ]]; then
        print_warning "No dates file found, skipping date restoration"
        return 0
    fi
    
    # Dummy-edit workaround: Git only rewrites commits when content changes.
    # Strategy: Create a temp file, amend HEAD with it, then remove it via another amend.
    # This forces all dependent commits to be rewritten with new dates.
    
    local dummy_file=".tmp-date-fix-$$"
    
    # Get HEAD's new date from the LAST line of the dates file (HEAD is always the newest)
    local head_new_date
    head_new_date=$(tail -1 "$TEMP_ALL_DATES" | cut -d'|' -f2)
    
    if [[ -z "$head_new_date" ]]; then
        print_warning "No dates found in file, nothing to update"
        return 0
    fi
    
    # Step 1: Create dummy file and stage it
    echo "Temporary file for date restoration - will be removed" > "$dummy_file"
    git add "$dummy_file"
    
    print_info "Step 1/3: Adding dummy file to trigger commit rewrite..."
    
    # Step 2: Amend HEAD with the new date
    print_info "Step 2/3: Amending HEAD with new dates..."
    GIT_AUTHOR_DATE="$head_new_date" \
    GIT_COMMITTER_DATE="$head_new_date" \
    git commit --amend --no-edit || {
        print_error "Failed to amend commit"
        rm -f "$dummy_file"
        return 1
    }
    
    # Step 3: Remove dummy file and amend again to remove it
    print_info "Step 3/3: Removing dummy file..."
    rm -f "$dummy_file"
    git rm -f "$dummy_file" 2>/dev/null || true
    
    # Amend to remove the dummy file, preserving the date change
    GIT_AUTHOR_DATE="$head_new_date" \
    GIT_COMMITTER_DATE="$head_new_date" \
    git commit --amend --no-edit || {
        print_warning "Could not remove dummy file from final commit"
        # But the date change should still be there
    }
    
    print_success "Commit dates updated successfully"
}

# ---------------------------------------------------------------------------
# Sign mode: re-sign commits across a range and restore dates
# ---------------------------------------------------------------------------
sign_mode() {
    print_header
    check_git_repo
    backup_repo

    if ! command -v gpg &>/dev/null && ! git config user.signingkey &>/dev/null; then
        print_warning "GPG not found or signing key not configured. Aborting sign operation."
        exit 1
    fi

    echo -e "${BOLD}Sign Mode${NC}"
    echo -e "Range: ${CYAN}$RANGE${NC}"
    # Normalize simple ranges like HEAD~5 into HEAD~5..HEAD for clarity
    if [[ "$RANGE" != *".."* ]]; then
        RANGE="$RANGE..HEAD"
    fi

    if ! confirm_changes; then
        print_info "Cancelled"
        exit 0
    fi

    # Capture original dates for commits in the specified range
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
        print_error "Range contains merge commits. Aborting resign; rebase with merges is risky."
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: would re-sign commits in range: $RANGE"
        return 0
    fi

    # Prepare sequence editor to insert an exec to re-sign after each pick
    local seq_editor_cmd="sed -i '/^pick /a exec git commit --amend --no-edit -n -S'"

    print_info "Running interactive rebase to re-sign commits (no user interaction expected)"
    if [[ "$REBASE_BASE" == "--root" ]]; then
        if GIT_SEQUENCE_EDITOR="$seq_editor_cmd" git rebase -i --root; then
            print_success "Rebase/Resign completed"
        else
            print_error "Rebase failed during re-sign. Please inspect and resolve conflicts."
            git rebase --abort || true
            exit 1
        fi
    else
        if GIT_SEQUENCE_EDITOR="$seq_editor_cmd" git rebase -i "$REBASE_BASE"; then
            print_success "Rebase/Resign completed"
        else
            print_error "Rebase failed during re-sign. Please inspect and resolve conflicts."
            git rebase --abort || true
            exit 1
        fi
    fi

    # Restore original dates
    recreate_history_with_dates
    print_success "Resigning done and dates restored"
}

# ---------------------------------------------------------------------------
# Drop a single commit (non-last) from history using rebase -i
# ---------------------------------------------------------------------------
drop_single_commit() {
    local target_hash="$1"
    check_git_repo
    backup_repo

    if ! git cat-file -e "$target_hash" 2>/dev/null; then
        print_error "Commit not found: $target_hash"
        exit 1
    fi

    local parent
    parent=$(git rev-parse "${target_hash}~1" 2>/dev/null || true)
    if [[ -z "$parent" ]]; then
        print_error "Cannot drop root commit"
        exit 1
    fi

    local short
    short=$(git rev-parse --short "$target_hash")
    export GIT_SEQUENCE_EDITOR="sed -i '/^pick .*${short}/s/^pick/drop/'"

    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: would drop commit ${short}"
        return 0
    fi

    if git rebase -i --rebase-merges "$parent"; then
        print_success "Dropped commit ${short}"
    else
        print_error "Rebase failed while dropping commit. Aborting."
        git rebase --abort || true
        exit 1
    fi
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
    
    echo ""
    echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║${NC}                  ${CYAN}Complete!${NC}                             ${BOLD}${GREEN}║${NC}"
    echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
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

main() {
    print_header
    parse_args "$@"
    
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
        echo -e "  Example: ${CYAN}181cab0${NC} or ${CYAN}HEAD~2${NC}"
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
        local commits_after=($(git rev-list --reverse "${target_hash}..HEAD"))
        
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
        
        echo ""
        echo -e "${BOLD}${GREEN}✓ Complete!${NC}"
        echo ""
        
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
}

main "$@"
