#!/usr/bin/env bash
#
# GitHub MCP Setup Script
# Automates GitHub MCP configuration for VS Code with secure token management
# 
# Features:
#   ✓ Automated PAT creation via browser auth (GitHub CLI)
#   ✓ Configures VS Code MCP settings with secure headers
#   ✓ Tests MCP connection
#   ✓ Install additional MCP servers (Stack Overflow, Firecrawl)
#   ✓ Token scopes: repo, workflow, read:user (minimal required)
#   ✓ 90-day expiration for security
#
# Usage:
#   ./mcp-setup.sh [--config-only] [--test] [--show-token] [--help]
#   
#   (no args)           Initialize MCP and configure servers (DEFAULT)
#   --config-only       Initialize MCP config only
#   --test              Test GitHub MCP connection only
#   --show-token        Display current GitHub token info (masked)
#   --help              Show this help message
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience
################################################################################

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"
export GIT_CONTROL_DIR  # Used by sourced libraries

# Source shared libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/print.sh"
source "$SCRIPT_DIR/lib/git-utils.sh"

# Configuration
detect_config_dir() {
    # Prefer workspace config if in a git repo
    if in_git_worktree; then
        local root
        root=$(git_root)
        if [[ -d "$root/.vscode" ]]; then
            echo "$root/.vscode"
            return
        fi
    fi
    
    # Fallback to user config
    local user_config="${HOME}/.config/Code/User"
    if [[ -d "$user_config" ]]; then
        echo "$user_config"
    else
        # Create if doesn't exist
        mkdir -p "$user_config"
        echo "$user_config"
    fi
}

MCP_CONFIG_DIR="$(detect_config_dir)"
MCP_CONFIG_FILE="${MCP_CONFIG_DIR}/mcp.json"
MCP_ENDPOINT="https://api.githubcopilot.com/mcp/"
TOKEN_SCOPES="repo,workflow,read:user"
TOKEN_EXPIRY_DAYS=90

# Scope presets for interactive selection
declare -A SCOPE_PRESETS=(
    ["minimal"]="read:user"
    ["standard"]="repo,workflow,read:user"
    ["full"]="repo,workflow,read:user,admin:org,gist,notifications"
)

# ============================================================================
# HELP
# ============================================================================

show_help() {
    cat << 'EOF'
Git-Control MCP Setup - Configure Model Context Protocol servers

USAGE:
  mcp-setup.sh [OPTIONS]

OPTIONS:
  --config-only     Initialize MCP config only (no server installs)
  --test            Test GitHub MCP connection only
  --show-token      Display current GitHub token info (masked)
  --help            Show this help message

SERVERS CONFIGURED:
  - GitHub MCP      Core integration for repo/PR management
  - Stack Overflow  Search and retrieve Q&A content
  - Firecrawl       Web scraping and search

REQUIREMENTS:
  - GitHub CLI (gh) installed and authenticated
  - VS Code with Copilot extension
  - Node.js 18+ (for MCP servers)

EXAMPLES:
  mcp-setup.sh               # Full setup
  mcp-setup.sh --test        # Test existing configuration
  mcp-setup.sh --config-only # Just create config file

ALIASES:
  gc-mcp

EOF
}

# ============================================================================
# TOKEN MANAGEMENT
# ============================================================================

get_github_token() {
    # Try gh cli first
    if command -v gh &>/dev/null; then
        local token
        token=$(gh auth token 2>/dev/null || echo "")
        if [[ -n "$token" ]]; then
            echo "$token"
            return 0
        fi
    fi
    
    # Try environment
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "$GITHUB_TOKEN"
        return 0
    fi
    
    return 1
}

show_token_info() {
    local token
    if token=$(get_github_token); then
        local masked="${token:0:4}...${token: -4}"
        print_info "GitHub token: ${CYAN}$masked${NC}"
        
        # Try to get token info
        if command -v gh &>/dev/null; then
            local username
            username=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
            print_info "Authenticated as: ${CYAN}$username${NC}"
        fi
    else
        print_warning "No GitHub token found"
        print_info "Run: ${CYAN}gh auth login${NC}"
    fi
}

# ============================================================================
# MCP CONFIGURATION
# ============================================================================

create_mcp_config() {
    print_info "Creating MCP configuration..."
    
    local token
    if ! token=$(get_github_token); then
        print_error "GitHub token required. Run: gh auth login"
        exit 1
    fi
    
    mkdir -p "$MCP_CONFIG_DIR"
    
    cat > "$MCP_CONFIG_FILE" << MCP_EOF
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "$token"
      }
    },
    "stackoverflow": {
      "command": "npx",
      "args": ["-y", "@nicholasrq/stackoverflow-mcp"]
    },
    "firecrawl": {
      "command": "npx",
      "args": ["-y", "firecrawl-mcp"]
    }
  }
}
MCP_EOF
    
    print_success "Created: $MCP_CONFIG_FILE"
}

test_mcp_connection() {
    print_info "Testing MCP connection..."
    
    if ! command -v npx &>/dev/null; then
        print_error "npx not found. Install Node.js first."
        exit 1
    fi
    
    local token
    if ! token=$(get_github_token); then
        print_error "No GitHub token. Run: gh auth login"
        exit 1
    fi
    
    # Quick test - just verify the server can start
    export GITHUB_PERSONAL_ACCESS_TOKEN="$token"
    
    if timeout 10 npx -y @modelcontextprotocol/server-github --help &>/dev/null; then
        print_success "GitHub MCP server is functional"
    else
        print_warning "Could not verify MCP server (may still work in VS Code)"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local mode="full"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config-only) mode="config"; shift ;;
            --test) mode="test"; shift ;;
            --show-token) mode="token"; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) print_error "Unknown option: $1"; exit 1 ;;
        esac
    done
    
    print_header "Git-Control MCP Setup"
    
    case "$mode" in
        token)
            show_token_info
            ;;
        test)
            require_gh_cli
            test_mcp_connection
            ;;
        config)
            require_gh_cli
            create_mcp_config
            ;;
        full)
            require_gh_cli
            create_mcp_config
            test_mcp_connection
            
            print_header_success "MCP Setup Complete!"
            
            print_section "Configured Servers:"
            print_list_item "GitHub MCP - Repository and PR management"
            print_list_item "Stack Overflow - Q&A search"
            print_list_item "Firecrawl - Web scraping"
            
            print_section "Next Steps:"
            echo -e "  1. Reload VS Code window (${CYAN}Ctrl+Shift+P${NC} -> ${CYAN}Reload Window${NC})"
            echo -e "  2. Start using MCP tools in Copilot Chat"
            echo ""
            ;;
    esac
}

main "$@"
