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
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

set -e

# Source shared libraries - use cli.sh for script path resolution
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
GIT_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"
# Fallback if in git-control root
[[ ! -d "$GIT_CONTROL_DIR/docs-templates" ]] && [[ -d "./docs-templates" ]] && GIT_CONTROL_DIR="$(pwd)"

# Source shared libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/print.sh"
source "$SCRIPT_DIR/lib/git-utils.sh"
source "$SCRIPT_DIR/lib/cli.sh"
source "$SCRIPT_DIR/lib/validation.sh"

# CLI options
CLI_FILES=""
CLI_OVERWRITE=false
CLI_HELP=false
# Batch mode options
BATCH_MODE=false
REUSE_OWNER=false
ASSUME_YES=false
POSITIONAL_ARGS=()
# Batch owner prefill control: when true, do not prefill owner prompts with detected ORG_NAME
BATCH_SKIP_OWNER=false
# Reuse templates/settings across the batch
BATCH_REUSE_TEMPLATES=false
BATCH_SELECTED_CHOICES=""
BATCH_LICENSE_TYPE=""
BATCH_STABILITY=""
BATCH_STABILITY_COLOR=""
# Creation queue for batch mode
CREATE_QUEUE=()

# ============================================================================
# CLI ARGUMENT PARSING
# ============================================================================

show_help() {
    print_header "Git-Control Template Loader" 50
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    print_section "Options"
    print_menu_item "-f, --files FILE1,FILE2" "Only process specific files (comma-separated)"
    print_menu_item "-o, --overwrite" "Overwrite existing files without prompting"
    print_menu_item "-b, --batch" "Batch mode: initialise multiple repositories"
    print_menu_item "    --reuse-owner" "Prompt for repository owner once and reuse"
    print_menu_item "-y, --yes" "Assume defaults and run non-interactively"
    print_menu_item "-h, --help" "Show this help message"
    echo ""
    print_section "Examples"
    print_command_hint "Interactive mode" "$(basename "$0")"
    print_command_hint "Update single file" "$(basename "$0") -f CONTRIBUTING.md -o"
    print_command_hint "Update multiple files" "$(basename "$0") --files README.md,SECURITY.md"
    print_command_hint "Update license" "$(basename "$0") -f LICENSE -o"
    echo ""
    print_section "Available Template Files"
    for dir in "$GIT_CONTROL_DIR"/*-templates; do
        if [[ -d "$dir" ]]; then
            echo "  $(basename "$dir"):"
            for file in "$dir"/*; do
                [[ -f "$file" ]] && print_list_item "$(basename "$file")"
            done
        fi
    done
}

parse_args() {
    POSITIONAL_ARGS=()
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
            -b|--batch)
                BATCH_MODE=true
                shift
                ;;
            --reuse-owner)
                REUSE_OWNER=true
                shift
                ;;
            -y|--yes)
                ASSUME_YES=true
                shift
                ;;
            -h|--help)
                CLI_HELP=true
                shift
                ;;
            --) # end of options
                shift
                break
                ;;
            -*)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                POSITIONAL_ARGS+=("$1")
                shift
                ;;
        esac
    done
} 

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Check if we're in a git repository with a LOCAL .git folder
check_git_repo() {
    # Check for local .git directory (not inherited from parent)
    if [[ ! -d ".git" ]]; then
        print_warning "No local .git directory. Initializing..."
        git init
        git config user.email "${GIT_EMAIL:-noreply@github.com}" 2>/dev/null || true
        git config user.name "${GIT_NAME:-User}" 2>/dev/null || true
        print_success "Repository initialized"
        echo ""
    fi
}

# Try to get git user info from global config
get_git_user_info() {
    GIT_NAME=$(git config --global user.name 2>/dev/null || echo "")
    GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")
}

# Get repository information (uses git-utils.sh functions)
get_repo_info() {
    # Use git-utils.sh for remote URL
    REPO_URL=$(get_remote_url)
    
    if [[ -n "$REPO_URL" ]]; then
        # Use git-utils.sh for parsing
        read -r ORG_NAME REPO_SLUG <<< "$(parse_github_url "$REPO_URL")"
        [[ -n "$ORG_NAME" && -n "$REPO_SLUG" ]] && REPO_URL="https://github.com/$ORG_NAME/$REPO_SLUG"
    else
        ORG_NAME=""
        REPO_SLUG=$(basename "$(pwd)")
        REPO_URL=""
    fi
    
    # Try to prefill GitHub username from gh CLI if not detected from remote
    if [[ -z "$ORG_NAME" ]] && command -v gh &>/dev/null; then
        local gh_user
        gh_user=$(gh api user --jq .login 2>/dev/null || true)
        if [[ -n "$gh_user" ]]; then
            ORG_NAME="$gh_user"
            print_info "Detected GitHub user from gh CLI: $ORG_NAME"
        fi
    fi

    # Load cached metadata from git config (set by previous gc-init runs)
    # Only load from LOCAL config if a local .git directory exists
    if [[ -d ".git" ]]; then
        local cached_license
        cached_license=$(git config --local gc-init.license-type 2>/dev/null || echo "")
        if [[ -n "$cached_license" ]]; then
            LICENSE_TYPE="$cached_license"
            print_info "Loaded licence from git config: $LICENSE_TYPE"
        fi
        
        local cached_org
        cached_org=$(git config --local gc-init.org-name 2>/dev/null || echo "")
        if [[ -n "$cached_org" ]]; then
            ORG_NAME="$cached_org"
        fi
        
        local cached_description
        cached_description=$(git config --local gc-init.description 2>/dev/null || echo "")
        if [[ -n "$cached_description" ]]; then
            SHORT_DESCRIPTION="$cached_description"
        fi
    fi

    # If we have an org and repo slug, try to fetch repo metadata from GitHub (only if not cached)
    if [[ -n "$ORG_NAME" && -n "$REPO_SLUG" ]] && command -v gh &>/dev/null; then
        # Try to detect repository description from GitHub (if not already cached)
        if [[ -z "$SHORT_DESCRIPTION" ]]; then
            local gh_desc
            gh_desc=$(gh repo view "${ORG_NAME}/${REPO_SLUG}" --json description --jq .description 2>/dev/null || true)
            if [[ -n "$gh_desc" && "$gh_desc" != "null" ]]; then
                SHORT_DESCRIPTION="$gh_desc"
                print_info "Detected GitHub description: $SHORT_DESCRIPTION"
            fi
        fi

        # Try to detect licence from GitHub (if not already cached)
        if [[ -z "$LICENSE_TYPE" ]]; then
            local gh_license
            gh_license=$(gh repo view "${ORG_NAME}/${REPO_SLUG}" --json licenseInfo --jq .licenseInfo.spdxId 2>/dev/null || true)
            if [[ -n "$gh_license" && "$gh_license" != "null" ]]; then
                LICENSE_TYPE="$gh_license"
                print_info "Detected GitHub licence: $LICENSE_TYPE"
            fi
        fi
    fi

    PROJECT_NAME="${REPO_SLUG}"
}

# ============================================================================
# TEMPLATE PROCESSING
# ============================================================================

collect_project_info() {
    # Quick exit if batch reusing config and this is not the first repo
    # BUT: description is always per-repo, so we must ask it separately below
    local skip_shared_config=false
    if [[ "$BATCH_REUSE_TEMPLATES" == "true" && -n "$BATCH_SELECTED_CHOICES" ]]; then
        skip_shared_config=true
        print_info "Skipping shared config (using initialisation config)"
    fi
    
    print_section "Project Configuration"
    
    # Project name - use read_input from print.sh
    PROJECT_NAME=$(read_input "Project name" "$PROJECT_NAME")
    
    # Repository slug
    REPO_SLUG=$(read_input "Repository slug" "$REPO_SLUG")
    
    # Repository owner (GitHub username or organisation) — allow overriding detected value
    if [[ "$BATCH_MODE" == "true" && "$REUSE_OWNER" == "true" ]]; then
        # Shared owner was selected for the batch; skip per-repo prompting and use shared value
        REPO_OWNER="${REPO_OWNER}"
        print_info "Using shared repository owner: $REPO_OWNER"
        if [[ -n "$ORG_NAME" && "$ORG_NAME" != "$REPO_OWNER" ]]; then
            print_warning "Detected remote owner '$ORG_NAME' differs from chosen shared owner '$REPO_OWNER'"
        fi
    elif [[ "$BATCH_MODE" == "true" && "$BATCH_SKIP_OWNER" == "true" ]]; then
        # In batch non-shared mode we do not prefill owner prompt with detected ORG_NAME
        REPO_OWNER=$(read_input "Repository owner (user/org)" "")
        REPO_OWNER="${REPO_OWNER:-$ORG_NAME}"
        if [[ -n "$ORG_NAME" && -n "$REPO_OWNER" && "$REPO_OWNER" != "$ORG_NAME" ]]; then
            print_warning "Detected remote owner '$ORG_NAME' differs from entered owner '$REPO_OWNER'"
        fi
    else
        REPO_OWNER=$(read_input "Repository owner (user/org)" "$ORG_NAME")
    fi

    # Mirror back to ORG_NAME for compatibility with older code paths
    ORG_NAME="$REPO_OWNER"

    # Repository URL (constructed from chosen owner)
    REPO_URL="https://github.com/$REPO_OWNER/$REPO_SLUG"
    REPO_URL=$(read_input "Repository URL" "$REPO_URL")
    
    # Short description — ALWAYS asked per-repo, never shared in batch mode
    # Prefill from THIS repo's cached config (loaded by get_repo_info)
    SHORT_DESCRIPTION=$(read_input "Short description" "$SHORT_DESCRIPTION")
    
    # Long description
    echo "Long description (press Enter twice when done):"
    LONG_DESCRIPTION=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && break
        LONG_DESCRIPTION+="$line\n"
    done
    LONG_DESCRIPTION="${LONG_DESCRIPTION:-$SHORT_DESCRIPTION}"
    
    # If not reusing batch config, ask for licence and stability per-repo
    if [[ "$skip_shared_config" != "true" ]]; then
        echo ""
        print_section "Select Licence Type"
        print_menu_item "1" "MIT"
        print_menu_item "2" "Apache-2.0"
        print_menu_item "3" "GPL-3.0"
        print_menu_item "4" "BSD-3-Clause"
        print_menu_item "5" "Other"
        # Determine default from detected LICENSE_TYPE
        local default_license_choice=1
        if [[ -n "$LICENSE_TYPE" ]]; then
            case "${LICENSE_TYPE,,}" in
                mit) default_license_choice=1 ;;
                apache*|apache-2.0) default_license_choice=2 ;;
                gpl*|gpl-3.0) default_license_choice=3 ;;
                bsd*|bsd-3-clause) default_license_choice=4 ;;
                *) default_license_choice=5 ;;
            esac
            print_info "Detected licence: $LICENSE_TYPE (will be used if you leave blank)"
        fi
        read -rp "Choice [${default_license_choice}]: " license_choice
        case "${license_choice:-$default_license_choice}" in
            1) LICENSE_TYPE="MIT" ;;
            2) LICENSE_TYPE="Apache-2.0" ;;
            3) LICENSE_TYPE="GPL-3.0" ;;
            4) LICENSE_TYPE="BSD-3-Clause" ;;
            5) 
                LICENSE_TYPE=$(read_input "Enter licence name" "$LICENSE_TYPE")
                ;;
        esac
        
        # Stability
        echo ""
        print_section "Select Stability Level"
        print_menu_item "1" "experimental (orange)"
        print_menu_item "2" "beta (yellow)"
        print_menu_item "3" "stable (green)"
        print_menu_item "4" "mature (blue)"
        read -rp "Choice [1]: " stability_choice
        case "${stability_choice:-1}" in
            1) STABILITY="experimental"; STABILITY_COLOR="orange" ;;
            2) STABILITY="beta"; STABILITY_COLOR="yellow" ;;
            3) STABILITY="stable"; STABILITY_COLOR="green" ;;
            4) STABILITY="mature"; STABILITY_COLOR="blue" ;;
            *) STABILITY="experimental"; STABILITY_COLOR="orange" ;;
        esac
    fi
    
    CURRENT_YEAR=$(date +%Y)
}

process_template() {
    local src="$1"
    local dest="$2"
    
    # Use validation.sh for file check
    if ! is_file "$src"; then
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
        if is_directory "$dir"; then
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
    print_section "Select Templates to Install"
    echo ""
    
    local idx=1
    declare -gA TEMPLATE_FOLDERS
    
    # docs-templates
    if is_directory "$GIT_CONTROL_DIR/docs-templates"; then
        print_menu_item "$idx" "Documentation - README, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY (→ docs/)"
        echo -e "     ${YELLOW}Sub-options:${NC} A) README AX) README+BADGES B) CONTRIBUTING C) CODE_OF_CONDUCT D) SECURITY"
        TEMPLATE_FOLDERS[$idx]="docs"
        ((idx++))
    fi
    
    # workflows-templates  
    if is_directory "$GIT_CONTROL_DIR/workflows-templates"; then
        print_menu_item "$idx" "Workflows - GitHub Actions (→ .github/workflows/)"
        TEMPLATE_FOLDERS[$idx]="workflows"
        ((idx++))
    fi
    
    # github-templates (issue templates, PR template)
    if is_directory "$GIT_CONTROL_DIR/github-templates"; then
        print_menu_item "$idx" "GitHub Templates - Issue & PR templates (→ .github/)"
        TEMPLATE_FOLDERS[$idx]="github"
        ((idx++))
    fi
    
    # license-templates (or licenses-templates)
    if is_directory "$GIT_CONTROL_DIR/license-templates" || is_directory "$GIT_CONTROL_DIR/licenses-templates"; then
        print_menu_item "$idx" "Licenses - LICENSE file"
        TEMPLATE_FOLDERS[$idx]="licenses"
        ((idx++))
    fi
    
    # Any other *-templates folders
    for dir in "$GIT_CONTROL_DIR"/*-templates; do
        if is_directory "$dir"; then
            local name=$(basename "$dir")
            if [[ "$name" != "docs-templates" && "$name" != "workflows-templates" && "$name" != "license-templates" && "$name" != "licenses-templates" && "$name" != "github-templates" ]]; then
                local display=$(get_folder_display_name "$dir")
                print_menu_item "$idx" "$display"
                TEMPLATE_FOLDERS[$idx]="${name%-templates}"
                ((idx++))
            fi
        fi
    done
    
    echo ""
    echo -e "  ${GREEN}A)${NC} Install ALL templates"
    echo -e "  ${YELLOW}Q)${NC} Quit"
    echo ""
    
    read -rp "Enter choices (e.g., 1AX, 1C, 1D, 2, 3, 4): " selection
    # Store selection in global variable (avoids subshell issues)
    SELECTED_TEMPLATE_CHOICES="$selection"
}

install_templates() {
    local selection="$1"
    local target_dir
    target_dir=$(pwd)
    
    # Track if installing all (for auto-license selection)
    local install_all=false
    
    # Handle 'A' for all
    if [[ "$selection" =~ [Aa] ]]; then
        install_all=true
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

    for rawsel in "${SELECTED[@]}"; do
        sel=$(echo "$rawsel" | tr -d ' ')
        # parse numeric and letter suffix (e.g., 1, 1A, 1AX)
        if [[ "$sel" =~ ^([0-9]+)([A-Za-z]+)$ ]]; then
            num="${BASH_REMATCH[1]}"
            suffix="${BASH_REMATCH[2]}"
        else
            num="$sel"
            suffix=""
        fi
        folder_type="${TEMPLATE_FOLDERS[$num]}"
        
        if [[ "$folder_type" == "docs" && -n "$suffix" ]]; then
            # If suffix contains X -> add badges after title
            if [[ "$suffix" =~ [Xx] ]]; then
                add_badges_after_title "$target_dir/README.md"
                # if only X present, continue to next selection
                if [[ ! "$suffix" =~ [AaBbCcDd] ]]; then
                    continue
                fi
            fi
            # Map letters to specific doc files
            declare -a docs_files=()
            [[ "$suffix" =~ [Aa] ]] && docs_files+=("README.md")
            [[ "$suffix" =~ [Bb] ]] && docs_files+=("CONTRIBUTING.md")
            [[ "$suffix" =~ [Cc] ]] && docs_files+=("CODE_OF_CONDUCT.md")
            [[ "$suffix" =~ [Dd] ]] && docs_files+=("SECURITY.md")
            
            if [[ "${#docs_files[@]}" -gt 0 ]]; then
                for f in "${docs_files[@]}"; do
                    local tpl="$GIT_CONTROL_DIR/docs-templates/$f"
                    if is_file "$tpl"; then
                        process_template "$tpl" "$target_dir/$f"
                    else
                        print_warning "Template not found: $f"
                    fi
                done
            fi
            continue
        fi
        
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
                install_licenses_templates "$target_dir" "$install_all"
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
        if is_file "$file"; then
            local filename=$(basename "$file")
            process_template "$file" "$target_dir/$filename"
        fi
    done
}

# Insert badges block after the first title line in README (idempotent)
add_badges_after_title() {
    local readme_path="$1"
    local tmp
    tmp=$(mktemp)

    local badges
    badges=$(cat <<'EOF'

<p align="center">
  <a href="{{REPO_URL}}">
    <img alt="GitHub repo" src="https://img.shields.io/badge/GitHub-{{ORG_NAME}}%2F-{{REPO_SLUG}}-181717?style=for-the-badge&logo=github">
  </a>
  <a href="{{REPO_URL}}/releases">
    <img alt="GitHub release" src="https://img.shields.io/github/v/release/{{ORG_NAME}}/{{REPO_SLUG}}?style=for-the-badge&logo=semantic-release&color=blue">
  </a>
  <a href="{{REPO_URL}}/blob/main/LICENSE">
    <img alt="License" src="https://img.shields.io/github/license/{{ORG_NAME}}/{{REPO_SLUG}}?style=for-the-badge&color=green">
  </a>
</p>

EOF
)
    
    # Process badges with placeholders
    badges=$(echo "$badges" | sed \
        -e "s|{{ORG_NAME}}|$ORG_NAME|g" \
        -e "s|{{REPO_SLUG}}|$REPO_SLUG|g" \
        -e "s|{{REPO_URL}}|$REPO_URL|g")
    
    if ! is_file "$readme_path"; then
        print_warning "README not found: $readme_path"
        return 1
    fi
    
    # Check if badges already exist (idempotent)
    if grep -q 'img.shields.io' "$readme_path" 2>/dev/null; then
        print_info "Badges already present in README"
        return 0
    fi
    
    # Insert after first # line (title)
    awk -v badges="$badges" '
        NR==1 && /^#/ { print; print badges; next }
        { print }
    ' "$readme_path" > "$tmp"
    
    mv "$tmp" "$readme_path"
    print_success "Added badges to README"
}

install_workflows_templates() {
    local target_dir="$1"
    local workflows_dir="$GIT_CONTROL_DIR/workflows-templates"
    local dest_dir="$target_dir/.github/workflows"
    
    print_info "Installing workflow templates..."
    mkdir -p "$dest_dir"
    
    for file in "$workflows_dir"/*.yml; do
        if is_file "$file"; then
            local filename=$(basename "$file")
            cp "$file" "$dest_dir/$filename"
            print_success "Copied: .github/workflows/$filename"
        fi
    done
}

install_github_templates() {
    local target_dir="$1"
    local github_templates_dir="$GIT_CONTROL_DIR/github-templates"
    local dest_dir="$target_dir/.github"
    
    print_info "Installing GitHub templates..."
    mkdir -p "$dest_dir"
    
    # Copy PR template
    if is_file "$github_templates_dir/PULL_REQUEST_TEMPLATE.md"; then
        cp "$github_templates_dir/PULL_REQUEST_TEMPLATE.md" "$dest_dir/"
        print_success "Copied: .github/PULL_REQUEST_TEMPLATE.md"
    fi
    
    # Copy issue templates
    if is_directory "$github_templates_dir/ISSUE_TEMPLATE"; then
        mkdir -p "$dest_dir/ISSUE_TEMPLATE"
        for file in "$github_templates_dir/ISSUE_TEMPLATE"/*; do
            if is_file "$file"; then
                cp "$file" "$dest_dir/ISSUE_TEMPLATE/"
                print_success "Copied: .github/ISSUE_TEMPLATE/$(basename "$file")"
            fi
        done
    fi
}

install_licenses_templates() {
    local target_dir="$1"
    local install_all="$2"
    local license_dir="$GIT_CONTROL_DIR/license-templates"
    [[ ! -d "$license_dir" ]] && license_dir="$GIT_CONTROL_DIR/licenses-templates"
    
    print_info "Installing license..."
    
    # If we have a LICENSE_TYPE, try to find matching template
    if [[ -n "$LICENSE_TYPE" ]]; then
        local license_file="$license_dir/$LICENSE_TYPE"
        if is_file "$license_file"; then
            process_template "$license_file" "$target_dir/LICENSE"
            return 0
        fi
    fi
    
    # Interactive selection if not auto-selected
    if [[ "$install_all" != "true" ]]; then
        echo ""
        print_section "Available Licenses"
        local idx=1
        declare -a license_files=()
        for file in "$license_dir"/*; do
            if is_file "$file"; then
                print_menu_item "$idx" "$(basename "$file")"
                license_files+=("$file")
                ((idx++))
            fi
        done
        
        read -rp "Select license [1]: " choice
        choice="${choice:-1}"
        
        local selected_idx=$((choice - 1))
        if [[ $selected_idx -ge 0 && $selected_idx -lt ${#license_files[@]} ]]; then
            process_template "${license_files[$selected_idx]}" "$target_dir/LICENSE"
        else
            print_warning "Invalid selection"
        fi
    else
        # Auto-select first license for 'all' mode
        for file in "$license_dir"/*; do
            if is_file "$file"; then
                process_template "$file" "$target_dir/LICENSE"
                break
            fi
        done
    fi
}

install_generic_templates() {
    local target_dir="$1"
    local folder_type="$2"
    local template_dir="$GIT_CONTROL_DIR/${folder_type}-templates"
    
    print_info "Installing $folder_type templates..."
    
    for file in "$template_dir"/*; do
        if is_file "$file"; then
            local filename=$(basename "$file")
            process_template "$file" "$target_dir/$filename"
        fi
    done
}

# ============================================================================
# BATCH MODE
# ============================================================================

run_batch_mode() {
    print_header "Batch Template Initialization"
    
    local dirs=()
    
    # Collect directories
    if [[ ${#POSITIONAL_ARGS[@]} -eq 0 ]] || [[ "${POSITIONAL_ARGS[0]}" == "*" ]]; then
        # Select all subdirectories
        for d in */; do
            [[ -d "$d" ]] && dirs+=("${d%/}")
        done
    else
        dirs=("${POSITIONAL_ARGS[@]}")
    fi
    
    if [[ ${#dirs[@]} -eq 0 ]]; then
        print_error "No directories found"
        exit 1
    fi
    
    print_info "Found ${#dirs[@]} directories to process"
    
    # Ask for shared owner if --reuse-owner
    if [[ "$REUSE_OWNER" == "true" ]]; then
        REPO_OWNER=$(read_input "Shared repository owner" "")
    fi
    
    # Ask about reusing templates
    if confirm "Reuse template selections for all repos?" "y"; then
        BATCH_REUSE_TEMPLATES=true
    fi
    
    # Process first repo to get template selections
    local first_dir="${dirs[0]}"
    pushd "$first_dir" > /dev/null
    check_git_repo
    get_repo_info
    get_git_user_info
    collect_project_info
    select_templates
    BATCH_SELECTED_CHOICES="$SELECTED_TEMPLATE_CHOICES"
    BATCH_LICENSE_TYPE="$LICENSE_TYPE"
    BATCH_STABILITY="$STABILITY"
    BATCH_STABILITY_COLOR="$STABILITY_COLOR"
    install_templates "$SELECTED_TEMPLATE_CHOICES"
    popd > /dev/null
    
    print_success "Completed: $first_dir"
    
    # Process remaining directories
    for dir in "${dirs[@]:1}"; do
        echo ""
        print_separator
        print_info "Processing: $dir"
        
        pushd "$dir" > /dev/null
        check_git_repo
        get_repo_info
        
        # Restore shared config if reusing
        if [[ "$BATCH_REUSE_TEMPLATES" == "true" ]]; then
            LICENSE_TYPE="$BATCH_LICENSE_TYPE"
            STABILITY="$BATCH_STABILITY"
            STABILITY_COLOR="$BATCH_STABILITY_COLOR"
        fi
        
        collect_project_info
        
        if [[ "$BATCH_REUSE_TEMPLATES" == "true" ]]; then
            install_templates "$BATCH_SELECTED_CHOICES"
        else
            select_templates
            install_templates "$SELECTED_TEMPLATE_CHOICES"
        fi
        
        popd > /dev/null
        print_success "Completed: $dir"
    done
    
    print_header_success "Batch Complete" 40
    print_info "Processed ${#dirs[@]} directories"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    parse_args "$@"
    
    if [[ "$CLI_HELP" == "true" ]]; then
        show_help
        exit 0
    fi
    
    if [[ "$BATCH_MODE" == "true" ]]; then
        run_batch_mode
        exit 0
    fi
    
    # Single repository mode
    print_header "Git-Control Template Loader"
    
    check_git_repo
    get_repo_info
    get_git_user_info
    
    # If specific files requested via CLI
    if [[ -n "$CLI_FILES" ]]; then
        collect_project_info
        IFS=',' read -ra FILES <<< "$CLI_FILES"
        for filename in "${FILES[@]}"; do
            filename=$(echo "$filename" | tr -d ' ')
            # Search for template
            local found=false
            for tpl_dir in "$GIT_CONTROL_DIR"/*-templates; do
                if is_file "$tpl_dir/$filename"; then
                    if [[ -f "$filename" && "$CLI_OVERWRITE" != "true" ]]; then
                        if ! confirm "Overwrite $filename?"; then
                            print_info "Skipping: $filename"
                            continue
                        fi
                    fi
                    process_template "$tpl_dir/$filename" "$filename"
                    found=true
                    break
                fi
            done
            if [[ "$found" != "true" ]]; then
                print_warning "Template not found: $filename"
            fi
        done
        exit 0
    fi
    
    # Interactive mode
    collect_project_info
    select_templates
    install_templates "$SELECTED_TEMPLATE_CHOICES"
    
    print_header_success "Templates Installed" 40
    print_section "Next Steps"
    print_command_hint "Review changes" "git status"
    print_command_hint "Stage files" "git add ."
    print_command_hint "Commit" "git commit -m 'chore: add project templates'"
}

main "$@"
