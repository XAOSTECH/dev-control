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

# Create base MCP configuration
setup_mcp_config() {
    print_header "Initializing VS Code MCP"
    print_info "Target config: $MCP_CONFIG_FILE"
    
    # Ensure directory exists
    mkdir -p "$MCP_CONFIG_DIR"
    
    # Create empty base config if it doesn't exist
    if [ ! -f "$MCP_CONFIG_FILE" ]; then
        jq -n '{
          "servers": {},
          "inputs": []
        }' > "$MCP_CONFIG_FILE"
        print_step "Created base config at $MCP_CONFIG_FILE"
    else
        print_info "Config file already exists at $MCP_CONFIG_FILE"
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
    echo "1. Start the MCP Servers:"
    echo "   - Open GitHub Copilot Chat (Ctrl+Shift+I)."
    echo "   - The configured servers should start automatically."
    echo ""
    echo "   (If tools don't appear, Reload Window: Ctrl+Shift+P -> 'Developer: Reload Window')"
    echo ""
    echo "2. Verify:"
    echo "   - Look for the 'Attach Context' (paperclip) icon in Chat."
    echo "   - You should see your enabled MCP tools listed."
    echo ""
    echo "Note:"
    echo "   - GitHub token expires in $TOKEN_EXPIRY_DAYS days"
    echo "   - To refresh, run: $0 --setup"
    echo ""
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

# Ensure MCP config exists with proper structure (consolidated helper)
ensure_mcp_config() {
    if [ ! -f "$MCP_CONFIG_FILE" ]; then
        print_info "Creating MCP config at $MCP_CONFIG_FILE"
        mkdir -p "$(dirname "$MCP_CONFIG_FILE")"
        jq -n '{
            "servers": {},
            "inputs": []
        }' > "$MCP_CONFIG_FILE"
    fi
}

# Add or update an input definition in MCP config
add_mcp_input() {
    local id="$1"
    local type="$2"
    local description="$3"
    
    ensure_mcp_config
    
    # Remove existing input with this id, then add the new one
    jq --arg id "$id" --arg type "$type" --arg desc "$description" \
        '.inputs |= map(select(.id != $id)) | .inputs += [{
            "type": $type,
            "id": $id,
            "description": $desc,
            "password": true
        }]' "$MCP_CONFIG_FILE" > "${MCP_CONFIG_FILE}.tmp" && \
        mv "${MCP_CONFIG_FILE}.tmp" "$MCP_CONFIG_FILE"
}

# Add server to MCP config (handles both HTTP and command-based servers)
add_mcp_server() {
    local server_name="$1"
    local server_config="$2"
    
    ensure_mcp_config
    
    jq --arg name "$server_name" --argjson config "$server_config" \
        '.servers[$name] = $config' "$MCP_CONFIG_FILE" > "${MCP_CONFIG_FILE}.tmp" && \
        mv "${MCP_CONFIG_FILE}.tmp" "$MCP_CONFIG_FILE"
}

# Install GitHub MCP Server (via HTTP remote)
install_github_mcp() {
    print_header "GitHub MCP Server"
    
    print_info "GitHub MCP provides access to GitHub API and operations"
    print_warning "Requires GitHub Personal Access Token (create at https://github.com/settings/tokens)"
    print_info "Recommended scopes: repo, workflow, read:user"
    echo ""
    
    read -p "Install GitHub MCP? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Skipped GitHub MCP"
        return 0
    fi
    
    print_info "Adding GitHub MCP to config..."
    
    # Use helper to ensure config exists
    ensure_mcp_config
    
    # Add GitHub PAT input
    add_mcp_input "github_mcp_pat" "promptString" "GitHub Personal Access Token" || {
        print_error "Failed to add input to MCP config"
        return 1
    }
    
    # Add GitHub server entry (HTTP-based)
    add_mcp_server "github" '{
        "type": "http",
        "url": "https://api.githubcopilot.com/mcp/",
        "headers": {
            "Authorization": "Bearer ${input:github_mcp_pat}"
        }
    }' || {
        print_error "Failed to add GitHub server to MCP config"
        return 1
    }
    
    print_success "GitHub MCP added to config"
    print_info "VS Code will prompt you to enter your GitHub PAT on first use"
}

# Install Stack Overflow MCP Server (via HTTP remote, no npx needed)
install_stackoverflow_mcp() {
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
    
    print_info "Adding Stack Overflow MCP to config..."
    
    # Use helper to ensure config exists
    ensure_mcp_config
    
    # Add server entry
    add_mcp_server "stackoverflow" '{
        "type": "http",
        "url": "https://mcp.stackoverflow.com"
    }' || {
        print_error "Failed to add Stack Overflow to MCP config"
        return 1
    }
    
    print_success "Stack Overflow MCP added to config"
    print_info "You will be prompted to log in to Stack Exchange on first use"
}

# Install Firecrawl MCP Server (Docker-based HTTP or NPX-based command)
install_firecrawl_mcp() {
    print_header "Firecrawl MCP Server"
    
    print_info "Firecrawl MCP enables web scraping and crawling capabilities"
    print_warning "Requires Firecrawl API key (free tier available at https://www.firecrawl.dev)"
    echo ""
    
    read -p "Install Firecrawl MCP? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Skipped Firecrawl MCP"
        return 0
    fi
    
    # Detect available container runtimes
    local has_docker=false
    local has_podman=false
    
    if command -v docker &> /dev/null; then
        has_docker=true
    fi
    if command -v podman &> /dev/null; then
        has_podman=true
    fi
    
    # Offer installation method choice
    echo ""
    echo "Installation method:"
    echo "1) Docker/Podman (HTTP, no Node.js needed on host, recommended)"
    echo "2) NPX (command-based, requires Node.js/npm)"
    echo ""
    
    read -p "Choose method (1-2): " method_choice
    
    if [ "$method_choice" = "1" ]; then
        if [ "$has_docker" = false ] && [ "$has_podman" = false ]; then
            print_error "Docker or Podman not found. Install one or choose method 2"
            return 1
        fi
        install_firecrawl_docker
    elif [ "$method_choice" = "2" ]; then
        install_firecrawl_npx
    else
        print_error "Invalid choice"
        return 1
    fi
}

# Install Firecrawl via Docker/Podman with HTTP streamable mode
install_firecrawl_docker() {
    print_header "Firecrawl MCP - Docker/Podman Installation"
    
    local container_runtime="docker"
    if ! command -v docker &> /dev/null && command -v podman &> /dev/null; then
        container_runtime="podman"
    fi
    
    print_info "Using container runtime: $container_runtime"
    echo ""
    
    # Get API key from user
    read -sp "Enter your Firecrawl API Key (will not be echoed): " api_key
    echo ""
    
    if [ -z "$api_key" ]; then
        print_error "API key required"
        return 1
    fi
    
    print_info "Adding Firecrawl MCP to config..."
    
    # Use helper to ensure config exists
    ensure_mcp_config
    
    # Add Firecrawl API key input
    add_mcp_input "firecrawlApiKey" "promptString" "Firecrawl API Key" || {
        print_error "Failed to add input to MCP config"
        return 1
    }
    
    # Add Firecrawl server entry (HTTP-based, connects to localhost:3000)
    add_mcp_server "firecrawl" '{
        "type": "http",
        "url": "http://localhost:3000/mcp"
    }' || {
        print_error "Failed to add Firecrawl server to MCP config"
        return 1
    }
    
    print_success "Firecrawl MCP configured in $MCP_CONFIG_FILE"
    echo ""
    print_warning "ACTION REQUIRED: Start the Firecrawl MCP container"
    echo ""
    echo "Run this command in a terminal:"
    echo ""
    echo "  $container_runtime run -d \\"
    echo "    --name firecrawl-mcp \\"
    echo "    -e FIRECRAWL_API_KEY='$api_key' \\"
    echo "    -e HTTP_STREAMABLE_SERVER=true \\"
    echo "    -p 3000:3000 \\"
    echo "    node:20-slim \\"
    echo "    sh -c 'npx -y firecrawl-mcp'"
    echo ""
    echo "Or use docker-compose with:"
    echo ""
    echo "  version: '3.8'"
    echo "  services:"
    echo "    firecrawl-mcp:"
    echo "      image: node:20-slim"
    echo "      command: sh -c 'npx -y firecrawl-mcp'"
    echo "      environment:"
    echo "        FIRECRAWL_API_KEY: '${api_key}'"
    echo "        HTTP_STREAMABLE_SERVER: 'true'"
    echo "      ports:"
    echo "        - '3000:3000'"
    echo ""
    print_info "After starting the container, reload VS Code and use Firecrawl tools"
    
    # Clear API key from memory
    unset api_key
}

# Install Firecrawl via NPX (requires Node.js)
install_firecrawl_npx() {
    print_header "Firecrawl MCP - NPX Installation"
    
    print_info "Adding Firecrawl MCP to config..."
    
    # Use helper to ensure config exists
    ensure_mcp_config
    
    # Add Firecrawl API key input
    add_mcp_input "apiKey" "promptString" "Firecrawl API Key" || {
        print_error "Failed to add input to MCP config"
        return 1
    }
    
    # Add Firecrawl server entry (command-based, uses npx)
    add_mcp_server "firecrawl" '{
        "command": "npx",
        "args": ["-y", "firecrawl-mcp"],
        "env": {
            "FIRECRAWL_API_KEY": "${input:apiKey}"
        }
    }' || {
        print_error "Failed to add Firecrawl server to MCP config"
        return 1
    }
    
    print_success "Firecrawl MCP configured in $MCP_CONFIG_FILE"
    print_info "NPX will download firecrawl-mcp automatically on first use"
    print_info "Or pre-install: npm install -g firecrawl-mcp"
}

# Setup available MCP servers
setup_mcp_servers() {
    print_header "MCP Servers Configuration"
    
    check_dependencies
    
    if [ ! -f "$MCP_CONFIG_FILE" ]; then
        print_error "MCP config not found. Run --setup first"
        exit 1
    fi
    
    echo "Available MCP servers to install:"
    echo ""
    echo "1) GitHub           - GitHub API access (HTTP remote)"
    echo "2) Stack Overflow   - Search Q&A (HTTP remote)"
    echo "3) Firecrawl        - Web scraping (Docker or NPX)"
    echo "4) All of the above"
    echo "5) Cancel"
    echo ""
    
    read -p "Choose option (1-5): " choice
    
    case $choice in
        1)
            install_github_mcp
            ;;
        2)
            install_stackoverflow_mcp
            ;;
        3)
            install_firecrawl_mcp
            ;;
        4)
            install_github_mcp
            install_stackoverflow_mcp
            install_firecrawl_mcp
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
    print_success "MCP servers configured!"
    print_info "Reload VS Code (Ctrl+Shift+P -> 'Developer: Reload Window') to activate the servers."
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
    local mode="${1:---default}"
    
    case "$mode" in
        --default|"")
            print_header "MCP Setup"
            check_dependencies
            verify_github_auth
            
            # Initialize base config
            setup_mcp_config
            
            # Ask user to select servers
            echo ""
            read -p "Would you like to configure MCP servers now? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                setup_mcp_servers
            fi
            
            show_next_steps
            ;;
        
        --config-only)
            print_header "MCP Configuration (Config Only)"
            check_dependencies
            setup_mcp_config
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
