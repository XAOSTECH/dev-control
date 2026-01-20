#!/usr/bin/env bash
#
# Dev-Control Status Command
# Show Dev-Control and repository status
#
# Demonstrates --json, --quiet, --verbose output modes
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience

set -e

if [[ -z "$DC_ROOT" ]]; then
    SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    DC_ROOT="$(dirname "$SCRIPT_PATH")"
fi

source "$DC_ROOT/scripts/lib/colors.sh"
source "$DC_ROOT/scripts/lib/print.sh"
source "$DC_ROOT/scripts/lib/git-utils.sh"
source "$DC_ROOT/scripts/lib/output.sh"
source "$DC_ROOT/scripts/lib/config.sh"

show_help() {
    cat << 'EOF'
Dev-Control Status - Show Dev-Control and repository status

USAGE:
  gc status [options]

OPTIONS:
  -q, --quiet       Only output essential information
  --verbose         Show detailed information
  --json            Output as JSON
  -h, --help        Show this help

EXAMPLES:
  gc status
  gc status --json
  gc status --verbose

EOF
}

# Gather status information
gather_status() {
    # Git-control info
    DC_VERSION="${DC_VERSION:-2.0.0}"
    DC_LOCATION="$DC_ROOT"
    
    # Git info
    IN_GIT_REPO=false
    GIT_BRANCH=""
    GIT_REMOTE=""
    GIT_OWNER=""
    GIT_REPO_NAME=""
    GIT_UNCOMMITTED=0
    GIT_UNTRACKED=0
    GIT_STAGED=0
    
    if in_git_worktree; then
        IN_GIT_REPO=true
        GIT_BRANCH=$(get_current_branch)
        GIT_REMOTE=$(get_remote_url)
        GIT_OWNER=$(get_repo_owner "$GIT_REMOTE")
        GIT_REPO_NAME=$(get_repo_name "$GIT_REMOTE")
        
        # Count changes
        GIT_UNCOMMITTED=$(git diff --numstat 2>/dev/null | wc -l)
        GIT_UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)
        GIT_STAGED=$(git diff --cached --numstat 2>/dev/null | wc -l)
    fi
    
    # Config info
    HAS_GLOBAL_CONFIG=false
    HAS_PROJECT_CONFIG=false
    
    [[ -f "$DC_GLOBAL_CONFIG" ]] && HAS_GLOBAL_CONFIG=true
    
    if [[ "$IN_GIT_REPO" == "true" ]]; then
        local root
        root=$(git_root)
        [[ -f "$root/$DC_PROJECT_CONFIG" ]] && HAS_PROJECT_CONFIG=true
    fi
    
    # Tools
    HAS_GH=false
    HAS_GUM=false
    HAS_FZF=false
    HAS_GPG=false
    
    command -v gh &>/dev/null && HAS_GH=true
    command -v gum &>/dev/null && HAS_GUM=true
    command -v fzf &>/dev/null && HAS_FZF=true
    command -v gpg &>/dev/null && HAS_GPG=true
}

output_json() {
    cat << EOF
{
  "gc": {
    "version": "$DC_VERSION",
    "location": "$DC_LOCATION"
  },
  "git": {
    "inRepo": $IN_GIT_REPO,
    "branch": "$GIT_BRANCH",
    "remote": "$GIT_REMOTE",
    "owner": "$GIT_OWNER",
    "repo": "$GIT_REPO_NAME",
    "uncommitted": $GIT_UNCOMMITTED,
    "untracked": $GIT_UNTRACKED,
    "staged": $GIT_STAGED
  },
  "config": {
    "hasGlobal": $HAS_GLOBAL_CONFIG,
    "hasProject": $HAS_PROJECT_CONFIG
  },
  "tools": {
    "gh": $HAS_GH,
    "gum": $HAS_GUM,
    "fzf": $HAS_FZF,
    "gpg": $HAS_GPG
  }
}
EOF
}

output_text() {
    out_header "Dev-Control Status"
    
    out_section "Dev-Control"
    out "  Version:  $DC_VERSION"
    out "  Location: $DC_LOCATION"
    out ""
    
    out_section "Repository"
    if [[ "$IN_GIT_REPO" == "true" ]]; then
        out "  In repo:     Yes"
        out "  Branch:      $GIT_BRANCH"
        out "  Remote:      $GIT_REMOTE"
        out "  Owner/Repo:  $GIT_OWNER/$GIT_REPO_NAME"
        
        if [[ "$OUTPUT_VERBOSE" == "true" ]]; then
            out "  Uncommitted: $GIT_UNCOMMITTED files"
            out "  Untracked:   $GIT_UNTRACKED files"
            out "  Staged:      $GIT_STAGED files"
        fi
    else
        out "  Not in a git repository"
    fi
    out ""
    
    out_section "Configuration"
    out "  Global config:  $(if $HAS_GLOBAL_CONFIG; then echo "Found"; else echo "Not found"; fi)"
    out "  Project config: $(if $HAS_PROJECT_CONFIG; then echo "Found"; else echo "Not found"; fi)"
    out ""
    
    if [[ "$OUTPUT_VERBOSE" == "true" ]]; then
        out_section "Available Tools"
        out "  GitHub CLI (gh): $(if $HAS_GH; then echo "${GREEN}✓${NC}"; else echo "${RED}✗${NC}"; fi)"
        out "  gum (TUI):       $(if $HAS_GUM; then echo "${GREEN}✓${NC}"; else echo "${DIM}optional${NC}"; fi)"
        out "  fzf (fuzzy):     $(if $HAS_FZF; then echo "${GREEN}✓${NC}"; else echo "${DIM}optional${NC}"; fi)"
        out "  GPG (signing):   $(if $HAS_GPG; then echo "${GREEN}✓${NC}"; else echo "${RED}✗${NC}"; fi)"
        out ""
    fi
}

main() {
    # Parse flags
    parse_output_flags "$@"
    set -- "${REMAINING_ARGS[@]}"
    
    # Handle help
    if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
        show_help
        exit 0
    fi
    
    # Gather information
    gather_status
    
    # Output based on mode
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        output_json
    else
        output_text
    fi
}

main "$@"
