#!/usr/bin/env bash
#
# Dev-Control Shared Library: Restore — list and restore from backup bundles
# and tags created by previous fix-history runs.
#
# Required from the caller:
#   - print.sh / colours.sh sourced (print_info/print_success/print_warning/
#     print_error/print_header)
#   - check_git_repo function
#   - Globals: DRY_RUN
#   - File descriptor 3 (interactive prompts)
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# ============================================================================
# RESTORE — list/restore backup bundles, tags and tmp branches
# ============================================================================

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

    print_error "Candidate not recognised or missing: $candidate"
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
