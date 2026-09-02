#!/usr/bin/env bash
#
# Dev-Control: dc-key — unified GPG identity & repo-secret manager
# A sleek TUI (and flags) over the personal signing key, the machine/bot repo-secret
# refresh, and the user-token rotation. Shared logic lives in lib/gpg.sh; every secret
# name is resolved from the project's own config (repoVars.env), never hardcoded.
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# Exit immediately on errors, unassigned variables, or pipe failures
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${DEV_CONTROL_DIR:=$(cd "$LIB_DIR/../.." && pwd)}"
export DEV_CONTROL_DIR
source "$LIB_DIR/colours.sh" 2>/dev/null || true
source "$LIB_DIR/print.sh" 2>/dev/null || true
source "$LIB_DIR/tui.sh" 2>/dev/null || true
source "$LIB_DIR/gpg.sh"

DRY_RUN=false
FORCE=false

# Identity resolution — mirrors load_container_config in lib/container.sh
# Priority: container.yaml → git config → gh API
DC_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/dev-control/container.yaml"
EXPIRY="${EXPIRY:-1y}"

_yaml_get() { sed -n "s/^${1}:[[:space:]]*//p" "$2" 2>/dev/null | head -1 | tr -d "'\""; }

# Personal signing key: generate a modern Ed25519 key, enrol it to this GitHub
# account, configure git signing and cache the passphrase for zero-prompt commits.
keygen_user_flow() {
USERNAME=""
[[ -f "$DC_CONFIG" ]] && USERNAME=$(_yaml_get "github-user" "$DC_CONFIG")
[[ -z "$USERNAME" ]] && USERNAME=$(git config --get user.name 2>/dev/null || true)
[[ -z "$USERNAME" ]] && USERNAME=$(gh api user --jq '.login' 2>/dev/null || true)
[[ -z "$USERNAME" ]] && { echo "Error: cannot resolve GitHub username — set git config user.name or run gh auth login." >&2; exit 1; }

EMAIL=""
[[ -f "$DC_CONFIG" ]] && EMAIL=$(_yaml_get "github-user-email" "$DC_CONFIG")
[[ -z "$EMAIL" ]] && EMAIL=$(git config --get user.email 2>/dev/null || true)
if [[ -z "$EMAIL" ]]; then
    _gh_id=$(gh api user --jq '.id' 2>/dev/null || true)
    _gh_login=$(gh api user --jq '.login' 2>/dev/null || true)
    [[ -n "$_gh_id" && -n "$_gh_login" ]] && EMAIL="${_gh_id}+${_gh_login}@users.noreply.github.com"
fi
[[ -z "$EMAIL" ]] && { echo "Error: cannot resolve email — set git config user.email." >&2; exit 1; }

# Context detection — same logic as is_in_devcontainer() + gpg.sh container check
IN_CONTAINER=false
if [[ -f "/.dockerenv" ]] || [[ -n "${REMOTE_CONTAINERS:-}" ]] || [[ -n "${CODESPACES:-}" ]] \
        || grep -q 'docker\|lxc\|podman' /proc/1/cgroup 2>/dev/null; then
    IN_CONTAINER=true
fi

# Compute explicit expiration date string (e.g., "Exp: 2027-08-23")
EXP_DATE=$(date -d "+1 year" +"%Y-%m-%d")
KEY_COMMENT="GitHub Modern Signing Key ($USERNAME) [Exp: $EXP_DATE]"

echo "=== GPG Key Generation and GitHub Enrollment (DBUS FIXED) ==="

# 1. Dependency Validation (Strictly Core OS Utilities)
for cmd in gpg gh awk tr cut mktemp date gdbus printf; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required native dependency '$cmd' is missing." >&2
        exit 1
    fi
done

if ! gh auth status &> /dev/null; then
    echo "Error: You are not authenticated with 'gh'. Run 'gh auth login' first." >&2
    exit 1
fi

# 2. Nuclear Cleanup: Purge Entire Local Keyring Structure
if [[ -d "$HOME/.gnupg" ]]; then
    echo "Warning: Existing GPG keyring detected at $HOME/.gnupg."
    echo "  wipe   — delete keyring and continue (recommended for a clean key generation)"
    echo "  skip   — keep existing keyring and continue"
    echo "  cancel — exit now to back up or decide"
    read -rp "Choice [wipe/skip/cancel]: " _choice
    case "${_choice,,}" in
        wipe)
            echo "Executing nuclear purge of local GPG storage to prevent engine collisions..."
            gpgconf --kill gpg-agent &> /dev/null || true
            pkill -9 gpg-agent &> /dev/null || true
            rm -rf "$HOME/.gnupg"
            ;;
        skip)
            echo "Keeping existing keyring."
            ;;
        *)
            echo "Cancelled. No changes made." >&2
            exit 0
            ;;
    esac
fi

# Ensure .gnupg dir exists with correct permissions (covers wipe path and fresh install)
mkdir -p "$HOME/.gnupg"
chmod 700 "$HOME/.gnupg"

# 3. Fortify Environment Options & Enforce Strong Symmetric/Hashing Algorithms
echo "pinentry-mode loopback" > "$HOME/.gnupg/gpg.conf"
echo "allow-loopback-pinentry" > "$HOME/.gnupg/gpg-agent.conf"
echo "no-allow-external-cache" >> "$HOME/.gnupg/gpg-agent.conf"
cat <<EOF >> "$HOME/.gnupg/gpg.conf"
personal-cipher-preferences AES256
personal-digest-preferences SHA512
default-preference-list SHA512 AES256 ZIP Uncompressed
cert-digest-algo SHA512
s2k-digest-algo SHA512
s2k-cipher-algo AES256
EOF

gpg-connect-agent RELOADAGENT /bye &> /dev/null

# 4. Generate High-Entropy Passphrase
PASSPHRASE=$(LC_ALL=C tr -dc 'A-Za-z0-9!#%^&*()-_=+' < /dev/urandom | head -c 32 || true)

gpg_reveal_once "Generated passphrase (not saved to history)" "$PASSPHRASE"

# 5. Build Temporary Configuration Payload (ECC Formatting)
GPG_BATCH_CONF=$(mktemp)
chmod 600 "$GPG_BATCH_CONF"

cat <<EOF > "$GPG_BATCH_CONF"
Key-Type: EDDSA
Key-Curve: ed25519
Key-Usage: sign
Name-Real: $USERNAME
Name-Comment: $KEY_COMMENT
Name-Email: $EMAIL
Expire-Date: $EXPIRY
Passphrase: $PASSPHRASE
%commit
EOF

# 6. Generate and Export Cryptographic Key
echo "Generating modern sign-only Ed25519 GPG key..."
gpg --batch --pinentry-mode loopback --generate-key "$GPG_BATCH_CONF"
rm -f "$GPG_BATCH_CONF"

# Isolate the exact newly generated single Key fingerprint string
KEY_ID=$(gpg --list-secret-keys --keyid-format LONG "$EMAIL" 2>/dev/null | awk '/^sec/ {print $2}' | cut -d'/' -f2 | head -n 1) || true
if [ -z "$KEY_ID" ]; then
    echo "Error: Key generation completed but failed to parse Key ID from keyring." >&2
    exit 1
fi

# Extract the full long fingerprint string for the background caching engine
FINGERPRINT=$(gpg --with-colons --fingerprint "$EMAIL" 2>/dev/null | awk -F: '/^fpr/ {print $10}' | head -n 1)

PUB_KEY_FILE=$(mktemp)
chmod 600 "$PUB_KEY_FILE"
gpg --batch --pinentry-mode loopback --armor --export "$KEY_ID" > "$PUB_KEY_FILE"

echo "GPG Key generated successfully. Key ID: $(gpg_mask "$KEY_ID" 4)"

# 7. Upload directly to the GitHub Dashboard via native API
echo "Enrolling public key into your GitHub account..."
if ! gh api user/gpg_keys -f "title=Modern Ed25519 Signing Key ($KEY_ID)" -f "armored_public_key=$(cat "$PUB_KEY_FILE")" &> /dev/null; then
    echo "Error: Failed to upload GPG key via GitHub API. Confirm token has 'write:gpg_key' scopes." >&2
    rm -f "$PUB_KEY_FILE"
    exit 1
fi

echo "Success! GPG key has been securely linked to your GitHub account."
rm -f "$PUB_KEY_FILE"

# 8. Force Automatic Global Local Git Mapping
echo "Applying automated global Git signing parameters..."
git config --global user.signingkey "$KEY_ID"
git config --global commit.gpgsign true
git config --global user.email "$EMAIL"
git config --global user.name "$USERNAME"

# Write new key ID back to container.yaml so containerise.sh picks it up automatically
if [[ -f "$DC_CONFIG" ]]; then
    if grep -q "^gpg-key-id:" "$DC_CONFIG"; then
        sed -i "s/^gpg-key-id:.*/gpg-key-id: ${KEY_ID}/" "$DC_CONFIG"
    else
        printf '\ngpg-key-id: %s\n' "$KEY_ID" >> "$DC_CONFIG"
    fi
    echo "Updated $DC_CONFIG with gpg-key-id: $(gpg_mask "$KEY_ID" 4)"
fi

# Patch the signing key in all running dev-control containers (label-based, same as containerise.sh)
if [[ "$IN_CONTAINER" == "false" ]]; then
    _ctr=$(command -v podman 2>/dev/null || command -v docker 2>/dev/null || true)
    if [[ -n "$_ctr" ]]; then
        mapfile -t _ctrs < <("$_ctr" ps --filter "label=devcontainer.local_folder" -q 2>/dev/null | grep -v "^$" || true)
        if [[ ${#_ctrs[@]} -gt 0 ]]; then
            echo "Propagating signing key to ${#_ctrs[@]} running container(s)..."
            for _cid in "${_ctrs[@]}"; do
                _folder=$("$_ctr" inspect "$_cid" --format '{{index .Config.Labels "devcontainer.local_folder"}}' 2>/dev/null || echo "$_cid")
                "$_ctr" exec "$_cid" git config --global user.signingkey "$KEY_ID" 2>/dev/null || true
                echo "  → $(gpg_mask "$KEY_ID" 4) in ${_folder##*/}"
            done
        fi
    fi
fi

# Patch GPG_KEY_ID in static devcontainer configs across the nest (no dc-contain needed)
if [[ "$IN_CONTAINER" == "false" ]]; then
    _keygen_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _nest_json=""
    for _c in \
            "$(dirname "$DC_CONFIG")/nest.json" \
            "$_keygen_dir/../../config/containers/nest.json"; do
        [[ -f "$_c" ]] && { _nest_json="$_c"; break; }
    done

    if [[ -n "$_nest_json" ]]; then
        _start_dir=$(sed -n 's/.*"start_dir":[[:space:]]*"\([^"]*\)".*/\1/p' "$_nest_json" | head -1)
        echo "Patching devcontainer configs under $_start_dir (from $_nest_json)..."
        while IFS= read -r _p; do
            _dc="$_start_dir/$_p/.devcontainer"
            [[ -d "$_dc" ]] || continue
            if [[ -f "$_dc/devcontainer.json" ]]; then
                sed -i "s/\"GPG_KEY_ID\":[[:space:]]*\"[^\"]*\"/\"GPG_KEY_ID\": \"${KEY_ID}\"/g" \
                    "$_dc/devcontainer.json" && echo "  → $_p/devcontainer.json"
            fi
            if [[ -f "$_dc/Dockerfile" ]]; then
                sed -i "s/user\.signingkey \"[^\"]*\"/user.signingkey \"${KEY_ID}\"/g" \
                    "$_dc/Dockerfile" && echo "  → $_p/Dockerfile"
            fi
        done < <(sed -n 's/.*"path":[[:space:]]*"\([^"]*\)".*/\1/p' "$_nest_json")
    fi
fi

if [[ "$IN_CONTAINER" == "false" ]]; then
# 9. Automate Boot Unlocking (Fixed Native D-Bus GNOME Keyring Storage)
echo "Binding GPG passphrase securely to GNOME Keyring using native gdbus..."

# Fix: Explicitly wrap the empty second parameter inside a GLib Variant string structure <''>
DBUS_SESSION=$(gdbus call --session --dest org.freedesktop.secrets --object-path /org/freedesktop/secrets --method org.freedesktop.Secret.Service.OpenSession "plain" "<''>")
SESSION_PATH=$(echo "$DBUS_SESSION" | awk -F"'" '{print $4}')

# Format passphrase into a raw D-Bus compatible byte array payload safely using core builtins
BYTE_ARRAY=$(printf '%s' "$PASSPHRASE" | od -An -v -t u1 | awk 'BEGIN {ORS=""} {for(i=1;i<=NF;i++) printf "%s,", $i}')
BYTE_ARRAY="[${BYTE_ARRAY%,}]"

# Securely write the entry directly into the GNOME login collection path
gdbus call --session --dest org.freedesktop.secrets --object-path /org/freedesktop/secrets/collection/login --method org.freedesktop.Secret.Collection.CreateItem \
    "{'org.freedesktop.Secret.Item.Label': <'GPG Passphrase: $KEY_ID'>}" \
    "('$SESSION_PATH', [0x00], $BYTE_ARRAY, 'text/plain; charset=utf8')" \
    "{'gpg_fingerprint': <'$FINGERPRINT'>}" \
    true &>/dev/null || true
fi  # IN_CONTAINER guard

# Transition GPG configs back to normal background agent operation
sed -i '/pinentry-mode loopback/d' "$HOME/.gnupg/gpg.conf"
sed -i '/allow-loopback-pinentry/d' "$HOME/.gnupg/gpg-agent.conf"

cat <<EOF > "$HOME/.gnupg/gpg-agent.conf"
max-cache-ttl 60480000
default-cache-ttl 60480000
allow-preset-passphrase
EOF

if [[ "$IN_CONTAINER" == "false" ]]; then
    case "$(basename "${SHELL:-bash}")" in
        zsh)  SHELL_RC="$HOME/.zshrc" ;;
        fish) SHELL_RC="$HOME/.config/fish/config.fish" ;;
        *)    SHELL_RC="$HOME/.bashrc" ;;
    esac

    if ! grep -q "org.freedesktop.Secret.Service.SearchItems" "$SHELL_RC"; then
        cat << EOF >> "$SHELL_RC"

# Automated Background GPG Key Unlock Engine (Pure Native D-Bus)
if command -v gdbus &>/dev/null && command -v gpg-connect-agent &>/dev/null; then
    export GPG_TTY=\$(tty)
    G_FPR=\$(gpg --with-colons --fingerprint "$EMAIL" 2>/dev/null | awk -F: '/^fpr/ {print \$10}' | head -n 1) || ""
    if [ -n "\$G_FPR" ]; then
        SEARCH_RES=\$(gdbus call --session --dest org.freedesktop.secrets --object-path /org/freedesktop/secrets --method org.freedesktop.Secret.Service.SearchItems "{'gpg_fingerprint': <'\$G_FPR'>}" 2>/dev/null || echo "")
        ITEM_PATH=\$(echo "\$SEARCH_RES" | awk -F"'" '{print \$2}' || echo "")
        if [ -n "\$ITEM_PATH" ]; then
            SECRET_DATA=\$(gdbus call --session --dest org.freedesktop.secrets --object-path "\$ITEM_PATH" --method org.freedesktop.Secret.Item.GetSecret "/org/freedesktop/secrets/session/normal" 2>/dev/null || echo "")
            G_PASS=\$(echo "\$SECRET_DATA" | awk -F"[" '{print \$2}' | tr -d ' ]' | awk -F, '{for(i=1;i<=NF;i++) printf "\\\\%03o", \$i}')
            G_PASS=\$(printf "\$G_PASS")
            if [ -n "\$G_PASS" ]; then
                /usr/lib/gnupg/gpg-preset-passphrase --preset "\$G_FPR" <<< "\$G_PASS" &>/dev/null || \
                gpg-connect-agent "passwd \$G_FPR" /bye <<< "\$G_PASS" &>/dev/null
                unset G_PASS
            fi
        fi
    fi
fi
EOF
    fi
else
    echo "Container detected — passphrase caching and shell profile injection skipped; run on the host to set those up."
fi

gpgconf --kill gpg-agent &> /dev/null || true

unset PASSPHRASE
echo "Setup complete. GPG passphrase linked via native D-Bus channels. Ready for zero-prompt testing."
}

# ============================================================================
# dc-key HUB (TUI + flags)
# ============================================================================

dc_key_menu() {
    declare -f tui_set_theme &>/dev/null && tui_set_theme "${DC_THEME:-matrix}"
    declare -f check_gum &>/dev/null && check_gum || true
    while true; do
        declare -f tui_banner &>/dev/null && tui_banner "dc-key" "GPG identity & repo secrets"
        local choice
        choice=$(tui_choose "Select an action" \
            "Personal signing key (this GitHub account)" \
            "Refresh machine/bot repo secrets" \
            "Set / rotate user token (PAT)" \
            "Status" \
            "Quit") || true
        case "$choice" in
            Personal*) ( keygen_user_flow ) || true ;;
            Refresh*)  gpg_refresh_bot_secrets "$DRY_RUN" || true ;;
            Set*)      gpg_set_user_token "$DRY_RUN" || true ;;
            Status)    gpg_status || true ;;
            Quit|"")   break ;;
        esac
        echo ""
    done
}

show_help() {
    cat <<'EOF'
dc-key — unified GPG identity & repo-secret manager

USAGE:
  dc-key                 Interactive menu
  dc-key --user          Personal signing key: generate, enrol, cache
  dc-key --bot           Refresh machine/bot repo secrets (GPG private key + passphrase)
  dc-key --token         Set / rotate the user token (PAT) repo secret
  dc-key --status        Show key/secret status (read-only; values are never shown)
  dc-key --dry-run       Report actions without making changes
  dc-key --force         Override idempotency guards (rotate even if current)
  dc-key --help          This help

All secret names are resolved from config/profiles/repoVars.env; nothing is hardcoded.
EOF
}

main() {
    local action=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --user|user)         action="user" ;;
            --bot|--refresh|bot) action="bot" ;;
            --token|token)       action="token" ;;
            --status|status)     action="status" ;;
            --dry-run)           DRY_RUN=true ;;
            --force|--rotate)    FORCE=true ;;
            -h|--help|help)      show_help; exit 0 ;;
            *) print_warning "Unknown option: $1 (see --help)" ;;
        esac
        shift
    done
    case "$action" in
        user)   keygen_user_flow ;;
        bot)    gpg_refresh_bot_secrets "$DRY_RUN" ;;
        token)  gpg_set_user_token "$DRY_RUN" ;;
        status) gpg_status ;;
        *)      dc_key_menu ;;
    esac
}

main "$@"
