#!/usr/bin/env bash
#
# Dev-Control Shared Library: GPG Key Management
# Functions for generating and managing GPG keys for automation
#
# Usage:
#   source "${SCRIPT_DIR}/lib/git/gpg.sh"
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

# Ensure print functions are available
if ! declare -f print_info &>/dev/null; then
    print_info() { echo "[INFO] $*"; }
    print_success() { echo "[SUCCESS] $*"; }
    print_error() { echo "[ERROR] $*"; }
    print_warning() { echo "[WARNING] $*"; }
fi

# ============================================================================
# GPG KEY GENERATION
# ============================================================================

# Generate GPG key for GitHub Actions bot from config file
# Usage: generate_bot_gpg_key [config_file]
# Args:
#   config_file: Path to YAML config (default: config/profiles/github_actions[bot]_gpg.yml)
# Returns:
#   0 on success, 1 on error
# Outputs:
#   GPG_KEY_ID environment variable set to the generated key ID
#   GPG_PASSPHRASE environment variable set to the passphrase
generate_bot_gpg_key() {
    local config_file="${1:-config/profiles/github_actions[bot]_gpg.yml}"
    
    if [[ ! -f "$config_file" ]]; then
        print_error "Config file not found: $config_file"
        return 1
    fi
    
    print_info "Reading GPG configuration from: $config_file"
    
    # Parse YAML config (simple approach - assumes clean YAML)
    local key_type key_length name_real name_email expire_date
    key_type=$(grep "^Key-Type:" "$config_file" | awk '{print $2}')
    key_length=$(grep "^Key-Length:" "$config_file" | awk '{print $2}')
    name_real=$(grep "^Name-Real:" "$config_file" | sed 's/^Name-Real: //')
    name_email=$(grep "^Name-Email:" "$config_file" | awk '{print $2}')
    expire_date=$(grep "^Expire-Date:" "$config_file" | awk '{print $2}')
    
    # Generate secure passphrase (in memory only, never saved to file)
    local passphrase
    passphrase=$(openssl rand -base64 32)
    
    # Check if GPG is available
    if ! command -v gpg &>/dev/null; then
        print_error "GPG is not installed. Install with: apt install gnupg"
        return 1
    fi
    
    # Check if we're in a container - GPG key generation often fails in containers
    if [[ -f /.dockerenv ]] || grep -q docker /proc/1/cgroup 2>/dev/null; then
        print_warning "Running in a container/devcontainer detected"
        print_warning "GPG key generation may fail due to agent restrictions"
        echo ""
        print_info "💡 Recommended: Run this command on your HOST machine instead:"
        echo ""
        echo "  cd $(pwd)"
        echo "  dc-gpg-setup"
        echo ""
        read -rp "Continue anyway? [y/N]: " continue_choice
        if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
            print_info "Cancelled. Please run on host machine."
            return 0
        fi
    fi
    
    print_info "Generating GPG key..."
    print_info "  Type: $key_type $key_length"
    print_info "  Name: $name_real"
    print_info "  Email: $name_email"
    print_info "  Expires: $expire_date"
    
    # Create temporary batch file (auto-deleted after use)
    local batch_file
    batch_file=$(mktemp)
    
    cat > "$batch_file" <<EOF
Key-Type: $key_type
Key-Length: $key_length
Name-Real: $name_real
Name-Email: $name_email
Expire-Date: $expire_date
Passphrase: $passphrase
%commit
EOF
    
    # Generate key with verbose error output
    print_info "Running GPG key generation (this may take a minute)..."
    if ! gpg --batch --gen-key "$batch_file" 2>&1 | tee /tmp/gpg-gen.log; then
        print_error "Failed to generate GPG key"
        print_error "GPG output:"
        cat /tmp/gpg-gen.log
        rm -f "$batch_file" /tmp/gpg-gen.log
        return 1
    fi
    
    # Clean up batch file immediately (passphrase was only in memory and this temp file)
    rm -f "$batch_file" /tmp/gpg-gen.log
    
    # Get the key ID
    local key_id
    key_id=$(gpg --list-keys --with-colons "$name_email" 2>/dev/null | grep '^fpr:' | head -1 | cut -d: -f10)
    
    if [[ -z "$key_id" ]]; then
        print_error "Failed to retrieve generated key ID"
        return 1
    fi
    
    print_success "GPG key generated successfully"
    
    # Export to environment for calling script
    export GPG_KEY_ID="$key_id"
    export GPG_PASSPHRASE="$passphrase"
    
    return 0
}

# Export GPG private key
# Usage: export_gpg_private_key <key_id> [output_file]
# Args:
#   key_id: GPG key ID or email
#   output_file: Optional file to write to (default: stdout)
export_gpg_private_key() {
    local key_id="$1"
    local output_file="${2:-}"
    
    if [[ -z "$key_id" ]]; then
        print_error "Key ID required"
        return 1
    fi
    
    if [[ -n "$output_file" ]]; then
        gpg --armor --export-secret-keys "$key_id" > "$output_file" 2>&1
        
        # Verify export succeeded (file should contain PGP PRIVATE KEY BLOCK)
        if [[ ! -s "$output_file" ]] || ! grep -q "BEGIN PGP PRIVATE KEY BLOCK" "$output_file"; then
            print_error "Failed to export private key for: $key_id"
            print_error "Key may not exist in keyring"
            rm -f "$output_file"
            return 1
        fi
        
        print_info "Private key exported to: $output_file"
    else
        gpg --armor --export-secret-keys "$key_id"
    fi
}

# ============================================================================
# GITHUB SECRETS MANAGEMENT
# ============================================================================

# Add GPG key and passphrase to GitHub repository secrets
# Usage: add_gpg_secrets_to_repo <key_id> <passphrase> [repo]
# Args:
#   key_id: GPG key ID
#   passphrase: GPG key passphrase
#   repo: Optional repo (default: current repo from git remote)
# Requires: gh CLI authenticated
add_gpg_secrets_to_repo() {
    local key_id="$1"
    local passphrase="$2"
    local repo="${3:-}"
    
    if [[ -z "$key_id" || -z "$passphrase" ]]; then
        print_error "Key ID and passphrase required"
        return 1
    fi
    
    # Check gh CLI is available
    if ! command -v gh &>/dev/null; then
        print_error "gh CLI not found. Install from: https://cli.github.com/"
        return 1
    fi
    
    # Check authentication
    if ! gh auth status &>/dev/null; then
        print_error "gh CLI not authenticated. Run: gh auth login"
        return 1
    fi
    
    # Determine repo
    if [[ -z "$repo" ]]; then
        repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
        if [[ -z "$repo" ]]; then
            print_error "Could not determine repository. Specify manually or run from repo directory"
            return 1
        fi
    fi
    
    print_info "Adding GPG secrets to repository: $repo"
    
    # Export private key to temp file
    local temp_key
    temp_key=$(mktemp)
    if ! export_gpg_private_key "$key_id" "$temp_key"; then
        rm -f "$temp_key"
        return 1
    fi
    
    # Add secrets using gh CLI
    print_info "Adding GPG_PRIVATE_KEY secret..."
    if ! gh secret set GPG_PRIVATE_KEY --repo "$repo" < "$temp_key"; then
        print_error "Failed to add GPG_PRIVATE_KEY secret"
        rm -f "$temp_key"
        return 1
    fi
    
    print_info "Adding GPG_PASSPHRASE secret..."
    if ! echo "$passphrase" | gh secret set GPG_PASSPHRASE --repo "$repo"; then
        print_error "Failed to add GPG_PASSPHRASE secret"
        rm -f "$temp_key"
        return 1
    fi
    
    # Cleanup
    rm -f "$temp_key"
    
    print_success "GPG secrets added to $repo"
    
    # Get actual secret sizes for verification
    local key_size passphrase_size
    key_size=$(gh secret list --repo "$repo" --json name,updatedAt | jq -r '.[] | select(.name=="GPG_PRIVATE_KEY") | .updatedAt' | wc -c)
    passphrase_size=${#passphrase}
    
    print_info "Secrets added:"
    print_info "  - GPG_PRIVATE_KEY (exported successfully)"
    print_info "  - GPG_PASSPHRASE ($passphrase_size chars)"
    
    return 0
}

# ============================================================================
# FULL AUTOMATION
# ============================================================================

# Complete workflow: Generate GPG key and add to GitHub repo
# Usage: setup_bot_gpg_for_repo [config_file] [repo]
# Args:
#   config_file: Path to GPG config YAML (optional)
#   repo: GitHub repo (optional, auto-detected from git remote)
setup_bot_gpg_for_repo() {
    local config_file="${1:-config/profiles/github_actions[bot]_gpg.yml}"
    local repo="${2:-}"
    
    print_info "🔐 Setting up GPG bot key for GitHub Actions"
    echo ""
    
    # Step 1: Generate key
    if ! generate_bot_gpg_key "$config_file"; then
        return 1
    fi
    
    echo ""
    print_info "Generated key ID: $GPG_KEY_ID"
    
    # Step 2: Confirm before adding to repo
    local repo_display="$repo"
    if [[ -z "$repo_display" ]]; then
        repo_display=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "current repo")
    fi
    
    echo ""
    print_warning "This will add the following secrets to $repo_display:"
    echo "  - GPG_PRIVATE_KEY (private key)"
    echo "  - GPG_PASSPHRASE (passphrase)"
    echo ""
    read -rp "Continue? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Cancelled. GPG key generated but not added to repo."
        return 0
    fi
    
    # Step 3: Add secrets
    if ! add_gpg_secrets_to_repo "$GPG_KEY_ID" "$GPG_PASSPHRASE" "$repo"; then
        return 1
    fi
    
    echo ""
    print_success "✅ GPG bot setup complete!"
    echo ""
    print_info "Next steps:"
    print_info "  1. Your release workflow will now sign tags automatically"
    print_info "  2. Run a release: gh workflow run release.yml -f version=X.Y.Z"
    print_info "  3. Tags will be signed with: github_actions[bot] <actions@github.com>"
    echo ""
    print_info "Key details:"
    print_info "  Expires: $(grep "^Expire-Date:" "$config_file" | awk '{print $2}')"
    print_info "  Location: ~/.gnupg/"
    echo ""
    
    return 0
}

# ============================================================================
# KEY LISTING
# ============================================================================

# List GPG keys for bot identities
# Usage: list_bot_gpg_keys
list_bot_gpg_keys() {
    print_info "GPG keys for bot identities:"
    echo ""
    gpg --list-keys --with-colons | grep -A 3 "github" || {
        print_warning "No bot keys found"
        return 1
    }
}
