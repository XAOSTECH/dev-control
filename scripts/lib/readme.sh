#!/usr/bin/env bash
#
# Dev-Control README generation library
# Sourced by template-loading.sh to populate README/docs templates.
#
# Placeholders are discovered dynamically from the template ({{TOKEN}}), so a user can extend a template with new tokens and they are picked up without any code change. Each token resolves, in order, from a same-named variable already collected upstream, a git-config cache, an interactive prompt (skipped with
# --defaults), or empty. The result carries no leftover literal placeholders.
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# List the unique {{TOKEN}} placeholder names found in a file.
readme_extract_placeholders() {
    local file="$1"
    grep -oE '\{\{[A-Z0-9_]+\}\}' "$file" 2>/dev/null | sed 's/^{{//; s/}}$//' | sort -u
}

# Map a token to its git-config cache key: WHY_PROJECT -> dc-init.why-project
_readme_cfg_key() {
    local lower="${1,,}"
    echo "dc-init.${lower//_/-}"
}

# Turn a token into a human prompt label: WHY_PROJECT -> "Why project"
_readme_label() {
    local words="${1//_/ }"
    words="${words,,}"
    echo "${words^}"
}

# Resolve one placeholder into the variable named by $2.
# A token whose same-named variable is already declared (e.g. set by collect_project_info) is used as-is and never re-prompted; only genuinely new tokens fall through to cache, prompt or empty.
readme_resolve_placeholder() {
    local token="$1" __outvar="$2"
    if declare -p "$token" &>/dev/null; then
        printf -v "$__outvar" '%s' "${!token}"
        return
    fi
    local val=""
    if [[ -d .git ]]; then
        val="$(git config --local "$(_readme_cfg_key "$token")" 2>/dev/null || true)"
    fi
    if [[ -z "$val" && "${DEFAULTS_ONLY:-false}" != "true" && -t 0 ]]; then
        local input
        read -rp "  $(_readme_label "$token"): " input || input=""
        if [[ -n "$input" ]]; then
            val="$input"
            [[ -d .git ]] && git config --local "$(_readme_cfg_key "$token")" "$input" 2>/dev/null || true
        fi
    fi
    printf -v "$__outvar" '%s' "$val"
}

# Populate a template into a destination, resolving every discovered placeholder.
readme_apply() {
    local template="$1" dest="$2"
    if [[ ! -f "$template" ]]; then
        print_warning "Template not found: $template"
        return 1
    fi
    mkdir -p "$(dirname "$dest")"

    # Derive the licence badge token so {{LICENSE_TYPE_BADGE}} resolves to a static shields badge (a literal '-' must be doubled, e.g. GPL-3.0 -> GPL--3.0).
    LICENSE_TYPE_BADGE="${LICENCE_TYPE:-${LICENSE_TYPE:-unknown}}"
    LICENSE_TYPE_BADGE="${LICENSE_TYPE_BADGE//-/--}"

    local sed_args=() token value esc
    while IFS= read -r token; do
        [[ -z "$token" ]] && continue
        readme_resolve_placeholder "$token" value
        esc="${value//&/\\&}"
        esc="${esc//|/\\|}"
        sed_args+=(-e "s|{{${token}}}|${esc}|g")
    done < <(readme_extract_placeholders "$template")

    if [[ ${#sed_args[@]} -gt 0 ]]; then
        sed "${sed_args[@]}" "$template" >"$dest"
    else
        cp "$template" "$dest"
    fi
    print_success "Created: $dest"
}

# Install every docs-templates/*.md into <target>/docs/ with placeholders resolved.
readme_install_docs() {
    local target_dir="$1"
    local docs_dir="$DEV_CONTROL_DIR/docs-templates"

    print_info "Installing documentation templates to docs/..."
    mkdir -p "$target_dir/docs"

    local file
    for file in "$docs_dir"/*.md; do
        [[ -f "$file" ]] && readme_apply "$file" "$target_dir/docs/$(basename "$file")"
    done
}

# Replace the first <p align="center">…</p> block after the H1 with the current repo's standard badge row. Removes duplicate badge blocks (old-format or double-inserted).
readme_insert_badges() {
    local readme_path="$1"
    local tmp
    tmp=$(mktemp)

    # Static known-licence shield; '-' must be doubled for shields.io badge/ endpoint.
    local _lic_badge="${LICENCE_TYPE:-${LICENSE_TYPE:-unknown}}"
    _lic_badge="${_lic_badge//-/--}"

    local badges
    badges=$(
        cat <<'EOF'
<p align="center">
  <a href="{{REPO_URL}}"><img alt="GitHub repo" src="https://img.shields.io/badge/GitHub-{{ORG_NAME}}%2F{{REPO_SLUG}}-181717?style=for-the-badge&logo=github"></a>
  <a href="{{REPO_URL}}/releases"><img alt="GitHub release" src="https://img.shields.io/github/v/release/{{ORG_NAME}}/{{REPO_SLUG}}?style=for-the-badge&logo=semantic-release&color=blue"></a>
  <a href="{{REPO_URL}}/blob/main/LICENSE"><img alt="Licence" src="https://img.shields.io/badge/licence-{{LICENSE_TYPE_BADGE}}-green?style=for-the-badge"></a>
</p>
EOF
    )
    badges="${badges//\{\{REPO_URL\}\}/$REPO_URL}"
    badges="${badges//\{\{ORG_NAME\}\}/$ORG_NAME}"
    badges="${badges//\{\{REPO_SLUG\}\}/$REPO_SLUG}"
    badges="${badges//\{\{LICENSE_TYPE_BADGE\}\}/$_lic_badge}"

    if [[ ! -f "$readme_path" ]]; then
        mkdir -p "$(dirname "$readme_path")"
        if [[ -f "$DEV_CONTROL_DIR/docs-templates/README.md" ]]; then
            readme_apply "$DEV_CONTROL_DIR/docs-templates/README.md" "$readme_path"
        else
            echo -e "# $PROJECT_NAME\n" >"$readme_path"
        fi
    fi

    # State machine phases:
    #   pre_h1            – emit everything until H1; on H1 emit badge block then enter after_h1
    #   after_h1          – skip blanks/comments; on first <p> enter checking_first_p; on other content → rest
    #   checking_first_p  – buffer the first <p>…</p>; keep it if NOT the badge block, drop if badge
    #   post_first_p      – buffer blanks; check each subsequent <p> for duplicate badge content
    #   checking_p        – buffer subsequent <p>…</p>; keep if not badge, drop if duplicate badge
    #   rest              – print everything unchanged
    # ENVIRON["BADGE"] passes the multi-line badge string safely across the shell→awk boundary.
    BADGE="$badges" awk '
    BEGIN {
        new_b = ENVIRON["BADGE"]
        phase="pre_h1"; pending=""; checking_first_p=0; checking_p=0; is_badge_p=0; p_buf=""; skip_one_blank=0
    }
    # First <p> after H1: read it fully, keep it only if it is NOT the badge block.
    checking_first_p==1 {
        p_buf = p_buf $0 "\n"
        if (/"GitHub repo"/) is_badge_p=1
        if (/<\/p>/) {
            checking_first_p=0
            if (!is_badge_p) printf "%s", p_buf
            else skip_one_blank=1
            p_buf=""; is_badge_p=0; phase="post_first_p"
        }
        next
    }
    # Subsequent <p> blocks: keep unless they are a duplicate badge block.
    checking_p==1 {
        p_buf = p_buf $0 "\n"
        if (/"GitHub repo"/) is_badge_p=1
        if (/<\/p>/) {
            checking_p=0
            if (!is_badge_p) { printf "%s", pending; printf "%s", p_buf }
            pending=""; p_buf=""; is_badge_p=0
        }
        next
    }
    phase=="pre_h1" {
        if (/^#[[:space:]]/) { print; print ""; print new_b; print ""; phase="after_h1" }
        else print
        next
    }
    phase=="after_h1" {
        if (/^---$/ || /^##[[:space:]]/) { phase="rest"; print; next }
        if (/^[[:space:]]*$/ || /^<!--/) { next }
        if (/^<p /) {
            p_buf = $0 "\n"; is_badge_p = 0
            if (/"GitHub repo"/) is_badge_p = 1
            if (/<\/p>/) {
                if (!is_badge_p) printf "%s", p_buf
                else skip_one_blank=1
                p_buf = ""; is_badge_p = 0; phase = "post_first_p"
            } else {
                checking_first_p = 1
            }
            next
        }
        phase="rest"; print; next
    }
    phase=="post_first_p" {
        if (/^---$/ || /^##[[:space:]]/) {
            if (pending!="") printf "%s", pending
            pending=""; phase="rest"; print; next
        }
        if (/^[[:space:]]*$/) {
            if (skip_one_blank) { skip_one_blank=0; next }
            pending=pending"\n"; next
        }
        if (/^<!--/) { next }
        if (/^<p /) {
            p_buf = $0 "\n"; is_badge_p = 0
            if (/"GitHub repo"/) is_badge_p = 1
            if (/<\/p>/) {
                if (!is_badge_p) { printf "%s", pending; printf "%s", p_buf }
                pending = ""; p_buf = ""; is_badge_p = 0
            } else {
                checking_p = 1
            }
            next
        }
        if (pending!="") { printf "%s", pending; pending="" }
        phase="rest"; print; next
    }
    phase=="rest" { print; next }
    { print; next }
    ' "$readme_path" >"$tmp"

    # Only write back when something actually changed (idempotent)
    if ! diff -q "$readme_path" "$tmp" >/dev/null 2>&1; then
        mv "$tmp" "$readme_path"
        print_success "Updated badge block in $readme_path"
    else
        rm -f "$tmp"
        print_info "Badge block unchanged in $readme_path"
    fi
}
