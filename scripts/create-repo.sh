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

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

print_header() {
    echo -e "\n${BOLD}${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║${NC}                 ${CYAN}Git-Control Repository Creator${NC}               ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
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

# ============================================================================
# GIT CONFIG FETCHING
# ============================================================================

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
    
    # Repository name
    echo -e "${BOLD}Repository Configuration${NC}\n"
    read -rp "Repository name [$current_folder]: " REPO_NAME
    REPO_NAME="${REPO_NAME:-$current_folder}"
    
    # Validate repo name (GitHub rules)
    REPO_NAME=$(echo "$REPO_NAME" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
    REPO_NAME=$(echo "$REPO_NAME" | sed 's/[^a-z0-9._-]//g')
    
    # Description
    read -rp "Description: " REPO_DESCRIPTION
    REPO_DESCRIPTION="${REPO_DESCRIPTION:-A repository by $GH_USERNAME}"
    
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
    print_info "Creating GitHub repository: ${CYAN}$GH_USERNAME/$REPO_NAME${NC} ($REPO_VISIBILITY)"
    
    # Build gh command
    local gh_args=("repo" "create" "$REPO_NAME")
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
        REPO_URL="https://github.com/$GH_USERNAME/$REPO_NAME"
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
    print_header
    check_prerequisites
    get_git_credentials
    collect_repo_info
    
    echo -e "${BOLD}Ready to create:${NC}"
    echo -e "  Repository: ${CYAN}$GH_USERNAME/$REPO_NAME${NC}"
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
