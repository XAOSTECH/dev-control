#!/usr/bin/env bash
#
# Dev-Control Repository Creator
# Create GitHub repos from current folder with tags in one command
#
# Requirements:
#   - GitHub CLI (gh) installed and authenticated
#   - Git configured with user credentials
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"
export DEV_CONTROL_DIR  # Used by sourced libraries

# Source shared libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/print.sh"
source "$SCRIPT_DIR/lib/git/utils.sh"
source "$SCRIPT_DIR/lib/config.sh"

# CLI mode: none|topics|description|all
EDIT_MODE="none"
# Batch mode options
BATCH_MODE=false
ASSUME_YES=false
BATCH_DIRS=()

# ============================================================================
# PREREQUISITE CHECKS
# ============================================================================

check_prerequisites() {
    require_git
    require_gh_cli
}

# CLI argument parser (supports --edit and batch options)
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -e|--edit)
                case "${2:-all}" in
                    topics|description|all) EDIT_MODE="$2"; shift 2 ;;
                    *) EDIT_MODE="all"; shift ;;
                esac
                ;;
            -b|--batch)
                BATCH_MODE=true
                shift
                ;;
            -y|--yes)
                ASSUME_YES=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                exit 1
                ;;
            *)
                # Positional arg: treat as directory for batch
                BATCH_DIRS+=("$1")
                shift
                ;;
        esac
    done
}

show_help() {
    cat << 'EOF'
Dev-Control Repository Creator - Create GitHub repos with ease

USAGE:
  create-repo.sh [OPTIONS] [DIRECTORIES...]

OPTIONS:
  -e, --edit [MODE]      Edit existing repo metadata (topics|description|all)
  -b, --batch            Batch mode: process multiple directories
  -y, --yes              Assume yes to prompts
  -h, --help             Show this help

EXAMPLES:
  create-repo.sh                       # Create repo for current directory
  create-repo.sh --edit topics         # Edit topics only
  create-repo.sh --batch dir1 dir2     # Create repos for multiple dirs

ALIASES:
  dc-repo, dc-create

EOF
}

# ============================================================================
# GIT CONFIG FETCHING
# ============================================================================

load_gc_init_metadata() {
    # Try loading from dc-init config first
    if load_gc_metadata; then
        print_info "Loaded dc-init metadata from git config"
        # Map loaded variables to create-repo naming convention
        REPO_DESCRIPTION="${DESCRIPTION:-}"
        REPO_OWNER="${ORG_NAME:-}"
        REPO_WEBSITE="${WEBSITE_URL:-}"
    fi
    
    # Fallback to folder name
    if [[ -z "$REPO_NAME" ]]; then
        REPO_NAME=$(basename "$(pwd)")
    fi
    
    # Try to detect website URL from repo name if not set
    if [[ -z "$REPO_WEBSITE" ]]; then
        # Check if repo name looks like a domain (contains dots)
        if [[ "$REPO_NAME" =~ \. ]]; then
            REPO_WEBSITE="https://$REPO_NAME"
        fi
    fi
}

get_git_credentials() {
    # Get GitHub username from gh cli
    if command -v gh &>/dev/null; then
        GH_USERNAME=$(gh api user --jq '.login' 2>/dev/null || echo "")
    fi
    
    # Fallback to git config
    if [[ -z "$GH_USERNAME" ]]; then
        GH_USERNAME=$(git config --get user.name 2>/dev/null || echo "")
    fi
    
    GIT_EMAIL=$(git config --get user.email 2>/dev/null || echo "")
    
    print_info "GitHub user: ${CYAN}$GH_USERNAME${NC}"
}

# ============================================================================
# REPOSITORY CONFIGURATION
# ============================================================================

collect_repo_info() {
    print_section "Repository Configuration"
    
    # Repo name
    read -rp "Repository name [$REPO_NAME]: " input
    REPO_NAME="${input:-$REPO_NAME}"
    
    # Repository owner (user/org slug)
    if [[ -n "$REPO_OWNER" ]]; then
        read -rp "Repository owner (user/org) [$REPO_OWNER]: " input
        REPO_OWNER="${input:-$REPO_OWNER}"
    else
        read -rp "Repository owner (user/org): " REPO_OWNER
    fi
    
    # Description (prefill from dc-init metadata)
    if [[ -n "$REPO_DESCRIPTION" ]]; then
        read -rp "Description [$REPO_DESCRIPTION]: " input
        REPO_DESCRIPTION="${input:-$REPO_DESCRIPTION}"
    else
        read -rp "Description: " REPO_DESCRIPTION
    fi
    
    # Website URL (auto-detected from domain-like repo names)
    if [[ -n "$REPO_WEBSITE" ]]; then
        read -rp "Website URL [$REPO_WEBSITE]: " input
        REPO_WEBSITE="${input:-$REPO_WEBSITE}"
    else
        read -rp "Website URL (optional): " REPO_WEBSITE
    fi
    
    # Visibility
    echo ""
    echo "Visibility:"
    print_menu_item "1" "Public (default)"
    print_menu_item "2" "Private"
    read -rp "Choice [1]: " vis_choice
    
    case "${vis_choice:-1}" in
        2) REPO_VISIBILITY="private" ;;
        *) REPO_VISIBILITY="public" ;;
    esac
    
    # Topics
    echo ""
    read -rp "Topics (comma-separated, optional): " REPO_TOPICS
    
    echo ""
}

# ============================================================================
# REPOSITORY CREATION
# ============================================================================

init_local_git() {
    if [[ ! -d ".git" ]]; then
        print_info "Initialising local git repository..."
        git init -b main
        print_success "Git initialised with main branch"
    else
        print_info "Git repository already exists"
        # Ensure existing repo uses main branch
        if [[ "$(git symbolic-ref --short HEAD 2>/dev/null)" == "master" ]]; then
            git branch -m master main
            print_info "Renamed master to main"
        fi
    fi
}

create_initial_commit() {
    # Create .gitignore if it doesn't exist
    if [[ ! -f ".gitignore" ]]; then
        cat > .gitignore << 'GITIGNORE'
# OS generated files
.DS_Store
Thumbs.db

# IDE/Editor folders
.idea/
.vscode/
*.swp
*.swo

# Build outputs
dist/
build/
*.o
*.a

# Dependencies
node_modules/
venv/
__pycache__/

# Logs
*.log
logs/

# Environment
.env
.env.local
GITIGNORE
        print_info "Created .gitignore"
    fi
    
    # Stage and commit
    if [[ -z "$(git log -1 2>/dev/null)" ]]; then
        git add .
        git commit -m "Initial commit" --allow-empty
        print_success "Initial commit created"
    fi
}

create_github_repo() {
    print_info "Creating GitHub repository..."
    
    local gh_args=("repo" "create")
    
    # Use owner/repo format if owner is specified
    if [[ -n "$REPO_OWNER" ]]; then
        gh_args+=("$REPO_OWNER/$REPO_NAME")
    else
        gh_args+=("$REPO_NAME")
    fi
    
    gh_args+=("--source=.")
    gh_args+=("--push")
    gh_args+=("--$REPO_VISIBILITY")
    
    if [[ -n "$REPO_DESCRIPTION" ]]; then
        gh_args+=("--description" "$REPO_DESCRIPTION")
    fi
    
    if [[ -n "$REPO_WEBSITE" ]]; then
        gh_args+=("--homepage" "$REPO_WEBSITE")
    fi
    
    if gh "${gh_args[@]}"; then
        print_success "Repository created!"
        REPO_URL=$(gh repo view --json url --jq '.url' 2>/dev/null)
    else
        print_error "Failed to create repository"
        exit 1
    fi
}

update_repo_topics() {
    if [[ -n "$REPO_TOPICS" ]]; then
        print_info "Adding topics..."
        # Convert comma-separated to space-separated for gh
        local topics_list
        topics_list=$(echo "$REPO_TOPICS" | tr ',' ' ')
        
        for topic in $topics_list; do
            topic=$(echo "$topic" | xargs) # trim whitespace
            gh repo edit --add-topic "$topic" 2>/dev/null || true
        done
        print_success "Topics added"
    fi
}

save_repo_metadata() {
    # Save collected metadata to git config for future use
    if [[ -d ".git" ]]; then
        [[ -n "$REPO_OWNER" ]] && git config --local dc-init.org-name "$REPO_OWNER" 2>/dev/null || true
        [[ -n "$REPO_DESCRIPTION" ]] && git config --local dc-init.description "$REPO_DESCRIPTION" 2>/dev/null || true
        [[ -n "$REPO_WEBSITE" ]] && git config --local dc-init.website-url "$REPO_WEBSITE" 2>/dev/null || true
    fi
}

# ============================================================================
# EDIT MODE
# ============================================================================

edit_repo_metadata() {
    print_info "Editing repository metadata..."
    
    case "$EDIT_MODE" in
        topics)
            read -rp "New topics (comma-separated): " new_topics
            REPO_TOPICS="$new_topics"
            update_repo_topics
            ;;
        description)
            read -rp "New description: " new_desc
            gh repo edit --description "$new_desc"
            print_success "Description updated"
            ;;
        all)
            read -rp "New description (press Enter to skip): " new_desc
            [[ -n "$new_desc" ]] && gh repo edit --description "$new_desc"
            
            read -rp "New topics (comma-separated, press Enter to skip): " new_topics
            if [[ -n "$new_topics" ]]; then
                REPO_TOPICS="$new_topics"
                update_repo_topics
            fi
            print_success "Metadata updated"
            ;;
    esac
}

# ============================================================================
# BATCH MODE
# ============================================================================

process_batch_create() {
    print_header "Batch Repository Creation"
    
    if [[ ${#BATCH_DIRS[@]} -eq 0 ]]; then
        print_error "No directories specified for batch mode"
        exit 1
    fi
    
    for dir in "${BATCH_DIRS[@]}"; do
        echo ""
        print_separator
        print_info "Processing: $dir"
        
        if [[ ! -d "$dir" ]]; then
            print_warning "Directory not found: $dir, skipping"
            continue
        fi
        
        pushd "$dir" > /dev/null || continue
        
        REPO_NAME=$(basename "$dir")
        load_gc_init_metadata
        
        if [[ "$ASSUME_YES" != "true" ]]; then
            read -rp "Create repo '$REPO_NAME'? [Y/n]: " confirm
            if [[ "$confirm" =~ ^[Nn] ]]; then
                print_info "Skipped"
                popd > /dev/null || true
                continue
            fi
        fi
        
        init_local_git
        create_initial_commit
        create_github_repo
        update_repo_topics
        save_repo_metadata
        show_summary
        
        popd > /dev/null || true
    done
}

# ============================================================================
# SUMMARY
# ============================================================================

show_summary() {
    print_header_success "Repository Created!"
    
    print_section "Repository Details:"
    print_detail "Name" "$REPO_NAME"
    print_detail "Owner" "$GH_USERNAME"
    print_detail "Visibility" "$REPO_VISIBILITY"
    [[ -n "$REPO_URL" ]] && print_detail "URL" "$REPO_URL"
    [[ -n "$REPO_WEBSITE" ]] && print_detail "Website" "$REPO_WEBSITE"
    [[ -n "$REPO_DESCRIPTION" ]] && print_detail "Description" "$REPO_DESCRIPTION"
    [[ -n "$REPO_TOPICS" ]] && print_detail "Topics" "$REPO_TOPICS"
    
    print_section "Quick Commands:"
    print_command_hint "Open in browser" "gh repo view --web"
    print_command_hint "Edit settings" "gh repo edit"
    print_command_hint "Add templates" "dc-init"
    echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Parse CLI args
    parse_args "$@"

    # If batch mode requested, delegate to batch handler
    if [[ "$BATCH_MODE" == "true" ]] || [[ ${#BATCH_DIRS[@]} -gt 0 ]]; then
        check_prerequisites
        get_git_credentials
        process_batch_create
        exit 0
    fi

    print_header "Dev-Control Repo Creator"
    check_prerequisites
    get_git_credentials
    load_gc_init_metadata

    # If edit mode requested, perform edits and exit
    if [[ "${EDIT_MODE:-none}" != "none" ]]; then
        edit_repo_metadata
        exit 0
    fi

    collect_repo_info
    init_local_git
    create_initial_commit
    create_github_repo
    update_repo_topics
    save_repo_metadata
    show_summary
}

main "$@"
