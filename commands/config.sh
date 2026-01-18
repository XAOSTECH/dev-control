#!/usr/bin/env bash
#
# Git-Control Configuration Command
# Manage git-control configuration interactively
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

set -e

if [[ -z "$GC_ROOT" ]]; then
    SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    GC_ROOT="$(dirname "$SCRIPT_PATH")"
fi

source "$GC_ROOT/scripts/lib/colors.sh"
source "$GC_ROOT/scripts/lib/print.sh"
source "$GC_ROOT/scripts/lib/config.sh"
source "$GC_ROOT/scripts/lib/tui.sh"

show_help() {
    cat << 'EOF'
Git-Control Configuration Manager

USAGE:
  gc config                    Show current configuration
  gc config get <key>          Get a specific value
  gc config set <key> <value>  Set a value (project scope)
  gc config set --global <key> <value>  Set globally
  gc config edit               Open config in editor
  gc config init               Initialize project config

KEYS:
  default-license       Default license (MIT, GPL-3.0, etc.)
  default-branch        Default branch name
  auto-sign-commits     Sign commits with GPG (true/false)
  auto-push-after-fix   Push after history fix (true/false)
  github-org            Default GitHub organization
  template-set          Template set (default/minimal/full)

EXAMPLES:
  gc config
  gc config get default-license
  gc config set default-license Apache-2.0
  gc config set --global github-org myorg
  gc config init

FILES:
  Global:  ~/.config/git-control/config.yaml
  Project: .gc-init.yaml (in repo root)

EOF
}

cmd_show() {
    print_header "Git-Control Configuration"
    
    load_gc_config
    
    print_section "Current Values:"
    gc_config_show "${GC_JSON:+json}"
    
    echo ""
    print_section "Config Files:"
    print_detail "Global" "$GC_GLOBAL_CONFIG"
    
    local project_root
    if project_root=$(git rev-parse --show-toplevel 2>/dev/null); then
        if [[ -f "$project_root/$GC_PROJECT_CONFIG" ]]; then
            print_detail "Project" "$project_root/$GC_PROJECT_CONFIG"
        else
            print_detail "Project" "(none - run 'gc config init' to create)"
        fi
    fi
    echo ""
}

cmd_get() {
    local key="$1"
    if [[ -z "$key" ]]; then
        print_error "Usage: gc config get <key>"
        return 1
    fi
    
    load_gc_config
    gc_config "${key//-/_}"
}

cmd_set() {
    local scope="project"
    
    # Check for --global flag
    if [[ "$1" == "--global" ]]; then
        scope="global"
        shift
    fi
    
    local key="$1"
    local value="$2"
    
    if [[ -z "$key" || -z "$value" ]]; then
        print_error "Usage: gc config set [--global] <key> <value>"
        return 1
    fi
    
    gc_config_set "$key" "$value" "$scope"
    print_success "Set $key = $value ($scope)"
}

cmd_edit() {
    local scope="${1:-project}"
    local config_file
    
    if [[ "$scope" == "global" ]]; then
        config_file="$GC_GLOBAL_CONFIG"
        init_gc_config_dir
    else
        local project_root
        project_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
            print_error "Not in a git repository"
            return 1
        }
        config_file="$project_root/$GC_PROJECT_CONFIG"
    fi
    
    # Create if doesn't exist
    if [[ ! -f "$config_file" ]]; then
        print_info "Creating $config_file"
        cp "$GC_ROOT/config/example.gc-init.yaml" "$config_file" 2>/dev/null || \
            echo "# git-control configuration" > "$config_file"
    fi
    
    ${EDITOR:-nano} "$config_file"
}

cmd_init() {
    local project_root
    project_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
        print_error "Not in a git repository"
        return 1
    }
    
    local config_file="$project_root/$GC_PROJECT_CONFIG"
    
    if [[ -f "$config_file" ]]; then
        print_warning "Config already exists: $config_file"
        if ! tui_confirm "Overwrite?"; then
            return 0
        fi
    fi
    
    print_info "Creating project configuration..."
    
    # Interactive setup using TUI
    local project_name license github_org
    
    project_name=$(tui_input "Project name:" "$(basename "$project_root")")
    license=$(tui_choose "Default license:" "MIT" "Apache-2.0" "GPL-3.0" "BSD-3-Clause" "LGPL-3.0" "Unlicense")
    github_org=$(tui_input "GitHub organization (leave empty for personal):" "")
    
    cat > "$config_file" << EOF
# git-control project configuration
# Generated on $(date +%Y-%m-%d)

project-name: $project_name
repo-slug: $(echo "$project_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

default-license: $license
default-branch: main

github-org: $github_org
visibility: public

auto-sign-commits: true
template-set: default
EOF
    
    print_success "Created: $config_file"
}

# Main
main() {
    local cmd="${1:-show}"
    shift 2>/dev/null || true
    
    case "$cmd" in
        show|list) cmd_show ;;
        get) cmd_get "$@" ;;
        set) cmd_set "$@" ;;
        edit) cmd_edit "$@" ;;
        init) cmd_init ;;
        -h|--help|help) show_help ;;
        *)
            # Check if it looks like a key
            if [[ "$cmd" =~ ^[a-z-]+$ ]]; then
                cmd_get "$cmd"
            else
                print_error "Unknown command: $cmd"
                show_help
                exit 1
            fi
            ;;
    esac
}

main "$@"
