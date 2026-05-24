#!/usr/bin/env bash
#
# Dev-Control Shared Library: Rewrite — conflict resolution helpers used during git history rewriting operations.
#
# Required globals when sourced (set by the caller):
#   NO_EDIT_MODE       — if true, skip editor prompts
#   DRY_RUN            — if true, show what would be done without executing
#
# Required functions when sourced:
#   print_info(), print_success(), print_warning(), print_error()
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
# CONFLICT RESOLUTION
# ============================================================================

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

# Repeatedly attempt auto-resolution until rebase finishes or we hit an error
# mode: 'ours' or 'theirs'
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
