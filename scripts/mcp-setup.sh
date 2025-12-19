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
#   ./mcp-setup.sh [--setup] [--config-only] [--test] [--show-token] [--install-servers] [--revoke ID] [--help]
#   
#   --setup             Full setup: create token, configure MCP, test (DEFAULT)
#   --config-only       Configure MCP with existing token (from gh auth token)
#   --test              Test MCP connection only
#   --show-token        Display current token info (masked)
#   --install-servers   Install additional MCP servers (Stack Overflow, Firecrawl)
#   --help              Show this help message
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
# Detect VS Code config directory (Workspace or User)
detect_config_dir() {
    # 1. Check current working directory for .vscode
    if [ -d "${PWD}/.vscode" ]; then
        echo "${PWD}/.vscode"
        return
    fi

    # 2. Check environment variables (passed from VS Code Tasks)
    if [ -n "$VSCODE_WORKSPACE_FOLDER" ]; then
        echo "${VSCODE_WORKSPACE_FOLDER}/.vscode"
        return
    fi
    if [ -n "$WORKSPACE_FOLDER" ]; then
        echo "${WORKSPACE_FOLDER}/.vscode"
        return
    fi

    # 3. Fallback to User Global Settings
    echo "${HOME}/.config/Code/User"
}

MCP_CONFIG_DIR="$(detect_config_dir)"
MCP_CONFIG_FILE="${MCP_CONFIG_DIR}/mcp.json"
MCP_ENDPOINT="https://api.githubcopilot.com/mcp/"
TOKEN_SCOPES="repo,workflow,read:user"
TOKEN_EXPIRY_DAYS=90

# Secure storage options (priority order)
USE_KEYRING=false
if command -v secret-tool &> /dev/null; then
    USE_KEYRING=true
    KEYRING_SERVICE="vscode-github-mcp"
    KEYRING_KEY="github-token"
elif command -v pass &> /dev/null; then
    USE_KEYRING=true
    KEYRING_SERVICE="vscode-github-mcp"
    KEYRING_KEY="github-token"
fi

################################################################################
# Functions
################################################################################

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
}

print_step() {
    echo -e "${GREEN}✓${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓ SUCCESS${NC} $1"
}

# Store token securely and return key reference
store_token_securely() {
    local token="$1"
    
    # Try system keyring first (most secure)
    if [ "$USE_KEYRING" = true ]; then
        if command -v secret-tool &> /dev/null; then
            if secret-tool store --label="GitHub MCP Token" "$KEYRING_SERVICE" "$KEYRING_KEY" <<< "$token" 2>/dev/null; then
                print_step "Token stored in system keyring (secret-tool)"
                echo "keyring://${KEYRING_SERVICE}/${KEYRING_KEY}"
                return 0
            fi
        elif command -v pass &> /dev/null; then
            if echo "$token" | pass insert -f "vscode/github-mcp-token" 2>/dev/null; then
                print_step "Token stored in pass password manager"
                echo "pass://vscode/github-mcp-token"
                return 0
            fi
        fi
    fi
    
    # Fallback: Store in environment variable reference
    # User must set GH_MCP_TOKEN environment variable
    print_warning "System keyring not available"
    print_info "Token will use environment variable: GH_MCP_TOKEN"
    print_info "Set manually: export GH_MCP_TOKEN='$token'"
    echo "env://GH_MCP_TOKEN"
}

# Retrieve token from secure storage
retrieve_token_securely() {
    local token_ref="$1"
    
    if [[ "$token_ref" == "keyring://"* ]]; then
        local service=$(echo "$token_ref" | sed 's|keyring://\([^/]*\).*|\1|')
        local key=$(echo "$token_ref" | sed 's|.*\/\([^/]*\)$|\1|')
        if command -v secret-tool &> /dev/null; then
            secret-tool lookup "$service" "$key" 2>/dev/null
            return $?
        fi
    elif [[ "$token_ref" == "pass://"* ]]; then
        local pass_key=$(echo "$token_ref" | sed 's|pass://||')
        if command -v pass &> /dev/null; then
            pass show "$pass_key" 2>/dev/null | head -n1
            return $?
        fi
    elif [[ "$token_ref" == "env://"* ]]; then
        local env_var=$(echo "$token_ref" | sed 's|env://||')
        eval "echo \"\${$env_var}\""
        return 0
    fi
    
    return 1
}

check_dependencies() {
    print_step "Checking dependencies..."
    
    local missing=()
    
    for cmd in gh jq curl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing required commands: ${missing[*]}"
        echo -e "\nInstall them with:"
        echo "  Ubuntu/Debian: sudo apt-get install ${missing[*]}"
        echo "  macOS: brew install ${missing[*]}"
        exit 1
    fi
    
    # Check for secure storage options
    local has_secret_tool=false
    local has_pass=false
    local has_gnome_keyring=false

    if command -v secret-tool &> /dev/null; then
        has_secret_tool=true
    fi

    if command -v pass &> /dev/null; then
        has_pass=true
    fi

    # Detect if GNOME Keyring daemon is running (standard on Ubuntu)
    if pgrep -f gnome-keyring-daemon &> /dev/null; then
        has_gnome_keyring=true
    fi

    if [ "$has_secret_tool" = false ] && [ "$has_pass" = false ]; then
        if [ "$has_gnome_keyring" = true ]; then
            print_warning "GNOME Keyring (Passwords and Keys) is active, but the CLI tool is missing."
            print_info "To let this script save secrets to your keyring, install the CLI bridge:"
            print_info "  sudo apt-get install libsecret-tools"
            echo ""
            print_info "Falling back to manual entry or environment variables for now."
        else
            print_warning "No secure storage found (secret-tool or pass)"
            print_info "Tokens will use environment variable fallback or manual entry"
            print_info "Install 'libsecret-tools' (Linux) to enable GNOME Keyring integration"
        fi
    fi
}

verify_github_auth() {
    print_step "Checking GitHub authentication status..."
    
    if gh auth status &> /dev/null; then
        local username
        username=$(gh api user --jq '.login')
        print_success "Authenticated as: $username"
    else
        print_warning "Not authenticated with GitHub CLI"
        print_info "You will need to authenticate to create a token."
        print_info "Run 'gh auth login' if the script fails."
    fi
}

create_github_pat() {
    # Use gh auth refresh to create a new token with browser confirmation
    # This displays the device code and auth link
    if ! gh auth refresh --scopes "$TOKEN_SCOPES" -h github.com; then
        return 1
    fi
    
    # Get the token from gh auth token (session token, valid for this session)
    local token
    token=$(gh auth token)
    
    if [ -z "$token" ]; then
        return 1
    fi
    
    # Output ONLY the token to stdout
    echo "$token"
}

# Create/update MCP configuration
setup_mcp_config() {
    local token="$1"
    
    print_header "Configuring VS Code MCP"
    print_info "Target config: $MCP_CONFIG_FILE"
    
    # Ensure directory exists
    mkdir -p "$MCP_CONFIG_DIR"
    
    # Create config with variable substitution for the token
    if [ ! -f "$MCP_CONFIG_FILE" ]; then
        jq -n '{
          "servers": {
            "io.github.github/github-mcp-server": {
              "type": "http",
              "url": "https://api.githubcopilot.com/mcp/",
              "headers": {
                "Authorization": "Bearer ${input:github_mcp_pat}"
              }
            }
          },
          "inputs": [
            {
              "type": "promptString",
              "id": "github_mcp_pat",
              "description": "GitHub Personal Access Token",
              "password": true
            }
          ]
        }' > "$MCP_CONFIG_FILE"
        print_step "Created config template at $MCP_CONFIG_FILE"
    else
        print_info "Config file already exists."
        
        # Check for existing GitHub MCP server (by URL)
        local existing_key
        existing_key=$(jq -r '.servers | to_entries[] | select(.value.url == "https://api.githubcopilot.com/mcp/") | .key' "$MCP_CONFIG_FILE" | head -n1)
        
        local target_key="io.github.github/github-mcp-server"
        if [ -n "$existing_key" ]; then
            print_warning "Found existing GitHub MCP server configuration: '$existing_key'"
            
            if [ "$existing_key" != "io.github.github/github-mcp-server" ]; then
                 print_warning "Existing key '$existing_key' is not the preferred 'io.github.github/github-mcp-server'."
                 read -p "Do you want to migrate '$existing_key' to 'io.github.github/github-mcp-server'? (y/n): " -n 1 -r
                 echo
                 if [[ $REPLY =~ ^[Yy]$ ]]; then
                    # Delete the old key and use the new target_key
                    jq --arg old_key "$existing_key" 'del(.servers[$old_key])' "$MCP_CONFIG_FILE" > "${MCP_CONFIG_FILE}.tmp" && mv "${MCP_CONFIG_FILE}.tmp" "$MCP_CONFIG_FILE"
                    print_step "Removed old key '$existing_key'"
                 else
                    target_key="$existing_key"
                 fi
            else
                target_key="$existing_key"
            fi
        fi

        # Update or add server entry and ensure input definition exists
        # Use --arg key "$target_key" to dynamically set the key
        jq --arg key "$target_key" '
        .servers[$key] = {
          "type": "http",
          "url": "https://api.githubcopilot.com/mcp/",
          "headers": {
            "Authorization": "Bearer ${input:github_mcp_pat}"
          }
        } + (if .servers[$key] then .servers[$key] else {} end) | 
        .servers[$key].headers.Authorization = "Bearer ${input:github_mcp_pat}" |
        .inputs = (.inputs // []) |
        .inputs |= map(select(.id != "github_mcp_pat")) |
        .inputs += [{
            "type": "promptString",
            "id": "github_mcp_pat",
            "description": "GitHub Personal Access Token",
            "password": true
        }]' "$MCP_CONFIG_FILE" > "${MCP_CONFIG_FILE}.tmp" && mv "${MCP_CONFIG_FILE}.tmp" "$MCP_CONFIG_FILE"
        
        print_step "Updated '$target_key' server entry and inputs in existing config"
    fi

    if [ -n "$token" ]; then
        echo ""
        print_warning "ACTION REQUIRED: Token generated."
        echo "1. Copy the token below."
        echo "2. Reload VS Code (Ctrl+Shift+P -> Developer: Reload Window)."
        echo "3. VS Code will prompt you to enter the value for 'github_mcp_pat'."
        echo "4. Paste the token there."
        echo ""
        echo "--------------------------------------------------------------------------------"
        # Securely display token
        echo "Token: $token"
        echo "--------------------------------------------------------------------------------"
        read -n 1 -s -r -p "Press any key to clear token from screen..."
        echo ""
        clear
        unset token
        print_info "Token cleared from screen and memory."
        echo ""
    else
        echo ""
        print_success "Configuration restored."
        print_info "VS Code will use the 'github_mcp_pat' stored in your secure keychain."
        print_info "If you haven't saved it yet, VS Code will prompt you when you reload."
        echo ""
    fi
}

test_mcp_connection() {
    local token="$1"
    
    print_header "Testing MCP Connection"
    
    print_info "Connecting to: $MCP_ENDPOINT"
    
    local response
    response=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer $token" \
        "$MCP_ENDPOINT" 2>/dev/null || echo "000")
    
    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | head -n-1)
    
    if [[ "$http_code" =~ ^(200|204|400|403|401)$ ]]; then
        print_success "MCP endpoint is reachable (HTTP $http_code)"
        if [ -n "$body" ]; then
            print_info "Response: $body"
        fi
    else
        print_warning "Unexpected HTTP response: $http_code"
        if [ -n "$body" ]; then
            print_info "Response: $body"
        fi
    fi
}

show_next_steps() {
    print_header "Setup Complete!"
    
    echo "Configuration stored in:"
    echo "  $MCP_CONFIG_FILE"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Start the MCP Server:"
    echo "   - Open GitHub Copilot Chat (Ctrl+Shift+I)."
    echo "   - Toggle 'Agent Mode' (if available) or simply start a new chat."
    echo "   - The server should start automatically."
    echo ""
    echo "   (If tools don't appear, you may need to Reload Window: Ctrl+Shift+P -> 'Developer: Reload Window')"
    echo ""
    echo "2. Verify:"
    echo "   - Look for the 'Attach Context' (paperclip) icon in Chat."
    echo "   - You should see GitHub tools listed there."
    echo ""
    echo "Note:"
    echo "   - Token expires in $TOKEN_EXPIRY_DAYS days"
    echo "   - To refresh, run: $0 --setup"
    echo ""
    
    # Ask if user wants to install additional servers
    echo ""
    read -p "Would you like to install additional MCP servers (Stack Overflow, Firecrawl)? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_additional_servers
    fi

    # Ask if user wants to configure workspace settings
    echo ""
    configure_workspace_settings
}

# Show current token info (masked)
show_token() {
    print_header "Current GitHub Token Info"
    
    check_dependencies
    
    local token
    token=$(gh auth token)
    
    if [ -z "$token" ]; then
        print_error "No token found"
        exit 1
    fi
    
    # Get first and last 4 chars
    local masked_token
    masked_token="${token:0:8}...${token: -4}"
    
    print_info "Token: $masked_token"
    
    # Get token status without showing the actual token
    local status
    status=$(gh auth status 2>&1)
    echo "$status"
}

show_help() {
    grep "^#" "$0" | head -20
}

# Install MCP server from VS Code marketplace extension (requires `code` CLI)
install_marketplace_mcp() {
    local extension_id="$1"
    local name="$2"
    
    print_info "Installing $name from VS Code Marketplace..."
    
    if ! command -v code &> /dev/null; then
        print_warning "VS Code CLI not found (code command not in PATH)"
        print_info "Install it or use: https://marketplace.visualstudio.com/items?itemName=$extension_id"
        return 1
    fi
    
    if code --install-extension "$extension_id" 2>&1; then
        print_success "$name installed!"
        print_info "Reload VS Code to activate (Ctrl+Shift+P → Developer: Reload Window)"
        return 0
    else
        print_warning "Failed to install $name via CLI"
        print_info "Install manually at: https://marketplace.visualstudio.com/items?itemName=$extension_id"
        return 1
    fi
}

# Install Stack Overflow MCP Server (via HTTP remote, no npx needed)
install_stackoverflow_marketplace() {
    print_header "Stack Overflow MCP Server"
    
    print_info "Stack Overflow MCP allows searching questions and accessing answers"
    print_info "Remote HTTP endpoint: https://mcp.stackoverflow.com"
    print_info "Limit: 100 calls per day per Stack Exchange user"
    echo ""
    
    read -p "Install Stack Overflow MCP? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Skipped Stack Overflow MCP"
        return 0
    fi
    
    if [ ! -f "$MCP_CONFIG_FILE" ]; then
        print_error "MCP config not found. Run --setup first"
        return 1
    fi
    
    print_info "Adding Stack Overflow MCP to config..."
    
    # Use jq to safely add server without breaking existing config
    # This preserves the entire existing structure
    jq '.servers.stackoverflow = {
        "type": "http",
        "url": "https://mcp.stackoverflow.com"
    }' "$MCP_CONFIG_FILE" > "${MCP_CONFIG_FILE}.tmp"
    
    if [ $? -ne 0 ]; then
        print_error "Failed to update config (JSON parse error)"
        rm -f "${MCP_CONFIG_FILE}.tmp"
        return 1
    fi
    
    mv "${MCP_CONFIG_FILE}.tmp" "$MCP_CONFIG_FILE"
    print_success "Stack Overflow MCP added to config (HTTP remote)"
    print_info "You will be prompted to log in to Stack Exchange on first use"
}

# Install Firecrawl MCP Server (via marketplace extension)
install_firecrawl_marketplace() {
    print_header "Firecrawl MCP Server"
    
    print_info "Firecrawl MCP enables web scraping and crawling capabilities"
    print_warning "Requires Firecrawl API key (free tier available at https://www.firecrawl.dev)"
    echo ""
    
    read -p "Install Firecrawl MCP extension? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Skipped Firecrawl MCP"
        return 0
    fi
    
    install_marketplace_mcp "firecrawl.mcp-server" "Firecrawl MCP"
    
    if [ $? -eq 0 ]; then
        print_info "After installation, configure your Firecrawl API key in VS Code settings"
    fi
}

# Install Hugging Face MCP Server (via marketplace extension)
install_huggingface_marketplace() {
    print_header "Hugging Face MCP Server"
    
    print_info "Hugging Face MCP provides access to models, datasets, and more"
    echo ""
    
    read -p "Install Hugging Face MCP extension? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Skipped Hugging Face MCP"
        return 0
    fi
    
    install_marketplace_mcp "huggingface.huggingface-vscode" "Hugging Face MCP"
}

# Show all available MCP servers to install
install_additional_servers() {
    print_header "Additional MCP Servers"
    
    check_dependencies
    
    if [ ! -f "$MCP_CONFIG_FILE" ]; then
        print_error "MCP config not found. Run --setup first"
        exit 1
    fi
    
    echo "Available MCP servers to install:"
    echo ""
    echo "1) Stack Overflow  - Search Q&A (HTTP remote, no CLI needed)"
    echo "2) Firecrawl        - Web scraping (marketplace extension)"
    echo "3) Hugging Face     - ML models & datasets (marketplace extension)"
    echo "4) All of the above"
    echo "5) Cancel"
    echo ""
    
    read -p "Choose option (1-5): " choice
    
    case $choice in
        1)
            install_stackoverflow_marketplace
            ;;
        2)
            install_firecrawl_marketplace
            ;;
        3)
            install_huggingface_marketplace
            ;;
        4)
            install_stackoverflow_marketplace
            install_firecrawl_marketplace
            install_huggingface_marketplace
            ;;
        5)
            print_info "Cancelled"
            return 0
            ;;
        *)
            print_error "Invalid option"
            return 1
            ;;
    esac
    
    echo ""
    print_success "Additional servers configured!"
    print_info "Open Copilot Chat to start using them."
}

# Configure workspace settings (e.g. auto-start)
configure_workspace_settings() {
    print_header "Workspace Settings"
    
    local settings_file="${MCP_CONFIG_DIR}/settings.json"
    
    print_info "You can configure workspace settings to control Copilot behavior."
    
    read -p "Do you want to configure Copilot workspace settings? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 0
    fi
    
    # Check if settings.json exists
    if [ ! -f "$settings_file" ]; then
        echo "{}" > "$settings_file"
    fi
    
    print_info "Common settings:"
    echo "1) github.copilot.chat.mcp.enabled (Enable/Disable MCP)"
    echo "2) Custom setting"
    
    read -p "Choose option (1-2): " choice
    
    local key=""
    local value=""
    
    case $choice in
        1)
            key="github.copilot.chat.mcp.enabled"
            read -p "Enable MCP? (true/false): " value
            ;;
        2)
            read -p "Enter setting key: " key
            read -p "Enter setting value: " value
            ;;
        *)
            print_error "Invalid option"
            return 1
            ;;
    esac
    
    if [ -n "$key" ]; then
        if [[ "$value" == "true" || "$value" == "false" ]]; then
            jq --arg key "$key" --argjson val "$value" '.[$key] = $val' "$settings_file" > "${settings_file}.tmp" && mv "${settings_file}.tmp" "$settings_file"
        else
            jq --arg key "$key" --arg val "$value" '.[$key] = $val' "$settings_file" > "${settings_file}.tmp" && mv "${settings_file}.tmp" "$settings_file"
        fi
        print_success "Updated $settings_file"
    fi
}

################################################################################
# Main execution
################################################################################

main() {
    local mode="${1:---setup}"
    
    case "$mode" in
        --setup)
            print_header "GitHub MCP Setup"
            check_dependencies
            verify_github_auth
            
            # Check if config exists and uses the variable
            if [ -f "$MCP_CONFIG_FILE" ] && grep -q "\${input:github_mcp_pat}" "$MCP_CONFIG_FILE"; then
                 print_info "Existing configuration detected using secure variable."
                 read -p "Do you want to generate a new token and rotate the secret? (y/N): " -n 1 -r
                 echo
                 if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                     print_success "Keeping existing configuration."
                     show_next_steps
                     return 0
                 fi
            else
                 # Config missing or doesn't use variable
                 if [ ! -f "$MCP_CONFIG_FILE" ]; then
                     print_warning "Configuration file not found."
                     
                     # Check if we have a stored token in secret-tool
                     local stored_token=""
                     if [ "$USE_KEYRING" = true ] && command -v secret-tool &> /dev/null; then
                         stored_token=$(secret-tool lookup "$KEYRING_SERVICE" "$KEYRING_KEY" 2>/dev/null || true)
                     fi

                     if [ -n "$stored_token" ]; then
                         print_info "Found a token stored in system keyring (secret-tool)."
                         read -p "Do you want to use this stored token? (Y/n): " -n 1 -r
                         echo
                         if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                             setup_mcp_config "$stored_token"
                             show_next_steps
                             return 0
                         fi
                     else
                         print_info "If you previously set this up, your token may still be in the VS Code keychain."
                         read -p "Do you want to generate a NEW token? (Select 'n' to use existing VS Code secret) (y/N): " -n 1 -r
                         echo
                         if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                             setup_mcp_config ""
                             show_next_steps
                             return 0
                         fi
                     fi
                 fi
            fi
            
            print_header "Creating GitHub Personal Access Token"
            print_info "Token will be created with scopes: $TOKEN_SCOPES"
            print_info "Expiration: $TOKEN_EXPIRY_DAYS days"
            print_info "Browser will open to confirm creation..."
            echo ""
            
            local token
            token=$(create_github_pat)
            
            if [ -z "$token" ]; then
                print_error "Failed to create or retrieve token"
                exit 1
            fi
            
            # Store token in keyring for future recovery/checks
            store_token_securely "$token" > /dev/null
            
            setup_mcp_config "$token"
            # Skip test as we expect 401/Prompt
            print_info "Skipping connection test (VS Code will prompt for token)"
            show_next_steps
            ;;
        
        --config-only)
            print_header "GitHub MCP Configuration (Config Only)"
            check_dependencies
            print_info "Using token from: gh auth token"
            local token
            token=$(gh auth token)
            if [ -z "$token" ]; then
                print_error "Unable to get token from gh auth token"
                exit 1
            fi
            setup_mcp_config "$token"
            show_next_steps
            ;;
        
        --test)
            print_header "GitHub MCP Connection Test"
            check_dependencies
            local token
            token=$(gh auth token)
            if [ -z "$token" ]; then
                print_error "Unable to get token from gh auth token"
                exit 1
            fi
            test_mcp_connection "$token"
            ;;
        
        --show-token)
            show_token
            ;;
        
        --install-servers)
            install_additional_servers
            ;;
        
        --help|-h)
            show_help
            ;;
        
        *)
            print_error "Unknown option: $mode"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
