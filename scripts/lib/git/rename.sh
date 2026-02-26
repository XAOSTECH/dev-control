#!/usr/bin/env bash
#
# Batch rename Main -> main across repositories
#
# Usage:
#   rename.sh [OWNER] [OLD_BRANCH] [NEW_BRANCH] [PATHS...]
#   rename.sh xaoscience Main main /path/to/repo1 /path/to/repo2
#   rename.sh xaoscience Main main  # Auto-discover from GitHub
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEV_CONTROL_DIR="$(dirname "$LIB_DIR")"
export DEV_CONTROL_DIR

# Source shared libraries
source "$LIB_DIR/lib/colours.sh"
source "$LIB_DIR/lib/print.sh"

# Parse arguments
OWNER=""
OLD_BRANCH=""
NEW_BRANCH=""
REPO_PATHS=()
DRY_RUN=false

# Argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            cat << 'EOF'
Branch Renaming Tool - Rename default branches across repositories

USAGE:
  rename.sh [OPTIONS] [OWNER] [BRANCH_SPEC] [PATHS...]

ARGUMENTS:
  OWNER         GitHub user/org (default: current gh user)
  BRANCH_SPEC   Branch rename in format:
                  Main:main   - Rename Main to main
                  Main->main  - Rename Main to main
                  Main main   - Rename Main to main (two args)
                  main        - Auto-detect old branch, rename to main
  PATHS         Local repo paths (if omitted, fetches from GitHub)

OPTIONS:
  -n, --dry-run     Show what would be done without making changes
  -h, --help        Show this help

EXAMPLES:
  rename.sh                              # Auto-detect everything
  rename.sh xaoscience Main:main         # Rename Main to main
  rename.sh Main:main ~/repos/*          # Local repos only
  rename.sh -n xaoscience Main:main      # Dry run
  rename.sh "" Main:main ~/proj1 ~/proj2 # Multiple local repos
  rename.sh xaoscience main              # Auto-detect old, rename to main

NOTES:
  - Works with local repos (no cloning required)
  - Auto-detects current default branch if not specified
  - Skips repos that already use the target branch
  - Updates GitHub default branch setting

EOF
            exit 0
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            # Check if it's a branch spec (contains : or ->)
            if [[ "$1" =~ ^([^:]+):([^:]+)$ ]]; then
                # Format: Main:main
                OLD_BRANCH="${BASH_REMATCH[1]}"
                NEW_BRANCH="${BASH_REMATCH[2]}"
                shift
            elif [[ "$1" =~ ^([^-]+)-\>(.+)$ ]]; then
                # Format: Main->main
                OLD_BRANCH="${BASH_REMATCH[1]}"
                NEW_BRANCH="${BASH_REMATCH[2]}"
                shift
            elif [[ -z "$OWNER" ]]; then
                OWNER="$1"
                shift
            elif [[ -z "$NEW_BRANCH" ]]; then
                # Could be either old_branch or new_branch
                if [[ -z "$OLD_BRANCH" ]]; then
                    # If next arg looks like a branch or is missing, this is new_branch only
                    if [[ $# -eq 1 ]] || [[ "$2" == /* ]] || [[ "$2" == .* ]] || [[ -d "$2" ]]; then
                        NEW_BRANCH="$1"
                    else
                        OLD_BRANCH="$1"
                    fi
                else
                    NEW_BRANCH="$1"
                fi
                shift
            else
                # Must be a path
                REPO_PATHS+=("$1")
                shift
            fi
            ;;
    esac
done

# Set defaults
OWNER="${OWNER:-$(gh api user --jq '.login' 2>/dev/null || echo "")}"
NEW_BRANCH="${NEW_BRANCH:-main}"

if [[ "$DRY_RUN" == "true" ]]; then
    print_warning "DRY RUN MODE - No changes will be made"
fi

print_header "Branch Renaming Tool"

# Function to detect default branch in a git repo
detect_default_branch() {
    local repo_path="$1"
    local branch
    
    pushd "$repo_path" &>/dev/null || return 1
    
    # Try to get remote default branch
    branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    
    # Fallback to current branch
    if [[ -z "$branch" ]]; then
        branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
    fi
    
    popd &>/dev/null || true
    echo "$branch"
}

# Function to get repo name from path
get_repo_name() {
    local repo_path="$1"
    basename "$(cd "$repo_path" && git rev-parse --show-toplevel 2>/dev/null || echo "$repo_path")"
}

# Function to rename branch in a single repo
rename_repo_branch() {
    local repo_path="$1"
    local old_branch="$2"
    local new_branch="$3"
    local repo_name="$4"
    
    print_separator
    print_section "Processing: $repo_name"
    print_info "Path: $repo_path"
    
    pushd "$repo_path" &>/dev/null || {
        print_error "Failed to access directory: $repo_path"
        return 1
    }
    
    # Verify it's a git repo
    if [[ ! -d ".git" ]]; then
        print_error "Not a git repository: $repo_path"
        popd &>/dev/null || true
        return 1
    fi
    
    # Auto-detect old branch if not specified
    if [[ -z "$old_branch" ]]; then
        old_branch=$(detect_default_branch ".")
        if [[ -z "$old_branch" ]]; then
            print_warning "Could not detect default branch, skipping"
            popd &>/dev/null || true
            return 1
        fi
        print_info "Detected branch: $old_branch"
    fi
    
    # Check if already on target branch
    if [[ "$old_branch" == "$new_branch" ]]; then
        print_success "Already using '$new_branch', skipping"
        popd &>/dev/null || true
        return 0
    fi
    
    # Fetch latest from remote
    if git remote get-url origin &>/dev/null; then
        print_info "Fetching from remote..."
        git fetch origin --prune --prune-tags 2>/dev/null || print_warning "Failed to fetch (continuing anyway)"
    fi
    
    # Check if old branch exists
    if ! git show-ref --verify --quiet "refs/heads/$old_branch"; then
        print_warning "Branch '$old_branch' doesn't exist locally, checking remote..."
        if git show-ref --verify --quiet "refs/remotes/origin/$old_branch"; then
            print_info "Checking out $old_branch from remote..."
            git checkout -b "$old_branch" "origin/$old_branch" 2>/dev/null || {
                print_error "Failed to checkout $old_branch"
                popd &>/dev/null || true
                return 1
            }
        else
            print_warning "Branch '$old_branch' not found, skipping"
            popd &>/dev/null || true
            return 1
        fi
    fi
    
    # Checkout old branch if not already on it
    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
    if [[ "$current_branch" != "$old_branch" ]]; then
        print_info "Checking out $old_branch..."
        git checkout "$old_branch" 2>/dev/null || {
            print_error "Failed to checkout $old_branch"
            popd &>/dev/null || true
            return 1
        }
    fi
    
    # Check for tag conflicts
    if git show-ref --verify --quiet "refs/tags/$new_branch"; then
        print_warning "Local tag '$new_branch' exists and will cause push conflicts"
        if [[ "$DRY_RUN" != "true" ]]; then
            print_info "Deleting local tag '$new_branch'..."
            git tag -d "$new_branch" 2>/dev/null || print_warning "Could not delete tag"
        else
            print_info "[DRY RUN] Would delete local tag '$new_branch'"
        fi
    fi
    
    # Rename locally
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] Would rename $old_branch → $new_branch locally"
    else
        print_info "Renaming $old_branch → $new_branch locally..."
        git branch -m "$old_branch" "$new_branch"
    fi
    
    # Push new branch to remote if remote exists
    if git remote get-url origin &>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "[DRY RUN] Would push $new_branch to remote"
            print_info "[DRY RUN] Would update GitHub default branch"
            print_info "[DRY RUN] Would delete $old_branch from remote"
            print_success "[DRY RUN] ✓ $repo_name: $old_branch → $new_branch"
        else
            print_info "Pushing $new_branch to remote..."
            # Use refs/heads/ explicitly to avoid tag conflicts
            if git push origin "refs/heads/$new_branch:refs/heads/$new_branch"; then
                # Set upstream tracking
                git branch --set-upstream-to="origin/$new_branch" "$new_branch"
                
                # Try to update default branch on GitHub
                if command -v gh &>/dev/null && [[ -n "$OWNER" ]]; then
                    print_info "Updating default branch on GitHub..."
                    
                    # Debug: show what we're trying
                    local api_response
                    api_response=$(gh api "repos/$OWNER/$repo_name" -X PATCH -f default_branch="$new_branch" 2>&1)
                    local api_status=$?
                    
                    if [[ $api_status -eq 0 ]]; then
                        print_success "Default branch updated to $new_branch on GitHub"
                        
                        # Wait for GitHub to propagate the change
                        print_info "Waiting for GitHub to update..."
                        sleep 2
                        
                        # Delete old branch from remote (safe now that it's not default)
                        print_info "Deleting $old_branch from remote..."
                        if git push origin --delete "$old_branch" 2>/dev/null; then
                            print_success "Old branch $old_branch deleted from remote"
                        else
                            print_warning "Could not delete remote branch (may need more time)"
                            print_info "Try manually: git push origin --delete $old_branch"
                        fi
                    else
                        print_warning "Could not update GitHub default branch"
                        
                        # Diagnose the issue
                        if echo "$api_response" | grep -q "Not Found"; then
                            print_error "Repository not found: $OWNER/$repo_name"
                            print_info "Check that owner name matches exactly (case-sensitive)"
                        elif echo "$api_response" | grep -q "Must have admin"; then
                            print_error "Insufficient permissions - need admin access to $OWNER/$repo_name"
                        elif echo "$api_response" | grep -q "Requires authentication"; then
                            print_error "Not authenticated - run: gh auth login"
                        else
                            print_warning "API error: $api_response"
                        fi
                        
                        print_info "Manually update at: https://github.com/$OWNER/$repo_name/settings/branches"
                        print_warning "Cannot delete $old_branch from remote (it's still the default branch)"
                        print_info "After updating default branch on GitHub, run:"
                        print_info "  git push origin --delete $old_branch"
                    fi
                else
                    print_warning "GitHub CLI not available, cannot update default branch"
                    print_info "Manually update at: https://github.com/$OWNER/$repo_name/settings/branches"
                fi
                
                print_success "✓ $repo_name: $old_branch → $new_branch"
            else
                print_error "Failed to push to remote"
                # Revert local rename on push failure
                git branch -m "$new_branch" "$old_branch"
                popd &>/dev/null || true
                return 1
            fi
        fi
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            print_warning "[DRY RUN] No remote configured, would rename locally only"
            print_success "[DRY RUN] ✓ $repo_name: $old_branch → $new_branch (local only)"
        else
            print_warning "No remote configured, renamed locally only"
            print_success "✓ $repo_name: $old_branch → $new_branch (local only)"
        fi
    fi
    
    popd &>/dev/null || true
    echo ""
    return 0
}

# Main execution
if [[ ${#REPO_PATHS[@]} -gt 0 ]]; then
    # Local mode: process specified paths
    print_info "Local mode: Processing ${#REPO_PATHS[@]} repositories"
    
    if [[ -n "$OLD_BRANCH" ]]; then
        print_info "Renaming: $OLD_BRANCH → $NEW_BRANCH"
    else
        print_info "Auto-detecting branches, renaming to: $NEW_BRANCH"
    fi
    
    echo ""
    for repo_path in "${REPO_PATHS[@]}"; do
        repo_name=$(get_repo_name "$repo_path")
        rename_repo_branch "$repo_path" "$OLD_BRANCH" "$NEW_BRANCH" "$repo_name"
    done
    
else
    # GitHub mode: fetch repos from GitHub
    if [[ -z "$OWNER" ]]; then
        print_error "No owner specified and gh CLI not configured"
        print_info "Usage: rename.sh OWNER [OLD_BRANCH] [NEW_BRANCH] [PATHS...]"
        exit 1
    fi
    
    # Auto-detect old branch if not specified
    if [[ -z "$OLD_BRANCH" ]]; then
        print_warning "No branch specified, detecting from GitHub repos..."
        # Get most common default branch
        OLD_BRANCH=$(gh repo list "$OWNER" --limit 1000 --json defaultBranchRef --jq '.[].defaultBranchRef.name' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
        if [[ -z "$OLD_BRANCH" ]]; then
            print_error "Could not auto-detect branch"
            exit 1
        fi
        print_info "Detected most common branch: $OLD_BRANCH"
    fi
    
    print_info "GitHub mode: Renaming $OLD_BRANCH → $NEW_BRANCH for $OWNER"
    
    # Get all repos with the old branch
    print_info "Fetching repositories from GitHub..."
    REPOS=$(gh repo list "$OWNER" --limit 1000 --json name,defaultBranchRef --jq ".[] | select(.defaultBranchRef.name == \"$OLD_BRANCH\") | .name")
    
    if [[ -z "$REPOS" ]]; then
        print_warning "No repositories found with default branch '$OLD_BRANCH'"
        exit 0
    fi
    
    echo ""
    print_info "Found repositories with '$OLD_BRANCH' branch:"
    echo "$REPOS" | while read -r repo; do
        echo "  - $repo"
    done
    echo ""
    
    if ! confirm "Rename $OLD_BRANCH → $NEW_BRANCH for all these repos?"; then
        print_info "Aborted"
        exit 0
    fi
    
    # Process each repo
    echo "$REPOS" | while read -r repo; do
        # Check if we have it locally
        if [[ -d "$repo" ]]; then
            rename_repo_branch "$repo" "$OLD_BRANCH" "$NEW_BRANCH" "$repo"
        else
            # Need to clone
            print_separator
            print_section "Processing: $OWNER/$repo"
            print_info "Not found locally, cloning..."
            
            if gh repo clone "$OWNER/$repo" "$repo"; then
                rename_repo_branch "$repo" "$OLD_BRANCH" "$NEW_BRANCH" "$repo"
            else
                print_error "Failed to clone $repo"
                echo ""
            fi
        fi
    done
fi

print_header_success "Branch Renaming Complete!"
print_info "All repositories now use '$NEW_BRANCH' as default branch"
