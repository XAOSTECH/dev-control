#!/usr/bin/env bash
#
# Dev-Control Shared Library: GPG identity & repo-secret management
#
# Unifies the personal signing key (see keygen.sh) and the machine/bot repo-secret
# refresh under one resolver. Every secret NAME is read from the project's own
# config (repoVars.env / container.yaml / git / gh) and never hardcoded here, so the
# same XB_* indirection the workflows use drives this flow untouched.
#
# Zero-trust: key material and passphrases are generated in an ephemeral keyring,
# streamed straight to gh, and never printed. Fingerprints are masked on display.
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# Dual-mode bootstrap. When executed directly, enable strict mode and pull in the
# shared colour/print/TUI libs; when sourced by a master (keygen.sh), the parent owns them.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    _GPG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    DEV_CONTROL_DIR="$(cd "$_GPG_LIB_DIR/../.." && pwd)"
    export DEV_CONTROL_DIR
    source "$_GPG_LIB_DIR/colours.sh" 2>/dev/null || true
    source "$_GPG_LIB_DIR/print.sh" 2>/dev/null || true
    source "$_GPG_LIB_DIR/tui.sh" 2>/dev/null || true
fi

_GPG_LIB_DIR="${_GPG_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
: "${DEV_CONTROL_DIR:=$(cd "$_GPG_LIB_DIR/../.." && pwd)}"

# Minimal print fallbacks when sourced without the print lib.
if ! declare -f print_info &>/dev/null; then
    print_info()    { echo "[INFO] $*"; }
    print_success() { echo "[OK] $*"; }
    print_warning() { echo "[WARN] $*" >&2; }
    print_error()   { echo "[ERROR] $*" >&2; }
fi

# ============================================================================
# OBFUSCATION HELPERS (zero-trust: nothing sensitive appears in the clear)
# ============================================================================

# Mask a fingerprint/token for display: keep the head and tail, asterisk the middle.
gpg_mask() {
    local s="${1:-}" keep="${2:-4}" n
    n=${#s}
    if (( n == 0 )); then
        printf '********'
    elif (( n <= keep * 2 )); then
        printf '%*s' "$n" '' | tr ' ' '*'
    else
        printf '%s%s%s' "${s:0:keep}" "$(printf '%*s' $((n - keep * 2)) '' | tr ' ' '*')" "${s: -keep}"
    fi
}

# Reveal a value once on a cleared screen for the user to copy, then wipe the screen.
# Used only when the user genuinely must copy a value; the bot flow never calls this.
gpg_reveal_once() {
    local label="$1" value="$2"
    echo ""
    echo "=================================================================="
    echo "  ${label} — shown once, not stored, not logged"
    echo "=================================================================="
    printf '  %s\n' "$value"
    echo "=================================================================="
    printf 'Copy it now, then press [Enter] to clear the screen...'
    read -r _ < /dev/tty || true
    clear 2>/dev/null || printf '\033c'
}

# ============================================================================
# VARIABLE RESOLUTION (repoVars.env -> container.yaml -> git -> gh)
# ============================================================================

# Populate the GPG-flow variables from the project's own configuration. Secret NAMES
# (e.g. GPG_PRIVATE_KEY_SECRET=XB_GK) are read verbatim from repoVars.env — never invented.
gpg_resolve_vars() {
    local repovars="$DEV_CONTROL_DIR/config/profiles/repoVars.env"
    if [[ -f "$repovars" ]]; then
        # shellcheck source=/dev/null
        source "$repovars"
    else
        print_warning "repoVars.env not found ($repovars) — falling back to git/gh for names"
    fi

    # Repository owner/name (org-wide standard first, then gh, then git remote).
    if [[ -z "${REPO_SLUG:-}" ]]; then
        REPO_SLUG=$(gh repo view --json name --jq .name 2>/dev/null || true)
    fi
    if [[ -z "${REPO_OWNER:-}" ]]; then
        REPO_OWNER=$(gh repo view --json owner --jq .owner.login 2>/dev/null || true)
    fi
    REPO_NWO=""
    if [[ -n "${REPO_OWNER:-}" && -n "${REPO_SLUG:-}" ]]; then
        REPO_NWO="${REPO_OWNER}/${REPO_SLUG}"
    else
        REPO_NWO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
    fi

    # Personal identity (for the user signing key) from container.yaml -> git -> gh.
    local dc_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/dev-control/container.yaml"
    USER_NAME="${USER_NAME:-}"
    USER_EMAIL="${USER_EMAIL:-}"
    if [[ -f "$dc_cfg" ]]; then
        [[ -z "$USER_NAME" ]]  && USER_NAME=$(sed -n 's/^github-user:[[:space:]]*//p' "$dc_cfg" | head -1 | tr -d "'\"")
        [[ -z "$USER_EMAIL" ]] && USER_EMAIL=$(sed -n 's/^github-user-email:[[:space:]]*//p' "$dc_cfg" | head -1 | tr -d "'\"")
    fi
    [[ -z "$USER_NAME" ]]  && USER_NAME=$(git config --get user.name 2>/dev/null || true)
    [[ -z "$USER_EMAIL" ]] && USER_EMAIL=$(git config --get user.email 2>/dev/null || true)

    # Bot identity and secret names come from repoVars (already sourced); leave as-is.
    BOT_NAME="${BOT_NAME:-}"
    BOT_EMAIL="${BOT_EMAIL:-}"
    GPG_PRIVATE_KEY_SECRET="${GPG_PRIVATE_KEY_SECRET:-}"
    GPG_PASSPHRASE_SECRET="${GPG_PASSPHRASE_SECRET:-}"
    USER_TOKEN_SECRET="${USER_TOKEN_SECRET:-}"
}

# ============================================================================
# STATUS (read-only, idempotent)
# ============================================================================

gpg_status() {
    gpg_resolve_vars
    echo ""
    if declare -f tui_echo &>/dev/null; then tui_echo "dc-key status" "primary"; else echo "== dc-key status =="; fi
    echo "  Repository:    ${REPO_NWO:-<unresolved>}"
    echo "  Bot identity:  ${BOT_NAME:-<unset>} <${BOT_EMAIL:-<unset>}>"
    echo "  Personal id:   ${USER_NAME:-<unset>} <${USER_EMAIL:-<unset>}>"
    echo "  Secret names:  ${GPG_PRIVATE_KEY_SECRET:-<unset>} / ${GPG_PASSPHRASE_SECRET:-<unset>} / ${USER_TOKEN_SECRET:-<unset>}"
    echo ""
    echo "  Local secret keys (fingerprints masked):"
    local found=false fpr exp uid expd
    while IFS='|' read -r fpr exp uid; do
        [[ -z "$fpr" ]] && continue
        found=true
        expd="never"
        [[ -n "$exp" && "$exp" != "0" ]] && expd=$(date -u -d "@$exp" +%Y-%m-%d 2>/dev/null || echo "$exp")
        echo "    - $(gpg_mask "$fpr" 6)  expires: ${expd}  uid: ${uid:-?}"
    done < <(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '
        $1=="sec"{ if(f!=""){print f"|"e"|"u}; e=$7; f=""; u="" }
        $1=="fpr" && f==""{ f=$10 }
        $1=="uid" && u==""{ u=$10 }
        END{ if(f!=""){print f"|"e"|"u} }')
    $found || echo "    (none)"

    if command -v gh &>/dev/null && [[ -n "$REPO_NWO" ]]; then
        echo ""
        echo "  Repo secret metadata (values are write-only, never readable):"
        if gh secret list --repo "$REPO_NWO" >/tmp/_dckey_secrets 2>/dev/null; then
            sed 's/^/    /' /tmp/_dckey_secrets
        else
            echo "    (unable to list — check gh auth / repo access)"
        fi
        rm -f /tmp/_dckey_secrets
    fi
}

# ============================================================================
# BOT / MACHINE REPO-SECRET REFRESH
# ============================================================================

# Read Key-Type/Length/Expire from a bot profile (identity is ignored — it comes
# from repoVars BOT_NAME/BOT_EMAIL so the UID matches the committer and verifies).
_gpg_profile_field() {
    local field="$1" profile="$2" default="$3" val
    val=$(sed -n "s/^${field}:[[:space:]]*//p" "$profile" 2>/dev/null | head -1)
    printf '%s' "${val:-$default}"
}

# Generate a fresh machine/bot key and push it to the repo secrets named by
# GPG_PRIVATE_KEY_SECRET / GPG_PASSPHRASE_SECRET. Everything is ephemeral and masked.
# The workflow identity action re-registers the public key on the bot account next run.
gpg_refresh_bot_secrets() {
    local dry_run="${1:-false}"
    gpg_resolve_vars

    command -v gpg &>/dev/null     || { print_error "gpg is not installed"; return 1; }
    command -v gh &>/dev/null      || { print_error "gh CLI is not installed"; return 1; }
    command -v openssl &>/dev/null || { print_error "openssl is not installed"; return 1; }
    if ! gh auth status &>/dev/null; then print_error "gh is not authenticated (run: gh auth login)"; return 1; fi
    [[ -n "$REPO_NWO" ]] || { print_error "Could not resolve the repository (owner/name)"; return 1; }
    if [[ -z "$GPG_PRIVATE_KEY_SECRET" || -z "$GPG_PASSPHRASE_SECRET" ]]; then
        print_error "Secret names unresolved — set GPG_PRIVATE_KEY_SECRET / GPG_PASSPHRASE_SECRET in repoVars.env"
        return 1
    fi
    if [[ -z "$BOT_NAME" || -z "$BOT_EMAIL" ]]; then
        print_error "Bot identity unresolved — set BOT_NAME / BOT_EMAIL in repoVars.env"
        return 1
    fi

    local profile="$DEV_CONTROL_DIR/config/profiles/xaos-bot[bot]_gpg.yml"
    [[ -f "$profile" ]] || profile="$DEV_CONTROL_DIR/config/profiles/github_actions[bot]_gpg.yml"
    local key_type key_length expire
    key_type=$(_gpg_profile_field "Key-Type" "$profile" "RSA")
    key_length=$(_gpg_profile_field "Key-Length" "$profile" "4096")
    expire=$(_gpg_profile_field "Expire-Date" "$profile" "1y")

    print_info "Repository:     $REPO_NWO"
    print_info "Bot identity:   $BOT_NAME <$BOT_EMAIL>"
    print_info "Key algorithm:  ${key_type}/${key_length} (expires ${expire})"
    print_info "Target secrets: $GPG_PRIVATE_KEY_SECRET, $GPG_PASSPHRASE_SECRET"

    if [[ "$dry_run" == "true" ]]; then
        print_info "[dry-run] Would generate the key and set both secrets on $REPO_NWO (no changes made)"
        print_info "[dry-run] The identity action re-registers the public key on the bot account at next run"
        return 0
    fi

    local ok=false
    if declare -f tui_confirm &>/dev/null; then
        tui_confirm "Generate a new ${key_type}/${key_length} bot key and overwrite ${GPG_PRIVATE_KEY_SECRET}/${GPG_PASSPHRASE_SECRET} on ${REPO_NWO}?" "no" && ok=true
    else
        local c; read -rp "Proceed? [y/N]: " c; [[ "$c" =~ ^[Yy] ]] && ok=true
    fi
    [[ "$ok" == "true" ]] || { print_info "Cancelled — no changes made"; return 0; }

    # Isolated ephemeral keyring so the user's own keyring is never touched.
    local gnupg_home batch keyfile passphrase fpr
    gnupg_home=$(mktemp -d); chmod 700 "$gnupg_home"
    passphrase=$(openssl rand -base64 32)
    batch=$(mktemp); chmod 600 "$batch"
    cat > "$batch" <<EOF
Key-Type: $key_type
Key-Length: $key_length
Name-Real: $BOT_NAME
Name-Email: $BOT_EMAIL
Expire-Date: $expire
Passphrase: $passphrase
%commit
EOF
    if ! GNUPGHOME="$gnupg_home" gpg --batch --pinentry-mode loopback --gen-key "$batch" 2>/dev/null; then
        rm -f "$batch"; rm -rf "$gnupg_home"; unset passphrase
        print_error "Key generation failed (GPG). In a container, try again on the host."
        return 1
    fi
    rm -f "$batch"

    fpr=$(GNUPGHOME="$gnupg_home" gpg --batch --with-colons --list-secret-keys 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')
    if [[ -z "$fpr" ]]; then
        rm -rf "$gnupg_home"; unset passphrase
        print_error "Could not read the generated key fingerprint"
        return 1
    fi

    keyfile=$(mktemp); chmod 600 "$keyfile"
    GNUPGHOME="$gnupg_home" gpg --batch --pinentry-mode loopback --passphrase "$passphrase" \
        --armor --export-secret-keys "$fpr" > "$keyfile" 2>/dev/null

    local set_ok=true
    gh secret set "$GPG_PRIVATE_KEY_SECRET" --repo "$REPO_NWO" < "$keyfile"       || set_ok=false
    printf '%s' "$passphrase" | gh secret set "$GPG_PASSPHRASE_SECRET" --repo "$REPO_NWO" || set_ok=false

    # Shred/wipe every trace of the key material.
    shred -u "$keyfile" 2>/dev/null || rm -f "$keyfile"
    rm -rf "$gnupg_home"
    unset passphrase

    if [[ "$set_ok" != "true" ]]; then
        print_error "One or more secrets failed to set — check gh permissions on $REPO_NWO"
        return 1
    fi
    print_success "Refreshed $GPG_PRIVATE_KEY_SECRET + $GPG_PASSPHRASE_SECRET on $REPO_NWO (fingerprint $(gpg_mask "$fpr" 6))"
    print_info "The identity action will register the new public key on the bot account at the next workflow run."
}

# ============================================================================
# USER TOKEN (PAT) SET / ROTATE
# ============================================================================

# Store a classic PAT (write:gpg_key scope) in the repo secret named by USER_TOKEN_SECRET.
# The token is read masked and streamed to gh; it is never echoed or stored locally.
gpg_set_user_token() {
    local dry_run="${1:-false}"
    gpg_resolve_vars

    command -v gh &>/dev/null || { print_error "gh CLI is not installed"; return 1; }
    if ! gh auth status &>/dev/null; then print_error "gh is not authenticated (run: gh auth login)"; return 1; fi
    [[ -n "$REPO_NWO" ]] || { print_error "Could not resolve the repository (owner/name)"; return 1; }
    [[ -n "$USER_TOKEN_SECRET" ]] || { print_error "USER_TOKEN_SECRET unresolved — set it in repoVars.env"; return 1; }

    print_info "Target secret: $USER_TOKEN_SECRET on $REPO_NWO"
    print_info "Provide a classic PAT for the bot account with 'write:gpg_key' scope (input is masked)."

    if [[ "$dry_run" == "true" ]]; then
        print_info "[dry-run] Would set $USER_TOKEN_SECRET on $REPO_NWO (no changes made)"
        return 0
    fi

    local token
    if declare -f tui_password &>/dev/null; then
        token=$(tui_password "Paste PAT (hidden)")
    else
        read -rsp "Paste PAT (hidden): " token; echo ""
    fi
    [[ -n "$token" ]] || { print_warning "No token entered — aborting"; return 1; }

    if printf '%s' "$token" | gh secret set "$USER_TOKEN_SECRET" --repo "$REPO_NWO"; then
        unset token
        print_success "Set $USER_TOKEN_SECRET on $REPO_NWO"
    else
        unset token
        print_error "Failed to set $USER_TOKEN_SECRET — check gh permissions on $REPO_NWO"
        return 1
    fi
}
