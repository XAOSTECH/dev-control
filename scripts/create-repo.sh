#!/usr/bin/env bash
#
# Git-Control Repository Creator
# Create GitHub repos from current folder with tags in one command
#
# Requirements:
#   - GitHub CLI (gh) installed and authenticated
#   - Git configured with user credentials
#

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"

# Source shared libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/print.sh"

# CLI mode: none|topics|description|all
EDIT_MODE="none"
# Batch mode options
BATCH_MODE=false
ASSUME_YES=false
BATCH_DIRS=()

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# ============================================================================
# PREREQUISITE CHECKS
# ============================================================================

check_prerequisites() {
    # Check for gh CLI
    if ! command -v gh &> /dev/null; then
        print_error "GitHub CLI (gh) is not installed."
        echo -e "  Install with: ${CYAN}sudo apt install gh${NC} or ${CYAN}brew install gh${NC}"
        echo -e "  Then run: ${CYAN}gh auth login${NC}"
        exit 1
    fi
    
    # Check gh authentication
    if ! gh auth status &> /dev/null; then
        print_error "GitHub CLI is not authenticated."
        echo -e "  Run: ${CYAN}gh auth login${NC}"
        exit 1
    fi
    
    # Check for git
    if ! command -v git &> /dev/null; then
        print_error "Git is not installed."
        exit 1
    fi
}

# CLI argument parser (supports --edit and batch options)
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --edit)
                EDIT_MODE="all" ; shift ;;
            --edit=*)
                val="${1#*=}"
                case "$val" in
                    topics) EDIT_MODE="topics" ;;
                    description) EDIT_MODE="description" ;;
                    all) EDIT_MODE="all" ;;
                    *) EDIT_MODE="$val" ;;
                esac
                shift ;;
            --edit-topics)
                EDIT_MODE="topics" ; shift ;;
            --batch)
                BATCH_MODE=true ; shift ;;
            -y|--yes)
                ASSUME_YES=true ; shift ;;
            -h|--help)
                echo "Usage: $0 [--edit[=topics|description|all]] [--batch] [--yes] [DIR...]

Examples:
  $0 --batch ./repo1 ./repo2    # Create repos from these directories using cached gc-init metadata
  $0 --batch -y                 # Create repos for all subfolders non-interactively
  $0 ./some/repo                # Create repo for a specific directory" ; exit 0 ;;
            *)
                # Positional args are treated as directories to create
                BATCH_DIRS+=("$1")
                shift ;;
        esac
    done
} 

# ============================================================================
# GIT CONFIG FETCHING
# ============================================================================

load_gc_init_metadata() {
    # Try to load metadata saved by gc-init from git config
    PROJECT_NAME=$(git config --local gc-init.project-name 2>/dev/null || echo "")
    REPO_SLUG=$(git config --local gc-init.repo-slug 2>/dev/null || echo "")
    ORG_NAME=$(git config --local gc-init.org-name 2>/dev/null || echo "")
    SHORT_DESCRIPTION=$(git config --local gc-init.description 2>/dev/null || echo "")
    LICENSE_TYPE=$(git config --local gc-init.license-type 2>/dev/null || echo "")

    if [[ -n "$PROJECT_NAME" ]]; then
        print_info "Loaded project metadata from gc-init"
        print_info "  Project: $PROJECT_NAME"
        print_info "  Repo: $REPO_SLUG"
        print_info "  Org: $ORG_NAME"
        local owner_display="${REPO_OWNER:-${ORG_NAME:-$GH_USERNAME}}"
        if [[ -n "$owner_display" && -n "$REPO_SLUG" ]]; then
            print_info "  Full: ${owner_display}/${REPO_SLUG}"
            print_info "  Repo URL: https://github.com/${owner_display}/${REPO_SLUG}"
        fi
        if [[ -n "$SHORT_DESCRIPTION" ]]; then
            print_info "  Description: $SHORT_DESCRIPTION"
        fi
        echo ""
    fi
}

get_git_credentials() {
    # Get username from git config
    GIT_USERNAME=$(git config --get user.name 2>/dev/null || echo "")
    GIT_EMAIL=$(git config --get user.email 2>/dev/null || echo "")
    
    # Get GitHub username from gh CLI (more reliable for API calls)
    GH_USERNAME=$(gh api user --jq '.login' 2>/dev/null || echo "")
    
    if [[ -z "$GH_USERNAME" ]]; then
        print_error "Could not fetch GitHub username."
        echo -e "  Ensure you're authenticated: ${CYAN}gh auth login${NC}"
        exit 1
    fi
    
    print_info "GitHub User: ${CYAN}$GH_USERNAME${NC}"
    if [[ -n "$GIT_USERNAME" ]]; then
        print_info "Git Name: ${CYAN}$GIT_USERNAME${NC}"
    fi
    if [[ -n "$GIT_EMAIL" ]]; then
        print_info "Git Email: ${CYAN}$GIT_EMAIL${NC}"
    fi
    echo ""
}

# ============================================================================
# REPOSITORY CONFIGURATION
# ============================================================================

collect_repo_info() {
    local current_folder
    current_folder=$(basename "$(pwd)")
    
    # Use gc-init data if available, otherwise use current folder name
    local name_default="${PROJECT_NAME:-${REPO_SLUG:-$current_folder}}"
    local desc_default="${SHORT_DESCRIPTION:-A repository by $GH_USERNAME}"
    
    # Repository name (displayed as entered, preserve capitalization)
    echo -e "${BOLD}Repository Configuration${NC}\n"
    read -rp "Repository name [$name_default]: " REPO_NAME
    REPO_NAME="${REPO_NAME:-$name_default}"

    # Repository owner (user/org) - allow overriding the detected account/org
    read -rp "Repository owner (user/org) [${ORG_NAME:-$GH_USERNAME}]: " REPO_OWNER
    REPO_OWNER="${REPO_OWNER:-${ORG_NAME:-$GH_USERNAME}}"
    
    # Compute a sanitized slug for actual repo creation (lowercase, safe chars)
    REPO_SLUG=$(echo "$REPO_NAME" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]//g')
    
    # Description
    read -rp "Description [$desc_default]: " input_desc
    REPO_DESCRIPTION="${input_desc:-$desc_default}"
    
    # Visibility
    echo ""
    echo "Repository visibility:"
    echo -e "  ${CYAN}1)${NC} Private (default)"
    echo -e "  ${CYAN}2)${NC} Public"
    read -rp "Choice [1]: " visibility_choice
    case "${visibility_choice:-1}" in
        2) REPO_VISIBILITY="public" ;;
        *) REPO_VISIBILITY="private" ;;
    esac
    
    # Topics/Tags
    echo ""
    echo -e "Enter topics/tags (comma-separated, e.g., ${CYAN}python,automation,cli${NC}):"
    read -rp "> " REPO_TOPICS_INPUT
    
    # Clean and format topics
    if [[ -n "$REPO_TOPICS_INPUT" ]]; then
        # 1. Remove spaces around commas
        # 2. Convert remaining spaces within topics to hyphens
        # 3. Lowercase everything
        # 4. Remove any invalid characters
        REPO_TOPICS=$(echo "$REPO_TOPICS_INPUT" | \
            sed 's/[[:space:]]*,[[:space:]]*/,/g' | \
            tr ' ' '-' | \
            tr '[:upper:]' '[:lower:]' | \
            sed 's/[^a-z0-9,_-]//g' | \
            sed 's/^,//;s/,$//' | \
            sed 's/,,*/,/g')
    else
        REPO_TOPICS=""
    fi
    
    # Homepage (optional)
    echo ""
    read -rp "Homepage URL (optional): " REPO_HOMEPAGE
    
    echo ""
}

# ============================================================================
# REPOSITORY CREATION
# ============================================================================

init_local_git() {
    # Check if already a git repo
    if [[ -d ".git" ]]; then
        local has_remote=false
        local has_commits=false
        local existing_remote=""
        local commit_count=0
        
        # Check for existing remote
        if git remote get-url origin &>/dev/null; then
            has_remote=true
            existing_remote=$(git remote get-url origin)
        fi
        
        # Check for existing commits
        if git log --oneline -1 &>/dev/null; then
            has_commits=true
            commit_count=$(git rev-list --count HEAD 2>/dev/null || echo "0")
        fi
        
        # Report what we found
        print_warning "Existing .git folder detected"
        if [[ "$has_commits" == "true" ]]; then
            echo -e "  • ${CYAN}Commits:${NC} $commit_count existing commit(s)"
        fi
        if [[ "$has_remote" == "true" ]]; then
            echo -e "  • ${CYAN}Remote:${NC}  $existing_remote"
        fi
        echo ""
        
        # Offer options based on what exists
        echo "How would you like to proceed?"
        echo -e "  ${CYAN}1)${NC} Keep existing commits, remove remote only (recommended)"
        echo -e "  ${CYAN}2)${NC} Start fresh - remove .git entirely and reinitialise"
        echo -e "  ${CYAN}3)${NC} Cancel operation"
        read -rp "Choice [1]: " git_choice
        
        case "${git_choice:-1}" in
            2)
                print_info "Removing existing .git folder..."
                rm -rf .git
                print_info "Initialising fresh git repository..."
                git config --global init.defaultBranch Main
                git init
                create_initial_commit
                return
                ;;
            3)
                print_info "Cancelled."
                exit 0
                ;;
            *)
                # Option 1: Keep commits, remove remote if exists
                if [[ "$has_remote" == "true" ]]; then
                    git remote remove origin
                    print_info "Removed existing remote 'origin'"
                fi
                if [[ "$has_commits" == "false" ]]; then
                    print_info "No commits found, creating initial commit..."
                    create_initial_commit
                else
                    print_info "Keeping $commit_count existing commit(s)"
                fi
                ;;
        esac
    else
        print_info "Initialising git repository..."
        git config --global init.defaultBranch Main
        git init
        create_initial_commit
    fi
}

create_initial_commit() {
    if [[ ! -f ".gitignore" ]]; then
        cat > .gitignore << 'EOF'
# OS generated files
.DS_Store
Thumbs.db

# IDE/Editor folders
.idea/
.vscode/
*.swp
*.swo

# Dependencies
node_modules/
vendor/
__pycache__/
*.pyc

# Build outputs
dist/
build/
*.egg-info/

# Environment
.env
.env.local
*.env

# Logs
*.log
logs/
EOF
        print_info "Created default .gitignore"
    fi
    
    git add .
    git commit -m "Initial commit" || print_warning "Nothing to commit"
}

create_github_repo() {
    local REPO_OWNER_LOCAL="${REPO_OWNER:-${ORG_NAME:-$GH_USERNAME}}"
    print_info "Creating GitHub repository: ${CYAN}$REPO_OWNER_LOCAL/$REPO_NAME${NC} ($REPO_VISIBILITY)"
    
    # Build gh command (specify owner explicitly if provided)
    local gh_args=("repo" "create" "${REPO_OWNER_LOCAL}/${REPO_NAME}")
    gh_args+=("--$REPO_VISIBILITY")
    gh_args+=("--source" ".")
    gh_args+=("--push")
    
    if [[ -n "$REPO_DESCRIPTION" ]]; then
        gh_args+=("--description" "$REPO_DESCRIPTION")
    fi
    
    if [[ -n "$REPO_HOMEPAGE" ]]; then
        gh_args+=("--homepage" "$REPO_HOMEPAGE")
    fi
    
    # Create the repository
    if gh "${gh_args[@]}"; then
        print_success "Repository created successfully!"
        REPO_OWNER="$REPO_OWNER_LOCAL"
        REPO_URL="https://github.com/$REPO_OWNER_LOCAL/$REPO_SLUG"
    else
        print_error "Failed to create repository"
        exit 1
    fi
}

# ============================================================================
# TOPICS/TAGS UPDATE
# ============================================================================

update_repo_topics() {
    if [[ -z "$REPO_TOPICS" ]]; then
        print_info "No topics specified, skipping..."
        return 0
    fi
}

# Edit repository metadata (description/topics)
edit_repo_metadata() {
    # Ensure GitHub credentials are available (only if missing)
    if [[ -z "$GH_USERNAME" ]]; then
        get_git_credentials
    fi

    # Load saved metadata if available
    load_gc_init_metadata

    # Try to determine repository name from saved slug or git remote
    if [[ -z "$REPO_NAME" ]]; then
        if [[ -n "$REPO_SLUG" ]]; then
            REPO_NAME="$REPO_SLUG"
        elif git remote get-url origin &>/dev/null; then
            origin_url=$(git remote get-url origin 2>/dev/null || echo "")
            if [[ "$origin_url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
                GH_USERNAME="${BASH_REMATCH[1]}"
                REPO_NAME="${BASH_REMATCH[2]}"
            fi
        fi
    fi

    # If still unknown, present a short list of repos for selection
    if [[ -z "$REPO_NAME" ]]; then
        print_info "Fetching repositories for $GH_USERNAME..."
        mapfile -t repos < <(gh repo list "$GH_USERNAME" --limit 20 --json name --jq '.[].name' 2>/dev/null || true)
        if [[ ${#repos[@]} -gt 0 ]]; then
            echo "Select a repository to edit:"
            for i in "${!repos[@]}"; do
                printf "  %d) %s\n" $((i+1)) "${repos[$i]}"
            done
            read -rp "Choice (number or name): " choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#repos[@]} )); then
                REPO_NAME="${repos[$((choice-1))]}"
            else
                REPO_NAME="$choice"
            fi
        else
            read -rp "Repository name to edit: " REPO_NAME
        fi
    fi

    # Fetch current topics from GitHub if not provided
    if [[ -z "$REPO_TOPICS" ]]; then
        REPO_TOPICS=$(gh api "/repos/$GH_USERNAME/$REPO_NAME/topics" -H "Accept: application/vnd.github+json" --jq '.names|join(",")' 2>/dev/null || echo "")
    fi

    # Description
    if [[ "$EDIT_MODE" == "all" || "$EDIT_MODE" == "description" ]]; then
        read -rp "Description [${REPO_DESCRIPTION:-none}]: " input_desc
        input_desc="${input_desc:-$REPO_DESCRIPTION}"
        if [[ -n "$input_desc" ]]; then
            if gh repo edit "$GH_USERNAME/$REPO_NAME" --description "$input_desc" &>/dev/null; then
                print_success "Description updated"
                REPO_DESCRIPTION="$input_desc"
            else
                print_warning "Failed to update description via gh"
            fi
        fi
    fi

    # Topics
    if [[ "$EDIT_MODE" == "all" || "$EDIT_MODE" == "topics" ]]; then
        read -rp "Topics (comma-separated) [${REPO_TOPICS:-none}]: " input_topics
        input_topics="${input_topics:-$REPO_TOPICS}"
        REPO_TOPICS="$input_topics"
        if [[ -n "$REPO_TOPICS" ]]; then
            update_repo_topics || print_warning "Topics update failed — try 'gh repo edit --add-topic <topic>'"
        fi
    fi
}

# Restore update_repo_topics function (start of function)
update_repo_topics() { 
    
    print_info "Updating repository topics..."
    
    # Convert comma-separated to JSON array
    local topics_json
    topics_json=$(echo "$REPO_TOPICS" | tr ',' '\n' | while read -r topic; do
        [[ -n "$topic" ]] && echo "\"$topic\""
    done | paste -sd ',' | sed 's/^/[/;s/$/]/')
    
    # Use GitHub API to set topics
    if gh api \
        --method PUT \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/$GH_USERNAME/$REPO_NAME/topics" \
        --input - <<< "{\"names\": $topics_json}" &>/dev/null; then
        print_success "Topics updated!"
    else
        # Fallback: use gh repo edit
        print_warning "API method failed, trying gh repo edit..."
        
        # Build --add-topic arguments
        local topic_args=""
        IFS=',' read -ra TOPIC_ARRAY <<< "$REPO_TOPICS"
        for topic in "${TOPIC_ARRAY[@]}"; do
            topic=$(echo "$topic" | tr -d ' ')
            topic_args+="--add-topic $topic "
        done
        
        # Run single command with all topics
        if eval "gh repo edit $GH_USERNAME/$REPO_NAME $topic_args" 2>/dev/null; then
            print_success "Topics updated!"
        else
            print_warning "Could not update topics. Add them manually with:"
            echo -e "  ${CYAN}gh repo edit --add-topic <topic>${NC}"
        fi
    fi
}

# ============================================================================
# BATCH HANDLER
# ============================================================================

process_batch_create() {
    # If no explicit dirs passed, find immediate subdirectories
    local dirs=()
    if [[ ${#BATCH_DIRS[@]} -gt 0 ]]; then
        dirs=("${BATCH_DIRS[@]}")
    else
        while IFS= read -r d; do
            dirs+=("$d")
        done < <(find . -maxdepth 1 -mindepth 1 -type d -printf '%P\n')
    fi

    if [[ ${#dirs[@]} -eq 0 ]]; then
        print_warning "No directories found to process for batch create"
        return 1
    fi

    check_prerequisites
    get_git_credentials

    for d in "${dirs[@]}"; do
        if [[ ! -d "$d" ]]; then
            print_warning "Skipping non-directory: $d"
            continue
        fi

        print_header
        print_info "Processing: $d"
        pushd "$d" > /dev/null || { print_error "Failed to enter $d"; continue; }

        # Load metadata saved by gc-init (if any)
        load_gc_init_metadata

        # If minimal metadata present, use it for non-interactive create
        if [[ "$ASSUME_YES" == "true" && -n "$PROJECT_NAME" ]]; then
            REPO_NAME="$PROJECT_NAME"
            REPO_SLUG="${REPO_SLUG:-$(echo "$REPO_NAME" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]//g')}"
            REPO_OWNER="${ORG_NAME:-$GH_USERNAME}"
            REPO_DESCRIPTION="${SHORT_DESCRIPTION:-A project by $REPO_OWNER}"
            REPO_VISIBILITY="private"

            echo "Creating repository: $REPO_OWNER/$REPO_SLUG"
            init_local_git
            create_github_repo
            update_repo_topics || true
            show_summary
        else
            # Fallback to interactive per-directory flow
            collect_repo_info
            init_local_git
            create_github_repo
            update_repo_topics
            show_summary
        fi

        popd > /dev/null || true
    done
}


# ============================================================================
# SUMMARY
# ============================================================================

show_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║${NC}                   ${CYAN}Repository Created!${NC}                        ${BOLD}${GREEN}║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Repository Details:${NC}"
    echo -e "  • ${CYAN}Name:${NC}        $REPO_NAME"
    echo -e "  • ${CYAN}Owner:${NC}       $GH_USERNAME"
    echo -e "  • ${CYAN}Visibility:${NC}  $REPO_VISIBILITY"
    echo -e "  • ${CYAN}URL:${NC}         $REPO_URL"
    if [[ -n "$REPO_DESCRIPTION" ]]; then
        echo -e "  • ${CYAN}Description:${NC} $REPO_DESCRIPTION"
    fi
    if [[ -n "$REPO_TOPICS" ]]; then
        echo -e "  • ${CYAN}Topics:${NC}      $REPO_TOPICS"
    fi
    echo ""
    echo -e "${BOLD}Quick Commands:${NC}"
    echo -e "  ${GREEN}gh repo view --web${NC}    - Open in browser"
    echo -e "  ${GREEN}gh repo edit${NC}          - Edit settings"
    echo -e "  ${GREEN}gc-init${NC}               - Add templates"
    echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Parse CLI args (e.g., --edit or --batch)
    parse_args "$@"

    # If batch mode requested, delegate to batch handler
    if [[ "$BATCH_MODE" == "true" ]] || [[ ${#BATCH_DIRS[@]} -gt 0 ]]; then
        process_batch_create
        exit 0
    fi

    print_header
    check_prerequisites
    get_git_credentials
    load_gc_init_metadata

    # If edit mode requested, perform edits and exit
    if [[ "${EDIT_MODE:-none}" != "none" ]]; then
        edit_repo_metadata
        exit 0
    fi

    collect_repo_info
    
    local REPO_OWNER_DISPLAY="${REPO_OWNER:-${ORG_NAME:-$GH_USERNAME}}"
    echo -e "${BOLD}Ready to create:${NC}"
    echo -e "  Repository: ${CYAN}$REPO_OWNER_DISPLAY/$REPO_NAME${NC}"
    echo -e "  Visibility: ${CYAN}$REPO_VISIBILITY${NC}"
    if [[ -n "$REPO_TOPICS" ]]; then
        echo -e "  Topics:     ${CYAN}$REPO_TOPICS${NC}"
    fi
    echo ""
    read -rp "Proceed? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        print_info "Cancelled."
        exit 0
    fi
    
    echo ""
    
    init_local_git
    create_github_repo
    update_repo_topics
    show_summary
}

main "$@"
