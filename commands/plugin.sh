#!/usr/bin/env bash
#
# Dev-Control Plugin Manager
# Install, remove, and manage plugins
#
# Usage:
#   gc plugin list              List installed plugins
#   gc plugin install <source>  Install a plugin
#   gc plugin remove <name>     Remove a plugin
#   gc plugin update <name>     Update a plugin
#   gc plugin info <name>       Show plugin details
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

set -e

# Get DC_ROOT from environment or resolve
if [[ -z "$DC_ROOT" ]]; then
    SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    DC_ROOT="$(dirname "$(dirname "$SCRIPT_PATH")")"
fi

PLUGINS_DIR="$DC_ROOT/plugins"

source "$DC_ROOT/scripts/lib/colours.sh"
source "$DC_ROOT/scripts/lib/print.sh"

# ============================================================================
# PLUGIN DISCOVERY
# ============================================================================

list_plugins() {
    local format="${1:-text}"
    local plugins=()
    
    for plugin_dir in "$PLUGINS_DIR"/*/; do
        [[ -d "$plugin_dir" ]] || continue
        [[ -f "${plugin_dir}plugin.yaml" ]] || continue
        
        local name version description
        name=$(basename "$plugin_dir")
        version=$(grep '^version:' "${plugin_dir}plugin.yaml" | cut -d: -f2 | tr -d ' ')
        description=$(grep '^description:' "${plugin_dir}plugin.yaml" | cut -d: -f2- | sed 's/^ *//')
        
        if [[ "$format" == "json" ]]; then
            plugins+=("{\"name\": \"$name\", \"version\": \"$version\", \"description\": \"$description\"}")
        else
            printf "  ${CYAN}%-20s${NC} ${DIM}v%-8s${NC} %s\n" "$name" "$version" "$description"
        fi
    done
    
    if [[ "$format" == "json" ]]; then
        echo "[$(IFS=,; echo "${plugins[*]}")]"
    elif [[ ${#plugins[@]} -eq 0 ]]; then
        echo "  No plugins installed"
    fi
}

show_plugin_info() {
    local name="$1"
    local plugin_dir="$PLUGINS_DIR/$name"
    
    if [[ ! -d "$plugin_dir" ]]; then
        print_error "Plugin not found: $name"
        return 1
    fi
    
    print_header "Plugin: $name"
    
    if [[ -f "${plugin_dir}/plugin.yaml" ]]; then
        cat "${plugin_dir}/plugin.yaml"
    fi
    
    echo ""
    print_section "Commands:"
    for cmd in "${plugin_dir}/commands/"*.sh; do
        [[ -f "$cmd" ]] || continue
        local cmd_name
        cmd_name=$(basename "$cmd" .sh)
        echo "  - gc $cmd_name"
    done
}

# ============================================================================
# PLUGIN INSTALLATION
# ============================================================================

install_plugin() {
    local source="$1"
    
    if [[ -z "$source" ]]; then
        print_error "Usage: gc plugin install <source>"
        echo "  Sources:"
        echo "    gh:user/repo     - GitHub repository"
        echo "    /path/to/plugin  - Local directory"
        return 1
    fi
    
    # GitHub source
    if [[ "$source" =~ ^gh: ]]; then
        local repo="${source#gh:}"
        local name
        name=$(basename "$repo")
        name="${name#dc-plugin-}"  # Remove common prefix
        
        print_info "Installing plugin from GitHub: $repo"
        
        if [[ -d "$PLUGINS_DIR/$name" ]]; then
            print_warning "Plugin already exists: $name"
            read -rp "Overwrite? [y/N]: " confirm
            [[ "$confirm" =~ ^[Yy] ]] || return 0
            rm -rf "${PLUGINS_DIR:?}/$name"
        fi
        
        git clone --depth 1 "https://github.com/$repo.git" "$PLUGINS_DIR/$name"
        rm -rf "${PLUGINS_DIR:?}/$name/.git"
        
        print_success "Installed: $name"
        return 0
    fi
    
    # Local source
    if [[ -d "$source" ]]; then
        local name
        name=$(basename "$source")
        
        if [[ -d "$PLUGINS_DIR/$name" ]]; then
            print_error "Plugin already exists: $name"
            return 1
        fi
        
        cp -r "$source" "$PLUGINS_DIR/$name"
        print_success "Installed: $name"
        return 0
    fi
    
    print_error "Unknown source format: $source"
    return 1
}

remove_plugin() {
    local name="$1"
    local plugin_dir="$PLUGINS_DIR/$name"
    
    if [[ ! -d "$plugin_dir" ]]; then
        print_error "Plugin not found: $name"
        return 1
    fi
    
    read -rp "Remove plugin '$name'? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy] ]] || return 0
    
    rm -rf "$plugin_dir"
    print_success "Removed: $name"
}

update_plugin() {
    local name="$1"
    local plugin_dir="$PLUGINS_DIR/$name"
    
    if [[ ! -d "$plugin_dir" ]]; then
        print_error "Plugin not found: $name"
        return 1
    fi
    
    # Check if we have source info
    local url
    url=$(grep '^url:' "${plugin_dir}/plugin.yaml" 2>/dev/null | cut -d: -f2- | tr -d ' ')
    
    if [[ -z "$url" ]]; then
        print_error "No update URL found in plugin.yaml"
        return 1
    fi
    
    print_info "Updating $name from $url"
    
    # Re-install
    rm -rf "$plugin_dir"
    git clone --depth 1 "$url" "$plugin_dir"
    rm -rf "$plugin_dir/.git"
    
    print_success "Updated: $name"
}

# ============================================================================
# HELP
# ============================================================================

show_help() {
    cat << 'EOF'
Dev-Control Plugin Manager

USAGE:
  gc plugin <command> [args]

COMMANDS:
  list              List installed plugins
  install <source>  Install a plugin
  remove <name>     Remove a plugin
  update <name>     Update a plugin
  info <name>       Show plugin details

SOURCES:
  gh:user/repo      GitHub repository
  /path/to/plugin   Local directory

EXAMPLES:
  gc plugin list
  gc plugin install gh:user/dc-plugin-example
  gc plugin remove example
  gc plugin info example

EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local cmd="${1:-list}"
    shift 2>/dev/null || true
    
    case "$cmd" in
        list)
            print_section "Installed Plugins:"
            list_plugins "${DC_JSON:+json}"
            ;;
        install)
            install_plugin "$@"
            ;;
        remove|uninstall)
            remove_plugin "$@"
            ;;
        update)
            update_plugin "$@"
            ;;
        info)
            show_plugin_info "$@"
            ;;
        -h|--help|help)
            show_help
            ;;
        *)
            print_error "Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
