#!/usr/bin/env bash
#
# Git-Control Pull Request Creator
# Create GitHub pull requests from current branch with interactive options
#
# Requirements:
#   - GitHub CLI (gh) installed and authenticated
#   - Git configured with user credentials
#   - Currently on a feature/fix branch (not main/master)
#

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"

# Source shared libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/print.sh"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# ============================================================================
# PREREQUISITE CHECKS
# ============================================================================

check_prerequisites() {
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
    
    if ! command -v git &> /dev/null; then
        print_error "Git is not installed."
        exit 1
    fi
}

# ============================================================================
# GIT CHECKS
# ============================================================================

check_git_status() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Not a git repository."
        exit 1
    fi
    
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    
    if [[ "$CURRENT_BRANCH" == "main" ]] || [[ "$CURRENT_BRANCH" == "master" ]]; then
        print_error "You are on the main branch. Create a feature branch first."
        exit 1
    fi
    
    if git diff --quiet; then
        print_warning "No uncommitted changes."
    else
        print_warning "You have uncommitted changes."
        read -rp "Commit changes first? [Y/n]: " commit_choice
        if [[ ! "$commit_choice" =~ ^[Nn] ]]; then
            read -rp "Commit message: " commit_msg
            git add .
            git commit -m "$commit_msg"
        fi
    fi
    
    REMOTE=$(git config --get remote.origin.url 2>/dev/null || echo "")
    if [[ -z "$REMOTE" ]]; then
        print_error "No remote 'origin' configured."
        exit 1
    fi
    
    print_info "Current branch: ${CYAN}$CURRENT_BRANCH${NC}"
    echo ""
}

# ============================================================================
# PR CONFIGURATION
# ============================================================================

collect_pr_info() {
    echo -e "${BOLD}Pull Request Details${NC}\n"
    
    read -rp "PR Title: " PR_TITLE
    if [[ -z "$PR_TITLE" ]]; then
        print_error "Title is required."
        exit 1
    fi
    
    echo ""
    echo "Description (press Enter twice to finish):"
    PR_BODY=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && break
        PR_BODY+="$line"$'\n'
    done
    
    echo ""
    echo "Target base branch:"
    echo -e "  ${CYAN}1)${NC} main (default)"
    echo -e "  ${CYAN}2)${NC} master"
    echo -e "  ${CYAN}3)${NC} develop"
    echo -e "  ${CYAN}4)${NC} Other"
    read -rp "Choice [1]: " base_choice
    
    case "${base_choice:-1}" in
        2) PR_BASE="master" ;;
        3) PR_BASE="develop" ;;
        4)
            read -rp "Enter branch name: " PR_BASE
            ;;
        *)
            PR_BASE="main"
            ;;
    esac
    
    echo ""
    echo "PR Type:"
    echo -e "  ${CYAN}1)${NC} 🐛 Bug fix"
    echo -e "  ${CYAN}2)${NC} ✨ New feature"
    echo -e "  ${CYAN}3)${NC} 📚 Documentation"
    echo -e "  ${CYAN}4)${NC} 🔧 Refactoring"
    echo -e "  ${CYAN}5)${NC} 🧪 Tests"
    read -rp "Choice [1]: " type_choice
    
    case "${type_choice:-1}" in
        2) PR_LABEL="enhancement" ;;
        3) PR_LABEL="documentation" ;;
        4) PR_LABEL="refactoring" ;;
        5) PR_LABEL="tests" ;;
        *) PR_LABEL="bug" ;;
    esac
    
    echo ""
    echo "Options:"
    read -rp "Link an issue? Enter issue number (or press Enter to skip): " ISSUE_NUMBER
    
    read -rp "Mark as draft? [y/N]: " draft_choice
    [[ "$draft_choice" =~ ^[Yy] ]] && PR_DRAFT="--draft" || PR_DRAFT=""
    
    echo ""
}

# ============================================================================
# PR CREATION
# ============================================================================

push_branch() {
    if git rev-parse --verify "origin/$CURRENT_BRANCH" &> /dev/null; then
        print_info "Branch already exists on remote."
        return 0
    fi
    
    print_info "Pushing branch to remote..."
    if git push -u origin "$CURRENT_BRANCH"; then
        print_success "Branch pushed!"
    else
        print_error "Failed to push branch."
        exit 1
    fi
}

create_pull_request() {
    print_info "Creating pull request..."
    
    local gh_args=("pr" "create")
    gh_args+=("--title" "$PR_TITLE")
    gh_args+=("--base" "$PR_BASE")
    gh_args+=("--head" "$CURRENT_BRANCH")
    
    if [[ -n "$PR_BODY" ]]; then
        gh_args+=("--body" "$PR_BODY")
    fi
    
    if [[ -n "$ISSUE_NUMBER" ]]; then
        gh_args+=("--body-file" <(echo "Fixes #$ISSUE_NUMBER"))
    fi
    
    if [[ -n "$PR_DRAFT" ]]; then
        gh_args+=("$PR_DRAFT")
    fi
    
    if gh "${gh_args[@]}"; then
        print_success "Pull request created!"
        PR_URL=$(gh pr view "$CURRENT_BRANCH" --json url --jq '.url')
    else
        print_error "Failed to create pull request."
        exit 1
    fi
}

add_labels() {
    if [[ -n "$PR_LABEL" ]]; then
        print_info "Adding label: $PR_LABEL"
        gh pr edit "$CURRENT_BRANCH" --add-label "$PR_LABEL" 2>/dev/null || \
            print_warning "Could not add label (label may not exist in repository)"
    fi
}

# ============================================================================
# SUMMARY
# ============================================================================

show_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║${NC}              ${CYAN}Pull Request Created!${NC}                          ${BOLD}${GREEN}║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}PR Details:${NC}"
    echo -e "  • ${CYAN}Title:${NC}       $PR_TITLE"
    echo -e "  • ${CYAN}Branch:${NC}      $CURRENT_BRANCH → $PR_BASE"
    echo -e "  • ${CYAN}Label:${NC}       $PR_LABEL"
    if [[ -n "$ISSUE_NUMBER" ]]; then
        echo -e "  • ${CYAN}Issue:${NC}       #$ISSUE_NUMBER"
    fi
    if [[ -n "$PR_DRAFT" ]]; then
        echo -e "  • ${CYAN}Status:${NC}      Draft"
    fi
    echo ""
    echo -e "${BOLD}Quick Commands:${NC}"
    echo -e "  ${GREEN}gh pr view --web${NC}      - Open in browser"
    echo -e "  ${GREEN}gh pr status${NC}         - Check PR status"
    echo -e "  ${GREEN}gh pr merge${NC}          - Merge PR"
    echo ""
    if [[ -n "$PR_URL" ]]; then
        echo -e "  ${CYAN}URL:${NC} $PR_URL"
    fi
    echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    print_header
    check_prerequisites
    check_git_status
    collect_pr_info
    
    echo -e "${BOLD}Ready to create PR:${NC}"
    echo -e "  Branch:  ${CYAN}$CURRENT_BRANCH${NC} → ${CYAN}$PR_BASE${NC}"
    echo -e "  Title:   ${CYAN}$PR_TITLE${NC}"
    echo ""
    read -rp "Proceed? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        print_info "Cancelled."
        exit 0
    fi
    
    echo ""
    
    push_branch
    create_pull_request
    add_labels
    show_summary
}

main "$@"
