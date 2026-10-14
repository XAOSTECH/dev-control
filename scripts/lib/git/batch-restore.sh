#!/usr/bin/env bash
#
# Dev-Control Shared Library: Restore Diagnostics
# Tracker, diagnostic and recovery functions for dc-fix history rewrites.
#
# Works on a single repo or a batch of repos from a tracker file.
# --batch is always just a flag, not a mode confinement.
#
# Key capabilities:
#   - tracker_path / tracker_record : track original state before any rewrite
#   - diagnose_repo                 : compare backup vs current, detect orphaned tags,
#                                     lost commits, missing releases
#   - find_equivalent_commit        : map an old commit to its closest match in new history
#   - fix_orphaned_tags             : re-anchor release/latest tags after history rewrite
#   - batch_restore_all             : restore every repo in a tracker file
#
# Tracker format (pipe-delimited, one repo per line):
#   repo_path|original_branch|original_commit|backup_tag_or_empty
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# Dual-mode bootstrap.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    source "$SCRIPT_DIR/lib/colours.sh"
    source "$SCRIPT_DIR/lib/print.sh"
fi

# Return (echo) the path to today's tracker file, creating the header if new.
batch_restore_tracker_path() {
    local today; today=$(date +%Y%m%d)
    local base="${TMPDIR:-/tmp}"
    local path="${base}/dc-fix-batch-${today}.tracker"
    if [[ ! -f "$path" ]]; then
        {
            echo "# dc-fix batch tracker — $(date -Iseconds)"
            echo "# Restore with: dc-fix --batch-restore $path"
        } > "$path"
    fi
    echo "$path"
}

# Record one repo's pre-run state.  Skips if already recorded (preserves first backup of day).
# Usage: batch_restore_record <tracker> <repo_path> <branch> <commit> [backup_tag]
batch_restore_record() {
    local tracker="$1" repo="$2" branch="$3" commit="$4" btag="${5:-}"
    [[ -z "$tracker" || ! -f "$tracker" ]] && return 0
    # Check if this repo is already recorded (first backup of day takes precedence).
    if grep -q "^${repo}|" "$tracker" 2>/dev/null; then
        return 0
    fi
    echo "${repo}|${branch}|${commit}|${btag}" >> "$tracker"
}

# Restore every repo listed in the tracker to its recorded pre-run state.
# Usage: batch_restore_all <tracker_file>
batch_restore_all() {
    local tracker="${1:-$(batch_restore_tracker_path)}"
    if [[ ! -f "$tracker" ]]; then
        print_error "Tracker file not found: $tracker"
        return 1
    fi

    print_info "Restoring batch from: $tracker"
    local orig_dir="$PWD"
    local restored=0 skipped=0

    while IFS='|' read -r repo branch commit btag; do
        [[ "$repo" == \#* || -z "$repo" ]] && continue
        if [[ ! -d "$repo" ]]; then
            print_warning "Repo not found: $repo — skipping"
            ((skipped++)) || true
            continue
        fi

        print_info "Restoring $repo → $branch @ ${commit:0:8}"
        pushd "$repo" > /dev/null || { print_warning "Cannot enter $repo"; ((skipped++)) || true; continue; }

        # Resolve restore ref: original commit → local backup tag → fetched backup tag.
        local restore_ref="$commit"
        if ! git cat-file -e "$commit" 2>/dev/null; then
            if [[ -n "$btag" ]]; then
                if git cat-file -e "refs/tags/$btag" 2>/dev/null; then
                    restore_ref="refs/tags/$btag"
                    print_info "  commit not reachable — using local backup tag: $btag"
                elif git fetch origin "refs/tags/${btag}:refs/tags/${btag}" &>/dev/null; then
                    restore_ref="refs/tags/$btag"
                    print_info "  fetched backup tag from origin: $btag"
                else
                    print_warning "  cannot resolve restore ref for $repo — skipping"
                    popd > /dev/null; ((skipped++)) || true; continue
                fi
            else
                print_warning "  original commit $commit not reachable and no backup tag recorded — skipping"
                popd > /dev/null; ((skipped++)) || true; continue
            fi
        fi

        local ok=true
        git checkout "$branch" 2>/dev/null || git checkout -b "$branch" 2>/dev/null || ok=false
        if [[ "$ok" == "true" ]]; then
            git reset --hard "$restore_ref" 2>/dev/null || ok=false
        fi

        if [[ "$ok" == "true" ]]; then
            if git remote get-url origin &>/dev/null && \
               git rev-parse --verify "refs/remotes/origin/$branch" &>/dev/null; then
                if git push --force-with-lease origin "$branch" 2>/dev/null; then
                    print_success "  Restored and pushed"
                else
                    print_warning "  Restored locally; push failed — run: git push --force-with-lease"
                fi
            else
                print_success "  Restored locally (no remote tracking)"
            fi
            ((restored++)) || true
        else
            print_warning "  Restore failed for $repo"
            ((skipped++)) || true
        fi

        popd > /dev/null || true
    done < "$tracker"

    cd "$orig_dir" || true
    print_success "Batch restore complete: ${restored} restored, ${skipped} skipped"
}

# ============================================================================
# DIAGNOSTIC AND RECOVERY
# ============================================================================

# Find the best matching commit in the current HEAD history for an old commit.
# Matches on identical subject first, then falls back to same date ± 60s.
# Usage: find_equivalent_commit <old_commit> [repo_path]
find_equivalent_commit() {
    local old_commit="$1" repo="${2:-.}"
    local old_subj old_epoch
    old_subj=$(git -C "$repo" log -1 --format="%s" "$old_commit" 2>/dev/null || echo "")
    old_epoch=$(git -C "$repo" log -1 --format="%at" "$old_commit" 2>/dev/null || echo "0")
    [[ -z "$old_subj" ]] && return
    # Exact subject match in current history
    local match
    match=$(git -C "$repo" log --format="%H %s" HEAD 2>/dev/null \
        | grep -F " ${old_subj}" | head -1 | awk '{print $1}')
    if [[ -n "$match" ]]; then
        echo "$match"; return
    fi
    # Date-proximity fallback (within 60s, same author)
    local old_author
    old_author=$(git -C "$repo" log -1 --format="%ae" "$old_commit" 2>/dev/null || echo "")
    while IFS=' ' read -r h epoch ae; do
        [[ "$ae" != "$old_author" ]] && continue
        local diff=$(( epoch - old_epoch )); (( diff < 0 )) && diff=$(( -diff ))
        if (( diff <= 60 )); then echo "$h"; return; fi
    done < <(git -C "$repo" log --format="%H %at %ae" HEAD 2>/dev/null)
}

# Diagnose a single repo: detect orphaned release/latest tags and other issues.
# Usage: diagnose_repo [repo_path] [--fix] [--dry-run]
# Returns: number of issues found (0 = clean).
diagnose_repo() {
    local repo="." fix=false dry=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --fix)     fix=true; shift ;;
            --dry-run) dry=true; shift ;;
            *)         repo="$1"; shift ;;
        esac
    done

    local label; label=$(git -C "$repo" config --get remote.origin.url 2>/dev/null \
        | sed 's|.*github\.com[:/]||;s|\.git$||' || basename "$repo")
    print_info "Diagnosing: $label"

    local issues=0

    # ── 1. Find backup baseline (prefer remote backup tag, then local, then tracker)
    local backup_ref=""
    local -a btags
    mapfile -t btags < <(git -C "$repo" tag -l 'backup/*' --sort=-creatordate 2>/dev/null)
    for t in "${btags[@]}"; do
        if git -C "$repo" cat-file -e "refs/tags/$t" 2>/dev/null; then
            backup_ref="refs/tags/$t"; break
        fi
    done
    if [[ -z "$backup_ref" ]]; then
        print_info "  No backup tag found — limited diagnosis only"
    else
        print_info "  Backup baseline: $backup_ref"
    fi

    # ── 2. Detect orphaned release/latest tags
    local -a rel_tags
    mapfile -t rel_tags < <(git -C "$repo" tag -l 'v*' 'latest' 2>/dev/null | sort -V)
    local -a orphaned_tags=()
    for tag in "${rel_tags[@]}"; do
        local tc; tc=$(git -C "$repo" rev-parse "${tag}^{}" 2>/dev/null || echo "")
        [[ -z "$tc" ]] && continue
        if ! git -C "$repo" merge-base --is-ancestor "$tc" HEAD 2>/dev/null; then
            local ts tm
            ts=$(git -C "$repo" log -1 --format="%aI" "$tc" 2>/dev/null || echo "?")
            tm=$(git -C "$repo" log -1 --format="%s"  "$tc" 2>/dev/null || echo "?")
            print_warning "  ORPHANED TAG: $tag → ${tc:0:8}  ($tm  @  $ts)"
            local equiv; equiv=$(find_equivalent_commit "$tc" "$repo")
            if [[ -n "$equiv" ]]; then
                local em; em=$(git -C "$repo" log -1 --format="%s" "$equiv" 2>/dev/null)
                print_info "    → equivalent in current history: ${equiv:0:8}  ($em)"
            else
                print_warning "    → no equivalent found in current history"
            fi
            orphaned_tags+=("$tag:$tc:$equiv")
            ((issues++)) || true
        fi
    done

    # ── 3. Commits present in backup but absent in current (net loss beyond squash)
    if [[ -n "$backup_ref" ]]; then
        local lost
        lost=$(git -C "$repo" log --oneline "${backup_ref}..HEAD" 2>/dev/null | wc -l)
        local gained
        gained=$(git -C "$repo" log --oneline "HEAD..${backup_ref}" 2>/dev/null | wc -l)
        if (( gained > 0 )); then
            print_warning "  $gained commit(s) in backup not reachable from current HEAD:"
            git -C "$repo" log --oneline "HEAD..${backup_ref}" 2>/dev/null | head -10 | sed 's/^/    /'
            ((issues++)) || true
        fi
    fi

    [[ $issues -eq 0 ]] && print_success "  Clean — no orphaned tags or lost commits"

    # ── 4. Apply fixes if requested
    if [[ "$fix" == "true" && ${#orphaned_tags[@]} -gt 0 ]]; then
        fix_orphaned_tags "$repo" "$dry" "${orphaned_tags[@]}"
    fi

    return $issues
}

# Re-anchor orphaned tags to their equivalents in the current history.
# Usage: fix_orphaned_tags <repo> <dry_run:true|false> [tag:oldcommit:equiv ...]
fix_orphaned_tags() {
    local repo="$1" dry="$2"; shift 2
    local fixed=0
    for entry in "$@"; do
        local tag oldtc equiv
        tag="${entry%%:*}"; rest="${entry#*:}"; oldtc="${rest%%:*}"; equiv="${rest#*:}"
        if [[ -z "$equiv" ]]; then
            print_warning "  Skipping $tag — no equivalent commit found"
            continue
        fi
        local em; em=$(git -C "$repo" log -1 --format="%s" "$equiv" 2>/dev/null)
        if [[ "$dry" == "true" ]]; then
            print_info "  [dry-run] would re-anchor $tag → ${equiv:0:8} ($em)"
            continue
        fi
        print_info "  Re-anchoring $tag → ${equiv:0:8} ($em)"
        git -C "$repo" tag -d "$tag" 2>/dev/null || true
        # Sign if GPG available, otherwise annotated
        if git -C "$repo" -c gpg.program=gpg tag -s "$tag" \
               -m "Re-anchored after history rewrite (was ${oldtc:0:8})" "$equiv" 2>/dev/null; then
            print_success "  Signed tag $tag created"
        else
            git -C "$repo" tag -a "$tag" \
                -m "Re-anchored after history rewrite (was ${oldtc:0:8})" "$equiv"
            print_info "  Unsigned tag $tag created"
        fi
        if git -C "$repo" remote get-url origin &>/dev/null; then
            git -C "$repo" push --force origin "refs/tags/$tag" 2>/dev/null && \
                print_success "  Pushed $tag to origin" || \
                print_warning "  Push failed — run: git push --force origin refs/tags/$tag"
        fi
        # Update GitHub release to point to new tag if gh available
        if command -v gh &>/dev/null; then
            local repo_slug
            repo_slug=$(git -C "$repo" remote get-url origin 2>/dev/null \
                | sed 's|.*github\.com[:/]||;s|\.git$||')
            if [[ -n "$repo_slug" ]]; then
                gh api -X PATCH "repos/${repo_slug}/releases/tags/${tag}" \
                    -f tag_name="$tag" 2>/dev/null && \
                    print_success "  GitHub release updated for $tag" || \
                    print_info "  Note: update GitHub release manually if needed"
            fi
        fi
        ((fixed++)) || true
    done
    [[ $fixed -gt 0 ]] && print_success "  $fixed tag(s) re-anchored"
}

# Diagnose all repos from a tracker file (or today's if none given).
# Usage: diagnose_batch [tracker_file] [--fix] [--dry-run]
diagnose_batch() {
    local tracker="" fix=false dry=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --fix)     fix=true; shift ;;
            --dry-run) dry=true; shift ;;
            *)         tracker="$1"; shift ;;
        esac
    done
    [[ -z "$tracker" ]] && tracker=$(batch_restore_tracker_path)
    if [[ ! -f "$tracker" ]]; then
        print_error "Tracker file not found: $tracker"
        return 1
    fi
    print_info "Batch diagnosis from: $tracker"
    local orig_dir="$PWD" total=0 issues=0
    while IFS='|' read -r repo branch commit btag; do
        [[ "$repo" == \#* || -z "$repo" ]] && continue
        [[ ! -d "$repo" ]] && { print_warning "Repo not found: $repo"; continue; }
        ((total++)) || true
        local fix_arg=(); [[ "$fix" == "true" ]] && fix_arg=(--fix)
        [[ "$dry" == "true" ]]  && fix_arg+=(--dry-run)
        diagnose_repo "$repo" "${fix_arg[@]}" || ((issues++)) || true
    done < "$tracker"
    cd "$orig_dir" || true
    echo ""
    if (( issues == 0 )); then
        print_success "All $total repos clean"
    else
        print_warning "$issues of $total repos have issues${fix:+ (fixes applied)}"
    fi
}

