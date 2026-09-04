#!/usr/bin/env bash
#
# Dev-Control Shared Library: GPG identity & repo-secret management
#
# Unifies the personal signing key (see keygen.sh) and the machine/bot repo-secret refresh under one resolver. Every secret NAME is read from the project's own config (repoVars.env / container.yaml / git / gh) and never hardcoded here, so the same XB_* indirection the workflows use drives this flow untouched.
#
# Zero-trust: key material and passphrases are generated in an ephemeral keyring, streamed straight to gh, and never printed. Fingerprints are masked on display.
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# Dual-mode bootstrap. When executed directly, enable strict mode and pull in the shared colour/print/TUI libs; when sourced by a master (keygen.sh), the parent owns them.
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

# Populate the GPG-flow variables from the project's own configuration. Secret NAMES (e.g. GPG_PRIVATE_KEY_SECRET=XB_GK) are read verbatim from repoVars.env — never invented.
gpg_resolve_vars() {
    local repovars="$DEV_CONTROL_DIR/config/profiles/repoVars.env"
    if [[ -f "$repovars" ]]; then
        # shellcheck source=/dev/null
        source "$repovars"
    else
        print_warning "repoVars.env not found ($repovars) — falling back to git/gh for names"
    fi

    # Repository owner/name (org-wide standard first, then gh, then git remote). When org scope is set and REPO_OWNER is already known from repoVars, skip the gh repo view calls so dc key works from any directory without a git remote.
    if [[ -z "${REPO_SLUG:-}" ]]; then
        if [[ "${SECRET_SCOPE:-}" != "org" || -z "${REPO_OWNER:-}" ]]; then
            REPO_SLUG=$(gh repo view --json name --jq .name 2>/dev/null || true)
        fi
    fi
    if [[ -z "${REPO_OWNER:-}" ]]; then
        REPO_OWNER=$(gh repo view --json owner --jq .owner.login 2>/dev/null || true)
    fi
    REPO_NWO=""
    if [[ -n "${REPO_OWNER:-}" && -n "${REPO_SLUG:-}" ]]; then
        REPO_NWO="${REPO_OWNER}/${REPO_SLUG}"
    elif [[ "${SECRET_SCOPE:-}" != "org" ]]; then
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
    # Optional: actual PAT for the bot account with write:gpg_key scope. Used locally for sandboxed GPG key registration. Never a secret name — value only. Stays in gitignored repoVars.env.
    BOT_TOKEN="${BOT_TOKEN:-}"
    # Secret scope: "org" to write org-level secrets, "repo" for repo-level. Auto-defaults to "org" when REPO_OWNER is set.
    SECRET_SCOPE="${SECRET_SCOPE:-}"
    if [[ -z "$SECRET_SCOPE" && -n "${REPO_OWNER:-}" ]]; then
        SECRET_SCOPE="org"
    elif [[ -z "$SECRET_SCOPE" ]]; then
        SECRET_SCOPE="repo"
    fi
}

# Set a named secret at the correct scope (org or repo), reading the value from stdin. The NAME comes from repoVars, so nothing is hardcoded here.
_gpg_secret_set() {
    local name="$1"
    if [[ "${SECRET_SCOPE:-repo}" == "org" && -n "${REPO_OWNER:-}" ]]; then
        gh secret set "$name" --org "$REPO_OWNER"
    else
        gh secret set "$name" --repo "$REPO_NWO"
    fi
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
    done < <({ gpg --list-secret-keys --with-colons 2>/dev/null || true; } | awk -F: '
        $1=="sec"{ if(f!=""){print f"|"e"|"u}; e=$7; f=""; u="" }
        $1=="fpr" && f==""{ f=$10 }
        $1=="uid" && u==""{ u=$10 }
        END{ if(f!=""){print f"|"e"|"u} }')
    $found || echo "    (none)"

    if command -v gh &>/dev/null; then
        echo ""
        local _scope_label
        if [[ "${SECRET_SCOPE:-repo}" == "org" && -n "${REPO_OWNER:-}" ]]; then
            _scope_label="org ${REPO_OWNER} secrets (values are write-only, never readable):"
            if gh secret list --org "$REPO_OWNER" >/tmp/_dckey_secrets 2>/dev/null; then
                echo "  $_scope_label"
                sed 's/^/    /' /tmp/_dckey_secrets
            else
                echo "  $_scope_label"
                echo "    (unable to list — check gh auth / org admin access)"
            fi
        elif [[ -n "${REPO_NWO:-}" ]]; then
            _scope_label="repo ${REPO_NWO} secrets (values are write-only, never readable):"
            if gh secret list --repo "$REPO_NWO" >/tmp/_dckey_secrets 2>/dev/null; then
                echo "  $_scope_label"
                sed 's/^/    /' /tmp/_dckey_secrets
            else
                echo "  $_scope_label"
                echo "    (unable to list — check gh auth / repo access)"
            fi
        fi
        rm -f /tmp/_dckey_secrets
    fi
}

# ============================================================================
# BOT / MACHINE REPO-SECRET REFRESH
# ============================================================================

# Register a bot GPG public key to the bot's GitHub account using a sandboxed GH_TOKEN so the user's own gh auth is never touched. If BOT_TOKEN is not set in repoVars.env, the user is prompted once (masked, not stored) or can skip — the identity action handles registration automatically at next workflow run. Auto-skips when stdin is not a TTY (CI / non-interactive contexts).
gpg_register_bot_pubkey() {
    local gnupg_home="$1" fpr="$2"

    local pubkey key_id
    pubkey=$(GNUPGHOME="$gnupg_home" gpg --armor --export "$fpr" 2>/dev/null) || true
    [[ -n "$pubkey" ]] || { print_warning "Could not export public key — registration skipped"; return 0; }
    key_id=$(GNUPGHOME="$gnupg_home" gpg --list-secret-keys --keyid-format=long "$fpr" 2>/dev/null \
             | grep -oE '[0-9A-F]{16}' | head -1)

    local _tok="${BOT_TOKEN:-}"

    # If BOT_TOKEN looks like a secret NAME (e.g. XB_UT — all-caps/underscores, no ghp_ prefix)
    # rather than an actual PAT value, the primary path is to trigger keygen.yml on GitHub where
    # that secret is injected automatically. No local PAT needed; no local auth needed.
    if [[ -n "$_tok" && "$_tok" =~ ^[A-Z][A-Z0-9_]+$ ]]; then
        local _wf_ref _repo
        _repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "${REPO_NWO:-}")
        _wf_ref=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
        print_info "BOT_TOKEN=\"$_tok\" looks like an org secret name — triggering keygen.yml on GitHub where it is injected automatically."
        if gh workflow run keygen.yml --repo "$_repo" --ref "$_wf_ref" 2>/dev/null; then
            print_success "keygen.yml triggered on $_repo@$_wf_ref — the workflow will set secrets and register the pubkey."
            print_info "Monitor: gh run list --repo \"$_repo\" --workflow keygen.yml"
        else
            print_warning "Could not trigger keygen.yml (workflow may not exist or app token lacks actions:write). Falling through to local options."
            _tok=""  # clear so the chain falls through
        fi
        return 0
    fi

    if [[ -z "$_tok" ]]; then
        # Auto-skip in CI / non-interactive shells so bats and pipelines are unaffected.
        if [[ ! -t 0 ]] || ! { : >/dev/tty; } 2>/dev/null; then
            print_info "Non-interactive terminal — skipping bot GPG key registration. The identity action handles it at next workflow run."
            return 0
        fi
        echo ""
        print_info "BOT_TOKEN is not set. Three options to register the public key to the bot account:"
        printf '  1) Isolated bot account auth (browser/device — your own gh session is not touched)\n' >&2
        printf '  2) Enter a bot PAT once (masked, used once, not stored)\n' >&2
        printf '  3) Skip — the identity action registers the key at next workflow run\n\n' >&2
        local _n
        read -rp "  Choice [1/2/3, default 3]: " _n </dev/tty
        case "${_n:-3}" in
            1)
                local _tmp_ghcfg
                _tmp_ghcfg=$(mktemp -d)
                print_info "Opening isolated auth session for the bot account (your own gh session is NOT affected)..."
                print_info "Log in as the bot account. The config is discarded after this operation."
                if GH_CONFIG_DIR="$_tmp_ghcfg" gh auth login --hostname github.com 2>/dev/null; then
                    local _existing _result
                    _existing=$(GH_CONFIG_DIR="$_tmp_ghcfg" gh api /user/gpg_keys \
                        --jq ".[] | select(.key_id == \"$key_id\") | .id" 2>/dev/null || true)
                    if [[ "$_existing" =~ ^[0-9]+$ ]]; then
                        print_success "GPG key already registered to bot account (id: $_existing)"
                    else
                        _result=$(GH_CONFIG_DIR="$_tmp_ghcfg" gh api /user/gpg_keys --method POST \
                            -f armored_public_key="$pubkey" --jq '.id' 2>/dev/null) || _result=""
                        if [[ "$_result" =~ ^[0-9]+$ ]]; then
                            print_success "GPG key registered to bot account (id: $_result) — commits will show Verified"
                        else
                            print_warning "Registration returned: $_result"
                        fi
                    fi
                else
                    print_warning "Isolated auth failed — falling back to the identity action at next workflow run."
                fi
                rm -rf "$_tmp_ghcfg"
                return 0 ;;
            2)
                if declare -f tui_password &>/dev/null; then
                    _tok=$(tui_password "Bot PAT for ${BOT_NAME:-bot} account (masked, not stored)")
                else
                    read -rsp "  Bot PAT (hidden): " _tok </dev/tty; echo "" >&2
                fi ;;
            *)
                print_info "Skipped — the identity action will register the key at next workflow run."
                return 0 ;;
        esac
    fi
    [[ -n "$_tok" ]] || { print_info "No token supplied — registration skipped."; return 0; }

    # One sandboxed call per the bot's token; the user's gh session state is untouched.
    local existing
    existing=$(GH_TOKEN="$_tok" gh api /user/gpg_keys \
        --jq ".[] | select(.key_id == \"$key_id\") | .id" 2>/dev/null || true)
    if [[ "$existing" =~ ^[0-9]+$ ]]; then
        print_success "GPG key already registered to bot account (id: $existing)"
        unset _tok; return 0
    fi
    local result
    result=$(GH_TOKEN="$_tok" gh api /user/gpg_keys --method POST \
        -f armored_public_key="$pubkey" --jq '.id' 2>/dev/null) || result=""
    unset _tok
    if [[ "$result" =~ ^[0-9]+$ ]]; then
        print_success "GPG key registered to bot account (id: $result) — commits will show Verified"
    else
        print_warning "Registration did not return a key id — the identity action will retry at next workflow run"
    fi
}

# Read Key-Type/Length/Expire from a bot profile (identity is ignored — it comes from repoVars BOT_NAME/BOT_EMAIL so the UID matches the committer and verifies).
_gpg_profile_field() {
    local field="$1" profile="$2" default="$3" val
    val=$(sed -n "s/^${field}:[[:space:]]*//p" "$profile" 2>/dev/null | head -1)
    printf '%s' "${val:-$default}"
}

# Generate a fresh machine/bot key and push it to the repo secrets named by GPG_PRIVATE_KEY_SECRET / GPG_PASSPHRASE_SECRET. Everything is ephemeral and masked. The workflow identity action re-registers the public key on the bot account next run.
gpg_refresh_bot_secrets() {
    local dry_run="${1:-false}"
    gpg_resolve_vars

    command -v gpg &>/dev/null     || { print_error "gpg is not installed"; return 1; }
    command -v gh &>/dev/null      || { print_error "gh CLI is not installed"; return 1; }
    command -v openssl &>/dev/null || { print_error "openssl is not installed"; return 1; }
    if ! gh auth status &>/dev/null; then print_error "gh is not authenticated (run: gh auth login)"; return 1; fi
    # For org scope, only REPO_OWNER is needed; REPO_NWO is not used for secret writes.
    if [[ "${SECRET_SCOPE:-repo}" == "org" ]]; then
        [[ -n "${REPO_OWNER:-}" ]] || { print_error "Could not resolve REPO_OWNER — set it in repoVars.env"; return 1; }
        [[ -z "$REPO_NWO" ]] && REPO_NWO="$REPO_OWNER"
    else
        [[ -n "$REPO_NWO" ]] || { print_error "Could not resolve the repository (owner/name)"; return 1; }
    fi
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
    print_info "Secret scope:   ${SECRET_SCOPE} (${REPO_OWNER:-$REPO_NWO})"
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
    _gpg_secret_set "$GPG_PRIVATE_KEY_SECRET" < "$keyfile"       || set_ok=false
    printf '%s' "$passphrase" | _gpg_secret_set "$GPG_PASSPHRASE_SECRET" || set_ok=false

    # Key file is no longer needed; shred it before any further network calls.
    shred -u "$keyfile" 2>/dev/null || rm -f "$keyfile"
    unset passphrase

    if [[ "$set_ok" != "true" ]]; then
        rm -rf "$gnupg_home"
        print_error "One or more secrets failed to set — check gh permissions (${SECRET_SCOPE}:${REPO_OWNER:-$REPO_NWO})"
        return 1
    fi
    print_success "Refreshed $GPG_PRIVATE_KEY_SECRET + $GPG_PASSPHRASE_SECRET (${SECRET_SCOPE}:${REPO_OWNER:-$REPO_NWO}) — fingerprint $(gpg_mask "$fpr" 6)"

    # Register the new public key to the bot account before discarding the ephemeral keyring.
    gpg_register_bot_pubkey "$gnupg_home" "$fpr"
    rm -rf "$gnupg_home"
}

# ============================================================================
# USER TOKEN (PAT) SET / ROTATE
# ============================================================================

# Store a classic PAT (write:gpg_key scope) in the repo secret named by USER_TOKEN_SECRET. The token is read masked and streamed to gh; it is never echoed or stored locally.
gpg_set_user_token() {
    local dry_run="${1:-false}"
    gpg_resolve_vars

    command -v gh &>/dev/null || { print_error "gh CLI is not installed"; return 1; }
    if ! gh auth status &>/dev/null; then print_error "gh is not authenticated (run: gh auth login)"; return 1; fi
    # For org scope, only REPO_OWNER is needed; REPO_NWO is not used for secret writes.
    if [[ "${SECRET_SCOPE:-repo}" == "org" ]]; then
        [[ -n "${REPO_OWNER:-}" ]] || { print_error "Could not resolve REPO_OWNER — set it in repoVars.env"; return 1; }
        [[ -z "$REPO_NWO" ]] && REPO_NWO="$REPO_OWNER"
    else
        [[ -n "$REPO_NWO" ]] || { print_error "Could not resolve the repository (owner/name)"; return 1; }
    fi
    [[ -n "$USER_TOKEN_SECRET" ]] || { print_error "USER_TOKEN_SECRET unresolved — set it in repoVars.env"; return 1; }

    print_info "Target secret: $USER_TOKEN_SECRET (${SECRET_SCOPE}:${REPO_OWNER:-$REPO_NWO})"
    print_info "Provide a classic PAT for the bot account with 'write:gpg_key' scope (input is masked)."

    if [[ "$dry_run" == "true" ]]; then
        print_info "[dry-run] Would set $USER_TOKEN_SECRET (${SECRET_SCOPE}:${REPO_OWNER:-$REPO_NWO}) (no changes made)"
        return 0
    fi

    local token
    if declare -f tui_password &>/dev/null; then
        token=$(tui_password "Paste PAT (hidden)")
    else
        read -rsp "Paste PAT (hidden): " token; echo ""
    fi
    [[ -n "$token" ]] || { print_warning "No token entered — aborting"; return 1; }

    if printf '%s' "$token" | _gpg_secret_set "$USER_TOKEN_SECRET"; then
        unset token
        print_success "Set $USER_TOKEN_SECRET (${SECRET_SCOPE}:${REPO_OWNER:-$REPO_NWO})"
    else
        unset token
        print_error "Failed to set $USER_TOKEN_SECRET — check gh permissions (${SECRET_SCOPE}:${REPO_OWNER:-$REPO_NWO})"
        return 1
    fi
}
