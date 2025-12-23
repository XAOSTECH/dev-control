#!/usr/bin/env bash
#
# Git-Control History Fixer
# Interactive git commit history rewriting tool
#
# Allows you to:
#   - View original commit history with dates
#   - Reorder commits
#   - Edit commit messages
#   - Change commit dates (author and committer)
#   - Verify changes before applying
#
# Usage:
#   ./scripts/fix-history.sh                    # Interactive mode
#   ./scripts/fix-history.sh --range HEAD~5     # Fix last 5 commits
#   ./scripts/fix-history.sh --help
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
RANGE="HEAD~10"
INTERACTIVE=true
DRY_RUN=false
STASH_NUM=""
STASH_MODE=false
AMEND_MODE=false
AMEND_COMMIT=""
NO_EDIT_MODE=false
SIGN_MODE=false
DROP_COMMIT=""
# Auto-resolve strategy: empty|ours|theirs
# Can be set via environment (AUTO_RESOLVE=ours|theirs) or via --auto-resolve <mode>
AUTO_RESOLVE="${AUTO_RESOLVE:-}"
# Restore options
RESTORE_MODE=false
RESTORE_ARG=""
RESTORE_LIST_N=10
RESTORE_AUTO=false

TEMP_COMMITS="/tmp/git-fix-history-commits.txt"
TEMP_OPERATIONS="/tmp/git-fix-history-operations.txt"
TEMP_STASH_PATCH="/tmp/git-fix-history-stash.patch"
TEMP_ALL_DATES="/tmp/git-fix-history-all-dates.txt"
TEMP_BACKUP="/tmp/git-fix-history-backup-$(date +%s).bundle"

# Parse a simple --auto-resolve argument early so users can pass it anywhere on the command line
# Accepts: --auto-resolve <ours|theirs>
ARGS=("$@")
for ((i=0;i<${#ARGS[@]};i++)); do
    if [[ "${ARGS[$i]}" == "--auto-resolve" ]]; then
        if [[ $((i+1)) -lt ${#ARGS[@]} ]]; then
            AUTO_RESOLVE="${ARGS[$((i+1))]}"
            if [[ "$AUTO_RESOLVE" != "ours" && "$AUTO_RESOLVE" != "theirs" ]]; then
                echo "[WARNING] Invalid value for --auto-resolve: $AUTO_RESOLVE (allowed: ours|theirs). Ignoring." >&2
                AUTO_RESOLVE=""
            else
                echo "[INFO] Auto-resolve strategy set to: $AUTO_RESOLVE" >&2
            fi
        fi
    fi
done

# Harness configuration (minimal test harness integrated into script)
HARNESS_MODE=false
HARNESS_OP=""
HARNESS_ARG=""
HARNESS_CLEANUP=true
REPORT_DIR="/tmp/history-harness-reports"
RESTORE_MODE=false

mkdir -p "$REPORT_DIR"

# File descriptor for interactive prompts (uses /dev/tty if available)
if [[ -t 0 ]]; then
    # Try to open /dev/tty for interactive input
    if [[ -r /dev/tty ]]; then
        exec 3</dev/tty
    else
        # Fallback to stdin
        exec 3<&0
    fi
else
    exec 3<&0
fi

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

print_header() {
    echo -e "\n${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║${NC}            ${CYAN}Git-Control History Fixer${NC}                      ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}

# (rest of file unchanged)

# NOTE: This PR will include the full refactor implemented locally. Please review the changes in the PR and run the test harness before applying to sensitive branches.
