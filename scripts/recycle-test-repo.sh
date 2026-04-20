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
TEST_GNUPGHOME="${TEST_GNUPGHOME:-$TEST_REPO_DIR/.gnupg}"
TEST_GPG_NAME="Dev-Control Test"
TEST_GPG_EMAIL="test@dev-control.local"
TEST_GPG_KEY_ID=""   # populated by ensure_gpg_key

ACTION="cycle"   # cycle | clean | init | list
ONLY=""
NO_GPG=false

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
  --only NAME       Cycle only one fixture (linear|with-merges|unsigned|signed)
  --no-gpg          Skip GPG key generation; build all fixtures unsigned
                    (signing tests will not run; useful in environments
                    without gpg or where key creation is undesirable)
  -h, --help        Show this help

Environment:
  TEST_REPO_DIR     Override the destination root (default: \$DC_ROOT/test-repo)
  TEST_GNUPGHOME    Override the ephemeral GNUPGHOME
                    (default: \$TEST_REPO_DIR/.gnupg)

Notes:
  - test-repo/ (including .gnupg/) is gitignored at the dev-control repo root.
  - An ephemeral, passphrase-less GPG key is generated on first cycle and
    re-used for every fixture so that --sign / --auto-sign / --resign
    paths in dc-fix can be exercised end-to-end.
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
            --no-gpg) NO_GPG=true; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) print_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# GPG (ephemeral keyring under test-repo/.gnupg)
# ---------------------------------------------------------------------------

# Generate (or reuse) a passphrase-less RSA key inside an isolated
# GNUPGHOME so signing tests don't pollute the developer's real keyring
# and require no manual key import.  Idempotent: a second call with an
# existing key just re-discovers the fingerprint.
ensure_gpg_key() {
    if [[ "$NO_GPG" == "true" ]]; then
        TEST_GPG_KEY_ID=""
        return 0
    fi

    if ! command -v gpg >/dev/null 2>&1; then
        print_warning "gpg not found on PATH; signing fixtures will be skipped"
        NO_GPG=true
        return 0
    fi

    mkdir -p "$TEST_GNUPGHOME"
    chmod 700 "$TEST_GNUPGHOME"

    # Try to reuse an existing key first.
    TEST_GPG_KEY_ID="$(GNUPGHOME="$TEST_GNUPGHOME" gpg --batch --with-colons \
        --list-secret-keys 2>/dev/null \
        | awk -F: '/^sec:/{print $5; exit}')"

    if [[ -n "$TEST_GPG_KEY_ID" ]]; then
        print_info "Reusing test GPG key: $TEST_GPG_KEY_ID"
        return 0
    fi

    print_info "Generating ephemeral test GPG key in $TEST_GNUPGHOME"
    GNUPGHOME="$TEST_GNUPGHOME" gpg --batch --pinentry-mode loopback \
        --passphrase '' \
        --quick-generate-key \
        "$TEST_GPG_NAME <$TEST_GPG_EMAIL>" \
        rsa2048 sign 0 >/dev/null 2>&1 || {
        print_warning "Failed to generate test GPG key; signing fixtures will be skipped"
        NO_GPG=true
        return 0
    }

    TEST_GPG_KEY_ID="$(GNUPGHOME="$TEST_GNUPGHOME" gpg --batch --with-colons \
        --list-secret-keys 2>/dev/null \
        | awk -F: '/^sec:/{print $5; exit}')"

    if [[ -z "$TEST_GPG_KEY_ID" ]]; then
        print_warning "Test GPG key generated but not discoverable; disabling signing"
        NO_GPG=true
        return 0
    fi

    print_success "Test GPG key: $TEST_GPG_KEY_ID"
}

# Bind the ephemeral key to a fixture's local git config.  The repo will
# look up GNUPGHOME from the environment (recycle-test-repo.sh exports
# it for the build phase; for ad-hoc dc-fix runs the developer should
# `export GNUPGHOME=$DC_ROOT/test-repo/.gnupg` or run via this script's
# helpers).
_bind_gpg_to_repo() {
    local dir="$1" sign_default="$2"   # sign_default: true|false
    if [[ "$NO_GPG" == "true" || -z "$TEST_GPG_KEY_ID" ]]; then
        git -C "$dir" config commit.gpgsign false
        git -C "$dir" config tag.gpgsign false
        return 0
    fi
    git -C "$dir" config user.signingkey "$TEST_GPG_KEY_ID"
    git -C "$dir" config gpg.program "$(command -v gpg)"
    git -C "$dir" config commit.gpgsign "$sign_default"
    git -C "$dir" config tag.gpgsign false

    # Drop a tiny pointer file so the developer knows where the key lives.
    cat > "$dir/.git/TEST_GPG_INFO" <<EOF
Test GPG key bound to this fixture by scripts/recycle-test-repo.sh
GNUPGHOME=$TEST_GNUPGHOME
key=$TEST_GPG_KEY_ID
To run dc-fix --sign / --auto-sign against this repo:
  export GNUPGHOME="$TEST_GNUPGHOME"
  cd $dir
  bash $DC_ROOT/scripts/fix-history.sh --auto-sign
EOF
}

# ---------------------------------------------------------------------------
# FIXTURES
# ---------------------------------------------------------------------------

# Common per-repo bootstrap: init, set test identity, bind ephemeral GPG
# key.  sign_default controls whether commit.gpgsign is on (so the build
# phase below produces signed history) or off (build unsigned, then let
# dc-fix --auto-sign sign it later).
_init_repo() {
    local dir="$1" sign_default="${2:-false}"
    rm -rf "$dir"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main
    git -C "$dir" config user.email "$TEST_GPG_EMAIL"
    git -C "$dir" config user.name "$TEST_GPG_NAME"
    _bind_gpg_to_repo "$dir" "$sign_default"
}

# Make a commit with deterministic author + committer date.  Inherits
# GNUPGHOME from the caller (set by do_cycle/do_init when GPG is enabled)
# so commit.gpgsign=true repos actually find the test key.
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
    # Sign during build so we have a signed-history-with-merges fixture
    # ready for dc-fix --sign --preserve-topology / rebase-merges tests.
    _init_repo "$dir" true

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

    local merges signed
    merges=$(git -C "$dir" rev-list --merges HEAD | wc -l | tr -d ' ')
    signed=$(_count_signed "$dir")
    print_success "with-merges: $(git -C "$dir" rev-list --count HEAD) commits, $merges merge, $signed signed"
}

build_unsigned() {
    local dir="$TEST_REPO_DIR/unsigned"
    print_info "Building unsigned fixture: $dir"
    # Key is bound but commit.gpgsign=false → ready for --auto-sign tests.
    _init_repo "$dir" false
    local i
    for i in 1 2 3 4; do
        echo "u$i" > "$dir/u$i.txt"
        git -C "$dir" add "u$i.txt"
        _commit "$dir" "2024-03-0${i} 14:00:00 +0000" "unsigned: u$i"
    done
    print_success "unsigned: $(git -C "$dir" rev-list --count HEAD) commits (no signatures, key bound for --auto-sign)"
}

build_signed() {
    local dir="$TEST_REPO_DIR/signed"
    print_info "Building signed fixture: $dir"
    _init_repo "$dir" true
    local i
    for i in 1 2 3 4; do
        echo "s$i" > "$dir/s$i.txt"
        git -C "$dir" add "s$i.txt"
        _commit "$dir" "2024-04-0${i} 16:00:00 +0000" "signed: s$i"
    done
    local signed
    signed=$(_count_signed "$dir")
    print_success "signed: $(git -C "$dir" rev-list --count HEAD) commits, $signed signed"
}

# Count how many commits on HEAD carry a valid signature (G or U).
_count_signed() {
    local dir="$1"
    git -C "$dir" log --pretty=format:'%G?' 2>/dev/null \
        | grep -c -E '^[GU]$' || true
}

build_all() {
    mkdir -p "$TEST_REPO_DIR"
    ensure_gpg_key
    # Export so child git invocations during the build phase find the
    # ephemeral key when commit.gpgsign=true.
    if [[ "$NO_GPG" != "true" ]]; then
        export GNUPGHOME="$TEST_GNUPGHOME"
    fi
    case "$ONLY" in
        "")             build_linear; build_with_merges; build_unsigned; build_signed ;;
        linear)         build_linear ;;
        with-merges)    build_with_merges ;;
        unsigned)       build_unsigned ;;
        signed)         build_signed ;;
        *) print_error "Unknown fixture: $ONLY (allowed: linear|with-merges|unsigned|signed)"; exit 1 ;;
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
        # Skip the ephemeral keyring; it lives under test-repo/ but is
        # not a fixture.
        [[ "$(basename "$d")" == ".gnupg" ]] && continue
        found=1
        local name count head signed
        name=$(basename "$d")
        if [[ -d "$d/.git" ]]; then
            count=$(git -C "$d" rev-list --count HEAD 2>/dev/null || echo "?")
            head=$(git -C "$d" log -1 --format='%h %s' 2>/dev/null || echo "(empty)")
            signed=$(GNUPGHOME="$TEST_GNUPGHOME" _count_signed "$d")
            printf "  %-15s %s commits (%s signed), HEAD: %s\n" \
                "$name" "$count" "$signed" "$head"
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
