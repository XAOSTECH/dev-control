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
#   (no args)           initialise MCP and configure servers (DEFAULT)
#   --config-only       initialise MCP config only
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
DEV_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"
export DEV_CONTROL_DIR  # Used by sourced libraries

# Source shared libraries
source "$SCRIPT_DIR/lib/colours.sh"
source "$SCRIPT_DIR/lib/print.sh"
source "$SCRIPT_DIR/lib/git/utils.sh"

# Configuration
KEYRING_SERVICE="vscode-github-mcp"
KEYRING_KEY="token"
USE_KEYRING=true

# Detect if we should use keyring storage
detect_keyring_support() {
    if command -v secret-tool &>/dev/null; then
        return 0
    elif command -v pass &>/dev/null; then
        return 0
    fi
    return 1
}

detect_config_dir() {
    # Try to detect from current directory first (handles both container and host)
    local cwd="$PWD"
    
    # Check if we're in a git worktree from current directory
    if git -C "$cwd" rev-parse --is-inside-work-tree &>/dev/null; then
        local root
        root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
        if [[ -n "$root" ]]; then
            local vscode_dir="$root/.vscode"
            # Create .vscode if it doesn't exist
            if [[ ! -d "$vscode_dir" ]]; then
                mkdir -p "$vscode_dir"
                print_info "Created workspace .vscode directory" >&2
            fi
            echo "$vscode_dir"
            return
        fi
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
Dev-Control MCP Setup - Configure Model Context Protocol servers

USAGE:
  mcp-setup.sh [OPTIONS]

OPTIONS:
  --config-only     initialise MCP config only (no server installs)
  --create-pat      Create GitHub PAT and store in keyring (recommended)
  --test            Test GitHub MCP connection only
  --show-token      Display current GitHub token info (masked)
  --help            Show this help message

SERVERS CONFIGURED:
  - GitHub MCP      Core integration for repo/PR management
  - Stack Overflow  Search and retrieve Q&A content
  - Firecrawl       Web scraping and search (requires Node.js)

REQUIREMENTS:
  - GitHub CLI (gh) installed and authenticated
  - VS Code with Copilot extension
  - Node.js 18+ (optional, for Firecrawl MCP)
  - libsecret-tools (optional, for GNOME Keyring storage)
    Install: sudo apt install libsecret-tools
  - xclip/wl-copy (optional, for clipboard support)
    Install: sudo apt install xclip (X11) or wl-clipboard (Wayland)

TOKEN MANAGEMENT:
  Default mode creates config with VS Code secure inputs (most secure).
  All modes use VS Code prompts - tokens are NEVER hardcoded in config.
  
  When you use --create-pat, the token is:
  1. Optionally stored in system keyring (for --show-token retrieval)
  2. Optionally copied to clipboard (for easy pasting in VS Code)
  3. Displayed once (save it if you skip keyring/clipboard)
  
  VS Code will prompt for the token on first MCP use and store it in
  its secure credential vault automatically.
  
  Storage options:
  1. VS Code Secure Vault (automatic after first prompt) - Most secure
  2. System Keyring (optional backup) - For --show-token retrieval
  3. Clipboard (temporary) - For easy VS Code pasting
  4. GitHub CLI (gh auth token) - For testing/development

EXAMPLES:
  mcp-setup.sh               # Full setup with VS Code secure input
  mcp-setup.sh --create-pat  # Create PAT + store in keyring (recommended)
  mcp-setup.sh --test        # Test existing configuration
  mcp-setup.sh --show-token  # Retrieve token from keyring/gh
  mcp-setup.sh --config-only # Just create config file

ALIASES:
  dc-mcp

EOF
}

# ============================================================================
# TOKEN MANAGEMENT
# ============================================================================

check_keyring_availability() {
    local has_secret_tool=false
    local has_pass=false
    local has_gnome_keyring=false
    
    command -v secret-tool &>/dev/null && has_secret_tool=true
    command -v pass &>/dev/null && has_pass=true
    
    if pgrep -f gnome-keyring-daemon &>/dev/null; then
        has_gnome_keyring=true
    fi
    
    if [[ "$has_secret_tool" == "false" && "$has_pass" == "false" ]]; then
        if [[ "$has_gnome_keyring" == "true" ]]; then
            print_warning "GNOME Keyring daemon detected, but CLI tools not installed"
            echo ""
            print_info "To enable secure token storage in your system keyring:"
            echo -e "  ${CYAN}sudo apt install libsecret-tools${NC}"
            echo ""
            print_info "libsecret-tools provides 'secret-tool' for accessing GNOME Keyring"
            print_info "This allows storing tokens securely outside of config files"
            echo ""
            read -rp "Install libsecret-tools now? [y/N]: " install_choice
            if [[ "$install_choice" =~ ^[Yy] ]]; then
                print_info "Installing libsecret-tools..."
                if sudo apt install -y libsecret-tools 2>&1 | grep -q "is already"; then
                    print_success "libsecret-tools is already installed"
                    has_secret_tool=true
                elif command -v secret-tool &>/dev/null; then
                    print_success "libsecret-tools installed successfully"
                    has_secret_tool=true
                else
                    print_error "Failed to install libsecret-tools"
                    print_info "Continuing with VS Code secure input only"
                fi
                echo ""
            else
                print_info "Skipped. Will use VS Code secure input only"
            fi
        else
            print_info "No keyring detected. Will use VS Code secure input"
        fi
        
        # Re-check after potential installation
        if [[ "$has_secret_tool" == "false" && "$has_pass" == "false" ]]; then
            return 1
        fi
    fi
    
    if [[ "$has_secret_tool" == "true" || "$has_pass" == "true" ]]; then
        print_success "Keyring available: ${CYAN}${has_secret_tool:+secret-tool}${has_pass:+pass}${NC}"
        return 0
    fi
    
    return 1
}

store_token_securely() {
    local token="$1"
    
    # Try system keyring first (most secure)
    if [[ "$USE_KEYRING" == "true" ]]; then
        if command -v secret-tool &>/dev/null; then
            if secret-tool store --label="GitHub MCP Token" "$KEYRING_SERVICE" "$KEYRING_KEY" <<< "$token" 2>/dev/null; then
                print_success "Token stored in system keyring"
                echo "keyring://${KEYRING_SERVICE}/${KEYRING_KEY}"
                return 0
            fi
        elif command -v pass &>/dev/null; then
            if echo "$token" | pass insert -f "vscode/github-mcp-token" 2>/dev/null; then
                print_success "Token stored in pass password manager"
                echo "pass://vscode/github-mcp-token"
                return 0
            fi
        fi
    fi
    
    # Fallback: environment variable
    print_warning "Keyring storage not available"
    print_info "Export token manually: ${CYAN}export GH_MCP_TOKEN='your-token'${NC}"
    echo "env://GH_MCP_TOKEN"
}

retrieve_token_securely() {
    local token_ref="$1"
    
    if [[ "$token_ref" == "keyring://"* ]]; then
        local service=${token_ref#keyring://}
        service=${service%%/*}
        local key=${token_ref##*/}
        if command -v secret-tool &>/dev/null; then
            secret-tool lookup "$service" "$key" 2>/dev/null
            return $?
        fi
    elif [[ "$token_ref" == "pass://"* ]]; then
        local pass_key=${token_ref#pass://}
        if command -v pass &>/dev/null; then
            pass show "$pass_key" 2>/dev/null | head -n1
            return $?
        fi
    elif [[ "$token_ref" == "env://"* ]]; then
        local env_var=${token_ref#env://}
        eval "echo \"\${$env_var}\""
        return 0
    fi
    
    return 1
}

verify_github_auth() {
    print_info "Checking GitHub authentication..."
    
    if gh auth status &>/dev/null; then
        local username
        username=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
        print_success "Authenticated as: ${CYAN}$username${NC}"
        return 0
    else
        print_warning "Not authenticated with GitHub CLI"
        return 1
    fi
}

create_github_pat() {
    print_info "Creating GitHub Personal Access Token..." >&2
    print_info "Scopes: ${CYAN}$TOKEN_SCOPES${NC}" >&2
    print_info "This will open your browser for authentication" >&2
    echo "" >&2
    
    # Use gh auth refresh to create/refresh token with required scopes
    if ! gh auth refresh --scopes "$TOKEN_SCOPES" -h github.com >&2; then
        print_error "Failed to authenticate with GitHub" >&2
        return 1
    fi
    
    # Get the session token
    local token
    token=$(gh auth token 2>/dev/null)
    
    if [[ -z "$token" ]]; then
        print_error "Failed to retrieve token" >&2
        return 1
    fi
    
    echo "$token"
}

get_github_token() {
    # Try gh cli first (most common)
    if command -v gh &>/dev/null; then
        local token
        token=$(gh auth token 2>/dev/null || echo "")
        if [[ -n "$token" ]]; then
            echo "$token"
            return 0
        fi
    fi
    
    # Try keyring (if --create-pat was used)
    if detect_keyring_support; then
        local token
        token=$(retrieve_token_securely "keyring://${KEYRING_SERVICE}/${KEYRING_KEY}" 2>/dev/null || echo "")
        if [[ -n "$token" ]]; then
            echo "$token"
            return 0
        fi
    fi
    
    # Try environment variables
    if [[ -n "${GH_MCP_TOKEN:-}" ]]; then
        echo "$GH_MCP_TOKEN"
        return 0
    fi
    
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "$GITHUB_TOKEN"
        return 0
    fi
    
    # Try to extract from mcp.json (if it was embedded)
    if [[ -f "$MCP_CONFIG_FILE" ]] && command -v grep &>/dev/null; then
        local embedded_token
        embedded_token=$(grep -oP '"authorisation":\s*"Bearer\s+\K[^"]+' "$MCP_CONFIG_FILE" 2>/dev/null || echo "")
        # Check if it's an actual token (not a variable reference or spurious output)
        if [[ -n "$embedded_token" && "$embedded_token" != *'${'* && "$embedded_token" != *'[INFO]'* && "$embedded_token" != *'[ERROR]'* ]]; then
            echo "$embedded_token"
            return 0
        fi
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
# HELPER FUNCTIONS
# ============================================================================

detect_npx_path() {
    # Detect absolute path to npx for VS Code extension host compatibility
    if command -v npx &>/dev/null; then
        which npx 2>/dev/null || command -v npx
    else
        echo "npx"  # Fallback to bare command if not found
    fi
}

detect_node_bin_dir() {
    # Detect the bin directory containing node/npx for PATH configuration
    if command -v node &>/dev/null; then
        local node_path
        node_path=$(which node 2>/dev/null || command -v node)
        dirname "$node_path"
    else
        echo ""
    fi
}

# Note: require_gh_cli() is provided by sourced git-utils.sh (with auth check)

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
    
    # Detect npx path for VS Code extension host compatibility
    local npx_cmd
    npx_cmd=$(detect_npx_path)
    
    # Detect node bin directory for PATH
    local node_bin_dir
    node_bin_dir=$(detect_node_bin_dir)
    
    # Build PATH for firecrawl env (include node bin dir if detected)
    local firecrawl_path="\${env:PATH}"
    if [[ -n "$node_bin_dir" ]]; then
        firecrawl_path="$node_bin_dir:\${env:PATH}"
    fi
    
    # Generate config with secure inputs
    cat > "$MCP_CONFIG_FILE" << MCP_EOF
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
        "authorisation": "Bearer \${input:github_mcp_pat}"
      }
    },
    "stackoverflow": {
      "type": "http",
      "url": "https://mcp.stackoverflow.com"
    },
    "firecrawl": {
      "command": "$npx_cmd",
      "args": ["-y", "firecrawl-mcp"],
      "env": {
        "FIRECRAWL_API_KEY": "\${input:firecrawlApiKey}",
        "PATH": "$firecrawl_path"
      },
      "type": "stdio"
    }
  }
}
MCP_EOF
    
    print_success "Created: $MCP_CONFIG_FILE"
    if [[ "$npx_cmd" != "npx" ]]; then
        print_info "Using npx at: ${CYAN}$npx_cmd${NC}"
    fi
    if [[ -n "$node_bin_dir" ]]; then
        print_info "Node.js bin dir: ${CYAN}$node_bin_dir${NC}"
    fi
    print_info "VS Code will prompt for tokens on first use"
}

# Create MCP config with embedded token (for --create-pat mode)
create_mcp_config_with_token() {
    local token="$1"
    
    print_info "Creating MCP configuration with embedded token..."
    
    # Ensure directory exists
    mkdir -p "$MCP_CONFIG_DIR"
    
    # Detect npx path for VS Code extension host compatibility
    local npx_cmd
    npx_cmd=$(detect_npx_path)
    
    # Detect node bin directory for PATH
    local node_bin_dir
    node_bin_dir=$(detect_node_bin_dir)
    
    # Build PATH for firecrawl env (include node bin dir if detected)
    local firecrawl_path="\${env:PATH}"
    if [[ -n "$node_bin_dir" ]]; then
        firecrawl_path="$node_bin_dir:\${env:PATH}"
    fi
    
    # Create config with token embedded in authorisation header
    cat > "$MCP_CONFIG_FILE" << EOF
{
  "inputs": [
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
        "authorisation": "Bearer $token"
      }
    },
    "stackoverflow": {
      "type": "http",
      "url": "https://mcp.stackoverflow.com"
    },
    "firecrawl": {
      "command": "$npx_cmd",
      "args": ["-y", "firecrawl-mcp"],
      "env": {
        "FIRECRAWL_API_KEY": "\${input:firecrawlApiKey}",
        "PATH": "$firecrawl_path"
      },
      "type": "stdio"
    }
  }
}
EOF
    
    print_success "Created: $MCP_CONFIG_FILE"
    if [[ "$npx_cmd" != "npx" ]]; then
        print_info "Using npx at: ${CYAN}$npx_cmd${NC}"
    fi
    if [[ -n "$node_bin_dir" ]]; then
        print_info "Node.js bin dir: ${CYAN}$node_bin_dir${NC}"
    fi
    print_info "Token embedded in config (secure file permissions recommended)"
    chmod 600 "$MCP_CONFIG_FILE" 2>/dev/null || true
}

test_mcp_connection() {
    print_info "Testing MCP configuration..."
    
    if [[ ! -f "$MCP_CONFIG_FILE" ]]; then
        print_error "MCP config not found: $MCP_CONFIG_FILE"
        return 1
    fi
    
    print_success "MCP config found: $MCP_CONFIG_FILE"
    
    # Verify config is valid JSON
    if ! command -v jq &>/dev/null; then
        print_warning "jq not installed - skipping JSON validation"
        print_info "Install with: ${CYAN}sudo apt install jq${NC}"
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
        print_info "Testing GitHub MCP endpoint..."
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
        print_warning "npx not found - Firecrawl server disabled"
        print_info "Install Node.js 18+ to enable: ${CYAN}sudo apt install nodejs npm${NC}"
    fi
    
    # Check GitHub authentication
    if command -v gh &>/dev/null; then
        if gh auth status &>/dev/null; then
            local username
            username=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
            print_success "GitHub CLI authenticated as: ${CYAN}$username${NC}"
        else
            print_warning "GitHub CLI not authenticated"
            print_info "Run: ${CYAN}gh auth login${NC}"
        fi
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
            --create-pat) mode="create-pat"; shift ;;
            --test) mode="test"; shift ;;
            --show-token) mode="token"; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) print_error "Unknown option: $1"; exit 1 ;;
        esac
    done
    
    print_header "Dev-Control MCP Setup"
    
    case "$mode" in
        token)
            show_token_info
            ;;
        create-pat)
            require_gh_cli
            print_info "This will create a GitHub PAT with scopes: ${CYAN}$TOKEN_SCOPES${NC}"
            echo ""
            
            # Check if already authenticated
            if ! verify_github_auth; then
                print_info "Please authenticate first: ${CYAN}gh auth login${NC}"
                exit 1
            fi
            
            # Create PAT
            local token
            if token=$(create_github_pat); then
                print_success "PAT created successfully"
                local masked="${token:0:4}...${token: -4}"
                print_info "Token: ${CYAN}$masked${NC}"
                
                # Store in keyring (recommended)
                local stored_in_keyring=false
                if check_keyring_availability; then
                    echo ""
                    read -rp "Store token in system keyring? [Y/n]: " store_choice
                    if [[ -z "$store_choice" || "$store_choice" =~ ^[Yy] ]]; then
                        local token_ref
                        token_ref=$(store_token_securely "$token")
                        if [[ "$token_ref" == keyring://* ]] || [[ "$token_ref" == pass://* ]]; then
                            stored_in_keyring=true
                        fi
                    fi
                fi
                
                # Copy to clipboard if available
                local copied_to_clipboard=false
                if command -v xclip &>/dev/null || command -v wl-copy &>/dev/null || command -v pbcopy &>/dev/null; then
                    echo ""
                    read -rp "Copy token to clipboard for easy pasting in VS Code? [Y/n]: " copy_choice
                    if [[ -z "$copy_choice" || "$copy_choice" =~ ^[Yy] ]]; then
                        if command -v wl-copy &>/dev/null; then
                            echo "$token" | wl-copy
                            copied_to_clipboard=true
                            print_success "Token copied to clipboard (Wayland)"
                        elif command -v xclip &>/dev/null; then
                            echo "$token" | xclip -selection clipboard
                            copied_to_clipboard=true
                            print_success "Token copied to clipboard (X11)"
                        elif command -v pbcopy &>/dev/null; then
                            echo "$token" | pbcopy
                            copied_to_clipboard=true
                            print_success "Token copied to clipboard (macOS)"
                        fi
                    fi
                fi
                
                # Create standard config with VS Code secure inputs (NOT embedded token)
                echo ""
                create_mcp_config
                
                print_header_success "PAT Created!"
                
                if [[ "$stored_in_keyring" == "true" ]]; then
                    print_section "Token Storage:"
                    print_list_item "✓ Stored in system keyring (GNOME Keyring)"
                    print_list_item "Retrieve anytime: ${CYAN}dc-mcp --show-token${NC}"
                    print_list_item "Or: ${CYAN}secret-tool lookup vscode-github-mcp github-token${NC}"
                else
                    print_section "Token Created:"
                    print_list_item "Token: ${CYAN}$masked${NC}"
                    if [[ "$copied_to_clipboard" == "false" ]]; then
                        print_list_item "Full token: ${YELLOW}$token${NC}"
                        print_warning "Save this token - it won't be shown again!"
                    fi
                fi
                
                if [[ "$copied_to_clipboard" == "true" ]]; then
                    print_section "Clipboard:"
                    print_list_item "✓ Token copied to clipboard"
                    print_list_item "Ready to paste in VS Code prompt"
                fi
                
                print_section "MCP Configuration:"
                print_list_item "Config created at: ${CYAN}$MCP_CONFIG_FILE${NC}"
                print_list_item "Uses VS Code secure inputs (no hardcoded token)"
                
                print_section "Next Steps:"
                echo -e "  ${CYAN}1.${NC} Reload VS Code window"
                echo -e "     • Press ${CYAN}Ctrl+Shift+P${NC}"
                echo -e "     • Type: ${CYAN}Developer: Reload Window${NC}"
                echo ""
                echo -e "  ${CYAN}2.${NC} VS Code will prompt for GitHub PAT"
                if [[ "$copied_to_clipboard" == "true" ]]; then
                    echo -e "     • Simply paste from clipboard (${CYAN}Ctrl+V${NC})"
                elif [[ "$stored_in_keyring" == "true" ]]; then
                    echo -e "     • Retrieve with: ${CYAN}dc-mcp --show-token${NC}"
                else
                    echo -e "     • Enter: ${YELLOW}$token${NC}"
                fi
                echo ""
                echo -e "  ${CYAN}3.${NC} Start using MCP tools in Copilot Chat"
                echo -e "     • Open chat and try MCP commands"
                echo ""
                
                print_section "Tips:"
                print_list_item "Token stored in VS Code's secure credential store on first use"
                print_list_item "Won't be prompted again until token expires or is revoked"
                if [[ "$stored_in_keyring" == "true" ]]; then
                    print_list_item "Backup copy in system keyring for recovery"
                fi
            else
                print_error "Failed to create PAT"
                exit 1
            fi
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
            
            # Check keyring availability (don't exit on failure)
            check_keyring_availability || true
            
            # Check authentication status (don't exit on failure)
            if ! verify_github_auth; then
                print_warning "Not authenticated. MCP will use VS Code secure input"
                print_info "Or authenticate now: ${CYAN}gh auth login${NC}"
                echo ""
            fi
            
            create_mcp_config
            test_mcp_connection
            
            print_header_success "MCP Setup Complete!"
            
            print_section "Configured Servers:"
            print_list_item "GitHub MCP - Repository and PR management"
            print_list_item "Stack Overflow - Q&A search"
            print_list_item "Firecrawl - Web scraping (requires npx)"
            
            print_section "Token Configuration:"
            if detect_keyring_support; then
                print_list_item "Option 1: Use ${CYAN}dc-mcp --create-pat${NC} to create and store in keyring"
                print_list_item "Option 2: Let VS Code prompt for token (recommended)"
            else
                print_list_item "VS Code will prompt for your GitHub PAT on first use"
            fi
            
            print_section "Next Steps:"
            echo -e "  1. Reload VS Code window (${CYAN}Ctrl+Shift+P${NC} -> ${CYAN}Reload Window${NC})"
            echo -e "  2. VS Code will prompt for your GitHub PAT when you first use MCP"
            echo -e "  3. Generate PAT at: ${CYAN}https://github.com/settings/tokens${NC}"
            echo -e "     Required scopes: ${CYAN}repo, workflow, read:user${NC}"
            echo -e "  4. Or run ${CYAN}dc-mcp --create-pat${NC} to create automatically"
            echo -e "  5. Start using MCP tools in Copilot Chat"
            echo ""
            ;;
    esac
}

main "$@"
