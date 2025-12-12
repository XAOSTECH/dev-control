#!/usr/bin/env bash
#
# Git-Control Template Loading Script
# Initialise repositories with standardised templates
# 
# This script copies template files from all *-templates folders in git-control:
#   - docs-templates/      → copied to repo root (with placeholder replacement)
#   - workflows-templates/ → copied to .github/workflows/
#   - licenses-templates/  → copied to repo root (future)
#   - Any other *-templates folders added later
#
# USAGE:
#   ./template-loading.sh                    # Interactive mode
#   ./template-loading.sh --files FILE1,FILE2 --overwrite
#   ./template-loading.sh -f CONTRIBUTING.md,SECURITY.md -o
#   ./template-loading.sh --help
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

# CLI options
CLI_FILES=""
CLI_OVERWRITE=false
CLI_HELP=false

# ============================================================================
# CLI ARGUMENT PARSING
# ============================================================================

show_help() {
    echo -e "${BOLD}Git-Control Template Loader${NC}"
    echo ""
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --files FILE1,FILE2    Only process specific files (comma-separated)"
    echo "  -o, --overwrite            Overwrite existing files without prompting"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0")                                    # Interactive mode"
    echo "  $(basename "$0") -f CONTRIBUTING.md -o              # Update single file"
    echo "  $(basename "$0") --files README.md,SECURITY.md      # Update multiple files"
    echo "  $(basename "$0") -f LICENSE -o                      # Update license"
    echo ""
    echo "Available template files:"
    for dir in "$GIT_CONTROL_DIR"/*-templates; do
        if [[ -d "$dir" ]]; then
            echo "  $(basename "$dir"):"
            for file in "$dir"/*; do
                [[ -f "$file" ]] && echo "    - $(basename "$file")"
            done
        fi
    done
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--files)
                CLI_FILES="$2"
                shift 2
                ;;
            -o|--overwrite)
                CLI_OVERWRITE=true
                shift
                ;;
            -h|--help)
                CLI_HELP=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

print_header() {
    echo -e "\n${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║${NC}         ${CYAN}Git-Control Template Loader${NC}                         ${BOLD}${BLUE}║${NC}"
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

# Check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Not a git repository!"
        echo -e "  Run ${CYAN}git init${NC} first, or navigate to a git repository."
        exit 1
    fi
}

# Get repository information
get_repo_info() {
    # Try to get remote URL
    REPO_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")
    
    if [[ -n "$REPO_URL" ]]; then
        # Extract org/repo from URL
        if [[ "$REPO_URL" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
            ORG_NAME="${BASH_REMATCH[1]}"
            REPO_SLUG="${BASH_REMATCH[2]}"
            REPO_URL="https://github.com/$ORG_NAME/$REPO_SLUG"
        else
            ORG_NAME=""
            REPO_SLUG=$(basename "$(pwd)")
        fi
    else
        ORG_NAME=""
        REPO_SLUG=$(basename "$(pwd)")
        REPO_URL=""
    fi
    
    PROJECT_NAME="${REPO_SLUG}"
}

# ============================================================================
# TEMPLATE PROCESSING
# ============================================================================

collect_project_info() {
    echo -e "${BOLD}Project Configuration${NC}\n"
    
    # Project name
    read -rp "Project name [$PROJECT_NAME]: " input
    PROJECT_NAME="${input:-$PROJECT_NAME}"
    
    # Repository slug
    read -rp "Repository slug [$REPO_SLUG]: " input
    REPO_SLUG="${input:-$REPO_SLUG}"
    
    # Organisation/Username
    if [[ -z "$ORG_NAME" ]]; then
        read -rp "GitHub username/org: " ORG_NAME
    else
        read -rp "GitHub username/org [$ORG_NAME]: " input
        ORG_NAME="${input:-$ORG_NAME}"
    fi
    
    # Repository URL
    REPO_URL="https://github.com/$ORG_NAME/$REPO_SLUG"
    read -rp "Repository URL [$REPO_URL]: " input
    REPO_URL="${input:-$REPO_URL}"
    
    # Short description
    read -rp "Short description: " SHORT_DESCRIPTION
    SHORT_DESCRIPTION="${SHORT_DESCRIPTION:-A project by $ORG_NAME}"
    
    # Long description
    echo "Long description (press Enter twice to finish):"
    LONG_DESCRIPTION=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && break
        LONG_DESCRIPTION+="$line\n"
    done
    LONG_DESCRIPTION="${LONG_DESCRIPTION:-$SHORT_DESCRIPTION}"
    
    # License
    echo ""
    echo "Select license type:"
    echo "  1) MIT"
    echo "  2) Apache-2.0"
    echo "  3) GPL-3.0"
    echo "  4) BSD-3-Clause"
    echo "  5) Other"
    read -rp "Choice [1]: " license_choice
    case "${license_choice:-1}" in
        1) LICENSE_TYPE="MIT" ;;
        2) LICENSE_TYPE="Apache-2.0" ;;
        3) LICENSE_TYPE="GPL-3.0" ;;
        4) LICENSE_TYPE="BSD-3-Clause" ;;
        *) read -rp "Enter license name: " LICENSE_TYPE ;;
    esac
    
    # Stability
    echo ""
    echo "Select stability level:"
    echo "  1) experimental (orange)"
    echo "  2) beta (yellow)"
    echo "  3) stable (green)"
    echo "  4) mature (blue)"
    read -rp "Choice [1]: " stability_choice
    case "${stability_choice:-1}" in
        1) STABILITY="experimental"; STABILITY_COLOR="orange" ;;
        2) STABILITY="beta"; STABILITY_COLOR="yellow" ;;
        3) STABILITY="stable"; STABILITY_COLOR="green" ;;
        4) STABILITY="mature"; STABILITY_COLOR="blue" ;;
        *) STABILITY="experimental"; STABILITY_COLOR="orange" ;;
    esac
    
    CURRENT_YEAR=$(date +%Y)
}

process_template() {
    local src="$1"
    local dest="$2"
    
    if [[ ! -f "$src" ]]; then
        print_warning "Template not found: $src"
        return 1
    fi
    
    mkdir -p "$(dirname "$dest")"
    
    # Copy and replace placeholders
    sed -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
        -e "s|{{REPO_SLUG}}|$REPO_SLUG|g" \
        -e "s|{{ORG_NAME}}|$ORG_NAME|g" \
        -e "s|{{REPO_URL}}|$REPO_URL|g" \
        -e "s|{{SHORT_DESCRIPTION}}|$SHORT_DESCRIPTION|g" \
        -e "s|{{LONG_DESCRIPTION}}|$LONG_DESCRIPTION|g" \
        -e "s|{{LICENSE_TYPE}}|$LICENSE_TYPE|g" \
        -e "s|{{STABILITY}}|$STABILITY|g" \
        -e "s|{{STABILITY_COLOR}}|$STABILITY_COLOR|g" \
        -e "s|{{CURRENT_YEAR}}|$CURRENT_YEAR|g" \
        "$src" > "$dest"
    
    print_success "Created: $dest"
}

# ============================================================================
# TEMPLATE DISCOVERY
# ============================================================================

discover_template_folders() {
    local folders=()
    for dir in "$GIT_CONTROL_DIR"/*-templates; do
        if [[ -d "$dir" ]]; then
            folders+=("$dir")
        fi
    done
    echo "${folders[@]}"
}

get_folder_display_name() {
    local folder="$1"
    local name=$(basename "$folder")
    name="${name%-templates}"
    echo "${name^}"
}

# ============================================================================
# TEMPLATE SELECTION
# ============================================================================

select_templates() {
    echo ""
    echo -e "${BOLD}Select templates to install:${NC}\n"
    
    local idx=1
    declare -gA TEMPLATE_FOLDERS
    
    # docs-templates
    if [[ -d "$GIT_CONTROL_DIR/docs-templates" ]]; then
        echo -e "  ${CYAN}$idx)${NC} Documentation       - README, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY"
        TEMPLATE_FOLDERS[$idx]="docs"
        ((idx++))
    fi
    
    # workflows-templates  
    if [[ -d "$GIT_CONTROL_DIR/workflows-templates" ]]; then
        echo -e "  ${CYAN}$idx)${NC} Workflows           - GitHub Actions (→ .github/workflows/)"
        TEMPLATE_FOLDERS[$idx]="workflows"
        ((idx++))
    fi
    
    # github-templates (issue templates, PR template)
    if [[ -d "$GIT_CONTROL_DIR/github-templates" ]]; then
        echo -e "  ${CYAN}$idx)${NC} GitHub Templates    - Issue & PR templates (→ .github/)"
        TEMPLATE_FOLDERS[$idx]="github"
        ((idx++))
    fi
    
    # licenses-templates
    if [[ -d "$GIT_CONTROL_DIR/licenses-templates" ]]; then
        echo -e "  ${CYAN}$idx)${NC} Licenses            - LICENSE file"
        TEMPLATE_FOLDERS[$idx]="licenses"
        ((idx++))
    fi
    
    # Any other *-templates folders
    for dir in "$GIT_CONTROL_DIR"/*-templates; do
        if [[ -d "$dir" ]]; then
            local name=$(basename "$dir")
            if [[ "$name" != "docs-templates" && "$name" != "workflows-templates" && "$name" != "licenses-templates" && "$name" != "github-templates" ]]; then
                local display=$(get_folder_display_name "$dir")
                echo -e "  ${CYAN}$idx)${NC} $display"
                TEMPLATE_FOLDERS[$idx]="${name%-templates}"
                ((idx++))
            fi
        fi
    done
    
    echo ""
    echo -e "  ${GREEN}A)${NC} Install ALL templates"
    echo -e "  ${YELLOW}Q)${NC} Quit"
    echo ""
    
    read -rp "Enter choices (comma-separated, e.g., 1,2,3 or A): " selection
    echo "$selection"
}

install_templates() {
    local selection="$1"
    local target_dir
    target_dir=$(pwd)
    
    # Handle 'A' for all
    if [[ "$selection" =~ [Aa] ]]; then
        selection=""
        for key in "${!TEMPLATE_FOLDERS[@]}"; do
            selection+="$key,"
        done
        selection="${selection%,}"
    fi
    
    # Handle quit
    if [[ "$selection" =~ [Qq] ]]; then
        print_info "Installation cancelled."
        exit 0
    fi
    
    IFS=',' read -ra SELECTED <<< "$selection"
    
    for sel in "${SELECTED[@]}"; do
        sel=$(echo "$sel" | tr -d ' ')
        local folder_type="${TEMPLATE_FOLDERS[$sel]}"
        
        case "$folder_type" in
            docs)
                install_docs_templates "$target_dir"
                ;;
            workflows)
                install_workflows_templates "$target_dir"
                ;;
            github)
                install_github_templates "$target_dir"
                ;;
            licenses)
                install_licenses_templates "$target_dir"
                ;;
            *)
                # Generic handler for other template folders
                if [[ -n "$folder_type" ]]; then
                    install_generic_templates "$target_dir" "$folder_type"
                fi
                ;;
        esac
    done
}

install_docs_templates() {
    local target_dir="$1"
    local docs_dir="$GIT_CONTROL_DIR/docs-templates"
    
    print_info "Installing documentation templates..."
    
    for file in "$docs_dir"/*.md; do
        if [[ -f "$file" ]]; then
            local filename=$(basename "$file")
            process_template "$file" "$target_dir/$filename"
        fi
    done
}

install_workflows_templates() {
    local target_dir="$1"
    local wf_dir="$GIT_CONTROL_DIR/workflows-templates"
    
    print_info "Installing workflow templates to .github/workflows/..."
    mkdir -p "$target_dir/.github/workflows"
    
    for file in "$wf_dir"/*.yml; do
        if [[ -f "$file" ]]; then
            local filename=$(basename "$file")
            # Skip init.yml and remote-init.yml (those are for manual copy)
            if [[ "$filename" != "init.yml" && "$filename" != "remote-init.yml" ]]; then
                cp "$file" "$target_dir/.github/workflows/$filename"
                print_success "Created: .github/workflows/$filename"
            fi
        fi
    done
}

install_github_templates() {
    local target_dir="$1"
    local gh_dir="$GIT_CONTROL_DIR/github-templates"
    
    if [[ ! -d "$gh_dir" ]]; then
        print_warning "github-templates folder not found"
        return
    fi
    
    print_info "Installing GitHub templates to .github/..."
    
    mkdir -p "$target_dir/.github"
    
    # Copy ISSUE_TEMPLATE folder
    if [[ -d "$gh_dir/ISSUE_TEMPLATE" ]]; then
        mkdir -p "$target_dir/.github/ISSUE_TEMPLATE"
        for file in "$gh_dir/ISSUE_TEMPLATE"/*; do
            if [[ -f "$file" ]]; then
                local filename=$(basename "$file")
                process_template "$file" "$target_dir/.github/ISSUE_TEMPLATE/$filename"
            fi
        done
    fi
    
    # Copy PR template
    if [[ -f "$gh_dir/PULL_REQUEST_TEMPLATE.md" ]]; then
        process_template "$gh_dir/PULL_REQUEST_TEMPLATE.md" "$target_dir/.github/PULL_REQUEST_TEMPLATE.md"
    fi
    
    # Copy any other files in github-templates root
    for file in "$gh_dir"/*.md "$gh_dir"/*.yml; do
        if [[ -f "$file" ]]; then
            local filename=$(basename "$file")
            if [[ "$filename" != "PULL_REQUEST_TEMPLATE.md" ]]; then
                process_template "$file" "$target_dir/.github/$filename"
            fi
        fi
    done
}

install_licenses_templates() {
    local target_dir="$1"
    local lic_dir="$GIT_CONTROL_DIR/licenses-templates"
    
    if [[ ! -d "$lic_dir" ]]; then
        print_warning "licenses-templates folder not found"
        return
    fi
    
    print_info "Installing license templates..."
    
    # Show license options
    echo ""
    echo "Select license:"
    local idx=1
    declare -A LICENSE_FILES
    for file in "$lic_dir"/*; do
        if [[ -f "$file" ]]; then
            local fname=$(basename "$file")
            echo "  $idx) $fname"
            LICENSE_FILES[$idx]="$file"
            ((idx++))
        fi
    done
    
    read -rp "Choice [1]: " lic_choice
    lic_choice="${lic_choice:-1}"
    
    local selected_license="${LICENSE_FILES[$lic_choice]}"
    if [[ -f "$selected_license" ]]; then
        process_template "$selected_license" "$target_dir/LICENSE"
    fi
}

install_generic_templates() {
    local target_dir="$1"
    local folder_type="$2"
    local tpl_dir="$GIT_CONTROL_DIR/${folder_type}-templates"
    
    if [[ ! -d "$tpl_dir" ]]; then
        print_warning "${folder_type}-templates folder not found"
        return
    fi
    
    print_info "Installing ${folder_type} templates..."
    
    for file in "$tpl_dir"/*; do
        if [[ -f "$file" ]]; then
            local filename=$(basename "$file")
            process_template "$file" "$target_dir/$filename"
        fi
    done
}

# ============================================================================
# TARGETED FILE PROCESSING (CLI mode)
# ============================================================================

find_template_file() {
    local filename="$1"
    
    # Extract just the basename if a path was provided
    local base_filename
    base_filename=$(basename "$filename")
    
    # Search all *-templates folders for this file
    for dir in "$GIT_CONTROL_DIR"/*-templates; do
        if [[ -d "$dir" ]]; then
            local filepath="$dir/$base_filename"
            if [[ -f "$filepath" ]]; then
                echo "$filepath"
                return 0
            fi
        fi
    done
    
    return 1
}

get_target_path() {
    local template_path="$1"
    local user_path="$2"
    local target_dir
    target_dir=$(pwd)
    
    # If user provided a path (contains /), use it directly
    if [[ "$user_path" == *"/"* ]]; then
        echo "$target_dir/$user_path"
        return
    fi
    
    # Otherwise, determine destination based on source folder
    local folder_name
    folder_name=$(basename "$(dirname "$template_path")")
    
    case "$folder_name" in
        workflows-templates)
            echo "$target_dir/.github/workflows/$user_path"
            ;;
        docs-templates)
            # Default docs to repo root (user can override with path)
            echo "$target_dir/$user_path"
            ;;
        *)
            echo "$target_dir/$user_path"
            ;;
    esac
}

process_specific_files() {
    local target_dir
    target_dir=$(pwd)
    
    IFS=',' read -ra FILES <<< "$CLI_FILES"
    
    for user_path in "${FILES[@]}"; do

        user_path=$(echo "$user_path" | tr -d ' ')

        local filename
        filename=$(basename "$user_path")
        
        local template_path
        if ! template_path=$(find_template_file "$filename"); then
            print_error "Template not found: $filename"
            continue
        fi
        
        local target_path
        target_path=$(get_target_path "$template_path" "$user_path")
        
        # Check if file exists and handle overwrite
        if [[ -f "$target_path" ]] && [[ "$CLI_OVERWRITE" != "true" ]]; then
            echo -e "${YELLOW}File exists:${NC} $target_path"
            read -rp "Overwrite? [y/N]: " confirm
            if [[ ! "$confirm" =~ ^[Yy] ]]; then
                print_info "Skipped: $user_path"
                continue
            fi
        fi
        
        mkdir -p "$(dirname "$target_path")"
        
        process_template "$template_path" "$target_path"
    done
}

# ============================================================================
# SUMMARY
# ============================================================================

show_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║${NC}                   ${CYAN}Templates Installed!${NC}                      ${BOLD}${GREEN}║${NC}"
    echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Project:${NC} $PROJECT_NAME"
    echo -e "${BOLD}Repository:${NC} $REPO_URL"
    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    echo -e "  1. Review and customise the generated files"
    echo -e "  2. Replace placeholder sections (marked with {{}})"
    echo -e "  3. Commit the changes: ${CYAN}git add . && git commit -m 'Add documentation'${NC}"
    echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    parse_args "$@"
    
    if [[ "$CLI_HELP" == "true" ]]; then
        show_help
        exit 0
    fi
    
    print_header
    
    local template_folders
    template_folders=$(discover_template_folders)
    
    if [[ -z "$template_folders" ]]; then
        print_error "No *-templates folders found in: $GIT_CONTROL_DIR"
        exit 1
    fi
    
    # CLI mode: process specific files
    if [[ -n "$CLI_FILES" ]]; then
        print_info "CLI mode: Processing specific files"
        print_info "Files: $CLI_FILES"
        print_info "Overwrite: $CLI_OVERWRITE"
        echo ""
        
        get_repo_info
        
        # Collect project info (or use defaults for quick mode)
        if [[ "$CLI_OVERWRITE" == "true" ]]; then
            # Quick mode - use defaults from git
            PROJECT_NAME="${PROJECT_NAME:-$(basename "$(pwd)")}"
            SHORT_DESCRIPTION="${SHORT_DESCRIPTION:-A project by $ORG_NAME}"
            LONG_DESCRIPTION="${LONG_DESCRIPTION:-$SHORT_DESCRIPTION}"
            LICENSE_TYPE="${LICENSE_TYPE:-MIT}"
            STABILITY="${STABILITY:-experimental}"
            STABILITY_COLOR="${STABILITY_COLOR:-orange}"
            CURRENT_YEAR=$(date +%Y)
            
            print_info "Using detected values:"
            echo "  Project: $PROJECT_NAME"
            echo "  Org: $ORG_NAME"
            echo "  URL: $REPO_URL"
            echo ""
        else
            collect_project_info
        fi
        
        process_specific_files
        
        echo ""
        print_success "Done!"
        exit 0
    fi
    
    print_info "Git-Control directory: $GIT_CONTROL_DIR"
    print_info "Working directory: $(pwd)"
    print_info "Available template folders:"
    for dir in $template_folders; do
        echo "  • $(basename "$dir")"
    done
    echo ""
    
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_warning "Not a git repository - some features may not work."
        echo ""
    fi
    
    get_repo_info
    collect_project_info
    
    local selection
    selection=$(select_templates)
    
    echo ""
    print_info "Installing templates..."
    install_templates "$selection"
    
    show_summary
}

main "$@"