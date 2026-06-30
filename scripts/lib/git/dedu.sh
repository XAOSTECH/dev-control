#!/usr/bin/env bash
#
# Dev-Control Shared Library: Dedup — squash consecutive commits that share
# an identical subject line into the first commit of each run.
#
# Workflow:
#   1. Snapshot the commit list for the selected range (oldest first),
#      capturing hash, author/committer dates, author name/email and subject.
#   2. Group runs of consecutive commits whose subject is byte-for-byte equal.
#   3. Reconstruct history with `git commit-tree` from the parent of the
#      oldest in-range commit:
#        - Duplicate groups collapse to a single commit using the FIRST
#          commit's tree and full message, preserving its author date, name
#          and email; the committer date is refreshed to "now".
#        - Non-duplicate commits are recreated verbatim (tree, author and
#          committer metadata preserved).
#   4. Move the original branch to the rebuilt tip and offer to push.
#
# Honours: --dry-run (preview only), --sign (commit-tree -S), --no-cleanup,
# and the shared confirm/push/backup conventions.
#
# Required from the caller:
#   - print.sh / colours.sh sourced (print_info/print_success/print_warning/
#     print_error/print_header, BOLD/CYAN/GREEN/YELLOW/NC)
#   - check_git_repo, confirm_changes (fix-history.sh)
#   - backup_repo (lib/git/amend.sh)
#   - prompt_and_push_branch (lib/git/drop.sh)
#   - Globals: RANGE, DRY_RUN, SIGN_MODE, NO_CLEANUP, HARNESS_MODE,
#     ORIGINAL_BRANCH
#   - File descriptor 3 (interactive prompts)
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# Dual-mode bootstrap. When executed directly (rather than sourced), enable strict mode and pull in the shared colour/print libs so the module's functions can be exercised standalone. When sourced by a master, skip this block — the parent owns those globals.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    DEV_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"
    export DEV_CONTROL_DIR
    # shellcheck source=../colours.sh
    source "$SCRIPT_DIR/lib/colours.sh"
    # shellcheck source=../print.sh
    source "$SCRIPT_DIR/lib/print.sh"
fi

# ============================================================================
# DEDUP MODE — squash consecutive identical-subject commits into the first
# ============================================================================

deduplicate_mode() {
    print_header
    check_git_repo

    # Remember the branch we started on so we can move it to the rebuilt tip
    ORIGINAL_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    print_info "Original branch recorded: $ORIGINAL_BRANCH"

    # Normalise simple ranges like HEAD~5 into HEAD~5..HEAD for clarity
    if [[ "$RANGE" != *".."* ]]; then
        RANGE="$RANGE..HEAD"
    fi

    echo -e "${BOLD}Deduplicate Mode${NC}"
    echo -e "Range: ${CYAN}$RANGE${NC}"

    # Extract commits oldest-first using the unit separator (0x1f) as a delimiter
    # so subjects containing pipes or spaces survive intact.
    local -a commits=()
    mapfile -t commits < <(git log --reverse --format="%H%x1f%aI%x1f%cI%x1f%an%x1f%ae%x1f%cn%x1f%ce%x1f%s" "$RANGE")

    if [[ ${#commits[@]} -eq 0 ]]; then
        print_error "No commits found in range: $RANGE"
        exit 1
    fi

    # Base = parent of the oldest in-range commit (empty if range starts at root)
    local oldest_hash="${commits[0]%%$'\x1f'*}"
    local base
    base=$(git rev-parse "${oldest_hash}~1" 2>/dev/null || true)

    # Build the squash plan: a list of "kept" representative commits, each with
    # a member count describing how many consecutive duplicates collapse into it.
    local -a plan_hash=() plan_count=() plan_subject=()
    local prev_subject="" idx=-1
    local entry h ad cd an ae cn ce subj
    for entry in "${commits[@]}"; do
        IFS=$'\x1f' read -r h ad cd an ae cn ce subj <<< "$entry"
        if [[ $idx -ge 0 && "$subj" == "$prev_subject" ]]; then
            plan_count[$idx]=$(( plan_count[idx] + 1 ))
        else
            idx=$((idx + 1))
            plan_hash[$idx]="$h"
            plan_count[$idx]=1
            plan_subject[$idx]="$subj"
        fi
        prev_subject="$subj"
    done

    # Tally duplicates
    local dup_groups=0 dup_commits=0 i
    for ((i = 0; i <= idx; i++)); do
        if [[ ${plan_count[$i]} -gt 1 ]]; then
            dup_groups=$((dup_groups + 1))
            dup_commits=$((dup_commits + plan_count[i] - 1))
        fi
    done

    if [[ $dup_groups -eq 0 ]]; then
        print_success "No consecutive duplicate commit messages found in range: $RANGE"
        exit 0
    fi

    # Preview the plan
    echo ""
    echo -e "${BOLD}Deduplication plan:${NC}\n"
    for ((i = 0; i <= idx; i++)); do
        if [[ ${plan_count[$i]} -gt 1 ]]; then
            echo -e "  ${YELLOW}squash ${plan_count[$i]}×${NC} ${CYAN}${plan_hash[$i]:0:7}${NC}  ${plan_subject[$i]:0:50}"
        else
            echo -e "  ${GREEN}keep    ${NC} ${CYAN}${plan_hash[$i]:0:7}${NC}  ${plan_subject[$i]:0:50}"
        fi
    done
    echo ""
    print_info "Would squash ${CYAN}$dup_commits${NC} commit(s) across ${CYAN}$dup_groups${NC} group(s)"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        print_info "${YELLOW}${BOLD}DRY RUN${NC} - no commits will be rewritten."
        echo -e "  To apply, re-run without ${CYAN}--dry-run${NC}"
        exit 0
    fi

    # Confirm before rewriting (auto-confirm under the test harness)
    if [[ "${HARNESS_MODE:-false}" == "true" ]]; then
        print_info "Harness mode: auto-confirming deduplication"
    else
        if ! confirm_changes; then
            print_info "Cancelled - no commits modified"
            exit 0
        fi
    fi

    backup_repo

    # Reconstruct history from the base using commit-tree
    local -a sign_flag=()
    if [[ "$SIGN_MODE" == "true" ]]; then
        sign_flag=(-S)
    fi
    local now
    now="$(date -uIseconds)"

    print_info "Rebuilding history..."

    local new_parent="$base"
    for ((i = 0; i <= idx; i++)); do
        local rep="${plan_hash[$i]}"
        local tree msg r_an r_ae r_cn r_ce r_ad committer_date
        tree=$(git rev-parse "${rep}^{tree}")
        msg=$(git log -1 --format=%B "$rep")
        r_an=$(git log -1 --format=%an "$rep")
        r_ae=$(git log -1 --format=%ae "$rep")
        r_cn=$(git log -1 --format=%cn "$rep")
        r_ce=$(git log -1 --format=%ce "$rep")
        r_ad=$(git log -1 --format=%aI "$rep")

        if [[ ${plan_count[$i]} -gt 1 ]]; then
            # Squashed group: preserve the first commit's author identity/date,
            # refresh the committer date to now.
            committer_date="$now"
        else
            committer_date=$(git log -1 --format=%cI "$rep")
        fi

        local -a parent_arg=()
        if [[ -n "$new_parent" ]]; then
            parent_arg=(-p "$new_parent")
        fi

        local new_sha
        new_sha=$(GIT_AUTHOR_NAME="$r_an" GIT_AUTHOR_EMAIL="$r_ae" GIT_AUTHOR_DATE="$r_ad" \
            GIT_COMMITTER_NAME="$r_cn" GIT_COMMITTER_EMAIL="$r_ce" GIT_COMMITTER_DATE="$committer_date" \
            git commit-tree "${sign_flag[@]}" "${parent_arg[@]}" -m "$msg" "$tree") || {
            print_error "Failed to recreate commit ${rep:0:7}"
            exit 1
        }
        new_parent="$new_sha"
    done

    if [[ -z "$new_parent" ]]; then
        print_error "Reconstruction produced no commits"
        exit 1
    fi

    # Move the original branch (and working tree) to the rebuilt tip
    print_info "Moving ${ORIGINAL_BRANCH} to rebuilt history..."
    if ! git reset --hard "$new_parent"; then
        print_error "Failed to update branch to rebuilt history"
        exit 1
    fi

    print_success "Deduplicated $dup_commits commit(s) across $dup_groups group(s)"
    echo ""
    echo -e "${BOLD}Resulting history:${NC}"
    git --no-pager log --format="%h %aI %s" "$RANGE" 2>/dev/null || git --no-pager log --oneline -10
    echo ""

    # Offer to push the rewritten branch (creates a backup tag first)
    prompt_and_push_branch || print_warning "Automatic push failed or was cancelled"

    # Offer cleanup of tmp/backup refs unless suppressed
    if [[ "${NO_CLEANUP:-false}" != "true" ]]; then
        echo ""
        cleanup_tmp_and_backup_refs 2>/dev/null || true
    fi
}
