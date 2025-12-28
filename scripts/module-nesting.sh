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
# Additional flows provided by this script:
#   --copy-temp / --only-copy-temp : Collect and merge temporary folders into $ROOT/.tmp (handler: copy_temp_dirs)
#   --prune / --only-prune         : Move originals to recycle (or delete) and replace with symlinks to backups (handler: prune_temp_dirs)
#   --aggressive                   : Aggressively replace temp folders, remove originals and append entries to .gitignore (handler: aggressive_replace_dirs). --dry-run will simulate these changes without modifying files.
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

# Added common build/output directories to avoid archiving transient build artifacts
EXCLUDE_TEMP=(build CMakeFiles dist target bin obj out cmake-build-debug .git .wrangler)

# Return 0 if any path component of $1 matches an entry in EXCLUDE_DIRS
# (used for module-nesting discovery only)
path_has_excluded_component() {
    local p="$1"
    IFS='/' read -ra parts <<< "$p"
    for comp in "${parts[@]}"; do
        for e in "${EXCLUDE_DIRS[@]}"; do
            if [[ "$comp" == "$e" ]]; then
                return 0
            fi
        done
    done
    return 1
}

# Return 0 if any path component of $1 matches an entry in EXCLUDE_TEMP
# (used when inspecting temp/build directories during copy/prune/aggressive flows)
path_has_excluded_temp_component() {
    local p="$1"
    IFS='/' read -ra parts <<< "$p"
    for comp in "${parts[@]}"; do
        for e in "${EXCLUDE_TEMP[@]}"; do
            if [[ "$comp" == "$e" ]]; then
                return 0
            fi
        done
    done
    return 1
}

# Feature flags: --copy-temp  (run after module nesting)
#                --only-copy-temp  (run only the copy-temp flow)
#                --prune           (after copying, prune originals and link to backup)
#                --only-prune      (run prune flow only)
#                --dry-run         (show what would be done, no changes)  # supported with --aggressive to preview destructive actions
#                --delete          (permanently delete originals instead of moving to recycle)
#                -y                (auto-confirm prompts)
#                --aggressive      (AGGRESSIVE replace: merge into $ROOT/.tmp/<parent>, delete originals, create symlink of parent instead of files, and append to .gitignore when the temp folder name is not '.tmp'; overrides other destructive flags; --dry-run is allowed) 
COPY_TEMP=false
ONLY_COPY_TEMP=false
PRUNE=false
ONLY_PRUNE=false
DRY_RUN=false
DELETE=false
FORCE=false
AGGRESSIVE=false
TEST=false

# Temp file to record copied mappings (source<TAB>target)
COPIED_RECORD=""
# Internal flag: true when COPIED_RECORD was created as ephemeral temp for DRY-RUN previews
COPIED_RECORD_TEMP=false

# Track whether we've already shown dry-run preview messages (to avoid duplicates)
DRY_RUN_PREVIEW_SHOWN=false
# Track whether ephemeral record removal notice has been shown
DRY_RUN_EPHEMERAL_NOTICE_SHOWN=false

# Print a DRY-RUN preview message once per invocation
print_dry_run_preview_once() {
    local msg="$1"
    if [[ "${DRY_RUN_PREVIEW_SHOWN:-false}" != "true" ]]; then
        print_info "$msg"
        DRY_RUN_PREVIEW_SHOWN=true
    fi
}

# Print ephemeral-record removal notice once per invocation
print_ephemeral_notice_once() {
    local msg="$1"
    if [[ "${DRY_RUN_EPHEMERAL_NOTICE_SHOWN:-false}" != "true" ]]; then
        print_info "$msg"
        DRY_RUN_EPHEMERAL_NOTICE_SHOWN=true
    fi
} 


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
            if [[ "$DRY_RUN" == "true" ]]; then
                print_info "DRY-RUN: Would remove .gitmodules in $(basename \"$repo_dir\") at $gitmodules_path"
            else
                print_info "No submodules found in $(basename \"$repo_dir\") - removing .gitmodules"
                rm "$gitmodules_path"
            fi
        fi
        return
    fi

    print_debug "Writing .gitmodules to $gitmodules_path (content length: ${#content} chars)"
    print_debug "First line of content: $(printf '%s' \"$content\" | sed -n '1p')"

    if [[ "$DRY_RUN" == "true" ]]; then
        local line_count
        line_count=$(printf '%s' "$content" | wc -l)
        print_info "DRY-RUN: Would write .gitmodules (${line_count} lines) to $gitmodules_path for repo $(basename \"$repo_dir\")"
        if [[ "${DEBUG:-false}" == "true" ]]; then
            echo -e "DRY-RUN: .gitmodules content preview (first 120 lines):"
            printf '%s
' "$content" | sed -n '1,120p'
        fi
    else
        echo -e "$content" > "$gitmodules_path"
        print_success "Generated .gitmodules for: $(basename \"$repo_dir\")"
    fi
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

# Prune temp directories after successful copy: move to recycle (or delete) and replace with symlink
prune_temp_dirs() {
    local root_dir="$1"
    local record_file="$2"

    if [[ -z "$root_dir" ]]; then
        print_error "prune_temp_dirs: root_dir required"
        return 1
    fi
    if [[ -n "$record_file" && ! -f "$record_file" ]]; then
        print_error "prune_temp_dirs: record_file not found: $record_file"
        return 1
    fi

    local dest_dir="$root_dir/.tmp"
    local recycle_base="$dest_dir/.recycle"
    # For DRY_RUN we avoid creating $dest_dir or $recycle_base inside the repo to
    # prevent leaving preview artifacts; instead create a temporary recycle base
    # that will be removed at the end of the preview.
    local PRUNE_CREATED_TEMP=false
    if [[ "$DRY_RUN" == "true" ]]; then
        recycle_base=$(mktemp -d)
        PRUNE_CREATED_TEMP=true
    else
        mkdir -p "$recycle_base"
    fi

    local total=0
    local pruned=0
    local skipped=0
    local warned_large=0

    # If record_file not provided, try to find latest
    if [[ -z "$record_file" ]]; then
        record_file=$(ls -1t "$dest_dir"/copied_dirs.* 2>/dev/null | head -n1 || true)
        if [[ -z "$record_file" ]]; then
            print_error "No copied record file found in $dest_dir"
            return 1
        fi
    fi

    print_info "Prune: using record file: $record_file"

    while IFS=$'\t' read -r src tgt; do
        [[ -z "$src" || -z "$tgt" ]] && continue
        total=$((total + 1))

        # safety: skip if src is the destination or under the destination (exact directory or subpath)
        case "$src" in
            "$dest_dir" | "$dest_dir"/* )
                print_info "Skipping $src (inside destination: $dest_dir)"
                [[ "${DEBUG:-false}" == "true" ]] && print_debug "Skipped because it matches destination pattern: $src starts with $dest_dir"
                skipped=$((skipped + 1))
                continue
                ;;
        esac

        # verify target exists and has files
        if [[ ! -d "$tgt" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                # In DRY-RUN we simulate the presence of the target so prune preview
                # can proceed even though no real backups were created during preview.
                print_info "DRY-RUN: Target backup not found for $src -> $tgt; simulating presence for preview"
                local file_count=1
            else
                print_warning "Target backup not found for $src -> $tgt; skipping"
                skipped=$((skipped + 1))
                continue
            fi
        else
            local file_count
            file_count=$(find "$tgt" -type f 2>/dev/null | wc -l || true)
            if [[ "$file_count" -eq 0 ]]; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    print_info "DRY-RUN: Backup target $tgt appears empty; simulating non-empty target for preview"
                    file_count=1
                else
                    print_warning "Backup target $tgt appears empty; skipping $src"
                    skipped=$((skipped + 1))
                    continue
                fi
            fi
        fi

        # detect large files (>10M) in source if deleting requested or for warning
        local large_files
        large_files=$(find "$src" -type f -size +10M -print 2>/dev/null || true)
        local large_count=0
        if [[ -n "$large_files" ]]; then
            large_count=$(printf '%s' "$large_files" | wc -l)
        fi

        if [[ "$DELETE" == "true" && $large_count -gt 0 ]]; then
            print_warning "$src contains $large_count file(s) >10MB (will be affected by --delete)."
            warned_large=$((warned_large + large_count))
            if [[ "$DRY_RUN" == "true" ]]; then
                print_info "DRY-RUN: would delete these large files from $src"
                [[ "${DEBUG:-false}" == "true" ]] && echo "$large_files"
            else
                if [[ "$FORCE" != "true" ]]; then
                    read -rp "There are $large_count large files in $src. Proceed to delete? [y/N]: " yn
                    if [[ ! "$yn" =~ ^[Yy] ]]; then
                        print_info "Skipping $src"
                        skipped=$((skipped + 1))
                        continue
                    fi
                fi
            fi
        fi

        # perform action
        if [[ "$DRY_RUN" == "true" ]]; then
            # If this target was generated as a simulated target during a dry-run
            # preview (under SIM_TARGET_MARKER), present the logical final
            # destination to the user (i.e., $root_dir/.tmp/<parent>) instead of
            # exposing the ephemeral /tmp path used for simulation.
            local display_tgt="$tgt"
            if [[ -n "${SIM_TARGET_MARKER:-}" && "$tgt" == "${SIM_TARGET_MARKER}"/* ]]; then
                local parent_name
                parent_name=$(basename "$tgt")
                display_tgt="$dest_dir/$parent_name"
            fi

            if [[ "$DELETE" == "true" ]]; then
                print_info "DRY-RUN: Would delete contents of $src and create symlinks thereof in $display_tgt"
            else
                print_info "DRY-RUN: Would move contents of $src to recycle and create symlinks thereof in $display_tgt"
            fi
            pruned=$((pruned + 1))
            continue
        fi

        # actual action
        if [[ "$DELETE" == "true" ]]; then
            # delete files inside src but keep the directory so we can place symlink in its place
            if [[ -d "$src" ]]; then
                rm -rf "$src" || true
                print_info "Deleted $src"
            fi
        else
            # move the original dir to recycle with timestamp, preserving path
            local stamp
            stamp=$(date +%Y%m%d_%H%M%S)
            local rel
            rel=${src#"$root_dir"/}
            local recycle_dest="$recycle_base/$stamp/$rel"
            mkdir -p "$(dirname "$recycle_dest")"
            mv "$src" "$recycle_dest" || {
                print_error "Failed to move $src to $recycle_dest; skipping"
                skipped=$((skipped + 1))
                continue
            }
            print_info "Moved $src -> $recycle_dest"
        fi

        # create symlink at original location pointing to backup target
        # ensure parent dir exists
        local parent_dir
        parent_dir=$(dirname "$src")
        mkdir -p "$parent_dir"
        # Create a relative symlink target to make links portable across hosts/containers
        local rel_tgt
        rel_tgt=$(realpath --relative-to="$parent_dir" "$tgt" 2>/dev/null || echo "$tgt")
        ln -sfn "$rel_tgt" "$src"
        print_info "Linked $src -> $rel_tgt (relative -> $tgt)"

        pruned=$((pruned + 1))
    done < "$record_file"

    print_success "Prune complete: processed=$total pruned=$pruned skipped=$skipped"
    if [[ $warned_large -gt 0 ]]; then
        print_warning "There were $warned_large large files (>10MB) encountered during prune operations."
    fi

    # If we created a temporary recycle base for DRY-RUN, remove it to avoid stragglers
    if [[ "$PRUNE_CREATED_TEMP" == "true" && -n "$recycle_base" && -d "$recycle_base" ]]; then
        rm -rf "$recycle_base" || true
        print_debug "Removed temporary recycle base used for DRY-RUN preview: $recycle_base"
    fi

    return 0
}

# Copy temp directories into $ROOT/.tmp/<parent_name> (non-destructive)
copy_temp_dirs() {
    local root_dir="$1"
    local KEEP_EPHEMERAL="${2:-false}"
    if [[ -z "$root_dir" ]]; then
        print_error "copy_temp_dirs: root_dir required"
        return 1
    fi

    local dest_dir="$root_dir/.tmp"

    # In dry-run mode we do not create the destination folders in the workspace,
    # but we do create an ephemeral COPIED_RECORD in /tmp so we can preview --prune
    # without writing files into the repository. This keeps preview behavior
    # comprehensive while remaining non-destructive.
    if [[ "$DRY_RUN" == "true" ]]; then
        # Print the workspace-level preview message only once
        if [[ "${DRY_RUN_PREVIEW_SHOWN:-false}" != "true" ]]; then
            print_info "DRY-RUN: preview mode — will NOT create $dest_dir folders in workspace; creating ephemeral record to simulate mappings for prune preview"
            DRY_RUN_PREVIEW_SHOWN=true
        fi
        COPIED_RECORD=$(mktemp)
        COPIED_RECORD_TEMP=true
    else
        mkdir -p "$dest_dir"
        # create a record file to list copied mappings for potential prune step
        COPIED_RECORD=$(mktemp -p "$dest_dir" copied_dirs.XXXXXX)
        COPIED_RECORD_TEMP=false
    fi

    local found=0
    local skipped=0
    local skipped_list=""
    local skipped_dest=0
    local skipped_excluded=0
    local skipped_other=0
    # Canonicalize destination path to correctly detect symlinks and subpaths
    local dest_canon
    dest_canon=$(realpath -m "$dest_dir" 2>/dev/null || echo "$dest_dir")
    # Find temp directories (case-insensitive) but exclude the destination dir itself
    # Build prune args from EXCLUDE_TEMP so we do not descend into known build/output directories
    local prune_args=()
    for e in "${EXCLUDE_TEMP[@]}"; do
        prune_args+=( -iname "$e" -o )
    done
    # remove trailing -o
    if [[ ${#prune_args[@]} -gt 0 ]]; then
        unset 'prune_args[${#prune_args[@]}-1]'
    fi

    # If in dry-run or DEBUG, list all matched temp directories for diagnosis
    if [[ "${DEBUG:-false}" == "true" || "$DRY_RUN" == "true" ]]; then
        print_info "Matched temp directories (diagnostic: showing canonical paths)"
        while IFS= read -r -d '' d; do
            dcanon=$(realpath -m "$d" 2>/dev/null || echo "$d")
            if [[ "$dcanon" == "$dest_canon" || "$dcanon" == "$dest_canon"/* ]]; then
                print_info "  [DEST->] $d  (canonical: $dcanon)"
            else
                print_info "  $d  (canonical: $dcanon)"
            fi
        done < <(if [[ ${#prune_args[@]} -gt 0 ]]; then find "$root_dir" \( "${prune_args[@]}" \) -prune -o -type d \( -iname '.tmp' -o -iname '.temp' -o -iname 'tmp' -o -iname 'temp' \) -print0 2>/dev/null; else find "$root_dir" -type d \( -iname '.tmp' -o -iname '.temp' -o -iname 'tmp' -o -iname 'temp' \) -print0 2>/dev/null; fi)
    fi

    while IFS= read -r -d '' tempdir; do
        # canonicalize the tempdir so symlinks are resolved and subpaths detected
        temp_canon=$(realpath -m "$tempdir" 2>/dev/null || echo "$tempdir")

        # skip temp dirs already under the destination path to avoid recursion
        if [[ "$temp_canon" == "$dest_canon" || "$temp_canon" == "$dest_canon"/* ]]; then
            skipped=$((skipped + 1))
            skipped_dest=$((skipped_dest + 1))
            skipped_list+="$tempdir (destination)\n"
            [[ "${DEBUG:-false}" == "true" ]] && print_debug "Skipped $tempdir (canonical: $temp_canon) because it is inside destination $dest_canon"
            continue
        fi

        # skip if the tempdir is inside a known build/output directory (e.g., build/, CMakeFiles)
        # Use EXCLUDE_TEMP here (not EXCLUDE_DIRS) so we don't skip legitimate .tmp folders
        # which are the target of these flows.
        if path_has_excluded_temp_component "$tempdir"; then
            skipped=$((skipped + 1))
            skipped_excluded=$((skipped_excluded + 1))
            skipped_list+="$tempdir (excluded parent component)\n"
            [[ "${DEBUG:-false}" == "true" ]] && print_debug "Skipped $tempdir because it contains an excluded component"
            continue
        fi

        local parent_name
        parent_name=$(basename "$(dirname "$tempdir")")
        local target="$dest_dir/$parent_name"
        # Only create the per-parent target when not in dry-run
        if [[ "$DRY_RUN" != "true" ]]; then
            mkdir -p "$target"
        fi

        # rsync contents non-destructively (don't overwrite existing files)
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "DRY-RUN: Would merge $tempdir -> $target"
        else
            rsync -a --ignore-existing --prune-empty-dirs "$tempdir/" "$target/"
            print_info "Merged $tempdir -> $target"
        fi

        # record mapping for pruning (source<TAB>target) — only when a record file exists
        if [[ -n "$COPIED_RECORD" ]]; then
            printf '%s\t%s\n' "$tempdir" "$target" >> "$COPIED_RECORD"
        else
            print_info "DRY-RUN: Would record mapping $tempdir -> $target"
        fi

        found=$((found + 1))
    done < <(if [[ ${#prune_args[@]} -gt 0 ]]; then find "$root_dir" \( "${prune_args[@]}" \) -prune -o -type d \( -iname '.tmp' -o -iname '.temp' -o -iname 'tmp' -o -iname 'temp' \) -print0 2>/dev/null; else find "$root_dir" -type d \( -iname '.tmp' -o -iname '.temp' -o -iname 'tmp' -o -iname 'temp' \) -print0 2>/dev/null; fi)

    if [[ $found -eq 0 && $skipped -eq 0 ]]; then
        print_info "No temp dirs found to copy in $root_dir"
        # If this was a DRY-RUN with an ephemeral record, keep it only when the
        # caller explicitly requested it (KEEP_EPHEMERAL) or when --prune was
        # requested so a subsequent prune preview can use it. Otherwise remove it.
        if [[ "${COPIED_RECORD_TEMP:-false}" == "true" ]]; then
            if [[ "$KEEP_EPHEMERAL" == "true" || "$PRUNE" == "true" ]]; then
                print_info "DRY-RUN: No temp dirs found; keeping ephemeral record $COPIED_RECORD for prune preview (will be cleaned up after preview)"
            else
                print_ephemeral_notice_once "DRY-RUN: No temp dirs found; ephemeral record will be removed"
                [[ -f "$COPIED_RECORD" ]] && rm -f "$COPIED_RECORD" && COPIED_RECORD=""
            fi
        else
            [[ -f "$COPIED_RECORD" ]] && rm -f "$COPIED_RECORD" && COPIED_RECORD=""
        fi
    elif [[ $found -eq 0 && $skipped -gt 0 ]]; then
        print_info "Found $skipped candidate temp dir(s) but none were copied. Summary: dest_skipped=$skipped_dest excluded_skipped=$skipped_excluded other_skipped=$skipped_other"
        print_info "Destination canonical path: $dest_canon"
        if [[ "${DEBUG:-false}" == "true" ]]; then
            echo -e "Skipped directories and reasons:\n$skipped_list"
        fi
        # Preserve ephemeral record for DRY-RUN prune preview only when asked
        # (KEEP_EPHEMERAL) or when --prune is set. Otherwise remove it.
        if [[ "${COPIED_RECORD_TEMP:-false}" == "true" ]]; then
            if [[ "$KEEP_EPHEMERAL" == "true" || "$PRUNE" == "true" ]]; then
                print_info "DRY-RUN: Candidate temp dirs were skipped; keeping ephemeral record $COPIED_RECORD for prune preview"
            else
                print_ephemeral_notice_once "DRY-RUN: Candidate temp dirs were skipped; ephemeral record will be removed"
                [[ -f "$COPIED_RECORD" ]] && rm -f "$COPIED_RECORD" && COPIED_RECORD=""
            fi
        else
            [[ -f "$COPIED_RECORD" ]] && rm -f "$COPIED_RECORD" && COPIED_RECORD=""
        fi
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "DRY-RUN: Would copy/merge $found temp dir(s) into $dest_dir (non-destructive). An ephemeral record was created to allow --prune preview (no workspace files will be created)."
            if [[ $skipped -gt 0 && "${DEBUG:-false}" == "true" ]]; then
                echo -e "Also skipped $skipped directory(s) located under $dest_dir:\n$skipped_list"
            fi
        else
            print_success "Copied/merged $found temp dir(s) into $dest_dir (non-destructive)"
            if [[ $skipped -gt 0 && "${DEBUG:-false}" == "true" ]]; then
                echo -e "Also skipped $skipped directory(s) located under $dest_dir:\n$skipped_list"
            fi
        fi
    fi

    # Return the record file path (if any) to caller via global COPIED_RECORD
    if [[ -n "$COPIED_RECORD" && -f "$COPIED_RECORD" ]]; then
        # Only echo the path if the file is being intentionally kept for a
        # follow-up prune preview or the record was created inside the repo.
        if [[ "${COPIED_RECORD_TEMP:-false}" == "true" && "$KEEP_EPHEMERAL" != "true" && "$PRUNE" != "true" ]]; then
            # ephemeral record is not requested to be kept; remove it and do not echo
            rm -f "$COPIED_RECORD" || true
            COPIED_RECORD=""
        else
            echo "$COPIED_RECORD"
        fi
    fi

}

# Aggressive replace: Merge temp dirs into $ROOT/.tmp/<parent>, delete originals, create symlinks, and append to .gitignore
aggressive_replace_dirs() {
    local root_dir="$1"
    local KEEP_EPHEMERAL="${2:-false}"
    if [[ -z "$root_dir" ]]; then
        print_error "aggressive_replace_dirs: root_dir required"
        return 1
    fi

    local dest_dir="$root_dir/.tmp"

    print_warning "AGGRESSIVE MODE: originals will be removed and replaced with symlinks to $dest_dir. This will also append to .gitignore for non '.tmp' folders."

    # If dry-run, skip interactive confirmation (we are previewing)
    if [[ "$FORCE" != "true" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            # Show this DRY-RUN confirmation message only once per run
            if [[ "${DRY_RUN_PREVIEW_SHOWN:-false}" != "true" ]]; then
                print_info "DRY-RUN: skipping interactive confirmation (preview mode)."
                DRY_RUN_PREVIEW_SHOWN=true
            fi
        else
            read -rp "Proceed with aggressive replace? [y/N]: " yn
            if [[ ! "$yn" =~ ^[Yy] ]]; then
                print_info "Cancelled."
                return 1
            fi
        fi
    fi

    # In dry-run mode we do not create the destination folder in the workspace,
    # but create an ephemeral record so the preview includes mappings that would
    # be used for pruning or inspection without making destructive changes.
    if [[ "$DRY_RUN" == "true" ]]; then
        # Print the workspace-level preview message only once for the whole run
        if [[ "${DRY_RUN_PREVIEW_SHOWN:-false}" != "true" ]]; then
            print_info "DRY-RUN: preview mode — will NOT create $dest_dir in workspace; creating ephemeral record to simulate mappings"
            DRY_RUN_PREVIEW_SHOWN=true
        fi
        COPIED_RECORD=$(mktemp)
        COPIED_RECORD_TEMP=true
    else
        mkdir -p "$dest_dir"
        COPIED_RECORD=$(mktemp -p "$dest_dir" copied_dirs.XXXXXX)
        COPIED_RECORD_TEMP=false
    fi

    # Build prune args from EXCLUDE_TEMP so we do not descend into known build/output directories
    local prune_args=()
    for e in "${EXCLUDE_TEMP[@]}"; do
        prune_args+=( -iname "$e" -o )
    done
    if [[ ${#prune_args[@]} -gt 0 ]]; then
        unset 'prune_args[${#prune_args[@]}-1]'
    fi

    local found=0
    local skipped=0
    local skipped_list=""
    local skipped_dest=0
    local skipped_excluded=0
    local skipped_other=0
    local dest_canon
    dest_canon=$(realpath -m "$dest_dir" 2>/dev/null || echo "$dest_dir")

    # If in dry-run or DEBUG, list all matched temp directories for diagnosis
    if [[ "${DEBUG:-false}" == "true" || "$DRY_RUN" == "true" ]]; then
        print_info "Matched temp directories (diagnostic: showing canonical paths)"
        while IFS= read -r -d '' d; do
            dcanon=$(realpath -m "$d" 2>/dev/null || echo "$d")
            if [[ "$dcanon" == "$dest_canon" || "$dcanon" == "$dest_canon"/* ]]; then
                print_info "  [DEST->] $d  (canonical: $dcanon)"
            else
                print_info "  $d  (canonical: $dcanon)"
            fi
        done < <(if [[ ${#prune_args[@]} -gt 0 ]]; then find "$root_dir" \( "${prune_args[@]}" \) -prune -o -type d \( -iname '.tmp' -o -iname '.temp' -o -iname 'tmp' -o -iname 'temp' \) -print0 2>/dev/null; else find "$root_dir" -type d \( -iname '.tmp' -o -iname '.temp' -o -iname 'tmp' -o -iname 'temp' \) -print0 2>/dev/null; fi)
    fi

    # If in dry-run or DEBUG, list all matched temp directories for diagnosis
    if [[ "${DEBUG:-false}" == "true" || "$DRY_RUN" == "true" ]]; then
        print_info "Matched temp directories (diagnostic)"
        while IFS= read -r -d '' d; do
            if [[ "$d" == "$dest_dir" || "$d" == "$dest_dir"/* ]]; then
                print_info "  [DEST] $d"
            else
                print_info "  $d"
            fi
        done < <(if [[ ${#prune_args[@]} -gt 0 ]]; then find "$root_dir" \( "${prune_args[@]}" \) -prune -o -type d \( -iname '.tmp' -o -iname '.temp' -o -iname 'tmp' -o -iname 'temp' \) -print0 2>/dev/null; else find "$root_dir" -type d \( -iname '.tmp' -o -iname '.temp' -o -iname 'tmp' -o -iname 'temp' \) -print0 2>/dev/null; fi)
    fi

    while IFS= read -r -d '' tempdir; do
        temp_canon=$(realpath -m "$tempdir" 2>/dev/null || echo "$tempdir")

        # skip temp dirs already under the destination path to avoid recursion (handles symlinks)
        if [[ "$temp_canon" == "$dest_canon" || "$temp_canon" == "$dest_canon"/* ]]; then
            skipped=$((skipped + 1))
            skipped_dest=$((skipped_dest + 1))
            skipped_list+="$tempdir (destination)\n"
            [[ "${DEBUG:-false}" == "true" ]] && print_debug "Skipped $tempdir (canonical: $temp_canon) because it is inside destination $dest_canon"
            continue
        fi

        # skip if the tempdir is inside a known build/output directory (e.g., build/, CMakeFiles)
        # Use EXCLUDE_TEMP here (not EXCLUDE_DIRS) so we don't skip legitimate .tmp folders
        # which are the target of these flows.
        if path_has_excluded_temp_component "$tempdir"; then
            skipped=$((skipped + 1))
            skipped_excluded=$((skipped_excluded + 1))
            skipped_list+="$tempdir (excluded parent component)\n"
            [[ "${DEBUG:-false}" == "true" ]] && print_debug "Skipped $tempdir because it contains an excluded component"
            continue
        fi

        local parent_name
        parent_name=$(basename "$(dirname "$tempdir")")
        local target="$dest_dir/$parent_name"
        mkdir -p "$target"

        # rsync contents non-destructively (don't overwrite existing files)
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "DRY-RUN: Would merge $tempdir -> $target"
        else
            rsync -a --ignore-existing --prune-empty-dirs "$tempdir/" "$target/"
            print_info "Merged $tempdir -> $target"
        fi

        # record mapping for tracing (source<TAB>target)
        printf '%s\t%s\n' "$tempdir" "$target" >> "$COPIED_RECORD"

        # Append to .gitignore if basename != .tmp (case-insensitive)
        local base
        base=$(basename "$tempdir")
        if [[ "$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')" != ".tmp" ]]; then
            local gitroot
            gitroot=$(git -C "$(dirname "$tempdir")" rev-parse --show-toplevel 2>/dev/null || true)
            local gitignore_file entry
            if [[ -n "$gitroot" ]]; then
                gitignore_file="$gitroot/.gitignore"
                # relative path to tempdir from repo root (fallback to basename)
                local rel
                rel=$(realpath --relative-to="$gitroot" "$tempdir" 2>/dev/null || echo "$base")
                entry="${rel}/"
            else
                gitignore_file="$(dirname "$tempdir")/.gitignore"
                entry="${base}/"
            fi
            mkdir -p "$(dirname "$gitignore_file")"
            touch "$gitignore_file"
            if [[ "$DRY_RUN" == "true" ]]; then
                # In DRY-RUN, report whether the gitignore already contains the entry
                if [[ -f "$gitignore_file" ]] && grep -Fxq "$entry" "$gitignore_file"; then
                    print_info "DRY-RUN: $gitignore_file already contains '$entry' — no change needed"
                else
                    print_info "DRY-RUN: Would append '$entry' to $gitignore_file"
                fi
            else
                if ! grep -Fxq "$entry" "$gitignore_file"; then
                    printf '%s\n' "$entry" >> "$gitignore_file"
                    print_info "Appended '$entry' to $gitignore_file"
                else
                    print_debug "'$entry' already in $gitignore_file"
                fi
            fi
        fi

        # remove original and create symlink pointing to backup target
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "DRY-RUN: Would remove $tempdir and create symlink pointing to $target"
        else
            # Ensure the target directory exists so the symlink points at a directory
            mkdir -p "$target"
            rm -rf "$tempdir"
            local parent_dir
            parent_dir=$(dirname "$tempdir")
            # Create a relative symlink target to make links portable across hosts/containers
            local rel_target
            rel_target=$(realpath --relative-to="$parent_dir" "$target" 2>/dev/null || echo "$target")
            ln -sfn "$rel_target" "$tempdir"
            print_info "Replaced $tempdir -> $rel_target (relative -> $target) (original removed and symlinked)"
        fi

        found=$((found + 1))
    done < <(if [[ ${#prune_args[@]} -gt 0 ]]; then find "$root_dir" \( "${prune_args[@]}" \) -prune -o -type d \( -iname '.tmp' -o -iname '.temp' -o -iname 'tmp' -o -iname 'temp' \) -print0 2>/dev/null; else find "$root_dir" -type d \( -iname '.tmp' -o -iname '.temp' -o -iname 'tmp' -o -iname 'temp' \) -print0 2>/dev/null; fi)

    if [[ $found -eq 0 && $skipped -eq 0 ]]; then
        print_info "No temp dirs found to aggressively replace in $root_dir"
        if [[ "${COPIED_RECORD_TEMP:-false}" == "true" ]]; then
            if [[ "$KEEP_EPHEMERAL" == "true" || "$PRUNE" == "true" ]]; then
                print_info "DRY-RUN: No temp dirs found; keeping ephemeral record $COPIED_RECORD for preview"
            else
                print_ephemeral_notice_once "DRY-RUN: No temp dirs found; ephemeral record will be removed"
                [[ -f "$COPIED_RECORD" ]] && rm -f "$COPIED_RECORD" && COPIED_RECORD=""
            fi
        else
            [[ -f "$COPIED_RECORD" ]] && rm -f "$COPIED_RECORD" && COPIED_RECORD=""
        fi
    elif [[ $found -eq 0 && $skipped -gt 0 ]]; then
        print_info "Found $skipped candidate temp dir(s) but none were processed. Summary: dest_skipped=$skipped_dest excluded_skipped=$skipped_excluded other_skipped=$skipped_other"
        print_info "Destination canonical path: $dest_canon"
        if [[ "${DEBUG:-false}" == "true" ]]; then
            echo -e "Skipped directories and reasons:\n$skipped_list"
        fi
        if [[ "${COPIED_RECORD_TEMP:-false}" == "true" ]]; then
            if [[ "$KEEP_EPHEMERAL" == "true" || "$PRUNE" == "true" ]]; then
                print_info "DRY-RUN: Candidate temp dirs were skipped; keeping ephemeral record $COPIED_RECORD for preview"
            else
                print_ephemeral_notice_once "DRY-RUN: Candidate temp dirs were skipped; ephemeral record will be removed"
                [[ -f "$COPIED_RECORD" ]] && rm -f "$COPIED_RECORD" && COPIED_RECORD=""
            fi
        else
            [[ -f "$COPIED_RECORD" ]] && rm -f "$COPIED_RECORD" && COPIED_RECORD=""
        fi
    else
        print_success "Aggressively processed $found temp dir(s) into $dest_dir"
        if [[ $skipped -gt 0 && "${DEBUG:-false}" == "true" ]]; then
            echo -e "Also skipped $skipped directory(s) located under $dest_dir or excluded:\n$skipped_list"
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        # Only remove the temporary record if the caller did not request it to be
        # kept for a follow-up prune preview (e.g., ONLY_PRUNE or explicit flag).
        if [[ "${COPIED_RECORD_TEMP:-false}" == "true" && "$KEEP_EPHEMERAL" != "true" && "$PRUNE" != "true" ]]; then
            print_ephemeral_notice_once "DRY-RUN: No changes were made; temporary record file will be removed."
            if [[ -f "$COPIED_RECORD" ]]; then
                rm -f "$COPIED_RECORD" || true
                COPIED_RECORD=""
            fi
        else
            print_info "DRY-RUN: No changes were made; ephemeral mapping record retained for preview: $COPIED_RECORD"
        fi
    fi

    if [[ -n "$COPIED_RECORD" && -f "$COPIED_RECORD" ]]; then
        echo "$COPIED_RECORD"
    fi

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
    echo -e "Additional options:"
    echo -e "  --copy-temp       : After module nesting, collect and merge temp directories into \$ROOT/.tmp/<parent>"
    echo -e "  --only-copy-temp  : Skip module nesting; only run the temp collection flow (prompts for root)"
    echo -e "  --prune           : After copy, move originals to recycle (or delete with --delete) and replace with symlinks to backups"
    echo -e "  --only-prune      : Run prune flow only (uses latest copied record in \$ROOT/.tmp)"
    echo -e "  --dry-run         : Show actions without making changes (applies to copy, prune and aggressive)"
    echo -e "  --delete          : Permanently delete originals when pruning instead of moving to recycle"
    echo -e "  --aggressive      : Aggressively replace temp folders: merge into \$ROOT/.tmp/<parent>, remove originals, create symlinks, and append to .gitignore when folder name is not '.tmp' (overrides other flags)"
    echo -e "  -y, --yes         : Auto-confirm prompts (use with caution)"
    echo -e "  --test            : Run a safety test sequence (copy -> prune -> aggressive) in --dry-run mode by default"
    echo ""

    # Print a concise options summary for confirmation
    echo -e "${BOLD}Enabled actions:${NC}"
    echo -e "  Copy temp: ${CYAN}${COPY_TEMP}${NC}  | Only copy: ${CYAN}${ONLY_COPY_TEMP}${NC}  | Prune: ${CYAN}${PRUNE}${NC}  | Only prune: ${CYAN}${ONLY_PRUNE}${NC}"
    echo -e "  Aggressive: ${CYAN}${AGGRESSIVE}${NC}  | Delete: ${CYAN}${DELETE}${NC}  | Auto-confirm: ${CYAN}${FORCE}${NC}"
    echo -e "  Dry-run: ${CYAN}${DRY_RUN}${NC}"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY-RUN: PREVIEW MODE — no filesystem changes will be made. To perform changes, remove --dry-run."
        DRY_RUN_PREVIEW_SHOWN=true
    fi

    read -rp "Continue? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        print_info "Cancelled."
        exit 0
    fi

    # Confirm execution mode after user consent
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "Proceeding in DRY-RUN (preview) with the above options. No changes will be made."
    else
        print_info "Proceeding with live changes with the above options."
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

    # If prune requested, and we have a COPIED_RECORD, run prune
    if [[ "$PRUNE" == "true" && -n "$COPIED_RECORD" && -f "$COPIED_RECORD" ]]; then
        print_info "--prune enabled: pruning originals for copied temp dirs"
        prune_temp_dirs "$root_dir" "$COPIED_RECORD"
    fi

    # If only-prune flag provided independently, run prune now
    if [[ "$ONLY_PRUNE" == "true" ]]; then
        print_info "--only-prune enabled: running prune flow against $root_dir"
        # If no record provided, try to find latest record in $root_dir/.tmp
        if [[ -z "$COPIED_RECORD" || ! -f "$COPIED_RECORD" ]]; then
            COPIED_RECORD=$(ls -1t "$root_dir/.tmp"/copied_dirs.* 2>/dev/null | head -n1 || true)
            if [[ -z "$COPIED_RECORD" || ! -f "$COPIED_RECORD" ]]; then
                print_error "No copied record file found in $root_dir/.tmp. Run with --copy-temp first or provide a record."
            else
                prune_temp_dirs "$root_dir" "$COPIED_RECORD"
            fi
        else
            prune_temp_dirs "$root_dir" "$COPIED_RECORD"
        fi
    fi

    # Cleanup ephemeral copied-record if it was created for a dry-run preview
    if [[ "${COPIED_RECORD_TEMP:-false}" == "true" && -n "$COPIED_RECORD" && -f "$COPIED_RECORD" ]]; then
        rm -f "$COPIED_RECORD" || true
        COPIED_RECORD=""
        COPIED_RECORD_TEMP=false
        print_ephemeral_notice_once "Removed ephemeral copied-record used for DRY-RUN preview"
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    print_header
    
    local root_dir=""

    # Parse CLI flags: --copy-temp and --only-copy-temp
    local args=()
    for arg in "$@"; do
        case "$arg" in
            --copy-temp)
                COPY_TEMP=true
                ;;
            --only-copy-temp)
                ONLY_COPY_TEMP=true
                ;;
            --prune)
                PRUNE=true
                ;;
            --only-prune)
                ONLY_PRUNE=true
                ;;
            --dry-run)
                DRY_RUN=true
                ;;
            --delete)
                DELETE=true
                ;;
            --aggressive)
                AGGRESSIVE=true
                # Aggressive mode implies only-copy-temp behavior and overrides other flags
                ONLY_COPY_TEMP=true
                ;;
            --agressive)
                AGGRESSIVE=true
                ONLY_COPY_TEMP=true
                ;;
            --test)
                TEST=true
                ;;
            -y|--yes)
                FORCE=true
                ;;
            -h|--help)
                echo "Usage: $(basename "$0") [ROOT_DIR] [--copy-temp] [--only-copy-temp] [--prune] [--only-prune] [--dry-run] [--delete] [--aggressive] [-y]"
                exit 0
                ;;
            *)
                args+=("$arg")
                ;;
        esac
    done

    if [[ ${#args[@]} -gt 0 ]]; then
        root_dir="${args[0]}"
    fi

    # Run test sequence if requested: copy (ephemeral), prune (using ephemeral), aggressive (ephemeral)
    if [[ "$TEST" == "true" ]]; then
        root_dir=$(get_root_directory "$root_dir")
        print_info "Running --test sequence against: $root_dir"
        if [[ "$DRY_RUN" != "true" ]]; then
            print_info "--test defaults to --dry-run for safety; enabling DRY-RUN"
            DRY_RUN=true
        fi

        print_info "[TEST] Step 1: --only-copy-temp --dry-run"
        copy_temp_dirs "$root_dir" "true"

        print_info "[TEST] Step 2: --only-prune --dry-run"
        if [[ -n "$COPIED_RECORD" && -f "$COPIED_RECORD" ]]; then
            prune_temp_dirs "$root_dir" "$COPIED_RECORD"
        else
            # Ensure ephemeral record exists and then prune using it
            copy_temp_dirs "$root_dir" "true"
            prune_temp_dirs "$root_dir" "$COPIED_RECORD"
        fi

        print_info "[TEST] Step 3: --aggressive --dry-run"
        aggressive_replace_dirs "$root_dir" "true"

        # Cleanup ephemeral record created during test
        if [[ "${COPIED_RECORD_TEMP:-false}" == "true" && -n "$COPIED_RECORD" && -f "$COPIED_RECORD" ]]; then
            rm -f "$COPIED_RECORD" || true
            COPIED_RECORD=""
            COPIED_RECORD_TEMP=false
            print_info "[TEST] Removed ephemeral copied-record used by test"
        fi

        exit 0
    fi

    # If running only the prune flow, prompt for root and execute (skip module nesting)
    if [[ "$ONLY_PRUNE" == "true" ]]; then
        root_dir=$(get_root_directory "$root_dir")
        print_info "Root directory: $root_dir"
        # Find latest copied record in the root .tmp directory (if any)
        local record
        record=$(ls -1t "$root_dir/.tmp"/copied_dirs.* 2>/dev/null | head -n1 || true)

        if [[ -z "$record" || ! -f "$record" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                print_info "DRY-RUN: No copied record found in $root_dir/.tmp — simulating '--only-copy-temp --dry-run' to generate ephemeral record for prune preview"
                # Run ephemeral copy (dry-run) which will create an ephemeral COPIED_RECORD
                # Request the ephemeral record to be kept for the subsequent prune preview
                copy_temp_dirs "$root_dir" "true"
                # copy_temp_dirs sets global COPIED_RECORD; use it if present
                record="$COPIED_RECORD"
                if [[ -z "$record" || ! -f "$record" ]]; then
                    print_error "Failed to generate ephemeral copied record for prune preview"
                    exit 1
                fi
                print_info "DRY-RUN: Using ephemeral record $record for prune preview"

                # If the ephemeral record was created by a dry-run and is empty, generate
                # simulated target directories so prune preview can exercise the flow.
                if [[ "${COPIED_RECORD_TEMP:-false}" == "true" && $(wc -l < "$record" 2>/dev/null || echo 0) -eq 0 ]]; then
                    print_info "DRY-RUN: Ephemeral record is empty; generating simulated targets for prune preview"
                    SIM_TARGET_BASE=$(mktemp -d)
                    SIM_TARGET_MARKER="$SIM_TARGET_BASE"

                    # Re-use the same find arguments as copy_temp_dirs to locate candidates
                    local prune_args=()
                    for e in "${EXCLUDE_TEMP[@]}"; do
                        prune_args+=( -iname "$e" -o )
                    done
                    if [[ ${#prune_args[@]} -gt 0 ]]; then
                        unset 'prune_args[${#prune_args[@]}-1]'
                    fi

                    while IFS= read -r -d '' tempdir; do
                        # Include matched candidates even when they contain common excluded
                        # components; prune preview should show them so the user can
                        # review and decide.
                        parent_name=$(basename "$(dirname "$tempdir")")
                        target="$SIM_TARGET_BASE/$parent_name"
                        mkdir -p "$target"
                        touch "$target/.simulated"
                        printf '%s	%s
' "$tempdir" "$target" >> "$record"
                        print_info "DRY-RUN: Simulated mapping $tempdir -> $target"
                    done < <(if [[ ${#prune_args[@]} -gt 0 ]]; then find "$root_dir" \( "${prune_args[@]}" \) -prune -o -type d \( -iname '.tmp' -o -iname '.temp' -o -iname 'tmp' -o -iname 'temp' \) -print0 2>/dev/null; else find "$root_dir" -type d \( -iname '.tmp' -o -iname '.temp' -o -iname 'tmp' -o -iname 'temp' \) -print0 2>/dev/null; fi)
                fi
            else
                print_error "No copied record found in $root_dir/.tmp. Run with --copy-temp first or provide a record file."
                exit 1
            fi
        fi

        print_info "--only-prune enabled: running prune flow against $root_dir using record $record"
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "DRY-RUN: previewing prune actions (no changes will be made)"
        fi

        prune_temp_dirs "$root_dir" "$record"

        # Cleanup any simulated targets created for the prune preview
        if [[ -n "${SIM_TARGET_MARKER:-}" && -d "$SIM_TARGET_MARKER" ]]; then
            rm -rf "$SIM_TARGET_MARKER" || true
            print_debug "Removed simulated targets directory used for DRY-RUN prune preview: $SIM_TARGET_MARKER"
            unset SIM_TARGET_MARKER
        fi

        # Cleanup ephemeral record if it was created during DRY_RUN copy preview
        if [[ "${COPIED_RECORD_TEMP:-false}" == "true" && -n "$COPIED_RECORD" && -f "$COPIED_RECORD" ]]; then
            rm -f "$COPIED_RECORD" || true
            COPIED_RECORD=""
            COPIED_RECORD_TEMP=false
            print_ephemeral_notice_once "Removed ephemeral copied-record used for DRY-RUN-only-prune preview"
        fi

        exit 0
    fi

    # If running only the copy-temp flow, prompt for root and execute
    if [[ "$ONLY_COPY_TEMP" == "true" ]]; then
        root_dir=$(get_root_directory "$root_dir")
        print_info "Root directory: $root_dir"
        if [[ "$AGGRESSIVE" == "true" ]]; then
            print_warning "Aggressive mode enabled: originals will be removed and replaced with symlinks; --dry-run is supported to preview actions; other destructive flags are ignored."
            if [[ "$DRY_RUN" == "true" ]]; then
                print_info "DRY-RUN: previewing aggressive actions (no files will be modified)."
            fi
            aggressive_replace_dirs "$root_dir"
        else
            copy_temp_dirs "$root_dir"
            # If prune requested with only-copy-temp, run prune now
            if [[ "$PRUNE" == "true" ]]; then
                prune_temp_dirs "$root_dir"
            fi
        fi
        exit 0
    fi

    # Otherwise continue with normal flow (module nesting)
    root_dir=$(get_root_directory "$root_dir")

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

    # Optionally copy/merge temp folders after module nesting
    if [[ "$COPY_TEMP" == "true" ]]; then
        print_info "--copy-temp enabled: collecting temp directories into $root_dir/.tmp"
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "DRY-RUN: preview only — ephemeral record will be created to allow --prune preview (no workspace files will be created)."
        fi
        copy_temp_dirs "$root_dir"
        # If user also requested prune after copy, run prune (ephemeral record is used in DRY-RUN)
        if [[ "$PRUNE" == "true" && -n "$COPIED_RECORD" && -f "$COPIED_RECORD" ]]; then
            prune_temp_dirs "$root_dir" "$COPIED_RECORD"
        fi
    fi
}

main "$@"