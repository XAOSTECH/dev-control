#!/usr/bin/env bash
#
# Git-Control Shared Library: Git Utilities
# Common git detection and URL parsing functions
#
# Usage:
#   source "${SCRIPT_DIR}/lib/git-utils.sh"
#

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

# Get current branch name
# Usage: get_current_branch
get_current_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
}

# Get default branch (main/master)
# Usage: get_default_branch
get_default_branch() {
    # Try to get from remote HEAD
    local default
    default=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    
    if [[ -z "$default" ]]; then
        # Fallback: check for common branch names
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

# Check if there are uncommitted changes
# Usage: has_uncommitted_changes
has_uncommitted_changes() {
    ! git diff-index --quiet HEAD -- 2>/dev/null
}

# Check if there are untracked files
# Usage: has_untracked_files
has_untracked_files() {
    [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]
}

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
