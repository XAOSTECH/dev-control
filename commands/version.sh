#!/usr/bin/env bash
#
# gc version - Version and update management
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/lib/version.sh"
source "$SCRIPT_DIR/../scripts/lib/output.sh"

# ============================================================================
# COMMANDS
# ============================================================================

show_version() {
    local verbose=false
    [[ "${1:-}" == "-v" || "${1:-}" == "--verbose" ]] && verbose=true
    
    echo "$(gc_version_string)"
    
    if [[ "$verbose" == "true" ]]; then
        echo ""
        gc_install_info
        echo ""
        echo "Dependencies:"
        echo "  bash:  $(bash --version | head -n1)"
        echo "  git:   $(git --version)"
        command -v gh &>/dev/null && echo "  gh:    $(gh --version | head -n1)" || echo "  gh:    not installed"
        command -v gum &>/dev/null && echo "  gum:   $(gum --version)" || echo "  gum:   not installed"
        command -v fzf &>/dev/null && echo "  fzf:   $(fzf --version)" || echo "  fzf:   not installed"
    fi
}

show_json() {
    local install_dir
    install_dir=$(cd "$SCRIPT_DIR/.." && pwd)
    local commit="unknown"
    local branch="unknown"
    
    if [[ -d "$install_dir/.git" ]]; then
        commit=$(git -C "$install_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")
        branch=$(git -C "$install_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    fi
    
    cat << EOF
{
  "version": "$GC_VERSION",
  "date": "$GC_VERSION_DATE",
  "repo": "$GC_REPO",
  "branch": "$branch",
  "commit": "$commit",
  "install_dir": "$install_dir"
}
EOF
}

check_update() {
    gc_check_update
}

do_update() {
    gc_update
}

show_changelog() {
    local version="${1:-}"
    if [[ -n "$version" ]]; then
        gc_changelog "$version"
    else
        gc_recent_changes 3
    fi
}

show_help() {
    cat << 'EOF'
Version and update management

USAGE:
  gc version [COMMAND] [OPTIONS]

COMMANDS:
  show            Show version information (default)
  check           Check for updates
  update          Update to latest version
  changelog       Show recent changes

OPTIONS:
  -v, --verbose   Show detailed version info
  --json          Output as JSON

EXAMPLES:
  gc version                # Show version
  gc version -v             # Detailed info
  gc version --json         # JSON output
  gc version check          # Check for updates
  gc version update         # Perform update
  gc version changelog      # Show recent changes
  gc version changelog 1.0.0  # Show specific version

EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local cmd="${1:-show}"
    shift 2>/dev/null || true
    
    # Handle flags that can come first
    case "$cmd" in
        -v|--verbose)
            show_version --verbose
            return
            ;;
        --json)
            show_json
            return
            ;;
        -h|--help|help)
            show_help
            return
            ;;
    esac
    
    case "$cmd" in
        show)
            if [[ "${1:-}" == "--json" ]]; then
                show_json
            else
                show_version "$@"
            fi
            ;;
        check)
            check_update
            ;;
        update)
            do_update
            ;;
        changelog)
            show_changelog "$@"
            ;;
        *)
            show_help
            return 1
            ;;
    esac
}

main "$@"
