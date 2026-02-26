#!/usr/bin/env bash
#
# Dev-Control Shared Library: Git Date Utilities
# Functions for capturing and restoring commit dates during history rewriting
#
# Usage:
#   source "${SCRIPT_DIR}/lib/git/dates.sh"
#
# Required globals (set by caller before using these functions):
#   TEMP_ALL_DATES    - Path to temp file for storing date data
#   DRY_RUN           - If "true", skip destructive operations
#
# Optional globals (for advanced restoration):
#   PRESERVE_TOPOLOGY - If "true", use topology-aware date restoration
#   LAST_PRESERVE_MAP - Path to preserve map file for topology mode
#   ORIGINAL_BRANCH   - Original branch name before operations
#   RECONSTRUCTION_COMPLETED - Flag to track reconstruction state
#   RECONSTRUCT_TARGET - Target commit for reconstruction fallback
#   ALLOW_OVERRIDE_SAME_BRANCH - Allow automatic branch override
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# Ensure print functions are available (source print.sh before this)
# shellcheck disable=SC2034

# Array to track generated helper scripts for cleanup
GENERATED_HELPERS=()

# ============================================================================
# DATE CAPTURE FUNCTIONS
# ============================================================================

# Capture original dates for all commits from a start ref to HEAD
# Usage: capture_all_dates [start_ref]
# Writes to: $TEMP_ALL_DATES (format: commit_sha|author_date)
capture_all_dates() {
    local start_ref="$1"

    print_info "Capturing original dates for ALL commits..."

    > "$TEMP_ALL_DATES"

    # If start_ref is empty or equals HEAD, capture only HEAD
    if [[ -z "$start_ref" || "$start_ref" == "HEAD" ]]; then
        for commit in $(git rev-list --reverse HEAD); do
            local author_date
            author_date=$(git log -1 --format=%aI "$commit")
            echo "$commit|$author_date" >> "$TEMP_ALL_DATES"
        done
    else
        # If start_ref is a single commit hash (parent), we capture commits after it
        # If start_ref already contains '..' or is a range, use it directly
        local range
        if [[ "$start_ref" == *".."* ]]; then
            range="$start_ref"
        else
            range="$start_ref..HEAD"
        fi

        for commit in $(git rev-list --reverse "$range"); do
            local author_date
            author_date=$(git log -1 --format=%aI "$commit")
            echo "$commit|$author_date" >> "$TEMP_ALL_DATES"
        done
    fi

    local count
    count=$(wc -l < "$TEMP_ALL_DATES")
    print_success "Captured original dates for $count commits"
}

# Capture dates for an arbitrary git range
# Usage: capture_dates_for_range "range" (e.g., "HEAD~5..HEAD" or "main..HEAD")
# Writes to: $TEMP_ALL_DATES (format: commit_sha|author_date)
capture_dates_for_range() {
    local range="$1"
    print_info "Capturing dates for range: $range"
    > "$TEMP_ALL_DATES"
    for commit in $(git rev-list --reverse "$range"); do
        local author_date
        author_date=$(git log -1 --format=%aI "$commit")
        echo "$commit|$author_date" >> "$TEMP_ALL_DATES"
    done
    local count
    count=$(wc -l < "$TEMP_ALL_DATES")
    print_success "Captured original dates for $count commits in range"
}

# Get the date of a specific commit
# Usage: get_commit_date "commit_sha" [format]
# Default format: %aI (ISO 8601)
get_commit_date() {
    local commit="$1"
    local format="${2:-%aI}"
    git log -1 --format="$format" "$commit" 2>/dev/null
}

# Get both author and committer dates
# Usage: get_commit_dates "commit_sha"
# Returns: author_date|committer_date
get_commit_dates() {
    local commit="$1"
    local author_date committer_date
    author_date=$(git log -1 --format=%aI "$commit" 2>/dev/null)
    committer_date=$(git log -1 --format=%cI "$commit" 2>/dev/null)
    echo "${author_date}|${committer_date}"
}

# ============================================================================
# DATE APPLICATION HELPER GENERATION
# ============================================================================

# Generate a helper script for applying dates during rebase
# Usage: helper_path=$(generate_apply_dates_helper_file)
# Returns: Path to generated helper script
generate_apply_dates_helper_file() {
    local ts pid tmpf
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    pid=$$
    tmpf="/tmp/git-fix-apply-dates-${pid}-${ts}.sh"

    cat > "$tmpf" <<'APPLY_DATES_HELPER'
#!/usr/bin/env bash
set -euo pipefail
# Inline generated helper: applies first date line to current commit and verifies signing & date
DATES_FILE="${1:-/tmp/git-fix-history-all-dates.txt}"
if [[ -z "${DATES_FILE}" || ! -s "${DATES_FILE}" ]]; then
  echo "[INFO] Dates file missing or empty: ${DATES_FILE}" >&2
  exit 0
fi

# Read first non-empty line
line=""
while IFS= read -r L; do
  if [[ -n "${L//[[:space:]]/}" ]]; then line="$L"; break; fi
done < "$DATES_FILE"

if [[ -z "$line" ]]; then
  echo "[INFO] No date line to apply in: $DATES_FILE" >&2
  exit 0
fi

if [[ "$line" != *"|"* ]]; then
  echo "[WARN] Malformed date line (no '|'): $line" >&2
  sed -i '1d' "$DATES_FILE" || true
  exit 1
fi

commit_part="${line%%|*}"
date_part="${line#*|}"

if [[ -z "$date_part" ]]; then
  echo "[WARN] No date found in line: $line" >&2
  sed -i '1d' "$DATES_FILE" || true
  exit 1
fi

if ! date -d "$date_part" >/dev/null 2>&1; then
  echo "[ERROR] Unparseable date: $date_part" >&2
  sed -i '1d' "$DATES_FILE" || true
  exit 1
fi

# Amend and sign commit; fail loudly if anything goes wrong
GIT_AUTHOR_DATE="$date_part" GIT_COMMITTER_DATE="$date_part" \
  git commit --amend --no-edit -S >/dev/null 2>&1 || { echo "[ERROR] git commit --amend -S failed" >&2; exit 1; }

sig_status=$(git log -1 --format='%G?' HEAD 2>/dev/null || true)
if [[ "$sig_status" != "G" ]]; then
  echo "[ERROR] Amended commit not properly signed (G required). Status: $sig_status" >&2
  exit 1
fi

existing_epoch=$(git show -s --format=%at HEAD 2>/dev/null || true)
date_epoch=$(date -d "$date_part" +%s 2>/dev/null || true)
if [[ -z "$existing_epoch" || -z "$date_epoch" ]]; then
  echo "[ERROR] Date epoch retrieval failed (expected $date_epoch actual $existing_epoch)" >&2
  exit 1
fi
# Allow large tolerance for timezone/conversion differences and system time skew (seconds)
ALLOWED_EPOCH_DRIFT=86400
diff=$(( existing_epoch - date_epoch ))
if (( diff < 0 )); then diff=$(( -diff )); fi
if (( diff > ALLOWED_EPOCH_DRIFT )); then
  echo "[ERROR] Date mismatch after amend (expected $date_epoch actual $existing_epoch; diff=${diff}s > ${ALLOWED_EPOCH_DRIFT}s)" >&2
  exit 1
fi

# Success
sed -i '1d' "$DATES_FILE" || true
exit 0
APPLY_DATES_HELPER

    chmod +x "$tmpf" || true
    GENERATED_HELPERS+=("$tmpf")
    echo "$tmpf"
}

# Cleanup generated helper files
# Usage: cleanup_date_helpers
cleanup_date_helpers() {
    for h in "${GENERATED_HELPERS[@]}"; do
        rm -f "$h" 2>/dev/null || true
    done
    GENERATED_HELPERS=()
}

# ============================================================================
# DATE APPLICATION FUNCTIONS
# ============================================================================

# Apply dates to a preserved topology branch using a preserve map
# Usage: apply_dates_from_preserve_map "mapfile"
# Map format: original_sha|new_sha|date
apply_dates_from_preserve_map() {
    local mapfile="$1"
    if [[ -z "$mapfile" || ! -f "$mapfile" ]]; then
        print_warning "No preserve map provided to apply dates"
        return 1
    fi

    local ts logf
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    logf="/tmp/git-fix-preserve-dates-${ts}.log"
    : > "$logf"

    print_info "Applying dates using map: $mapfile (log: $logf)"
    local remaining=0

    # Fail-fast: if any entries in the preserve map indicate signing failure, abort
    local failed_sigs
    failed_sigs=$(grep -E '\|.*sig:FAIL$' "$mapfile" || true)
    if [[ -n "$failed_sigs" ]]; then
        print_warning "Preserve map contains commits that failed signing (sig:FAIL). Aborting map-based date application; reconstruction required."
        echo "$failed_sigs" | tee -a "$logf"
        return 1
    fi

    # Detect target branch (preferably the preserved branch)
    local cur_branch target_branch sample_sha
    cur_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)

    if [[ "$cur_branch" != "HEAD" ]]; then
        target_branch="$cur_branch"
    else
        # Try to detect a tmp/preserve branch that contains the first mapped sha
        sample_sha=$(awk -F'|' 'NR==1{print $2}' "$mapfile" || true)
        if [[ -n "$sample_sha" ]]; then
            target_branch=$(git branch --contains "$sample_sha" --format='%(refname:short)' 2>/dev/null | grep '^tmp/preserve' | head -n1 || true)
        fi

        # Fallback: try any tmp/preserve branch
        if [[ -z "$target_branch" ]]; then
            target_branch=$(git for-each-ref --format='%(refname:short)' refs/heads/tmp/preserve* | head -n1 || true)
        fi
    fi

    if [[ -z "$target_branch" ]]; then
        print_warning "Could not determine target branch to update refs. Proceeding but branch refs will not be adjusted." | tee -a "$logf"
    else
        print_info "Target branch for date application: $target_branch" | tee -a "$logf"
    fi

    # Read map lines into an array to avoid issues if we update the file in-place
    local map_lines=()
    while IFS= read -r L; do
        map_lines+=("$L")
    done < "$mapfile"

    for L in "${map_lines[@]}"; do
        local orig new_sha date
        IFS='|' read -r orig new_sha date <<< "$L"
        if [[ -z "$orig" || -z "$new_sha" || -z "$date" ]]; then
            echo "[WARN] Skipping malformed line: $L" | tee -a "$logf"
            continue
        fi

        # Compare by unix epoch to avoid formatting differences
        local existing_epoch date_epoch
        existing_epoch=$(git show -s --format=%at "$new_sha" 2>/dev/null || true)
        date_epoch=$(date -d "$date" +%s 2>/dev/null || true)

        if [[ -n "$existing_epoch" && -n "$date_epoch" && "$existing_epoch" -eq "$date_epoch" ]]; then
            echo "[INFO] Date for $new_sha already matches ($date)" | tee -a "$logf"
            continue
        fi

        echo "[INFO] Setting date for $new_sha -> $date" | tee -a "$logf"

        # Checkout commit in detached HEAD and try to amend with retry
        if ! git checkout --quiet "$new_sha" 2>/dev/null; then
            echo "[WARN] Failed to checkout $new_sha" | tee -a "$logf"
            remaining=$((remaining+1))
            continue
        fi

        local attempt=0
        local success=false
        while [[ $attempt -lt 3 ]]; do
            attempt=$((attempt+1))
            echo "[DEBUG] Amend attempt $attempt for $new_sha" | tee -a "$logf"
            GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
                git commit --amend --no-edit -n -S >/dev/null 2>>"$logf" && success=true && break
            sleep 0.1
        done

        if [[ "$success" != "true" ]]; then
            echo "[WARN] Amend failed for $new_sha after $attempt attempts" | tee -a "$logf"
            remaining=$((remaining+1))
            continue
        fi

        local signed_new
        signed_new=$(git rev-parse HEAD)
        echo "[INFO] Amended $new_sha -> $signed_new (date set: $date)" | tee -a "$logf"

        # Update the map: replace second field with the new SHA
        local tmp_map="${mapfile}.tmp"
        awk -F'|' -v OFS='|' -v o="$orig" -v ns="$signed_new" '{ if ($1==o) $2=ns; print }' "$mapfile" > "$tmp_map" && mv "$tmp_map" "$mapfile" || true

        # Update target branch ref if we detected it
        if [[ -n "$target_branch" ]]; then
            git update-ref -m "apply_dates $orig" "refs/heads/$target_branch" "$signed_new" || true
        fi
    done

    if [[ "$remaining" -eq 0 ]]; then
        # All dates applied: clear TEMP_ALL_DATES if set
        [[ -n "${TEMP_ALL_DATES:-}" ]] && : > "$TEMP_ALL_DATES" || true
        print_success "Applied all dates via preserve map (see $logf)"
        return 0
    else
        print_warning "Some dates could not be applied via preserve map (see $logf)"
        return 1
    fi
}

# ============================================================================
# INTERACTIVE DATE EDITING
# ============================================================================

# Display and optionally edit commit dates from a dates file
# Usage: display_and_edit_dates "dates_file" [highlight_commit]
# The highlight_commit will be marked as [AMENDING] in the display
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
        _edit_dates_interactive "$dates_file"
    fi
}

# Internal: interactive date editing loop
_edit_dates_interactive() {
    local dates_file="$1"
    
    echo ""
    echo -e "${BOLD}Edit timestamps:${NC}"
    echo -e "${GREY}(Accept formats: 2025-12-18, 2025-12-18 14:30, 2025-12-18T14:30:00+01:00, or empty to skip)${NC}"
    echo ""
    
    local commit_idx=0
    > "${dates_file}.edited"
    
    # Use FD4 for reading file to keep FD3 for interactive input
    while IFS='|' read -r commit_hash orig_date <&4; do
        commit_idx=$((commit_idx + 1))
        local short_hash
        short_hash=$(git rev-parse --short "$commit_hash" 2>/dev/null || echo "${commit_hash:0:7}")
        
        echo -e "[$commit_idx] $short_hash"
        echo -e "    Current: ${CYAN}$orig_date${NC}"
        
        local user_date
        if read -u 3 -rp "    New date (empty to keep): " user_date 2>/dev/null; then :
        else read -rp "    New date (empty to keep): " user_date
        fi
        
        local new_date="$orig_date"
        
        if [[ -n "$user_date" ]]; then
            new_date=$(_parse_user_date "$user_date" "$orig_date")
        fi
        
        echo "$commit_hash|$new_date" >> "${dates_file}.edited"
    done 4< "$dates_file"
    
    mv "${dates_file}.edited" "$dates_file"
    print_success "Dates updated"
}

# Internal: parse user-provided date string
_parse_user_date() {
    local user_date="$1"
    local fallback="$2"
    local parsed_date
    
    # Try to parse as-is (for already formatted dates)
    if parsed_date=$(date -d "$user_date" --iso-8601=seconds 2>/dev/null); then
        echo "$parsed_date"
        return 0
    fi
    
    # Try to handle common user input formats: "YYYY-MM-DD" or "YYYY-MM-DD HH:MM"
    if [[ "$user_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}($|\ [0-9]{2}:[0-9]{2}) ]]; then
        # Add time if not provided
        if [[ ! "$user_date" =~ \ [0-9]{2}:[0-9]{2} ]]; then
            user_date="$user_date 00:00"
        fi
        if parsed_date=$(date -d "$user_date" --iso-8601=seconds 2>/dev/null); then
            echo "$parsed_date"
            return 0
        fi
    fi
    
    print_warning "Could not parse date '$user_date'. Keeping original: $fallback"
    echo "$fallback"
}

# ============================================================================
# DATE VALIDATION
# ============================================================================

# Verify a commit has the expected date
# Usage: verify_commit_date "commit" "expected_date" [tolerance_seconds]
# Returns: 0 if matches within tolerance, 1 otherwise
verify_commit_date() {
    local commit="$1"
    local expected_date="$2"
    local tolerance="${3:-86400}"  # Default 24 hours
    
    local actual_epoch expected_epoch
    actual_epoch=$(git show -s --format=%at "$commit" 2>/dev/null || echo "0")
    expected_epoch=$(date -d "$expected_date" +%s 2>/dev/null || echo "0")
    
    if [[ "$actual_epoch" -eq 0 || "$expected_epoch" -eq 0 ]]; then
        return 1
    fi
    
    local diff=$((actual_epoch - expected_epoch))
    if (( diff < 0 )); then diff=$(( -diff )); fi
    
    if (( diff <= tolerance )); then
        return 0
    else
        return 1
    fi
}
