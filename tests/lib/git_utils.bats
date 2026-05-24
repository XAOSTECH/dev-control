#!/usr/bin/env bats
#
# Tests for scripts/lib/git/utils.sh
#
# Each test runs inside a fresh throw-away git repository so the checks against branches, remotes, commits and worktree state never depend on (nor disturb) the surrounding dev-control checkout.
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

setup() {
    # Source the colour/print libs first because some require_* helpers in utils.sh reference colour variables when emitting errors.
    source "$BATS_TEST_DIRNAME/../../scripts/lib/colours.sh"
    source "$BATS_TEST_DIRNAME/../../scripts/lib/print.sh"
    source "$BATS_TEST_DIRNAME/../../scripts/lib/git/utils.sh"

    REPO_DIR=$(mktemp -d)
    cd "$REPO_DIR"
    git init --quiet --initial-branch=main
    git config user.email "test@example.invalid"
    git config user.name "Test"
    git config commit.gpgsign false
    git config tag.gpgsign false
}

teardown() {
    cd /
    rm -rf "$REPO_DIR"
}

# ============================================================================
# parse_github_url — pure string parser, no git invocation
# ============================================================================

@test "parse_github_url: parses https URL with .git suffix" {
    result=$(parse_github_url "https://github.com/octocat/hello-world.git")
    assert_equal "$result" "octocat hello-world"
}

@test "parse_github_url: parses https URL without .git suffix" {
    result=$(parse_github_url "https://github.com/octocat/hello-world")
    assert_equal "$result" "octocat hello-world"
}

@test "parse_github_url: parses ssh URL" {
    result=$(parse_github_url "git@github.com:octocat/hello-world.git")
    assert_equal "$result" "octocat hello-world"
}

@test "parse_github_url: returns empty pair for non-github URL" {
    result=$(parse_github_url "https://gitlab.com/owner/repo.git")
    assert_equal "$result" " "
}

# ============================================================================
# Repository detection
# ============================================================================

@test "is_git_repo: true for a freshly-initialised repo" {
    run is_git_repo "$REPO_DIR"
    assert_success
}

@test "is_git_repo: false for a plain directory" {
    local plain
    plain=$(mktemp -d)
    run is_git_repo "$plain"
    assert_failure
    rm -rf "$plain"
}

@test "in_git_worktree: true inside the repo" {
    run in_git_worktree
    assert_success
}

@test "git_root: returns the repository toplevel" {
    result=$(git_root)
    # macOS/Linux temp dirs can be symlinked (e.g. /tmp -> /private/tmp); compare via realpath to stay portable.
    [[ "$(realpath "$result")" == "$(realpath "$REPO_DIR")" ]]
}

# ============================================================================
# Remote URL helpers
# ============================================================================

@test "get_remote_url: empty when no remote is configured" {
    result=$(get_remote_url)
    assert_equal "$result" ""
}

@test "get_remote_url: returns the configured origin URL" {
    git remote add origin "https://github.com/octocat/hello-world.git"
    result=$(get_remote_url)
    assert_equal "$result" "https://github.com/octocat/hello-world.git"
}

@test "get_repo_owner / get_repo_name: derive owner and repo from remote" {
    git remote add origin "git@github.com:octocat/hello-world.git"
    assert_equal "$(get_repo_owner)" "octocat"
    assert_equal "$(get_repo_name)" "hello-world"
}

# ============================================================================
# Branch operations
# ============================================================================

@test "get_current_branch: reports the initial branch" {
    # Some git versions need at least one commit before HEAD resolves; create one.
    git commit --quiet --allow-empty -m "init"
    result=$(get_current_branch)
    assert_equal "$result" "main"
}

@test "branch_exists: true for an existing branch, false for an unknown one" {
    git commit --quiet --allow-empty -m "init"
    run branch_exists "main"
    assert_success
    run branch_exists "no-such-branch"
    assert_failure
}

@test "get_default_branch: falls back to local main when no remote HEAD exists" {
    git commit --quiet --allow-empty -m "init"
    result=$(get_default_branch)
    assert_equal "$result" "main"
}

# ============================================================================
# Worktree status
# ============================================================================

@test "has_uncommitted_changes: false on a clean repo" {
    git commit --quiet --allow-empty -m "init"
    run has_uncommitted_changes
    assert_failure
}

@test "has_uncommitted_changes: true after modifying a tracked file" {
    echo "a" > file.txt
    git add file.txt
    git commit --quiet -m "add file"
    echo "b" >> file.txt
    run has_uncommitted_changes
    assert_success
}

@test "has_staged_changes: true after git add, false after commit" {
    echo "a" > file.txt
    git add file.txt
    run has_staged_changes
    assert_success
    git commit --quiet -m "add file"
    run has_staged_changes
    assert_failure
}

@test "has_untracked_files: true with a new file, false after add" {
    echo "x" > untracked.txt
    run has_untracked_files
    assert_success
    git add untracked.txt
    run has_untracked_files
    assert_failure
}

@test "get_status_summary: counts staged, modified and untracked entries" {
    echo "a" > tracked.txt
    git add tracked.txt
    git commit --quiet -m "init"

    echo "b" >> tracked.txt          # modified
    echo "c" > staged.txt
    git add staged.txt               # staged
    echo "d" > loose.txt             # untracked

    result=$(get_status_summary)
    assert_equal "$result" "staged:1 modified:1 untracked:1"
}

# ============================================================================
# Commit metadata
# ============================================================================

@test "get_short_hash: returns a 7+ character abbreviated hash" {
    git commit --quiet --allow-empty -m "init"
    result=$(get_short_hash HEAD)
    [[ ${#result} -ge 7 ]]
}

@test "get_commit_subject: returns the most recent commit subject" {
    git commit --quiet --allow-empty -m "hello world"
    result=$(get_commit_subject HEAD)
    assert_equal "$result" "hello world"
}

@test "get_commit_author: returns 'name <email>' for HEAD" {
    git commit --quiet --allow-empty -m "init"
    result=$(get_commit_author HEAD)
    assert_equal "$result" "Test <test@example.invalid>"
}

@test "get_commit_date: returns an ISO-8601 timestamp" {
    git commit --quiet --allow-empty -m "init"
    result=$(get_commit_date HEAD)
    [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]
}

# ============================================================================
# Pure helpers
# ============================================================================

@test "get_relative_path: strips the parent prefix" {
    result=$(get_relative_path "/parent" "/parent/child/file.txt")
    assert_equal "$result" "child/file.txt"
}
