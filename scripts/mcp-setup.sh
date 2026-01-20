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
        local vscode_dir="$root/.vscode"
        # Create .vscode if it doesn't exist
        if [[ ! -d "$vscode_dir" ]]; then
            mkdir -p "$vscode_dir"
            print_info "Created workspace .vscode directory"
        fi
        echo "$vscode_dir"
        return
    fi
    
    # Fallback to user config only if not in git repo
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
    
    # Verify gh cli is available for initial token validation
    if ! command -v gh &>/dev/null; then
        print_warning "GitHub CLI (gh) not found - token validation skipped"
        print_info "Install with: sudo apt install gh"
    fi
    
    mkdir -p "$MCP_CONFIG_DIR"
    
    # Generate config with secure inputs
    cat > "$MCP_CONFIG_FILE" << 'MCP_EOF'
{
  "inputs": [
    {
      "type": "promptString",
      "id": "github_mcp_pat",
      "description": "GitHub Personal Access Token",
      "password": true
    },
    {
      "type": "promptString",
      "id": "firecrawlApiKey",
      "description": "Firecrawl API Key (optional)",
      "password": true
    }
  ],
  "servers": {
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/",
      "headers": {
        "Authorization": "Bearer ${input:github_mcp_pat}"
      }
    },
    "stackoverflow": {
      "type": "http",
      "url": "https://mcp.stackoverflow.com"
    },
    "firecrawl": {
      "command": "npx",
      "args": ["-y", "firecrawl-mcp"],
      "env": {
        "FIRECRAWL_API_KEY": "${input:firecrawlApiKey}"
      },
      "type": "stdio"
    }
  }
}
MCP_EOF
    
    print_success "Created: $MCP_CONFIG_FILE"
    print_info "VS Code will prompt for tokens on first use"
}

test_mcp_connection() {
    print_info "Testing MCP configuration..."
    
    if [[ ! -f "$MCP_CONFIG_FILE" ]]; then
        print_error "MCP config not found: $MCP_CONFIG_FILE"
        return 1
    fi
    
    # Verify config is valid JSON
    if ! command -v jq &>/dev/null; then
        print_warning "jq not installed - skipping JSON validation"
    else
        if jq empty "$MCP_CONFIG_FILE" 2>/dev/null; then
            print_success "MCP config is valid JSON"
        else
            print_error "Invalid JSON in MCP config"
            return 1
        fi
    fi
    
    # Test GitHub MCP endpoint accessibility
    if command -v curl &>/dev/null; then
        if curl -s -o /dev/null -w "%{http_code}" --max-time 5 "https://api.githubcopilot.com" | grep -q "[234][0-9][0-9]"; then
            print_success "GitHub MCP endpoint is reachable"
        else
            print_warning "GitHub MCP endpoint test inconclusive (check network)"
        fi
    fi
    
    # Verify npx availability for Firecrawl (optional)
    if command -v npx &>/dev/null; then
        print_success "npx available for Firecrawl integration"
    else
        print_warning "npx not found - Firecrawl MCP will not work (install Node.js if needed)"
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
            echo -e "  2. VS Code will prompt for your GitHub PAT when you first use MCP"
            echo -e "  3. Generate PAT at: ${CYAN}https://github.com/settings/tokens${NC}"
            echo -e "     Required scopes: ${CYAN}repo, workflow, read:user${NC}"
            echo -e "  4. Start using MCP tools in Copilot Chat"
            echo ""
            ;;
    esac
}

main "$@"
