#!/usr/bin/env bash
#
# Dev-Control Test-Repo Recycler
#
# Build / wipe / refresh the disposable git repos under test-repo/ that
# the dc-fix smoke tests run against.  test-repo/ is gitignored, so the
# fixtures are never committed; this script lets a developer rebuild
# them deterministically on demand.
#
# Fixtures created:
#   test-repo/linear/        5 commits, deterministic dates 2024-01-01..05
#                            → exercises --amend, --drop, --blossom,
#                              --no-edit and the date-restore path.
#   test-repo/with-merges/   main + feature branch + non-ff merge
#                            → exercises --sign with PRESERVE_TOPOLOGY
#                              and the rebase-merges path.
#   test-repo/unsigned/      4 unsigned commits with explicit dates
#                            → exercises --auto-sign / --sign --resign.
#
# Usage:
#   recycle-test-repo.sh                # cycle: wipe + rebuild all fixtures
#   recycle-test-repo.sh --clean        # only wipe
#   recycle-test-repo.sh --init         # only build (fail if already present)
#   recycle-test-repo.sh --list         # show what is currently there
#   recycle-test-repo.sh --only linear  # rebuild a single fixture
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DC_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck source=lib/colours.sh
source "$SCRIPT_DIR/lib/colours.sh"
# shellcheck source=lib/print.sh
source "$SCRIPT_DIR/lib/print.sh"

TEST_REPO_DIR="${TEST_REPO_DIR:-$DC_ROOT/test-repo}"

ACTION="cycle"   # cycle | clean | init | list
ONLY=""

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

show_help() {
    cat <<EOF
Dev-Control Test-Repo Recycler

Usage: recycle-test-repo.sh [OPTIONS]

Options:
  (no flags)        Wipe and rebuild every fixture (default: cycle)
  --clean           Wipe test-repo/ entirely (no rebuild)
  --init            Build fixtures only; fail if they already exist
  --list            List existing fixtures and their commit counts
  --only NAME       Cycle only one fixture (linear|with-merges|unsigned)
  -h, --help        Show this help

Environment:
  TEST_REPO_DIR     Override the destination root (default: \$DC_ROOT/test-repo)

Notes:
  - test-repo/ is gitignored at the dev-control repo root.
  - Each fixture is a standalone git repo with deterministic commit dates
    so date-preservation tests are reproducible.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --clean) ACTION="clean"; shift ;;
            --init)  ACTION="init"; shift ;;
            --list)  ACTION="list"; shift ;;
            --only)  ONLY="$2"; shift 2 ;;
            -h|--help) show_help; exit 0 ;;
            *) print_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# FIXTURES
# ---------------------------------------------------------------------------

# Common per-repo bootstrap: init, set test identity, opt out of GPG signing
# so commits are reproducible regardless of the developer's git config.
_init_repo() {
    local dir="$1"
    rm -rf "$dir"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main
    git -C "$dir" config user.email "test@dev-control.local"
    git -C "$dir" config user.name "Dev-Control Test"
    git -C "$dir" config commit.gpgsign false
    git -C "$dir" config tag.gpgsign false
}

# Make a commit with deterministic author + committer date.
_commit() {
    local dir="$1" date="$2" msg="$3"
    GIT_AUTHOR_DATE="$date" \
    GIT_COMMITTER_DATE="$date" \
    git -C "$dir" commit -q --date "$date" -m "$msg"
}

build_linear() {
    local dir="$TEST_REPO_DIR/linear"
    print_info "Building linear fixture: $dir"
    _init_repo "$dir"
    local i
    for i in 1 2 3 4 5; do
        echo "line $i" > "$dir/file$i.txt"
        git -C "$dir" add "file$i.txt"
        _commit "$dir" "2024-01-0${i} 12:00:00 +0000" "c$i: add file$i"
    done
    print_success "linear: $(git -C "$dir" rev-list --count HEAD) commits"
}

build_with_merges() {
    local dir="$TEST_REPO_DIR/with-merges"
    print_info "Building with-merges fixture: $dir"
    _init_repo "$dir"

    echo "main 1" > "$dir/main.txt"
    git -C "$dir" add main.txt
    _commit "$dir" "2024-02-01 09:00:00 +0000" "main: initial"

    echo "main 2" >> "$dir/main.txt"
    git -C "$dir" add main.txt
    _commit "$dir" "2024-02-02 09:00:00 +0000" "main: extend"

    git -C "$dir" checkout -q -b feature
    echo "feature work" > "$dir/feature.txt"
    git -C "$dir" add feature.txt
    _commit "$dir" "2024-02-03 10:00:00 +0000" "feature: add feature.txt"
    echo "more feature" >> "$dir/feature.txt"
    git -C "$dir" add feature.txt
    _commit "$dir" "2024-02-04 10:00:00 +0000" "feature: extend feature.txt"

    git -C "$dir" checkout -q main
    echo "main 3" >> "$dir/main.txt"
    git -C "$dir" add main.txt
    _commit "$dir" "2024-02-05 09:00:00 +0000" "main: diverge"

    GIT_AUTHOR_DATE="2024-02-06 11:00:00 +0000" \
    GIT_COMMITTER_DATE="2024-02-06 11:00:00 +0000" \
    git -C "$dir" merge --no-ff --no-edit -q feature \
        -m "merge: feature into main" 2>/dev/null || {
        # If the merge auto-resolves cleanly we still want a deterministic date.
        :
    }

    print_success "with-merges: $(git -C "$dir" rev-list --count HEAD) commits ($(git -C "$dir" rev-list --merges HEAD | wc -l) merge)"
}

build_unsigned() {
    local dir="$TEST_REPO_DIR/unsigned"
    print_info "Building unsigned fixture: $dir"
    _init_repo "$dir"
    local i
    for i in 1 2 3 4; do
        echo "u$i" > "$dir/u$i.txt"
        git -C "$dir" add "u$i.txt"
        _commit "$dir" "2024-03-0${i} 14:00:00 +0000" "unsigned: u$i"
    done
    print_success "unsigned: $(git -C "$dir" rev-list --count HEAD) commits (no signatures)"
}

build_all() {
    mkdir -p "$TEST_REPO_DIR"
    case "$ONLY" in
        "")             build_linear; build_with_merges; build_unsigned ;;
        linear)         build_linear ;;
        with-merges)    build_with_merges ;;
        unsigned)       build_unsigned ;;
        *) print_error "Unknown fixture: $ONLY (allowed: linear|with-merges|unsigned)"; exit 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# ACTIONS
# ---------------------------------------------------------------------------

do_clean() {
    if [[ ! -d "$TEST_REPO_DIR" ]]; then
        print_info "Nothing to clean: $TEST_REPO_DIR does not exist"
        return 0
    fi
    if [[ -n "$ONLY" ]]; then
        local target="$TEST_REPO_DIR/$ONLY"
        if [[ -d "$target" ]]; then
            rm -rf "$target"
            print_success "Removed: $target"
        else
            print_info "Nothing to clean: $target does not exist"
        fi
        return 0
    fi
    rm -rf "$TEST_REPO_DIR"
    print_success "Removed: $TEST_REPO_DIR"
}

do_init() {
    if [[ -z "$ONLY" && -d "$TEST_REPO_DIR" ]] \
        && find "$TEST_REPO_DIR" -mindepth 1 -maxdepth 1 -print -quit \
            | grep -q .; then
        print_error "$TEST_REPO_DIR is not empty; use --clean first or run without --init to cycle"
        exit 1
    fi
    build_all
}

do_list() {
    if [[ ! -d "$TEST_REPO_DIR" ]]; then
        print_info "No test-repo directory: $TEST_REPO_DIR"
        return 0
    fi
    local found=0
    local d
    for d in "$TEST_REPO_DIR"/*/; do
        [[ -d "$d" ]] || continue
        found=1
        local name count head
        name=$(basename "$d")
        if [[ -d "$d/.git" ]]; then
            count=$(git -C "$d" rev-list --count HEAD 2>/dev/null || echo "?")
            head=$(git -C "$d" log -1 --format='%h %s' 2>/dev/null || echo "(empty)")
            printf "  %-15s %s commits, HEAD: %s\n" "$name" "$count" "$head"
        else
            printf "  %-15s (not a git repo)\n" "$name"
        fi
    done
    [[ $found -eq 1 ]] || print_info "No fixtures present in $TEST_REPO_DIR"
}

do_cycle() {
    do_clean
    build_all
    echo ""
    do_list
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------

parse_args "$@"

case "$ACTION" in
    cycle) do_cycle ;;
    clean) do_clean ;;
    init)  do_init ;;
    list)  do_list ;;
esac
