#!/usr/bin/env bash
#
# Dev-Control Template Loading Script
# Initialise repositories with standardised templates
# 
# This script copies template files from all *-templates folders in Dev-Control:
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

# Resolve script location (handles symlinks for global/PATH usage)
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
DEV_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"
# Fallback if in Dev-Control root
[[ ! -d "$DEV_CONTROL_DIR/docs-templates" ]] && [[ -d "./docs-templates" ]] && DEV_CONTROL_DIR="$(pwd)"

# Source shared libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/print.sh"

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
    echo -e "${BOLD}Dev-Control Template Loader${NC}"
    echo ""
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --files FILE1,FILE2    Only process specific files (comma-separated)"
    echo "  -o, --overwrite            Overwrite existing files without prompting"
    echo "  -b, --batch                Batch mode: initialise multiple repositories (provide directories or use '*' to select all subdirs)"
    echo "      --reuse-owner          Prompt for repository owner once and reuse for all repos in the batch"
    echo "  -y, --yes                  Assume defaults and run non-interactively in batch mode"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0")                                    # Interactive mode"
    echo "  $(basename "$0") -f CONTRIBUTING.md -o              # Update single file"
    echo "  $(basename "$0") --files README.md,SECURITY.md      # Update multiple files"
    echo "  $(basename "$0") -f LICENSE -o                      # Update license"
    echo ""
    echo "Available template files:"
    for dir in "$DEV_CONTROL_DIR"/*-templates; do
        if [[ -d "$dir" ]]; then
            echo "  $(basename "$dir"):"
            for file in "$dir"/*; do
                [[ -f "$file" ]] && echo "    - $(basename "$file")"
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
    
    # Try to prefill GitHub username from gh CLI if not detected from remote
    if [[ -z "$ORG_NAME" ]] && command -v gh &>/dev/null; then
        local gh_user
        gh_user=$(gh api user --jq .login 2>/dev/null || true)
        if [[ -n "$gh_user" ]]; then
            ORG_NAME="$gh_user"
            print_info "Detected GitHub user from gh CLI: $ORG_NAME"
        fi
    fi

    # Load cached metadata from git config (set by previous dc-init runs)
    # Only load from LOCAL config if a local .git directory exists
    if [[ -d ".git" ]]; then
        local cached_license
        cached_license=$(git config --local dc-init.license-type 2>/dev/null || echo "")
        if [[ -n "$cached_license" ]]; then
            LICENSE_TYPE="$cached_license"
            print_info "Loaded licence from git config: $LICENSE_TYPE"
        fi
        
        local cached_org
        cached_org=$(git config --local dc-init.org-name 2>/dev/null || echo "")
        if [[ -n "$cached_org" ]]; then
            ORG_NAME="$cached_org"
        fi
        
        local cached_description
        cached_description=$(git config --local dc-init.description 2>/dev/null || echo "")
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
    
    echo -e "${BOLD}Project Configuration${NC}"
    
    # Project name
    read -rp "Project name [$PROJECT_NAME]: " input
    PROJECT_NAME="${input:-$PROJECT_NAME}"
    
    # Repository slug
    read -rp "Repository slug [$REPO_SLUG]: " input
    REPO_SLUG="${input:-$REPO_SLUG}"
    
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
        read -rp "Repository owner (user/org): " input
        REPO_OWNER="${input:-$ORG_NAME}"
        if [[ -n "$ORG_NAME" && -n "$REPO_OWNER" && "$REPO_OWNER" != "$ORG_NAME" ]]; then
            print_warning "Detected remote owner '$ORG_NAME' differs from entered owner '$REPO_OWNER'"
        fi
    else
        if [[ -z "$ORG_NAME" ]]; then
            read -rp "Repository owner (user/org): " REPO_OWNER
            REPO_OWNER="${REPO_OWNER:-$ORG_NAME}"
        else
            read -rp "Repository owner (user/org) [${ORG_NAME}]: " input
            REPO_OWNER="${input:-$ORG_NAME}"
        fi
    fi

    # Mirror back to ORG_NAME for compatibility with older code paths
    ORG_NAME="$REPO_OWNER"

    # Repository URL (constructed from chosen owner)
    REPO_URL="https://github.com/$REPO_OWNER/$REPO_SLUG"
    read -rp "Repository URL [$REPO_URL]: " input
    REPO_URL="${input:-$REPO_URL}"
    
    # Short description — ALWAYS asked per-repo, never shared in batch mode
    # Prefill from THIS repo's cached config (loaded by get_repo_info)
    if [[ -n "$SHORT_DESCRIPTION" ]]; then
        read -rp "Short description [$SHORT_DESCRIPTION]: " input
        SHORT_DESCRIPTION="${input:-$SHORT_DESCRIPTION}"
    else
        read -rp "Short description: " SHORT_DESCRIPTION
    fi
    
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
        echo "Select licence type:"
        echo "  1) MIT"
        echo "  2) Apache-2.0"
        echo "  3) GPL-3.0"
        echo "  4) BSD-3-Clause"
        echo "  5) Other"
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
                read -rp "Enter licence name [${LICENSE_TYPE:-}]: " custom_license
                LICENSE_TYPE="${custom_license:-$LICENSE_TYPE}"
                ;;
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
    fi
    
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
    for dir in "$DEV_CONTROL_DIR"/*-templates; do
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
    if [[ -d "$DEV_CONTROL_DIR/docs-templates" ]]; then
        echo -e "  ${CYAN}$idx)${NC} Documentation       - README, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY  (→ docs/)"
        echo -e "     ${YELLOW}Sub-options:${NC} A) README AX) README, BADGES ONLY B) CONTRIBUTING  C) CODE_OF_CONDUCT  D) SECURITY "
        TEMPLATE_FOLDERS[$idx]="docs"
        ((idx++))
    fi
    
    # workflows-templates  
    if [[ -d "$DEV_CONTROL_DIR/workflows-templates" ]]; then
        echo -e "  ${CYAN}$idx)${NC} Workflows           - GitHub Actions (→ .github/workflows/)"
        TEMPLATE_FOLDERS[$idx]="workflows"
        ((idx++))
    fi
    
    # github-templates (issue templates, PR template)
    if [[ -d "$DEV_CONTROL_DIR/github-templates" ]]; then
        echo -e "  ${CYAN}$idx)${NC} GitHub Templates    - Issue & PR templates (→ .github/)"
        TEMPLATE_FOLDERS[$idx]="github"
        ((idx++))
    fi
    
    # license-templates (or licenses-templates)
    if [[ -d "$DEV_CONTROL_DIR/license-templates" ]] || [[ -d "$DEV_CONTROL_DIR/licenses-templates" ]]; then
        echo -e "  ${CYAN}$idx)${NC} Licenses            - LICENSE file"
        TEMPLATE_FOLDERS[$idx]="licenses"
        ((idx++))
    fi
    
    # Any other *-templates folders
    for dir in "$DEV_CONTROL_DIR"/*-templates; do
        if [[ -d "$dir" ]]; then
            local name=$(basename "$dir")
            if [[ "$name" != "docs-templates" && "$name" != "workflows-templates" && "$name" != "license-templates" && "$name" != "licenses-templates" && "$name" != "github-templates" ]]; then
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
                    local tpl="$DEV_CONTROL_DIR/docs-templates/$f"
                    if [[ -f "$tpl" ]]; then
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
    local docs_dir="$DEV_CONTROL_DIR/docs-templates"
    
    print_info "Installing documentation templates..."
    
    for file in "$docs_dir"/*.md; do
        if [[ -f "$file" ]]; then
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
    # Replace placeholders
    badges="${badges//\{\{REPO_URL\}\}/$REPO_URL}"
    badges="${badges//\{\{ORG_NAME\}\}/$ORG_NAME}"
    badges="${badges//\{\{REPO_SLUG\}\}/$REPO_SLUG}"

    # If README doesn't exist, create from template if available
    if [[ ! -f "$readme_path" ]]; then
        if [[ -f "$DEV_CONTROL_DIR/docs-templates/README.md" ]]; then
            process_template "$DEV_CONTROL_DIR/docs-templates/README.md" "$readme_path"
        else
            echo -e "# $PROJECT_NAME\n" > "$readme_path"
        fi
    fi

    # Check if badges already present
    if grep -q 'img alt="GitHub repo"' "$readme_path"; then
        print_info "Badges already present in README, skipping insertion"
        rm -f "$tmp"
        return
    fi

    # Insert badges after the first H1
    awk -v badges="$badges" 'BEGIN{inserted=0} /^# / && !inserted{print; print badges; inserted=1; next} {print}' "$readme_path" > "$tmp" || {
        # Fallback: prepend badges
        printf "%s\n%s" "$badges" "$(cat "$readme_path")" > "$tmp"
    }
    mv "$tmp" "$readme_path"
    print_success "Inserted badges into $readme_path"
}

install_workflows_templates() {
    local target_dir="$1"
    local wf_dir="$DEV_CONTROL_DIR/workflows-templates"
    
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
    local gh_dir="$DEV_CONTROL_DIR/github-templates"
    
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
    local auto_choice="${2:-false}"
    local lic_dir=""
    
    # Check both folder names
    if [[ -d "$DEV_CONTROL_DIR/license-templates" ]]; then
        lic_dir="$DEV_CONTROL_DIR/license-templates"
    elif [[ -d "$DEV_CONTROL_DIR/licenses-templates" ]]; then
        lic_dir="$DEV_CONTROL_DIR/licenses-templates"
    else
        print_warning "No license folder found (license-templates or licenses-templates)"
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
    
    # Auto-select license when installing ALL
    if [[ "$auto_choice" == "true" ]]; then
        local pick=1
        if [[ -n "$LICENSE_TYPE" ]]; then
            for k in "${!LICENSE_FILES[@]}"; do
                local bname
                bname=$(basename "${LICENSE_FILES[$k]}")
                if [[ "${bname,,}" == "${LICENSE_TYPE,,}" ]]; then
                    pick=$k
                    break
                fi
            done
        fi
        lic_choice="$pick"
        print_info "Auto-selected license: $(basename "${LICENSE_FILES[$lic_choice]}")" 
    else
        read -rp "Choice [1]: " lic_choice
        lic_choice="${lic_choice:-1}"
    fi
    
    local selected_license="${LICENSE_FILES[$lic_choice]}"
    if [[ -f "$selected_license" ]]; then
        process_template "$selected_license" "$target_dir/LICENSE"
    else
        print_warning "No license selected or license file not found"
    fi
}

install_generic_templates() {
    local target_dir="$1"
    local folder_type="$2"
    local tpl_dir="$DEV_CONTROL_DIR/${folder_type}-templates"
    
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
    for dir in "$DEV_CONTROL_DIR"/*-templates; do
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

run_batch_init() {
    local dirs=()

    if [[ ${#POSITIONAL_ARGS[@]} -gt 0 ]]; then
        dirs=("${POSITIONAL_ARGS[@]}")
    else
        # Collect immediate subdirectories in current directory
        while IFS= read -r d; do
            dirs+=("$d")
        done < <(find . -maxdepth 1 -mindepth 1 -type d -not -name '.*' -printf '%P\n')
    fi

    if [[ ${#dirs[@]} -eq 0 ]]; then
        print_warning "No directories found to process in batch mode"
        return 1
    fi

    # Ask whether to use a single repository owner for all repos (only once)
    # Default to Yes for convenience (empty input treated as Yes)
    read -rp "Use a single repository owner for all repos? (Y/n): " use_single_owner
    if [[ -z "${use_single_owner}" || "${use_single_owner}" =~ ^[Yy] ]]; then
        # For convenience, try to detect an owner from the first directory's local git config
        local candidate_owner=""
        if [[ -d "${dirs[0]}" ]]; then
            pushd "${dirs[0]}" > /dev/null 2>&1 || true
            # Only check local git config, don't init or fetch from GitHub
            if git rev-parse --git-dir > /dev/null 2>&1; then
                candidate_owner=$(git config --local dc-init.org-name 2>/dev/null || echo "")
            fi
            popd > /dev/null 2>&1 || true
        fi

        if [[ -n "$candidate_owner" ]]; then
            read -rp "Repository owner (user/org) [${candidate_owner}]: " shared_owner
            REPO_OWNER="${shared_owner:-$candidate_owner}"
        else
            read -rp "Repository owner (user/org): " shared_owner
            REPO_OWNER="${shared_owner:-$REPO_OWNER}"
        fi

        ORG_NAME="$REPO_OWNER"
        REUSE_OWNER=true
        BATCH_SKIP_OWNER=false
        print_info "Using owner: $REPO_OWNER for all repositories"
    else
        # Do not prefill owner prompts from detected remotes; prompt per-repo
        BATCH_SKIP_OWNER=true
        print_info "Will prompt for repository owner individually"
    fi

    # Offer to reuse initialisation config (templates, licence, stability) for all repos
    read -rp "Reuse initialisation config (templates, licence, stability) for all repositories? (y/N): " reuse_templates
    if [[ "${reuse_templates}" =~ ^[Yy] ]]; then
        BATCH_REUSE_TEMPLATES=true
        print_info "Will reuse initialisation config across the batch"
        # If --yes was passed, prefill sensible defaults for the batch
        if [[ "$ASSUME_YES" == "true" ]]; then
            BATCH_SELECTED_CHOICES="A"
            BATCH_LICENSE_TYPE="${LICENSE_TYPE:-GPL-3.0}"
            BATCH_STABILITY="${STABILITY:-stable}"
            BATCH_STABILITY_COLOR="${STABILITY_COLOR:-green}"
            print_info "Batch will run non-interactively with defaults"
        fi
    fi

    for d in "${dirs[@]}"; do
        print_header
        print_info "Processing: $d"

        pushd "$d" > /dev/null || { print_error "Failed to enter $d"; continue; }

        # Ensure git repo initialised for this folder FIRST (before any config operations)
        check_git_repo

        # Reset variables for this repo iteration (prevent carryover from previous repos)
        # These must be reset AFTER check_git_repo but BEFORE get_repo_info
        SHORT_DESCRIPTION=""
        LONG_DESCRIPTION=""
        LICENSE_TYPE=""
        STABILITY=""
        STABILITY_COLOR=""
        PROJECT_NAME=""
        REPO_SLUG=""
        REPO_URL=""
        ORG_NAME=""

        # Attempt to detect repo info (may set ORG_NAME if remote present)
        # This will load from THIS repo's local git config
        get_repo_info

        # If user provided a shared owner earlier, warn when the detected owner for this repo differs
        if [[ "$REUSE_OWNER" == "true" && -n "$ORG_NAME" && -n "$REPO_OWNER" && "$ORG_NAME" != "$REPO_OWNER" ]]; then
            print_warning "Detected remote owner '$ORG_NAME' differs from chosen shared owner '$REPO_OWNER' for $d"
        fi

        # Pre-fill sensible defaults based on folder name
        PROJECT_NAME="$(basename "$PWD")"
        REPO_SLUG="$(basename "$PWD")"
        if [[ -n "$REPO_OWNER" ]]; then
            ORG_NAME="$REPO_OWNER"
        fi
        REPO_URL="https://github.com/${ORG_NAME}/${REPO_SLUG}"

        if [[ "$ASSUME_YES" == "true" ]]; then
            SHORT_DESCRIPTION="${SHORT_DESCRIPTION:-A project by $ORG_NAME}"
            LONG_DESCRIPTION="${LONG_DESCRIPTION:-$SHORT_DESCRIPTION}"
            LICENSE_TYPE="${LICENSE_TYPE:-MIT}"
            STABILITY="${STABILITY:-experimental}"
            STABILITY_COLOR="${STABILITY_COLOR:-orange}"
            CURRENT_YEAR=$(date +%Y)
        else
            # Interactive collect (prefilled with defaults)
            collect_project_info
        fi

        # Handle batch reuse of initialisation config
        if [[ "$BATCH_REUSE_TEMPLATES" == "true" ]]; then
            if [[ -z "$BATCH_SELECTED_CHOICES" ]]; then
                # First repo: allow selection and capture it for reuse
                select_templates
                BATCH_SELECTED_CHOICES="${SELECTED_TEMPLATE_CHOICES:-A}"
                BATCH_LICENSE_TYPE="${LICENSE_TYPE:-$BATCH_LICENSE_TYPE}"
                BATCH_STABILITY="${STABILITY:-$BATCH_STABILITY}"
                BATCH_STABILITY_COLOR="${STABILITY_COLOR:-$BATCH_STABILITY_COLOR}"
                print_info "Captured initialisation config for reuse: ${BATCH_SELECTED_CHOICES}"
            else
                # Reuse previously captured initialisation config
                SELECTED_TEMPLATE_CHOICES="${BATCH_SELECTED_CHOICES}"
                LICENSE_TYPE="${BATCH_LICENSE_TYPE}"
                STABILITY="${BATCH_STABILITY}"
                STABILITY_COLOR="${BATCH_STABILITY_COLOR}"
                print_info "Using shared initialisation config (templates, licence, stability)"
            fi
        else
            # Not reusing batch config; allow interactive selection for this repo
            select_templates
            SELECTED_TEMPLATE_CHOICES="${SELECTED_TEMPLATE_CHOICES:-A}"
        fi

        # Default to installing ALL templates unless user set a different selection
        SELECTED_TEMPLATE_CHOICES="${SELECTED_TEMPLATE_CHOICES:-A}"
        print_info "Installing templates: ${SELECTED_TEMPLATE_CHOICES}"
        install_templates "${SELECTED_TEMPLATE_CHOICES}"

        # Save metadata for dc-create
        save_project_metadata

        # Show summary and auto-queue creation for batch mode (no per-repo prompts)
        local saved_batch="$BATCH_MODE"
        BATCH_MODE="true"
        show_summary
        BATCH_MODE="$saved_batch"

        if [[ "$BATCH_MODE" == "true" ]]; then
            CREATE_QUEUE+=("$PWD")
            print_info "Queued for creation: $PWD"
        fi

        popd > /dev/null || true
    done

    # After processing all folders, offer to create queued repos
    if [[ ${#CREATE_QUEUE[@]} -gt 0 ]]; then
        echo ""
        read -rp "Create queued repositories now? (y/n) [y]: " create_now
        if [[ "${create_now:-y}" =~ [Yy] ]]; then
            # Build args for create-repo.sh
            local cre_args=("--batch")
            [[ "$ASSUME_YES" == "true" ]] && cre_args+=("--yes")
            # Pass directories as relative paths
            cre_args+=("${CREATE_QUEUE[@]}")
            print_info "Launching create-repo for ${#CREATE_QUEUE[@]} repositories"
            bash "$DEV_CONTROL_DIR/scripts/create-repo.sh" "${cre_args[@]}"
        else
            print_info "Queued repositories preserved; you can run: create-repo --batch <dirs...>"
        fi
    fi
}

# ============================================================================
# SUMMARY
# ============================================================================

save_project_metadata() {
    # Store collected metadata in LOCAL git config for dc-create to retrieve
    # Only save if a local .git directory exists
    if [[ -d ".git" ]]; then
        print_info "Saving project metadata to git config..."
        git config --local dc-init.project-name "$PROJECT_NAME" 2>/dev/null || true
        git config --local dc-init.repo-slug "$REPO_SLUG" 2>/dev/null || true
        git config --local dc-init.org-name "${REPO_OWNER:-$ORG_NAME}" 2>/dev/null || true
        git config --local dc-init.repo-url "$REPO_URL" 2>/dev/null || true
        git config --local dc-init.description "$SHORT_DESCRIPTION" 2>/dev/null || true
        git config --local dc-init.long-description "$LONG_DESCRIPTION" 2>/dev/null || true
        git config --local dc-init.license-type "$LICENSE_TYPE" 2>/dev/null || true
    fi
}

show_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║${NC}                   ${CYAN}Templates Installed!${NC}                     ${BOLD}${GREEN}║${NC}"
    echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Project:${NC} $PROJECT_NAME"
    echo -e "${BOLD}Repository:${NC} $REPO_URL"
    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    echo -e "  1. Review and customise the generated files"
    echo -e "  2. Replace placeholder sections - if any remain (marked with {{}})"
    echo ""
    
    # Offer to create GitHub repository
    echo -e "${BOLD}Create GitHub Repository?${NC}"
    echo "dc-init can now launch create-repo to set up your GitHub repository"
    echo "with the configuration we just collected."
    echo ""

    local show_repo_instructions=false
    if [[ "$BATCH_MODE" == "true" ]]; then
        print_info "Batch mode: skipping create-repo prompt for $PROJECT_NAME"
        show_repo_instructions=true
    else
        read -rp "Launch create-repo now? (y/n) [y]: " launch_create_repo
        if [[ "${launch_create_repo:-y}" =~ [Yy] ]]; then
            echo ""
            print_info "Launching create-repo..."
            echo ""
            # Find and run create-repo script
            if [[ -f "$DEV_CONTROL_DIR/scripts/create-repo.sh" ]]; then
                bash "$DEV_CONTROL_DIR/scripts/create-repo.sh"
            else
                print_warning "create-repo.sh not found at $DEV_CONTROL_DIR/scripts/create-repo.sh"
                show_repo_instructions=true
            fi
        else
            show_repo_instructions=true
        fi
    fi

    if [[ "$show_repo_instructions" == "true" ]]; then
        echo -e "  3. Create repository: ${CYAN}dc-create${NC}"
        echo -e "  or"
        echo -e "  4. Create manually: ${CYAN}git init && git add . && git commit -m 'Add documentation'${NC}"
    fi
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
    
    print_header "Dev-Control Template Loader"
    
    # Initialize git repo if needed and get user info early
    get_git_user_info
    check_git_repo
    
    local template_folders
    template_folders=$(discover_template_folders)
    
    if [[ -z "$template_folders" ]]; then
        print_error "No *-templates folders found in: $DEV_CONTROL_DIR"
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

    if [[ "$BATCH_MODE" == "true" ]]; then
        print_info "Batch mode enabled"
        run_batch_init
        exit 0
    fi

    print_info "Dev-Control directory: $DEV_CONTROL_DIR"
    print_info "Working directory: $(pwd)"
    print_info "Available template folders:"
    for dir in $template_folders; do
        echo "  • $(basename "$dir")"
    done
    
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_warning "Not a git repository - some features may not work."
        echo ""
    fi
    
    get_repo_info
    collect_project_info
    
    # Call select_templates directly (avoids subshell)
    select_templates
    local selection="${SELECTED_TEMPLATE_CHOICES:-}"
    
    echo ""
    print_info "Installing templates..."
    install_templates "$selection"
    
    # Save metadata for dc-create to use
    save_project_metadata
    
    show_summary
}

main "$@"