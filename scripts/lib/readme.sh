#!/usr/bin/env bash
#
# Dev-Control README generation library
# Sourced by template-loading.sh to populate README/docs templates.
#
# Placeholders are discovered dynamically from the template ({{TOKEN}}), so a
# user can extend a template with new tokens and they are picked up without any
# code change. Each token resolves, in order, from a same-named variable already
# collected upstream, a git-config cache, an interactive prompt (skipped with
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
# A token whose same-named variable is already declared (e.g. set by
# collect_project_info) is used as-is and never re-prompted; only genuinely new
# tokens fall through to cache, prompt or empty.
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

    local sed_args=() token value esc
    while IFS= read -r token; do
        [[ -z "$token" ]] && continue
        readme_resolve_placeholder "$token" value
        esc="${value//&/\\&}"
        esc="${esc//|/\\|}"
        sed_args+=(-e "s|{{${token}}}|${esc}|g")
    done < <(readme_extract_placeholders "$template")

    if [[ ${#sed_args[@]} -gt 0 ]]; then
        sed "${sed_args[@]}" "$template" > "$dest"
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

# Insert the standard badge block after the first H1 of a README (idempotent).
readme_insert_badges() {
    local readme_path="$1"
    local tmp
    tmp=$(mktemp)

    local badges
    badges=$(cat <<'EOF'

<p align="center">
  <a href="{{REPO_URL}}">
    <img alt="GitHub repo" src="https://img.shields.io/badge/GitHub-{{ORG_NAME}}%2F{{REPO_SLUG}}-181717?style=for-the-badge&logo=github">
  </a>
  <a href="{{REPO_URL}}/releases">
    <img alt="GitHub release" src="https://img.shields.io/github/v/release/{{ORG_NAME}}/{{REPO_SLUG}}?style=for-the-badge&logo=semantic-release&color=blue">
  </a>
  <a href="{{REPO_URL}}/blob/main/LICENCE">
    <img alt="Licence" src="https://img.shields.io/github/license/{{ORG_NAME}}/{{REPO_SLUG}}?style=for-the-badge&color=green">
  </a>
</p>

EOF
)
    badges="${badges//\{\{REPO_URL\}\}/$REPO_URL}"
    badges="${badges//\{\{ORG_NAME\}\}/$ORG_NAME}"
    badges="${badges//\{\{REPO_SLUG\}\}/$REPO_SLUG}"

    if [[ ! -f "$readme_path" ]]; then
        mkdir -p "$(dirname "$readme_path")"
        if [[ -f "$DEV_CONTROL_DIR/docs-templates/README.md" ]]; then
            readme_apply "$DEV_CONTROL_DIR/docs-templates/README.md" "$readme_path"
        else
            echo -e "# $PROJECT_NAME\n" > "$readme_path"
        fi
    fi

    if grep -q 'img alt="GitHub repo"' "$readme_path"; then
        print_info "Badges already present in README, skipping insertion"
        rm -f "$tmp"
        return
    fi

    awk -v badges="$badges" 'BEGIN{inserted=0} /^# / && !inserted{print; print badges; inserted=1; next} {print}' "$readme_path" > "$tmp" || {
        printf "%s\n%s" "$badges" "$(cat "$readme_path")" > "$tmp"
    }
    mv "$tmp" "$readme_path"
    print_success "Inserted badges into $readme_path"
}
