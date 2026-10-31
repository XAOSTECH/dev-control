#!/usr/bin/env bash
#
# Dev-Control Shared Library: Dedup — squash consecutive commits that share an identical subject line into the first commit of each run.
#
# Workflow:
#   1. Snapshot the commit list for the selected range (oldest first),
#      capturing hash, author/committer dates, author name/email and subject.
#   2. Group commits that share a grouping key — a byte-for-byte identical
#      subject, or a known housekeeping "family" (tree-viz refreshes, submodule
#      bumps, dc-init syncs, anglicise/humanise passes and the merge commits of
#      their chore branches) whose subjects differ only in counts or PR numbers.
#      When a group of >1 is combined the resulting commit message aggregates
#      every combined subject so nothing is silently discarded. CHANGELOG
#      commits and any commit a v*/latest tag points at are pinned (never
#      dropped).
#   3. Reconstruct history with `git commit-tree` from the parent of the
#      oldest in-range commit:
#        - Duplicate groups collapse to a single commit using the FIRST
#          commit's tree and full message, preserving its author date, name
#          and email; the committer date is refreshed to "now".
#        - Non-duplicate commits are recreated verbatim (tree, author and
#          committer metadata preserved).
#   4. Move the original branch to the rebuilt tip and offer to push.
#
# Nest check (DEDUP_TIMES >= 2, e.g. `--dedu x2`): the periodic "abba abba" case where the same subjects recur but are NOT adjacent (separated by merges, submodule bumps, changelog commits, …). A plain consecutive pass cannot touch these — and iterating it is a no-op (it reaches a fixpoint after one pass).
# In nest mode the grouping key is the subject across the WHOLE range: every occurrence of a subject collapses onto its LAST occurrence (tip-safe), earlier duplicates are dropped in place, and the run loops up to N rounds, stopping early once a round finds nothing (converged). Because each surviving commit keeps its own full-tree snapshot and the range tip (HEAD) is always the last occurrence of its own subject, the net content is provably unchanged — this is verified after rebuilding (HEAD^{tree} must equal the original) and the branch is restored on any mismatch.
#
# Honours: --dry-run (preview only), --sign (commit-tree -S), --no-cleanup, and the shared confirm/push/backup conventions.
#
# Required from the caller:
#   - print.sh / colours.sh sourced (print_info/print_success/print_warning/
#     print_error/print_header, BOLD/CYAN/GREEN/YELLOW/RED/NC)
#   - check_git_repo, confirm_changes (fix-history.sh)
#   - backup_repo (lib/git/amend.sh)
#   - prompt_and_push_branch (lib/git/drop.sh)
#   - Globals: RANGE, DRY_RUN, SIGN_MODE, NO_CLEANUP, HARNESS_MODE,
#     ORIGINAL_BRANCH, DEDUP_TIMES (repeat/nest multiplier, default 1)
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

# Pinned tag commit SHAs (release/latest tags). Populated by _dedup_collect_pins; always defined so classification can run standalone.
declare -gA DEDUP_PIN_SHAS=()

# ============================================================================
# FAMILY CLASSIFICATION — group housekeeping/bot chores that are logically the
# same maintenance task even when their subject lines differ (submodule counts,
# merge-PR numbers, dc-init verbs, …). Each family maps to the workflow /
# template that emits it so the mapping stays auditable.
# ============================================================================

# Map a commit subject to a canonical family key, or "" when it is not a known
# housekeeping chore. Families (origin in brackets):
#   fam:tree-viz        chore: update git tree visualisation      [tree-viz.yml]
#   fam:submodules      chore: update N submodule(s) to latest     [update.yml]
#   fam:deps-update     chore: update N dependencies to latest     [update.yml]
#   fam:dc-init         chore(dc-init): <verb> workflows/actions … [template-loading.sh]
#   fam:anglicise       chore: convert American spellings …        [anglicise.yml]
#   fam:humanise        chore: humanise hard-wrapped comments …    [humanise.yml]
#   fam:merge-*         Merge pull request … from …/<chore-branch> [PR merges]
_dedup_family_of() {
    local s="$1"
    case "$s" in
        "chore: update git tree visualisation"|"chore(tree-viz):"*)   echo "fam:tree-viz" ;;
        "chore: update "[0-9]*" submodule(s) to latest")              echo "fam:submodules" ;;
        "chore: update "[0-9]*" dependencies to latest")              echo "fam:deps-update" ;;
        "chore(dc-init):"*CHANGELOG*|"chore(dc-init):"*changelog*)     echo "" ;;
        "chore(dc-init):"*)                                           echo "fam:dc-init" ;;
        "chore: convert American spellings to British English")       echo "fam:anglicise" ;;
        "chore: humanise hard-wrapped comments and prose")            echo "fam:humanise" ;;
        "Merge pull request #"*"chore/update-submodules-"*)           echo "fam:merge-submodules" ;;
        "Merge pull request #"*"anglicise/"*)                         echo "fam:merge-anglicise" ;;
        "Merge pull request #"*"humanise/"*)                          echo "fam:merge-humanise" ;;
        *)                                                           echo "" ;;
    esac
}

# A clean one-line headline used when a family group of >1 commits is combined.
# Falls back to "" for exact-subject (non-family) groups, where the first
# member's own subject is used verbatim instead.
_dedup_family_label() {
    case "$1" in
        fam:tree-viz)         echo "chore: update git tree visualisation" ;;
        fam:submodules)       echo "chore: update submodules to latest" ;;
        fam:deps-update)      echo "chore: update dependencies to latest" ;;
        fam:dc-init)          echo "chore(dc-init): sync workflows and actions" ;;
        fam:anglicise)        echo "chore: convert American spellings to British English" ;;
        fam:humanise)         echo "chore: humanise hard-wrapped comments and prose" ;;
        fam:merge-submodules) echo "chore: consolidate submodule update merges" ;;
        fam:merge-anglicise)  echo "chore: consolidate anglicise merges" ;;
        fam:merge-humanise)   echo "chore: consolidate humanise merges" ;;
        *)                    echo "" ;;
    esac
}

# True when a subject/SHA must never be dropped: CHANGELOG commits anchor
# release tags, and any commit a v*/latest tag points at is release scaffolding.
_dedup_is_pinned() {
    local subj="$1" h="$2"
    case "$subj" in
        "chore: update CHANGELOG"*|"chore(changelog)"*) return 0 ;;
    esac
    [[ -n "${DEDUP_PIN_SHAS[$h]:-}" ]] && return 0
    return 1
}

# Classify one commit into (_CLS_KEY, _CLS_COMBINABLE). Combinable commits may
# collapse onto a representative of the same key; non-combinable commits get a
# unique key so they are always kept in place.
_dedup_classify() {
    local subj="$1" h="$2" fam
    if _dedup_is_pinned "$subj" "$h"; then
        _CLS_KEY=""; _CLS_COMBINABLE="false"; return 0
    fi
    fam=$(_dedup_family_of "$subj")
    if [[ -n "$fam" ]]; then
        _CLS_KEY="$fam"; _CLS_COMBINABLE="true"; return 0
    fi
    if [[ "${DEDUP_CONSERVATIVE:-false}" == "true" ]]; then
        # Conservative: user commits are never squashed, only known chores.
        _CLS_KEY=""; _CLS_COMBINABLE="false"
    else
        # Liberal: fall back to exact-subject grouping (legacy behaviour).
        _CLS_KEY="exact:$subj"; _CLS_COMBINABLE="true"
    fi
    return 0
}

# Build the aggregated commit message for a combined group of >1 commits.
#   $1 key, $2 count, $3 newline-joined ordered-unique member subjects.
# Headline = family label (or first subject); the body lists every combined
# subject so nothing is silently discarded.
_dedup_group_message() {
    local key="$1" count="$2" subs="$3" label headline body s
    label=$(_dedup_family_label "$key")
    if [[ -n "$label" ]]; then
        headline="$label"
    else
        headline="${subs%%$'\n'*}"
    fi
    body="Consolidated ${count} commits:"
    while IFS= read -r s; do
        [[ -z "$s" ]] && continue
        body+=$'\n'"- $s"
    done <<< "$subs"
    printf '%s\n\n%s\n' "$headline" "$body"
}

# Collect the commit SHAs that release/latest tags point at, so they are pinned
# against removal. Safe to call once per run; stale entries are harmless.
_dedup_collect_pins() {
    DEDUP_PIN_SHAS=()
    local t sha
    while IFS= read -r t; do
        [[ -z "$t" ]] && continue
        sha=$(git rev-parse --verify --quiet "${t}^{commit}" 2>/dev/null) || continue
        DEDUP_PIN_SHAS["$sha"]=1
    done < <(git tag -l 'v*' 'latest' 2>/dev/null)
}

# ============================================================================
# DEDUP MODE — squash consecutive identical-subject commits into the first
# ============================================================================

# Build the squash plan for one round over $RANGE into shared PLAN_* globals.
#   $1 nest — "true" collapses every occurrence of a key onto its LAST
#             occurrence (non-adjacent, tip-safe); "false" collapses only
#             consecutive runs onto their FIRST occurrence (legacy behaviour).
# Grouping key comes from _dedup_classify: a known housekeeping family, an
# exact subject (liberal mode), or a unique keep:<i> for pinned/user commits.
# Populates: PLAN_TOTAL, PLAN_BASE, PLAN_EMIT_HASH[], PLAN_EMIT_CDATE[]
#            ("NOW" => refresh committer date, "" => keep original),
#            PLAN_EMIT_MSG[] (aggregated message for combined groups, "" to
#            keep the representative's own message verbatim),
#            PLAN_ROWS[] ("action|hash|subject" for preview),
#            PLAN_DUP_GROUPS, PLAN_DUP_COMMITS.
dedup_build_plan() {
    local nest="$1"

    PLAN_EMIT_HASH=(); PLAN_EMIT_CDATE=(); PLAN_EMIT_MSG=(); PLAN_ROWS=()
    PLAN_DUP_GROUPS=0; PLAN_DUP_COMMITS=0; PLAN_BASE=""

    # Extract commits oldest-first using the unit separator (0x1f) so subjects containing pipes or spaces survive intact.
    local -a commits=()
    mapfile -t commits < <(git log --reverse --format="%H%x1f%s" "$RANGE")
    PLAN_TOTAL=${#commits[@]}
    (( PLAN_TOTAL == 0 )) && return 0

    # Base = parent of the oldest in-range commit (empty if range starts at root).
    # --verify --quiet prints nothing (not the unresolved ref) when there is no parent.
    local oldest_hash="${commits[0]%%$'\x1f'*}"
    PLAN_BASE=$(git rev-parse --verify --quiet "${oldest_hash}~1" 2>/dev/null || true)

    # Pass 1: classify every commit into a grouping key. Combinable commits share
    # a family / exact-subject key; the rest get a unique "keep:<i>" key so they
    # are always emitted in place.
    local -a K=() SUB=() HASH=()
    local i entry h subj key
    for ((i = 0; i < PLAN_TOTAL; i++)); do
        entry="${commits[$i]}"; h="${entry%%$'\x1f'*}"; subj="${entry#*$'\x1f'}"
        HASH[$i]="$h"; SUB[$i]="$subj"
        _dedup_classify "$subj" "$h"
        if [[ "$_CLS_COMBINABLE" == "true" ]]; then
            K[$i]="$_CLS_KEY"
        else
            K[$i]="keep:$i"
        fi
    done

    if [[ "$nest" == "true" ]]; then
        # Nest: group by key across the whole range, keep the LAST occurrence.
        local -A last_idx=() cnt=() subs_join=()
        for ((i = 0; i < PLAN_TOTAL; i++)); do
            key="${K[$i]}"
            last_idx["$key"]="$i"
            cnt["$key"]=$(( ${cnt["$key"]:-0} + 1 ))
            # Accumulate ordered-unique member subjects for the aggregated message.
            case $'\n'"${subs_join["$key"]:-}"$'\n' in
                *$'\n'"${SUB[$i]}"$'\n'*) : ;;
                *) subs_join["$key"]="${subs_join["$key"]:+${subs_join["$key"]}$'\n'}${SUB[$i]}" ;;
            esac
        done
        for ((i = 0; i < PLAN_TOTAL; i++)); do
            key="${K[$i]}"; h="${HASH[$i]}"; subj="${SUB[$i]}"
            if [[ "${last_idx["$key"]}" == "$i" ]]; then
                PLAN_EMIT_HASH+=("$h"); PLAN_EMIT_CDATE+=("")
                if (( ${cnt["$key"]} > 1 )); then
                    PLAN_EMIT_MSG+=("$(_dedup_group_message "$key" "${cnt["$key"]}" "${subs_join["$key"]}")")
                    PLAN_ROWS+=("nest ${cnt["$key"]}×|$h|$subj")
                    PLAN_DUP_GROUPS=$((PLAN_DUP_GROUPS + 1))
                    PLAN_DUP_COMMITS=$((PLAN_DUP_COMMITS + ${cnt["$key"]} - 1))
                else
                    PLAN_EMIT_MSG+=("")
                    PLAN_ROWS+=("keep|$h|$subj")
                fi
            else
                PLAN_ROWS+=("drop|$h|$subj")
            fi
        done
    else
        # Consecutive: collapse adjacent same-key runs onto the FIRST occurrence.
        local prev_key="" idx=-1
        local -a run_first=() run_count=() run_subj=() run_subs=()
        for ((i = 0; i < PLAN_TOTAL; i++)); do
            key="${K[$i]}"; h="${HASH[$i]}"; subj="${SUB[$i]}"
            if (( idx >= 0 )) && [[ "$key" == "$prev_key" && "$key" != keep:* ]]; then
                run_count[$idx]=$(( run_count[idx] + 1 ))
                case $'\n'"${run_subs[$idx]}"$'\n' in
                    *$'\n'"$subj"$'\n'*) : ;;
                    *) run_subs[$idx]="${run_subs[$idx]}"$'\n'"$subj" ;;
                esac
            else
                idx=$((idx + 1)); run_first[$idx]="$h"; run_count[$idx]=1; run_subj[$idx]="$subj"; run_subs[$idx]="$subj"
            fi
            prev_key="$key"
        done
        local j
        for ((j = 0; j <= idx; j++)); do
            PLAN_EMIT_HASH+=("${run_first[$j]}")
            if (( run_count[$j] > 1 )); then
                PLAN_EMIT_CDATE+=("NOW")
                _dedup_classify "${run_subj[$j]}" "${run_first[$j]}"
                PLAN_EMIT_MSG+=("$(_dedup_group_message "$_CLS_KEY" "${run_count[$j]}" "${run_subs[$j]}")")
                PLAN_ROWS+=("squash ${run_count[$j]}×|${run_first[$j]}|${run_subj[$j]}")
                PLAN_DUP_GROUPS=$((PLAN_DUP_GROUPS + 1))
                PLAN_DUP_COMMITS=$((PLAN_DUP_COMMITS + run_count[$j] - 1))
            else
                PLAN_EMIT_CDATE+=("")
                PLAN_EMIT_MSG+=("")
                PLAN_ROWS+=("keep|${run_first[$j]}|${run_subj[$j]}")
            fi
        done
    fi
    return 0
}

# Rebuild $RANGE for one round using the current plan and move the branch to it.
# Returns: 0 changed history, 1 nothing to do, 2 hard failure.
# Sets ROUND_DUP_GROUPS / ROUND_DUP_COMMITS on success.
dedup_run_round() {
    local nest="$1"
    dedup_build_plan "$nest"
    (( PLAN_DUP_COMMITS == 0 )) && return 1

    ROUND_DUP_GROUPS=$PLAN_DUP_GROUPS
    ROUND_DUP_COMMITS=$PLAN_DUP_COMMITS

    local -a sign_flag=()
    [[ "$SIGN_MODE" == "true" ]] && sign_flag=(-S)
    local now; now="$(date -uIseconds)"

    local new_parent="$PLAN_BASE" k rep tree msg an ae ad cn ce cdate
    for ((k = 0; k < ${#PLAN_EMIT_HASH[@]}; k++)); do
        rep="${PLAN_EMIT_HASH[$k]}"
        tree=$(git rev-parse "${rep}^{tree}")
        if [[ -n "${PLAN_EMIT_MSG[$k]:-}" ]]; then
            msg="${PLAN_EMIT_MSG[$k]}"
        else
            msg=$(git log -1 --format=%B "$rep")
        fi
        an=$(git log -1 --format=%an "$rep"); ae=$(git log -1 --format=%ae "$rep"); ad=$(git log -1 --format=%aI "$rep")
        cn=$(git log -1 --format=%cn "$rep"); ce=$(git log -1 --format=%ce "$rep")
        if [[ "${PLAN_EMIT_CDATE[$k]}" == "NOW" ]]; then
            cdate="$now"
        else
            cdate=$(git log -1 --format=%cI "$rep")
        fi

        local -a parent_arg=()
        [[ -n "$new_parent" ]] && parent_arg=(-p "$new_parent")

        local new_sha
        new_sha=$(GIT_AUTHOR_NAME="$an" GIT_AUTHOR_EMAIL="$ae" GIT_AUTHOR_DATE="$ad" \
            GIT_COMMITTER_NAME="$cn" GIT_COMMITTER_EMAIL="$ce" GIT_COMMITTER_DATE="$cdate" \
            git commit-tree "${sign_flag[@]}" "${parent_arg[@]}" -m "$msg" "$tree") || {
            print_error "Failed to recreate commit ${rep:0:7}"
            return 2
        }
        new_parent="$new_sha"
    done

    [[ -z "$new_parent" ]] && { print_error "Reconstruction produced no commits"; return 2; }

    if ! git reset --hard "$new_parent" >/dev/null 2>&1; then
        print_error "Failed to update branch to rebuilt history"
        return 2
    fi
    return 0
}

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

    # Repeat/nest multiplier: `--dedu x2` (>=2) turns on nested (non-adjacent) resolution and loops up to N rounds; bare `--dedu` stays consecutive-only.
    local times="${DEDUP_TIMES:-1}"
    (( times < 1 )) && times=1
    local nest=false
    (( times >= 2 )) && nest=true

    echo -e "${BOLD}Deduplicate Mode${NC}"
    echo -e "Range: ${CYAN}$RANGE${NC}"
    if [[ "$nest" == "true" ]]; then
        echo -e "Mode:  ${CYAN}nest check${NC} (non-adjacent duplicates, up to ${CYAN}${times}${NC} round(s))"
    else
        echo -e "Mode:  ${CYAN}consecutive${NC}"
    fi

    # Pin release-tag commits so they survive deduplication, then preview round one.
    _dedup_collect_pins

    # Preview the first round's plan
    dedup_build_plan "$nest"
    if (( PLAN_TOTAL == 0 )); then
        print_error "No commits found in range: $RANGE"
        exit 1
    fi
    if (( PLAN_DUP_COMMITS == 0 )); then
        if [[ "$nest" == "true" ]]; then
            print_success "No duplicate commit messages (adjacent or nested) found in range: $RANGE"
        else
            print_success "No consecutive duplicate commit messages found in range: $RANGE"
        fi
        exit 0
    fi

    # Preview the plan
    echo ""
    echo -e "${BOLD}Deduplication plan:${NC}\n"
    local row rest action hash subj
    for row in "${PLAN_ROWS[@]}"; do
        action="${row%%|*}"; rest="${row#*|}"; hash="${rest%%|*}"; subj="${rest#*|}"
        case "$action" in
            keep) echo -e "  ${GREEN}keep     ${NC} ${CYAN}${hash:0:7}${NC}  ${subj:0:50}" ;;
            drop) echo -e "  ${RED}drop     ${NC} ${CYAN}${hash:0:7}${NC}  ${subj:0:50}" ;;
            *)    echo -e "  ${YELLOW}${action}${NC} ${CYAN}${hash:0:7}${NC}  ${subj:0:50}" ;;
        esac
    done
    echo ""
    print_info "Would squash ${CYAN}$PLAN_DUP_COMMITS${NC} commit(s) across ${CYAN}$PLAN_DUP_GROUPS${NC} group(s)"

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

    # Anchor the original state so the nest check can restore on any mismatch
    local original_head_sha original_tip_tree
    original_head_sha=$(git rev-parse HEAD)
    original_tip_tree=$(git rev-parse "HEAD^{tree}")

    print_info "Rebuilding history..."

    local round=0 total_groups=0 total_commits=0 rc
    while (( round < times )); do
        round=$((round + 1))
        if dedup_run_round "$nest"; then
            total_groups=$((total_groups + ROUND_DUP_GROUPS))
            total_commits=$((total_commits + ROUND_DUP_COMMITS))
            print_success "Round ${round}/${times}: squashed ${ROUND_DUP_COMMITS} commit(s) across ${ROUND_DUP_GROUPS} group(s)"
        else
            rc=$?
            if (( rc == 2 )); then
                print_error "Round ${round} failed; restoring original state"
                git reset --hard "$original_head_sha" >/dev/null 2>&1 || true
                exit 1
            fi
            if (( round > 1 )); then
                print_info "Round ${round}: no further duplicates — converged after $((round - 1)) round(s)"
            fi
            break
        fi
    done

    if (( total_commits == 0 )); then
        print_info "Nothing to deduplicate"
        exit 0
    fi

    # Nest check: the rewrite must not alter the net working tree. By construction the range tip (HEAD) is always the last occurrence of its own subject, so this holds; verify it and restore on the off-chance it does not.
    if [[ "$nest" == "true" ]]; then
        local new_tip_tree
        new_tip_tree=$(git rev-parse "HEAD^{tree}")
        if [[ "$new_tip_tree" != "$original_tip_tree" ]]; then
            print_error "Nest check FAILED: resulting tree ${new_tip_tree:0:12} != original ${original_tip_tree:0:12} — restoring"
            git reset --hard "$original_head_sha" >/dev/null 2>&1 || true
            exit 1
        fi
        print_success "Nest check: working tree identical to original (tree ${new_tip_tree:0:12} verified)"
    fi

    print_success "Deduplicated $total_commits commit(s) across $total_groups group(s) in $round round(s)"
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
