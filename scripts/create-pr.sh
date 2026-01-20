#!/usr/bin/env bash
#
# Dev-Control Pull Request Creator
# Create GitHub pull requests from current branch with interactive options
#
# Requirements:
#   - GitHub CLI (gh) installed and authenticated
#   - Git configured with user credentials
#   - Currently on a feature/fix branch (not main/master)
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
source "$SCRIPT_DIR/lib/git-utils.sh"

# ============================================================================
# PREREQUISITE CHECKS
# ============================================================================

check_prerequisites() {
    require_git
    require_gh_cli
    require_git_repo
    require_feature_branch
}

# ============================================================================
# GIT CHECKS
# ============================================================================

check_git_status() {
    CURRENT_BRANCH=$(get_current_branch)
    
    if has_uncommitted_changes; then
        print_warning "You have uncommitted changes."
        read -rp "Commit changes first? [Y/n]: " commit_choice
        if [[ ! "$commit_choice" =~ ^[Nn] ]]; then
            read -rp "Commit message: " commit_msg
            git add .
            git commit -m "$commit_msg"
        fi
    fi
    
    REMOTE=$(get_remote_url)
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
    print_section "Pull Request Details"
    
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
    print_menu_item "1" "main (default)"
    print_menu_item "2" "master"
    print_menu_item "3" "develop"
    print_menu_item "4" "Other"
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
    print_menu_item "1" "🐛 Bug fix"
    print_menu_item "2" "✨ New feature"
    print_menu_item "3" "📚 Documentation"
    print_menu_item "4" "🔧 Refactoring"
    print_menu_item "5" "🧪 Tests"
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
    if remote_branch_exists "$CURRENT_BRANCH"; then
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
    print_header_success "Pull Request Created!"
    
    print_section "PR Details:"
    print_detail "Title" "$PR_TITLE"
    print_detail "Branch" "$CURRENT_BRANCH → $PR_BASE"
    print_detail "Label" "$PR_LABEL"
    [[ -n "$ISSUE_NUMBER" ]] && print_detail "Issue" "#$ISSUE_NUMBER"
    [[ -n "$PR_DRAFT" ]] && print_detail "Status" "Draft"
    
    print_section "Quick Commands:"
    print_command_hint "Open in browser" "gh pr view --web"
    print_command_hint "Check PR status" "gh pr status"
    print_command_hint "Merge PR" "gh pr merge"
    
    if [[ -n "$PR_URL" ]]; then
        echo ""
        echo -e "  ${CYAN}URL:${NC} $PR_URL"
    fi
    echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    print_header "Dev-Control PR Creator"
    check_prerequisites
    check_git_status
    collect_pr_info
    push_branch
    create_pull_request
    add_labels
    show_summary
}

main "$@"
