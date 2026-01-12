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
#   --copy-temp / --only-copy-temp : Collect and merge temporary folders into $ROOT/.tmp
#   --prune / --only-prune         : Move originals to recycle (or delete) and replace with symlinks
#   --aggressive                   : Aggressively replace temp folders, remove originals and append entries to .gitignore
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"

# Make sure ERR is traced in functions
set -o errtrace

# Source shared libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/print.sh"
source "$SCRIPT_DIR/lib/git-utils.sh"
source "$SCRIPT_DIR/lib/cli.sh"
source "$SCRIPT_DIR/lib/validation.sh"

# Note: We define local is_git_repo and get_remote_url functions that take a dir argument
# These override the git-utils.sh versions which work on current directory
# This is intentional for this script's recursive directory scanning

# ============================================================================
# GIT DETECTION FUNCTIONS (local overrides for directory-based operations)
# ============================================================================

# Check if a directory is a git repository (has .git folder or file)
# Note: Overrides git-utils.sh version to accept a directory argument
local_is_git_repo() {
    local dir="$1"
    [[ -d "$dir/.git" ]] || [[ -f "$dir/.git" ]]
}

# Directories to skip (noisy or irrelevant)
EXCLUDE_DIRS=(.tmp .devcontainer .vscode node_modules .cache)

# Added common build/output directories to avoid archiving transient build artifacts
EXCLUDE_TEMP=(build CMakeFiles dist target bin obj out cmake-build-debug .git .wrangler)

# Return 0 if any path component of $1 matches an entry in EXCLUDE_DIRS
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

# Feature flags
COPY_TEMP=false
ONLY_COPY_TEMP=false
COPY_BAK=false
ONLY_COPY_BAK=false
PRUNE=false
ONLY_PRUNE=false
PRUNE_BAK=false
ONLY_PRUNE_BAK=false
DRY_RUN=false
DELETE=false
FORCE=false
AGGRESSIVE=false
AGGRESSIVE_BAK=false
TEST=false

# Temp file to record copied mappings
COPIED_RECORD=""
COPIED_RECORD_TEMP=false

# Track whether we've already shown dry-run preview messages
DRY_RUN_PREVIEW_SHOWN=false
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
        return 0
    elif [[ -d "$dir/.git" ]]; then
        return 0
    fi
    return 1
}

# Get the remote origin URL for a git repository (local version with dir argument)
local_get_remote_url() {
    local dir="$1"
    local url=""
    
    if local_is_git_repo "$dir"; then
        url=$(git -C "$dir" config --get remote.origin.url 2>/dev/null || echo "")
    fi
    
    echo "$url"
}

get_submodule_name() {
    local path="$1"
    local name

    name=$(basename "$path")
    name=$(echo "$name" | tr ' ' '_' | tr -cd '[:alnum:]._-')

    echo "$name"
}

# Use git-utils.sh get_relative_path or define locally
local_get_relative_path() {
    local parent="$1"
    local child="$2"
    
    local relative="${child#$parent/}"
    
    echo "$relative"
}

# ============================================================================
# SUBMODULE DISCOVERY
# ============================================================================

find_direct_git_children() {
    local parent_dir="$1"
    local git_children=()
    
    for dir in "$parent_dir"/*/; do
        [[ -d "$dir" ]] || continue
        dir="${dir%/}"
        if should_skip_dir "$dir"; then
            print_debug "Skipping excluded dir: $dir"
            continue
        fi

        if local_is_git_repo "$dir"; then
            git_children+=("$dir")
        fi
    done
    
    echo "${git_children[@]}"
}

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

generate_gitmodules() {
    local repo_dir="$1"
    local root_dir="$2"
    local content=""
    local submodule_count=0
    
    print_debug "generate_gitmodules: repo_dir=$repo_dir root_dir=$root_dir"
    
    for child_dir in "$repo_dir"/*/; do
        [[ -d "$child_dir" ]] || continue
        child_dir="${child_dir%/}"
        if should_skip_dir "$child_dir"; then
            print_debug "Skipping excluded dir: $child_dir"
            continue
        fi

        find_git_repos_for_parent "$repo_dir" "$child_dir" "$root_dir" content submodule_count
    done
    
    echo "$content"
}

find_git_repos_for_parent() {
    local parent_repo="$1"
    local current_dir="$2"
    local root_dir="$3"
    local content_name="$4"
    local count_name="$5"
    local -n content_ref="$content_name"
    local -n count_ref="$count_name"
    print_debug "ENTER find_git_repos_for_parent parent=${parent_repo} current=${current_dir} root=${root_dir}"
    
    if local_is_git_repo "$current_dir"; then
        local rel_path=$(local_get_relative_path "$parent_repo" "$current_dir")
        local name=$(get_submodule_name "$current_dir")
        local url=$(local_get_remote_url "$current_dir")
        
        if [[ -z "$url" ]]; then
            url=$(local_get_relative_path "$root_dir" "$current_dir")
        fi
        
        content_ref+="[submodule \"$name\"]"$'\n'
        content_ref+="\tpath = $rel_path"$'\n'
        content_ref+="\turl = $url"$'\n'
        content_ref+=$'\n'
        
        count_ref=$((count_ref + 1))
        print_debug "Added submodule: name=${name} rel_path=${rel_path} url=${url}"
        return
    fi
    
    for subdir in "$current_dir"/*/; do
        [[ -d "$subdir" ]] || continue
        subdir="${subdir%/}"
        if should_skip_dir "$subdir"; then
            print_debug "Skipping excluded dir: $subdir"
            continue
        fi
        print_debug "Recursing into subdir: $subdir (parent=${parent_repo})"
        find_git_repos_for_parent "$parent_repo" "$subdir" "$root_dir" "$content_name" "$count_name"
    done
}

write_gitmodules() {
    local repo_dir="$1"
    local content="$2"
    local gitmodules_path="$repo_dir/.gitmodules"

    if is_empty "$content"; then
        if is_file "$gitmodules_path"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                print_info "DRY-RUN: Would remove .gitmodules in $(basename "$repo_dir")"
            else
                print_info "No submodules found in $(basename "$repo_dir") - removing .gitmodules"
                rm "$gitmodules_path"
            fi
        fi
        return
    fi

    print_debug "Writing .gitmodules to $gitmodules_path (content length: ${#content} chars)"

    if [[ "$DRY_RUN" == "true" ]]; then
        local line_count
        line_count=$(printf '%s' "$content" | wc -l)
        print_info "DRY-RUN: Would write .gitmodules (${line_count} lines) for $(basename "$repo_dir")"
    else
        echo -e "$content" > "$gitmodules_path"
        print_success "Generated .gitmodules for: $(basename "$repo_dir")"
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
    
    print_info "${indent}Processing: $(local_get_relative_path "$root_dir" "$repo_dir")"
    print_debug "ENTER process_repository repo=${repo_dir} root=${root_dir} depth=${depth}"
    
    local content=""
    local submodule_count=0
    
    for child in "$repo_dir"/*/; do
        [[ -d "$child" ]] || continue
        child="${child%/}"
        
        [[ "$(basename "$child")" == ".git" ]] && continue
        
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
        if is_file "$repo_dir/.gitmodules"; then
            rm "$repo_dir/.gitmodules"
            print_info "${indent}  Removed empty .gitmodules"
        fi
    fi

    for child in "$repo_dir"/*/; do
        [[ -d "$child" ]] || continue
        child="${child%/}"

        if should_skip_dir "$child"; then
            print_debug "Skipping excluded dir: $child"
            continue
        fi

        if local_is_git_repo "$child"; then
            process_repository "$child" "$root_dir" $((depth + 1))
        else
            for nested in "$child"/*/; do
                [[ -d "$nested" ]] || continue
                nested="${nested%/}"
                if should_skip_dir "$nested"; then
                    print_debug "Skipping excluded nested dir: $nested"
                    continue
                fi
                if local_is_git_repo "$nested"; then
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
        if ! is_directory "$root_dir"; then
            print_error "Directory does not exist: $root_dir"
            exit 1
        fi
    else
        print_section "Enter the root directory path"
        echo -e "(Press Enter to use current directory: $(pwd))"
        read -rp "> " root_dir
        
        if is_empty "$root_dir"; then
            root_dir=$(pwd)
        fi
        
        root_dir="${root_dir/#\~/$HOME}"
        
        if ! is_directory "$root_dir"; then
            print_error "Directory does not exist: $root_dir"
            exit 1
        fi
    fi
    
    root_dir=$(cd "$root_dir" && pwd)
    
    echo "$root_dir"
}

show_help() {
    print_header "Git-Control Module Nesting" 50
    
    echo "Automatically manage .gitmodules for nested Git repositories."
    echo ""
    print_section "Usage"
    echo "  $(basename "$0") [OPTIONS] [ROOT_DIR]"
    echo ""
    print_section "Options"
    print_menu_item "--copy-temp" "Collect temp folders into ROOT/.tmp after nesting"
    print_menu_item "--only-copy-temp" "Run only the copy-temp flow"
    print_menu_item "--copy-bak" "Collect backup folders into ROOT/.bak"
    print_menu_item "--only-copy-bak" "Run only the copy-bak flow"
    print_menu_item "--prune" "Move originals to recycle and replace with symlinks"
    print_menu_item "--only-prune" "Run prune flow only"
    print_menu_item "--aggressive" "Aggressive replace: merge, delete originals, create symlinks"
    print_menu_item "--dry-run" "Preview changes without applying"
    print_menu_item "--delete" "Permanently delete originals instead of recycling"
    print_menu_item "-y" "Auto-confirm prompts"
    print_menu_item "--test" "Run safety test sequence in dry-run mode"
    print_menu_item "-h, --help" "Show this help message"
    echo ""
    print_section "Examples"
    print_command_hint "Interactive mode" "$(basename "$0")"
    print_command_hint "Dry run" "$(basename "$0") --dry-run ~/projects"
    print_command_hint "Copy temp folders" "$(basename "$0") --only-copy-temp ~/projects"
    print_command_hint "Aggressive cleanup" "$(basename "$0") --aggressive --dry-run ~/projects"
}

show_plan() {
    local root_dir="$1"
    
    print_header "Module Nesting Plan"
    print_detail "Root" "$root_dir"
    print_detail "Excluded" "${EXCLUDE_DIRS[*]}"
    print_detail "Mode" "$(if [[ "$DRY_RUN" == "true" ]]; then echo "DRY-RUN (preview only)"; else echo "LIVE (changes will be applied)"; fi)"
    echo ""
}

show_summary() {
    echo ""
    print_separator
    if [[ "$DRY_RUN" == "true" ]]; then
        print_header_warning "Module Nesting Complete (DRY-RUN)" 50
        print_info "No changes were made. Run without --dry-run to apply."
    else
        print_header_success "Module Nesting Complete" 50
    fi
    
    print_section "Next Steps"
    print_command_hint "Check git status" "git status"
    print_command_hint "Review .gitmodules" "cat .gitmodules"
    print_command_hint "Initialize submodules" "git submodule update --init --recursive"
}

# ============================================================================
# CLI ARGUMENT PARSING
# ============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --copy-temp)
                COPY_TEMP=true
                shift
                ;;
            --only-copy-temp)
                ONLY_COPY_TEMP=true
                shift
                ;;
            --copy-bak)
                COPY_BAK=true
                shift
                ;;
            --only-copy-bak)
                ONLY_COPY_BAK=true
                shift
                ;;
            --prune)
                PRUNE=true
                shift
                ;;
            --only-prune)
                ONLY_PRUNE=true
                shift
                ;;
            --prune-bak)
                PRUNE_BAK=true
                shift
                ;;
            --only-prune-bak)
                ONLY_PRUNE_BAK=true
                shift
                ;;
            --dry-run|-n)
                DRY_RUN=true
                shift
                ;;
            --delete)
                DELETE=true
                shift
                ;;
            -y|--yes)
                FORCE=true
                shift
                ;;
            --aggressive)
                AGGRESSIVE=true
                shift
                ;;
            --aggressive-bak)
                AGGRESSIVE_BAK=true
                shift
                ;;
            --test)
                TEST=true
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                DEBUG=true
                shift
                ;;
            --)
                shift
                break
                ;;
            -*)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                # Positional argument (root directory)
                root_dir="$1"
                shift
                ;;
        esac
    done
}

# ============================================================================
# TEMP/BAK DIRECTORY OPERATIONS
# ============================================================================

# Generic prune directories function (simplified for refactoring)
prune_dirs() {
    local root_dir="$1"
    local dest_term="$2"
    local record_file="$3"

    require_var "root_dir" "$root_dir"
    require_var "dest_term" "$dest_term"
    
    if [[ -n "$record_file" ]] && ! is_file "$record_file"; then
        print_error "prune_dirs: record_file not found: $record_file"
        return 1
    fi

    local dest_dir="$root_dir/$dest_term"
    local recycle_base="$dest_dir/.recycle"
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

    if is_empty "$record_file"; then
        record_file=$(ls -1t "$dest_dir"/copied_dirs.* 2>/dev/null | head -n1 || true)
        if is_empty "$record_file"; then
            print_error "No copied record file found in $dest_dir"
            return 1
        fi
    fi

    print_info "Prune ($dest_term): using record file: $record_file"

    while IFS=$'\t' read -r src tgt; do
        [[ -z "$src" || -z "$tgt" ]] && continue
        total=$((total + 1))

        case "$src" in
            "$dest_dir" | "$dest_dir"/* )
                print_info "Skipping $src (inside destination: $dest_dir)"
                skipped=$((skipped + 1))
                continue
                ;;
        esac

        if ! is_directory "$tgt"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                print_info "DRY-RUN: Target backup not found for $src -> $tgt; simulating presence"
            else
                print_warning "Target backup not found for $src -> $tgt; skipping"
                skipped=$((skipped + 1))
                continue
            fi
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            if [[ "$DELETE" == "true" ]]; then
                print_info "DRY-RUN: Would delete contents of $src and create symlinks"
            else
                print_info "DRY-RUN: Would move contents of $src to recycle and create symlinks"
            fi
            pruned=$((pruned + 1))
            continue
        fi

        if [[ "$DELETE" == "true" ]]; then
            if is_directory "$src"; then
                rm -rf "$src" || true
                print_info "Deleted $src"
            fi
        else
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

        local parent_dir
        parent_dir=$(dirname "$src")
        mkdir -p "$parent_dir"
        local rel_tgt
        rel_tgt=$(realpath --relative-to="$parent_dir" "$tgt" 2>/dev/null || echo "$tgt")
        ln -sfn "$rel_tgt" "$src"
        print_info "Linked $src -> $rel_tgt"

        pruned=$((pruned + 1))
    done < "$record_file"

    print_success "Prune ($dest_term) complete: processed=$total pruned=$pruned skipped=$skipped"

    if [[ "$PRUNE_CREATED_TEMP" == "true" && -n "$recycle_base" && -d "$recycle_base" ]]; then
        rm -rf "$recycle_base" || true
        print_debug "Removed temporary recycle base used for DRY-RUN preview"
    fi

    return 0
}

prune_temp_dirs() {
    prune_dirs "$1" ".tmp" "$2"
}

prune_bak_dirs() {
    prune_dirs "$1" ".bak" "$2"
}

# Copy directories function (simplified)
copy_dirs() {
    local root_dir="$1"
    local dest_term="$2"
    local KEEP_EPHEMERAL="${3:-false}"
    shift 3
    local patterns=("$@")

    require_var "root_dir" "$root_dir"
    require_var "dest_term" "$dest_term"
    
    if [[ ${#patterns[@]} -eq 0 ]]; then
        print_error "copy_dirs: at least one pattern required"
        return 1
    fi

    local dest_dir="$root_dir/$dest_term"

    if [[ "$DRY_RUN" == "true" ]]; then
        print_dry_run_preview_once "DRY-RUN: preview mode — will NOT create $dest_dir folders"
        COPIED_RECORD=$(mktemp)
        COPIED_RECORD_TEMP=true
    else
        mkdir -p "$dest_dir"
        COPIED_RECORD=$(mktemp -p "$dest_dir" copied_dirs.XXXXXX)
        COPIED_RECORD_TEMP=false
    fi

    local found=0
    local skipped=0
    local dest_canon
    dest_canon=$(realpath -m "$dest_dir" 2>/dev/null || echo "$dest_dir")
    
    local find_pattern=""
    for pattern in "${patterns[@]}"; do
        if is_empty "$find_pattern"; then
            find_pattern="-iname $pattern"
        else
            find_pattern="$find_pattern -o -iname $pattern"
        fi
    done

    local prune_args=()
    for e in "${EXCLUDE_TEMP[@]}"; do
        prune_args+=( -iname "$e" -o )
    done
    if [[ ${#prune_args[@]} -gt 0 ]]; then
        unset 'prune_args[${#prune_args[@]}-1]'
    fi

    while IFS= read -r -d '' srcdir; do
        src_canon=$(realpath -m "$srcdir" 2>/dev/null || echo "$srcdir")

        if [[ "$src_canon" == "$dest_canon" || "$src_canon" == "$dest_canon"/* ]]; then
            skipped=$((skipped + 1))
            continue
        fi

        if path_has_excluded_temp_component "$srcdir"; then
            skipped=$((skipped + 1))
            continue
        fi

        local folder_name
        folder_name=$(basename "$srcdir")
        local parent_name
        parent_name=$(basename "$(dirname "$srcdir")")
        
        local target="$dest_dir/$parent_name"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "DRY-RUN: Would copy $srcdir -> $target"
        else
            mkdir -p "$target"
            cp -r "$srcdir"/* "$target/" 2>/dev/null || true
            print_success "Copied: $srcdir -> $target"
        fi
        
        echo -e "$srcdir\t$target" >> "$COPIED_RECORD"
        found=$((found + 1))
        
    done < <(if [[ ${#prune_args[@]} -gt 0 ]]; then find "$root_dir" \( "${prune_args[@]}" \) -prune -o -type d \( $find_pattern \) -print0 2>/dev/null; else find "$root_dir" -type d \( $find_pattern \) -print0 2>/dev/null; fi)

    print_success "Copy ($dest_term) complete: found=$found skipped=$skipped"
}

copy_temp_dirs() {
    copy_dirs "$1" ".tmp" "${2:-false}" ".tmp" ".temp" "tmp" "temp"
}

copy_bak_dirs() {
    copy_dirs "$1" ".bak" "${2:-false}" ".bak" ".backup" "bak" "backup" "*.bak"
}

aggressive_replace_dirs() {
    local root_dir="$1"
    print_warning "Aggressive replace mode: originals will be removed and replaced with symlinks"
    
    copy_temp_dirs "$root_dir"
    
    if [[ -n "$COPIED_RECORD" ]] && is_file "$COPIED_RECORD"; then
        DELETE=true
        prune_temp_dirs "$root_dir" "$COPIED_RECORD"
    fi
}

aggressive_replace_bak_dirs() {
    local root_dir="$1"
    print_warning "Aggressive replace mode for .bak: originals will be removed and replaced with symlinks"
    
    copy_bak_dirs "$root_dir"
    
    if [[ -n "$COPIED_RECORD" ]] && is_file "$COPIED_RECORD"; then
        DELETE=true
        prune_bak_dirs "$root_dir" "$COPIED_RECORD"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local root_dir=""
    
    parse_args "$@"
    
    # Handle flow-specific modes first
    if [[ "$ONLY_PRUNE" == "true" ]]; then
        root_dir=$(get_root_directory "$root_dir")
        print_info "Root directory: $root_dir"
        
        local record
        record=$(ls -1t "$root_dir/.tmp"/copied_dirs.* 2>/dev/null | head -n1 || true)
        
        if is_empty "$record" || ! is_file "$record"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                print_info "DRY-RUN: No copied record found — generating ephemeral record"
                copy_temp_dirs "$root_dir" "true"
                record="$COPIED_RECORD"
            else
                print_error "No copied record found. Run with --copy-temp first."
                exit 1
            fi
        fi
        
        print_info "--only-prune: running prune flow using record $record"
        prune_temp_dirs "$root_dir" "$record"
        exit 0
    fi
    
    if [[ "$ONLY_COPY_TEMP" == "true" ]]; then
        root_dir=$(get_root_directory "$root_dir")
        print_info "Root directory: $root_dir"
        copy_temp_dirs "$root_dir"
        if [[ "$PRUNE" == "true" ]]; then
            prune_temp_dirs "$root_dir"
        fi
        exit 0
    fi
    
    if [[ "$AGGRESSIVE" == "true" ]]; then
        root_dir=$(get_root_directory "$root_dir")
        print_info "Root directory: $root_dir"
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "DRY-RUN: previewing aggressive actions"
        fi
        aggressive_replace_dirs "$root_dir"
        aggressive_replace_bak_dirs "$root_dir"
        exit 0
    fi
    
    if [[ "$ONLY_COPY_BAK" == "true" || "$AGGRESSIVE_BAK" == "true" ]]; then
        root_dir=$(get_root_directory "$root_dir")
        print_info "Root directory: $root_dir"
        if [[ "$AGGRESSIVE_BAK" == "true" ]]; then
            aggressive_replace_bak_dirs "$root_dir"
        else
            copy_bak_dirs "$root_dir"
            if [[ "$PRUNE_BAK" == "true" ]]; then
                prune_bak_dirs "$root_dir"
            fi
        fi
        exit 0
    fi
    
    if [[ "$ONLY_PRUNE_BAK" == "true" ]]; then
        root_dir=$(get_root_directory "$root_dir")
        print_info "Root directory: $root_dir"
        local record
        record=$(ls -1t "$root_dir/.bak"/copied_dirs.* 2>/dev/null | head -n1 || true)
        
        if is_empty "$record" || ! is_file "$record"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                print_info "DRY-RUN: Generating ephemeral record"
                copy_bak_dirs "$root_dir" "true"
                record="$COPIED_RECORD"
            else
                print_error "No copied record found. Run with --copy-bak first."
                exit 1
            fi
        fi
        
        prune_bak_dirs "$root_dir" "$record"
        exit 0
    fi
    
    # Normal module nesting flow
    root_dir=$(get_root_directory "$root_dir")
    print_info "Root directory: $root_dir"
    
    if ! local_is_git_repo "$root_dir"; then
        print_warning "Root directory is not a git repository."
        print_command_hint "Initialize" "cd $root_dir && git init"
        echo ""
        if ! confirm "Continue anyway?"; then
            exit 0
        fi
    fi
    
    show_plan "$root_dir"
    
    echo ""
    print_info "Scanning directory structure..."
    echo ""
    
    if local_is_git_repo "$root_dir"; then
        process_repository "$root_dir" "$root_dir" 0
    else
        while IFS= read -r -d '' git_dir; do
            local repo_dir=$(dirname "$git_dir")
            process_repository "$repo_dir" "$root_dir" 0
        done < <(find "$root_dir" -maxdepth 2 -name ".git" -print0 2>/dev/null)
    fi
    
    show_summary
    
    if [[ "$COPY_TEMP" == "true" ]]; then
        print_info "--copy-temp: collecting temp directories into $root_dir/.tmp"
        copy_temp_dirs "$root_dir"
        if [[ "$PRUNE" == "true" && -n "$COPIED_RECORD" ]] && is_file "$COPIED_RECORD"; then
            prune_temp_dirs "$root_dir" "$COPIED_RECORD"
        fi
    fi
}

main "$@"
