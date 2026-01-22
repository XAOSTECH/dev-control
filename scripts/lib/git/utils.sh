#!/usr/bin/env bash
#
# Dev-Control Shared Library: Git Utilities
# Common git detection and URL parsing functions
#
# Usage:
#   source "${SCRIPT_DIR}/lib/git/utils.sh"
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

# ============================================================================
# BASIC GIT CHECKS
# ============================================================================

# Check if a directory is a git repository
# Usage: is_git_repo "/path/to/dir"
is_git_repo() {
    local dir="${1:-.}"
    [[ -d "$dir/.git" ]] || [[ -f "$dir/.git" ]]
}

# Check if current directory is inside a git worktree
# Usage: in_git_worktree
in_git_worktree() {
    git rev-parse --is-inside-work-tree &>/dev/null
}

# Get the root directory of the current git repository
# Usage: git_root
git_root() {
    git rev-parse --show-toplevel 2>/dev/null
}

# ============================================================================
# REQUIREMENT CHECKS (with error messages)
# ============================================================================

# Require being in a git repository (exits with error if not)
# Usage: require_git_repo
require_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Not a git repository."
        exit 1
    fi
}

# Require a clean working tree (no uncommitted changes)
# Usage: require_clean_worktree [allow_prompt]
require_clean_worktree() {
    local allow_prompt="${1:-false}"
    
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        if [[ "$allow_prompt" == "true" ]]; then
            print_warning "You have uncommitted changes."
            read -rp "Continue anyway? [y/N]: " response
            if [[ ! "$response" =~ ^[Yy] ]]; then
                exit 1
            fi
        else
            print_error "Working tree has uncommitted changes. Commit or stash first."
            exit 1
        fi
    fi
}

# Require GitHub CLI to be installed and authenticated
# Usage: require_gh_cli
require_gh_cli() {
    if ! command -v gh &> /dev/null; then
        print_error "GitHub CLI (gh) is not installed."
        echo -e "  Install with: ${CYAN}sudo apt install gh${NC} or ${CYAN}brew install gh${NC}"
        echo -e "  Then run: ${CYAN}gh auth login${NC}"
        exit 1
    fi
    
    if ! gh auth status &> /dev/null; then
        print_error "GitHub CLI is not authenticated."
        echo -e "  Run: ${CYAN}gh auth login${NC}"
        exit 1
    fi
}

# Require git to be installed
# Usage: require_git
require_git() {
    if ! command -v git &> /dev/null; then
        print_error "Git is not installed."
        exit 1
    fi
}

# ============================================================================
# REMOTE URL PARSING
# ============================================================================

# Get the remote origin URL
# Usage: get_remote_url [dir]
get_remote_url() {
    local dir="${1:-.}"
    git -C "$dir" config --get remote.origin.url 2>/dev/null || echo ""
}

# Parse GitHub owner/repo from a git URL
# Usage: parse_github_url "https://github.com/owner/repo.git"
# Returns: owner repo (space-separated)
parse_github_url() {
    local url="$1"
    local owner="" repo=""
    
    if [[ "$url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]%.git}"
    fi
    
    echo "$owner $repo"
}

# Get owner from remote URL
# Usage: get_repo_owner [dir]
get_repo_owner() {
    local dir="${1:-.}"
    local url
    url=$(get_remote_url "$dir")
    read -r owner _ <<< "$(parse_github_url "$url")"
    echo "$owner"
}

# Get repo name from remote URL
# Usage: get_repo_name [dir]
get_repo_name() {
    local dir="${1:-.}"
    local url
    url=$(get_remote_url "$dir")
    read -r _ repo <<< "$(parse_github_url "$url")"
    echo "$repo"
}

# ============================================================================
# BRANCH OPERATIONS
# ============================================================================

# Get current branch name
# Usage: get_current_branch
get_current_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
}

# Get default branch (main/master/Main)
# Usage: get_default_branch
get_default_branch() {
    local default
    default=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    
    if [[ -z "$default" ]]; then
        if git show-ref --verify --quiet refs/heads/main; then
            default="main"
        elif git show-ref --verify --quiet refs/heads/Main; then
            default="Main"
        elif git show-ref --verify --quiet refs/heads/master; then
            default="master"
        fi
    fi
    
    echo "${default:-main}"
}

# Check if a branch exists locally
# Usage: branch_exists "branch-name"
branch_exists() {
    local branch="$1"
    git show-ref --verify --quiet "refs/heads/$branch"
}

# Check if a branch exists on remote
# Usage: remote_branch_exists "branch-name" [remote]
remote_branch_exists() {
    local branch="$1"
    local remote="${2:-origin}"
    git ls-remote --heads "$remote" "$branch" 2>/dev/null | grep -q "$branch"
}

# Require not being on default branch (for PR creation)
# Usage: require_feature_branch
require_feature_branch() {
    local current
    current=$(get_current_branch)
    local default
    default=$(get_default_branch)
    
    if [[ "$current" == "$default" ]] || [[ "$current" == "main" ]] || [[ "$current" == "master" ]]; then
        print_error "You are on the default branch ($current). Create a feature branch first."
        exit 1
    fi
}

# ============================================================================
# WORKTREE STATUS
# ============================================================================

# Check if there are uncommitted changes
# Usage: has_uncommitted_changes
has_uncommitted_changes() {
    ! git diff-index --quiet HEAD -- 2>/dev/null
}

# Check if there are staged changes
# Usage: has_staged_changes
has_staged_changes() {
    ! git diff --cached --quiet 2>/dev/null
}

# Check if there are untracked files
# Usage: has_untracked_files
has_untracked_files() {
    [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]
}

# Get short status summary
# Usage: get_status_summary
get_status_summary() {
    local staged=0 modified=0 untracked=0
    
    staged=$(git diff --cached --numstat 2>/dev/null | wc -l)
    modified=$(git diff --numstat 2>/dev/null | wc -l)
    untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)
    
    echo "staged:$staged modified:$modified untracked:$untracked"
}

# ============================================================================
# SUBMODULE UTILITIES
# ============================================================================

# Get relative path from one directory to another
# Usage: get_relative_path "/parent" "/parent/child/sub"
get_relative_path() {
    local parent="$1"
    local child="$2"
    echo "${child#$parent/}"
}

# List all submodules in a repository
# Usage: list_submodules [dir]
list_submodules() {
    local dir="${1:-.}"
    git -C "$dir" submodule status 2>/dev/null | awk '{print $2}'
}

# Check if a path is a submodule
# Usage: is_submodule "path/to/check"
is_submodule() {
    local path="$1"
    git ls-files --stage | grep -q "^160000.*$path\$"
}

# ============================================================================
# COMMIT UTILITIES
# ============================================================================

# Get short hash for a commit
# Usage: get_short_hash "full-hash-or-ref"
get_short_hash() {
    local ref="${1:-HEAD}"
    git rev-parse --short "$ref" 2>/dev/null || echo "${ref:0:7}"
}

# Get commit subject
# Usage: get_commit_subject "hash-or-ref"
get_commit_subject() {
    local ref="${1:-HEAD}"
    git log -1 --format='%s' "$ref" 2>/dev/null || echo ""
}

# Get commit author
# Usage: get_commit_author "hash-or-ref"
get_commit_author() {
    local ref="${1:-HEAD}"
    git log -1 --format='%an <%ae>' "$ref" 2>/dev/null || echo ""
}

# Get commit date (ISO format)
# Usage: get_commit_date "hash-or-ref"
get_commit_date() {
    local ref="${1:-HEAD}"
    git log -1 --format='%aI' "$ref" 2>/dev/null || echo ""
}
