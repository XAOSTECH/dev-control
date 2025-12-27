#!/usr/bin/env bash
#
# Git-Control Module Nesting Script
# Automatically manage .gitmodules for nested Git repositories
#
# This script scans a directory hierarchy for Git repositories and generates
# proper .gitmodules files for each parent repository, handling nested submodules.
#
# Usage:
#   ./module-nesting.sh [ROOT_DIR]
#
# If ROOT_DIR is not provided, the script will prompt for input or use CWD.
#

set -e

# Make sure ERR is traced in functions
set -o errtrace

# Trap errors and print useful context
trap 'last_cmd="$BASH_COMMAND"; print_error "ERROR: \"${last_cmd}\" at line ${BASH_LINENO[0]} in ${FUNCNAME[1]:-main}"' ERR

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

print_header() {
    echo -e "\n${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║${NC}         ${CYAN}Git-Control Module Nesting Manager${NC}                  ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    if [[ "${DEBUG:-false}" == "true" || "${DEBUG:-false}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}

# ============================================================================
# GIT DETECTION FUNCTIONS
# ============================================================================

# Check if a directory is a git repository (has .git folder or file)
is_git_repo() {
    local dir="$1"
    [[ -d "$dir/.git" ]] || [[ -f "$dir/.git" ]]
}

# Directories to skip (noisy or irrelevant)
EXCLUDE_DIRS=(.tmp .devcontainer .vscode node_modules .cache)

should_skip_dir() {
    local dname
    dname=$(basename "$1")
    for e in "${EXCLUDE_DIRS[@]}"; do
        [[ "$dname" == "$e" ]] && return 0
    done
    return 1
}

# Check if a directory is the root of a git worktree
is_git_worktree_root() {
    local dir="$1"
    if [[ -f "$dir/.git" ]]; then
        # This is a submodule or worktree (uses gitdir file)
        return 0
    elif [[ -d "$dir/.git" ]]; then
        return 0
    fi
    return 1
}

# Get the remote origin URL for a git repository
get_remote_url() {
    local dir="$1"
    local url=""
    
    if is_git_repo "$dir"; then
        url=$(git -C "$dir" config --get remote.origin.url 2>/dev/null || echo "")
    fi
    
    echo "$url"
}

get_submodule_name() {
    local path="$1"
    local name

    name=$(basename "$path")

    # Convert spaces to underscores and strip any remaining invalid chars
    name=$(echo "$name" | tr ' ' '_' | tr -cd '[:alnum:]._-')

    echo "$name"
}

get_relative_path() {
    local parent="$1"
    local child="$2"
    
    local relative="${child#$parent/}"
    
    echo "$relative"
}

# ============================================================================
# SUBMODULE DISCOVERY
# ============================================================================

# Find all git repositories under a directory (direct children only for submodules)
find_direct_git_children() {
    local parent_dir="$1"
    local git_children=()
    
    for dir in "$parent_dir"/*/; do
        [[ -d "$dir" ]] || continue
        dir="${dir%/}"
        # Skip noisy directories
        if should_skip_dir "$dir"; then
            print_debug "Skipping excluded dir: $dir"
            continue
        fi

        if is_git_repo "$dir"; then
            git_children+=("$dir")
        fi
    done
    
    echo "${git_children[@]}"
}

# Find all git repositories recursively
find_all_git_repos() {
    local root_dir="$1"
    local repos=()
    
    while IFS= read -r -d '' git_dir; do
        local repo_dir=$(dirname "$git_dir")
        repos+=("$repo_dir")
    done < <(find "$root_dir" -name ".git" -print0 2>/dev/null)
    
    echo "${repos[@]}"
}

# ============================================================================
# GITMODULES GENERATION
# ============================================================================

# Generate .gitmodules content for a repository
generate_gitmodules() {
    local repo_dir="$1"
    local root_dir="$2"
    local content=""
    local submodule_count=0
    
    print_debug "generate_gitmodules: repo_dir=$repo_dir root_dir=$root_dir"
    # Find direct git children (submodules)
    for child_dir in "$repo_dir"/*/; do
        [[ -d "$child_dir" ]] || continue
        child_dir="${child_dir%/}"
        # Skip noisy directories
        if should_skip_dir "$child_dir"; then
            print_debug "Skipping excluded dir: $child_dir"
            continue
        fi

        # Recursively check for git repos in this subtree
        # We need to find the first git repos under this directory
        find_git_repos_for_parent "$repo_dir" "$child_dir" "$root_dir" content submodule_count
    done
    
    echo "$content"
}

# Recursive function to find git repos that should be submodules of parent
find_git_repos_for_parent() {
    local parent_repo="$1"
    local current_dir="$2"
    local root_dir="$3"
    # Keep the original variable names so recursive calls can pass them.
    local content_name="$4"
    local count_name="$5"
    local -n content_ref="$content_name"
    local -n count_ref="$count_name"
    print_debug "ENTER find_git_repos_for_parent parent=${parent_repo} current=${current_dir} root=${root_dir} (content=${content_name} count=${count_name})"
    
    # If this is a git repo, add it as a submodule
    if is_git_repo "$current_dir"; then
        local rel_path=$(get_relative_path "$parent_repo" "$current_dir")
        local name=$(get_submodule_name "$current_dir")
        local url=$(get_remote_url "$current_dir")
        
        # If no remote URL, use relative path from root
        if [[ -z "$url" ]]; then
            url=$(get_relative_path "$root_dir" "$current_dir")
        fi
        
        content_ref+="[submodule \"$name\"]"$'\n'
        content_ref+="	path = $rel_path"$'\n'
        content_ref+="	url = $url"$'\n'
        content_ref+=$'\n'
        
        # Increment the caller's counter without triggering 'set -e' when the
        # previous value is 0 (using arithmetic expansion with direct assignment)
        count_ref=$((count_ref + 1))
        print_debug "count_ref now: ${count_ref} (parent_repo=${parent_repo}, current_dir=${current_dir})"
        print_debug "Added submodule: name=${name} rel_path=${rel_path} url=${url}"
        print_debug "Returning from find_git_repos_for_parent: parent=${parent_repo} current=${current_dir}"
        # Don't recurse into this git repo (it has its own submodules)
        return
    fi
    
    # Not a git repo, check subdirectories
    for subdir in "$current_dir"/*/; do
        [[ -d "$subdir" ]] || continue
        subdir="${subdir%/}"
        # Skip noisy directories
        if should_skip_dir "$subdir"; then
            print_debug "Skipping excluded dir: $subdir"
            continue
        fi
        print_debug "Recursing into subdir: $subdir (parent=${parent_repo})"
        find_git_repos_for_parent "$parent_repo" "$subdir" "$root_dir" "$content_name" "$count_name"
    done
}

# Write .gitmodules file
write_gitmodules() {
    local repo_dir="$1"
    local content="$2"
    local gitmodules_path="$repo_dir/.gitmodules"
    
    if [[ -z "$content" ]]; then
        # No submodules found - remove .gitmodules if it exists
        if [[ -f "$gitmodules_path" ]]; then
            print_info "No submodules found in $(basename "$repo_dir") - removing .gitmodules"
            rm "$gitmodules_path"
        fi
        return
    fi
    
    print_debug "Writing .gitmodules to $gitmodules_path (content length: ${#content} chars)"
    print_debug "First line of content: $(printf '%s' "$content" | sed -n '1p')"
    echo -e "$content" > "$gitmodules_path"
    print_success "Generated .gitmodules for: $(basename "$repo_dir")"
}

# ============================================================================
# MAIN PROCESSING
# ============================================================================

process_repository() {
    local repo_dir="$1"
    local root_dir="$2"
    local depth="$3"
    local indent=""
    
    for ((i=0; i<depth; i++)); do
        indent+="  "
    done
    
    print_info "${indent}Processing: $(get_relative_path "$root_dir" "$repo_dir")"
    print_debug "ENTER process_repository repo=${repo_dir} root=${root_dir} depth=${depth}"
    
    # Generate and write .gitmodules for this repository
    local content=""
    local submodule_count=0
    
    # Find all git repos that should be submodules of this repo
    for child in "$repo_dir"/*/; do
        [[ -d "$child" ]] || continue
        child="${child%/}"
        
        # Skip .git directory
        [[ "$(basename "$child")" == ".git" ]] && continue
        
        # Skip noisy directories
        if should_skip_dir "$child"; then
            print_debug "Skipping excluded dir: $child"
            continue
        fi

        find_git_repos_for_parent "$repo_dir" "$child" "$root_dir" content submodule_count
    done
    
    if [[ $submodule_count -gt 0 ]]; then
        write_gitmodules "$repo_dir" "$content"
        print_info "${indent}  Found $submodule_count submodule(s)"
    else
        # Remove empty .gitmodules if exists
        if [[ -f "$repo_dir/.gitmodules" ]]; then
            rm "$repo_dir/.gitmodules"
            print_info "${indent}  Removed empty .gitmodules"
        fi
    fi
    
    # Recursively process nested git repositories
    for child in "$repo_dir"/*/; do
        [[ -d "$child" ]] || continue
        child="${child%/}"
        
        # Skip noisy directories
        if should_skip_dir "$child"; then
            print_debug "Skipping excluded dir: $child"
            continue
        fi

        if is_git_repo "$child"; then
            process_repository "$child" "$root_dir" $((depth + 1))
        else
            # Check if any nested folders are git repos
            for nested in "$child"/*/; do
                [[ -d "$nested" ]] || continue
                nested="${nested%/}"
                # Skip noisy nested dirs
                if should_skip_dir "$nested"; then
                    print_debug "Skipping excluded nested dir: $nested"
                    continue
                fi
                if is_git_repo "$nested"; then
                    process_repository "$nested" "$root_dir" $((depth + 1))
                fi
            done
        fi
    done
    print_debug "EXIT process_repository repo=${repo_dir}"
}

# ============================================================================
# USER INTERFACE
# ============================================================================

get_root_directory() {
    local root_dir="${1:-}"
    
    if [[ -n "$root_dir" ]]; then
        if [[ ! -d "$root_dir" ]]; then
            print_error "Directory does not exist: $root_dir"
            exit 1
        fi
    else
        echo -e "${BOLD}Enter the root directory path${NC}" >&2
        echo -e "(Press Enter to use current directory: $(pwd))" >&2
        read -rp "> " root_dir
        
        if [[ -z "$root_dir" ]]; then
            root_dir=$(pwd)
        fi
        
        root_dir="${root_dir/#\~/$HOME}"
        
        if [[ ! -d "$root_dir" ]]; then
            print_error "Directory does not exist: $root_dir"
            exit 1
        fi
    fi
    
    root_dir=$(cd "$root_dir" && pwd)
    
    echo "$root_dir"
}

show_plan() {
    local root_dir="$1"
    
    echo ""
    echo -e "${BOLD}Scan Plan:${NC}"
    echo -e "  Root directory: ${CYAN}$root_dir${NC}"
    echo ""
    
    # Count git repos
    mapfile -d '' -t git_dirs < <(find "$root_dir" -name ".git" -print0 2>/dev/null)
    local repo_count=${#git_dirs[@]}

    # Debug: print first few .git paths (only if DEBUG=true)
    if [[ "${DEBUG}" == "true" && $repo_count -gt 0 ]]; then
        echo "DEBUG: first .git entries:"
        for ((i=0;i<${#git_dirs[@]} && i<10;i++)); do
            printf '  %s\n' "${git_dirs[i]}"
        done
    fi
    
    echo -e "  Git repositories found: ${GREEN}$repo_count${NC}"
    echo ""
    
    if [[ $repo_count -eq 0 ]]; then
        print_warning "No git repositories found in $root_dir"
        exit 0
    fi
    
    echo -e "${BOLD}This will:${NC}"
    echo -e "  • Scan all directories for git repositories"
    echo -e "  • Generate .gitmodules for each parent repository"
    echo -e "  • Use remote URLs where available, relative paths otherwise"
    echo -e "  • Overwrite existing .gitmodules files"
    echo ""
    
    read -rp "Continue? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        print_info "Cancelled."
        exit 0
    fi
}

show_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║${NC}                   ${CYAN}Processing Complete!${NC}                      ${BOLD}${GREEN}║${NC}"
    echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Generated .gitmodules files for all nested repositories.${NC}"
    echo ""
    echo -e "${BOLD}Note:${NC} This script manages .gitmodules files only."
    echo -e "To actually register submodules, use:"
    echo -e "  ${CYAN}git submodule add <url> <path>${NC}"
    echo ""
    echo -e "To update submodules after .gitmodules changes:"
    echo -e "  ${CYAN}git submodule sync${NC}"
    echo -e "  ${CYAN}git submodule update --init --recursive${NC}"
    echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    print_header
    
    local root_dir
    root_dir=$(get_root_directory "$1")
    
    print_info "Root directory: $root_dir"
    
    if ! is_git_repo "$root_dir"; then
        print_warning "Root directory is not a git repository."
        echo -e "  Initialise with: ${CYAN}cd $root_dir && git init${NC}"
        echo ""
        read -rp "Continue anyway? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy] ]]; then
            exit 0
        fi
    fi
    
    show_plan "$root_dir"
    
    echo ""
    print_info "Scanning directory structure..."
    echo ""
    
    if is_git_repo "$root_dir"; then
        process_repository "$root_dir" "$root_dir" 0
    else
        while IFS= read -r -d '' git_dir; do
            local repo_dir=$(dirname "$git_dir")
            process_repository "$repo_dir" "$root_dir" 0
        done < <(find "$root_dir" -maxdepth 2 -name ".git" -print0 2>/dev/null)
    fi
    
    show_summary
}

main "$@"