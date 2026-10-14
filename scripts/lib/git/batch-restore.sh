#!/usr/bin/env bash
#
# Dev-Control Shared Library: Batch Restore
# Records original repo state before a batch full-fix run and restores all repos from it.
#
# Design: one tracker file per calendar day; the FIRST batch run of the day creates it.
# Subsequent runs append only repos not already recorded, so the first (clean) baseline
# is always preserved even if the user re-runs after a partial failure.
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
