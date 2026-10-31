#!/usr/bin/env bats
#
# Tests for the dedup nest check (scripts/lib/git/dedu.sh, driven through
# scripts/fix-history.sh). Each test runs inside a throw-away git repository
# whose history contains both a consecutive duplicate run and a non-adjacent
# ("abba abba") nest, so consecutive-only and nested resolution can be told
# apart. The root commit doubles as an untouchable boundary.
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

# Commit a distinct file under a given subject so every tree differs.
_commit() {
    printf '%s @ %s\n' "$2" "$(date +%s%N)" > "$2"
    git add "$2"
    git commit --quiet -m "$1"
}

setup() {
    FIX="$BATS_TEST_DIRNAME/../scripts/fix-history.sh"
    REPO_DIR=$(mktemp -d)
    cd "$REPO_DIR"
    git init --quiet --initial-branch=main
    git config user.email "test@example.invalid"
    git config user.name "Test"
    git config commit.gpgsign false
    git config tag.gpgsign false

    _commit "base"  base.txt   # root — the untouchable boundary
    BASE=$(git rev-parse HEAD)
    _commit "alpha" a1.txt
    _commit "beta"  b1.txt
    _commit "alpha" a2.txt      # non-adjacent duplicate of "alpha"
    _commit "beta"  b2.txt      # non-adjacent duplicate of "beta"
    _commit "gamma" g1.txt
    _commit "gamma" g2.txt      # consecutive duplicate of "gamma"
    _commit "final" f1.txt      # unique tip
}

teardown() {
    cd /
    rm -rf "$REPO_DIR"
}

@test "dedu (plain) previews consecutive-only collapse" {
    run bash -c "set -o pipefail; bash '$FIX' --dedu --no-cleanup --range ${BASE}..HEAD --dry-run | sed 's/\x1b\[[0-9;]*m//g'"
    assert_success
    assert_output --partial "Mode:  consecutive"
    assert_output --partial "Would squash 1 commit(s) across 1 group(s)"
}

@test "dedu x2 previews the nested (non-adjacent) plan" {
    run bash -c "set -o pipefail; bash '$FIX' --dedu x2 --no-cleanup --range ${BASE}..HEAD --dry-run | sed 's/\x1b\[[0-9;]*m//g'"
    assert_success
    assert_output --partial "nest check"
    assert_output --partial "Would squash 3 commit(s) across 3 group(s)"
}

@test "dedu x2 collapses nests and preserves the working tree" {
    local before_tree before_count
    before_tree=$(git rev-parse "HEAD^{tree}")
    before_count=$(git rev-list --count "${BASE}..HEAD")
    assert_equal "$before_count" "7"

    run bash -c "printf 'y\nn\n' | bash '$FIX' --dedu x2 --no-cleanup --range ${BASE}..HEAD"
    assert_success
    assert_output --partial "Nest check: working tree identical to original"
    assert_output --partial "converged"

    # 7 in-range commits -> 4 (alpha, beta, gamma, final each kept once)
    assert_equal "$(git rev-list --count "${BASE}..HEAD")" "4"
    # Net content is unchanged (tip tree byte-identical)
    assert_equal "$(git rev-parse "HEAD^{tree}")" "$before_tree"
    # Boundary commit is still the parent of the oldest in-range commit
    assert_equal "$(git rev-parse "$(git rev-list "${BASE}..HEAD" | tail -1)^")" "$BASE"
    # Working tree is clean
    assert_equal "$(git status --porcelain | wc -l | tr -d ' ')" "0"
}

@test "dedu (plain) leaves non-adjacent duplicates intact" {
    run bash -c "printf 'y\nn\n' | bash '$FIX' --dedu --no-cleanup --range ${BASE}..HEAD"
    assert_success
    # Only the consecutive "gamma" run collapses: 7 -> 6
    assert_equal "$(git rev-list --count "${BASE}..HEAD")" "6"
    # The two non-adjacent "alpha" commits both survive
    assert_equal "$(git log --format='%s' "${BASE}..HEAD" | grep -c '^alpha$')" "2"
}

@test "dedu x2 combines chore families whose subjects differ and aggregates messages" {
    local fam_base before_tree
    fam_base=$(git rev-parse HEAD)
    _commit "chore: update 1 submodule(s) to latest" s1.txt
    _commit "chore: update git tree visualisation"   t1.txt
    _commit "chore: update 2 submodule(s) to latest" s2.txt   # same family, different subject
    _commit "chore: update git tree visualisation"   t2.txt
    _commit "feat: real work"                         w1.txt   # untouched tip
    before_tree=$(git rev-parse "HEAD^{tree}")

    run bash -c "printf 'y\nn\n' | bash '$FIX' --dedu x2 --no-cleanup --range ${fam_base}..HEAD"
    assert_success
    assert_output --partial "Nest check: working tree identical to original"

    # Both submodule-bump commits collapse to one despite differing counts; so do the tree-viz refreshes.
    assert_equal "$(git log --format='%s' "${fam_base}..HEAD" | grep -c 'submodule')" "1"
    assert_equal "$(git log --format='%s' "${fam_base}..HEAD" | grep -c 'tree visualisation')" "1"
    # Net content is unchanged.
    assert_equal "$(git rev-parse "HEAD^{tree}")" "$before_tree"

    # The combined submodule commit lists every squashed subject in its body.
    run git log --format='%B' "${fam_base}..HEAD"
    assert_output --partial "Consolidated 2 commits:"
    assert_output --partial "- chore: update 1 submodule(s) to latest"
    assert_output --partial "- chore: update 2 submodule(s) to latest"
}

@test "dedu x2 never combines CHANGELOG commits (release anchors are pinned)" {
    local cl_base
    cl_base=$(git rev-parse HEAD)
    _commit "chore: update CHANGELOG for v1.0.0" c1.txt
    _commit "feat: work"                          cw.txt
    _commit "chore: update CHANGELOG for v1.0.0" c2.txt   # identical subject, must NOT be squashed

    run bash -c "printf 'y\nn\n' | bash '$FIX' --dedu x2 --no-cleanup --range ${cl_base}..HEAD"
    assert_success
    # Both CHANGELOG commits survive even though their subjects match.
    assert_equal "$(git log --format='%s' "${cl_base}..HEAD" | grep -c 'CHANGELOG')" "2"
}

