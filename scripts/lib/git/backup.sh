#!/usr/bin/env bash
#
# Dev-Control Shared Library: Git Backup Utilities
# Functions for creating and managing git backup bundles
#
# Usage:
#   source "${SCRIPT_DIR}/lib/git/backup.sh"
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# Ensure print functions are available (source print.sh before this)
# shellcheck disable=SC2034

# ============================================================================
# BUNDLE CREATION
# ============================================================================

# Create a backup bundle of the entire repository
# Usage: create_backup_bundle [output_path]
# Returns: Path to created bundle
create_backup_bundle() {
    local output="${1:-/tmp/git-backup-$(date -u +%Y%m%dT%H%M%SZ).bundle}"
    
    print_info "Creating backup bundle..."
    if git bundle create "$output" --all; then
        print_success "Backup saved: $output"
        echo "$output"
        return 0
    else
        print_error "Failed to create backup bundle"
        return 1
    fi
}

# Create a backup bundle of a specific branch
# Usage: create_branch_bundle "branch-name" [output_path]
# Returns: Path to created bundle
create_branch_bundle() {
    local branch="$1"
    local ts
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    local output="${2:-/tmp/git-branch-backup-${branch//\//-}-${ts}.bundle}"
    
    print_info "Creating backup bundle for branch: $branch"
    if git bundle create "$output" "refs/heads/$branch"; then
        print_success "Branch backup saved: $output"
        echo "$output"
        return 0
    else
        print_error "Failed to create branch bundle"
        return 1
    fi
}

# Create a backup bundle of a specific ref (tag, branch, or commit)
# Usage: create_ref_bundle "ref" [output_path]
# Returns: Path to created bundle
create_ref_bundle() {
    local ref="$1"
    local ts
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    local safe_name="${ref//\//-}"
    local output="${2:-/tmp/git-ref-backup-${safe_name}-${ts}.bundle}"
    
    print_info "Creating backup bundle for ref: $ref"
    if git bundle create "$output" "$ref"; then
        print_success "Ref backup saved: $output"
        echo "$output"
        return 0
    else
        print_error "Failed to create ref bundle"
        return 1
    fi
}

# ============================================================================
# BUNDLE DISCOVERY
# ============================================================================

# List available backup bundles in /tmp
# Usage: list_backup_bundles [pattern]
# Returns: Newline-separated list of bundle paths
list_backup_bundles() {
    local pattern="${1:-git-*backup*.bundle}"
    ls -1 /tmp/${pattern} 2>/dev/null || true
}

# List bundle contents (refs it contains)
# Usage: show_bundle_contents "bundle_path"
show_bundle_contents() {
    local bundle="$1"
    
    if [[ ! -f "$bundle" ]]; then
        print_error "Bundle not found: $bundle"
        return 1
    fi
    
    print_info "Bundle contents: $bundle"
    git bundle list-heads "$bundle"
}

# Verify a bundle is valid and complete
# Usage: verify_bundle "bundle_path"
verify_bundle() {
    local bundle="$1"
    
    if [[ ! -f "$bundle" ]]; then
        print_error "Bundle not found: $bundle"
        return 1
    fi
    
    if git bundle verify "$bundle" 2>/dev/null; then
        print_success "Bundle is valid: $bundle"
        return 0
    else
        print_warning "Bundle may be incomplete or corrupt: $bundle"
        return 1
    fi
}

# ============================================================================
# BUNDLE RESTORATION
# ============================================================================

# Restore refs from a bundle (unbundle)
# Usage: unbundle "bundle_path"
unbundle() {
    local bundle="$1"
    
    if [[ ! -f "$bundle" ]]; then
        print_error "Bundle not found: $bundle"
        return 1
    fi
    
    print_info "Restoring from bundle: $bundle"
    if git bundle unbundle "$bundle"; then
        print_success "Bundle restored successfully"
        return 0
    else
        print_error "Failed to restore bundle"
        return 1
    fi
}

# Create a branch from a bundle ref
# Usage: create_branch_from_bundle "bundle_path" "ref_in_bundle" "new_branch_name"
create_branch_from_bundle() {
    local bundle="$1"
    local ref="$2"
    local new_branch="$3"
    
    if [[ ! -f "$bundle" ]]; then
        print_error "Bundle not found: $bundle"
        return 1
    fi
    
    print_info "Fetching $ref from bundle to create branch $new_branch"
    if git fetch "$bundle" "$ref:refs/heads/$new_branch"; then
        print_success "Created branch: $new_branch"
        return 0
    else
        print_error "Failed to create branch from bundle"
        return 1
    fi
}

# ============================================================================
# BACKUP TAG MANAGEMENT
# ============================================================================

# Create a backup tag for the current state of a branch
# Usage: create_backup_tag "branch_name" [prefix]
# Returns: Tag name created
create_backup_tag() {
    local branch="$1"
    local prefix="${2:-backup}"
    local ts
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    local tag_name="${prefix}/${branch//\//-}-${ts}"
    
    print_info "Creating backup tag: $tag_name"
    if git tag -f "$tag_name" "refs/heads/$branch" 2>/dev/null; then
        print_success "Created tag: $tag_name"
        echo "$tag_name"
        return 0
    else
        print_error "Failed to create backup tag"
        return 1
    fi
}

# List all backup tags
# Usage: list_backup_tags [prefix]
list_backup_tags() {
    local prefix="${1:-backup}"
    git tag -l "${prefix}/*" 2>/dev/null || true
}

# Push backup tag to remote
# Usage: push_backup_tag "tag_name" [remote]
push_backup_tag() {
    local tag="$1"
    local remote="${2:-origin}"
    
    print_info "Pushing backup tag: $tag"
    if git push "$remote" "refs/tags/$tag"; then
        print_success "Pushed tag: $tag"
        return 0
    else
        print_warning "Failed to push backup tag"
        return 1
    fi
}
