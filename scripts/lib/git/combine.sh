#!/usr/bin/env bash
#
# Dev-Control Shared Library: Combine — fuse two subsequent (adjacent) commits
# into one and surgically rebuild the rest of history.
#
# Workflow (deterministic, conflict-free via `git commit-tree`):
#   1. Resolve the two given commits and determine their order (the ancestor is
#      the "older", its child the "newer").
#   2. Require adjacency: the newer commit's parent must be the older commit.
#      Non-subsequent commits are rejected (drop the intermediate ones first
#      with --drop, or pick two adjacent commits).
#   3. Reconstruct from the parent of the older commit to HEAD:
#        - The older+newer pair collapses to ONE commit that uses the NEWER
#          commit's tree (the cumulative snapshot of both changes) and a joined
#          message, preserving the OLDER commit's author and committer identity
#          and dates.
#        - Every later commit is recreated verbatim (tree, author and committer
#          metadata preserved exactly).
#   4. Move the branch to the rebuilt tip and offer to push.
#
# Honours: --dry-run (preview only), --sign (commit-tree -S, re-signs the
# combined commit and all rebuilt commits), --no-cleanup, and the shared
# confirm/push/backup conventions. Linear (single-parent) commits only.
#
# Required from the caller:
#   - print.sh / colours.sh sourced (print_info/print_success/print_warning/
#     print_error/print_header, BOLD/CYAN/GREEN/YELLOW/NC)
#   - check_git_repo, confirm_changes (fix-history.sh)
#   - backup_repo (lib/git/amend.sh)
#   - prompt_and_push_branch (lib/git/drop.sh)
#   - cleanup_tmp_and_backup_refs (fix-history.sh)
#   - Globals: COMBINE_A, COMBINE_B, DRY_RUN, SIGN_MODE, NO_CLEANUP,
#     HARNESS_MODE, ORIGINAL_BRANCH
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
# COMBINE MODE — fuse two adjacent commits into one, rebuild the remainder
# ============================================================================

combine_commits() {
    print_header
    check_git_repo

    # Remember the branch so we can move it to the rebuilt tip
    ORIGINAL_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    print_info "Original branch recorded: $ORIGINAL_BRANCH"

    if [[ -z "$COMBINE_A" || -z "$COMBINE_B" ]]; then
        print_error "--combine requires two commits: --combine <commitA> <commitB>"
        exit 1
    fi

    # Resolve both refs to full commit SHAs
    local A B
    A=$(git rev-parse --verify --quiet "${COMBINE_A}^{commit}") || { print_error "Commit not found: $COMBINE_A"; exit 1; }
    B=$(git rev-parse --verify --quiet "${COMBINE_B}^{commit}") || { print_error "Commit not found: $COMBINE_B"; exit 1; }

    if [[ "$A" == "$B" ]]; then
        print_error "Cannot combine a commit with itself"
        exit 1
    fi

    # Determine chronological order (the ancestor is the older commit)
    local older newer
    if git merge-base --is-ancestor "$A" "$B" 2>/dev/null; then
        older="$A"; newer="$B"
    elif git merge-base --is-ancestor "$B" "$A" 2>/dev/null; then
        older="$B"; newer="$A"
    else
        print_error "Commits are on divergent branches; cannot combine."
        exit 1
    fi

    # Require adjacency: the newer commit's (first) parent must be the older commit
    local newer_parent
    newer_parent=$(git rev-parse --verify --quiet "${newer}^") || true
    if [[ "$newer_parent" != "$older" ]]; then
        print_error "Commits are not subsequent (adjacent)."
        print_info  "Non-subsequent combine is not supported here. Drop the intermediate commit(s) first (see --drop), or choose two adjacent commits."
        exit 1
    fi

    # Linear-history guard: combining a merge commit via commit-tree would drop a parent
    if [[ $(git rev-list --parents -n1 "$newer" | wc -w) -gt 2 || $(git rev-list --parents -n1 "$older" | wc -w) -gt 2 ]]; then
        print_error "One of the commits is a merge commit; --combine supports linear (single-parent) commits only."
        exit 1
    fi

    # Capture the older commit's identity/dates and both messages
    local o_an o_ae o_ad o_cn o_ce o_cd o_msg n_msg
    o_an=$(git log -1 --format=%an "$older")
    o_ae=$(git log -1 --format=%ae "$older")
    o_ad=$(git log -1 --format=%aI "$older")
    o_cn=$(git log -1 --format=%cn "$older")
    o_ce=$(git log -1 --format=%ce "$older")
    o_cd=$(git log -1 --format=%cI "$older")
    o_msg=$(git log -1 --format=%B "$older")
    n_msg=$(git log -1 --format=%B "$newer")

    local trailing
    trailing=$(git rev-list --count "${newer}..HEAD")

    echo ""
    echo -e "${BOLD}Combine Mode${NC}\n"
    echo -e "  ${YELLOW}fuse${NC}  ${CYAN}${older:0:7}${NC}  $(git log -1 --format=%s "$older")"
    echo -e "  ${YELLOW}into${NC}  ${CYAN}${newer:0:7}${NC}  $(git log -1 --format=%s "$newer")"
    echo ""
    print_info "Result: 1 combined commit (newer tree, older dates/author) + ${CYAN}$trailing${NC} trailing commit(s) rebuilt verbatim"
    if [[ "$SIGN_MODE" == "true" ]]; then
        print_info "Signing: the combined commit and all rebuilt commits will be re-signed"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        print_info "${YELLOW}${BOLD}DRY RUN${NC} - no commits will be rewritten."
        echo -e "  Combined message preview:"
        printf '%s\n\n%s\n' "$o_msg" "$n_msg" | sed 's/^/    /'
        echo -e "  To apply, re-run without ${CYAN}--dry-run${NC}"
        exit 0
    fi

    # Confirm before rewriting (auto-confirm under the test harness)
    if [[ "${HARNESS_MODE:-false}" == "true" ]]; then
        print_info "Harness mode: auto-confirming combine"
    else
        if ! confirm_changes; then
            print_info "Cancelled - no commits modified"
            exit 0
        fi
    fi

    backup_repo

    local -a sign_flag=()
    if [[ "$SIGN_MODE" == "true" ]]; then
        sign_flag=(-S)
    fi

    # Base = parent of the older commit (empty if the older commit is the root)
    local base
    base=$(git rev-parse --verify --quiet "${older}^") || base=""

    # Commits to replay, oldest first: older..HEAD inclusive (or root..HEAD)
    local -a replay=()
    if [[ -n "$base" ]]; then
        mapfile -t replay < <(git rev-list --reverse "${base}..HEAD")
    else
        mapfile -t replay < <(git rev-list --reverse HEAD)
    fi

    print_info "Rebuilding history..."

    local new_parent="$base" c
    for c in "${replay[@]}"; do
        # The older commit is deferred; it is merged into the combined commit emitted at the newer position
        if [[ "$c" == "$older" ]]; then
            continue
        fi

        local tree msg an ae ad cn ce cd
        if [[ "$c" == "$newer" ]]; then
            tree=$(git rev-parse "${newer}^{tree}")
            msg="${o_msg}"$'\n\n'"${n_msg}"
            an="$o_an"; ae="$o_ae"; ad="$o_ad"
            cn="$o_cn"; ce="$o_ce"; cd="$o_cd"
        else
            tree=$(git rev-parse "${c}^{tree}")
            msg=$(git log -1 --format=%B "$c")
            an=$(git log -1 --format=%an "$c"); ae=$(git log -1 --format=%ae "$c"); ad=$(git log -1 --format=%aI "$c")
            cn=$(git log -1 --format=%cn "$c"); ce=$(git log -1 --format=%ce "$c"); cd=$(git log -1 --format=%cI "$c")
        fi

        local -a parent_arg=()
        if [[ -n "$new_parent" ]]; then
            parent_arg=(-p "$new_parent")
        fi

        local new_sha
        new_sha=$(GIT_AUTHOR_NAME="$an" GIT_AUTHOR_EMAIL="$ae" GIT_AUTHOR_DATE="$ad" \
            GIT_COMMITTER_NAME="$cn" GIT_COMMITTER_EMAIL="$ce" GIT_COMMITTER_DATE="$cd" \
            git commit-tree "${sign_flag[@]}" "${parent_arg[@]}" -m "$msg" "$tree") || {
            print_error "Failed to recreate commit ${c:0:7}"
            exit 1
        }
        new_parent="$new_sha"
    done

    if [[ -z "$new_parent" ]]; then
        print_error "Reconstruction produced no commits"
        exit 1
    fi

    print_info "Moving ${ORIGINAL_BRANCH} to rebuilt history..."
    if ! git reset --hard "$new_parent"; then
        print_error "Failed to update branch to rebuilt history"
        exit 1
    fi

    print_success "Combined ${older:0:7} + ${newer:0:7} into one commit; rebuilt $trailing trailing commit(s)"
    echo ""
    echo -e "${BOLD}Resulting history:${NC}"
    git --no-pager log --format="%h %aI %s" -n "$((trailing + 3))" 2>/dev/null || git --no-pager log --oneline -10
    echo ""

    # Offer to push the rewritten branch (creates a backup tag first)
    prompt_and_push_branch || print_warning "Automatic push failed or was cancelled"

    # Offer cleanup of tmp/backup refs unless suppressed
    if [[ "${NO_CLEANUP:-false}" != "true" ]]; then
        echo ""
        cleanup_tmp_and_backup_refs 2>/dev/null || true
    fi
}
