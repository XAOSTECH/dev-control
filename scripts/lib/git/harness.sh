#!/usr/bin/env bash
# ============================================================================
# harness.sh - Test harness utilities for git history operations
# ============================================================================
# This module provides a minimal in-script harness to run safe test operations
# in temporary branches with automatic backup and restoration capabilities.
#
# Functions:
#   harness_post_checks()       - Verify operation results (commit absent, clean tree)
#   harness_finish_success()    - Cleanup after successful harness run
#   harness_restore_backup()    - Restore from backup bundle on failure
#   harness_run()               - Main harness execution entry point
#
# Required globals (defined in parent script):
#   DRY_RUN            - If true, show what would be done without executing
#   HARNESS_MODE       - If true, run in harness mode
#   HARNESS_OP         - Operation to perform (drop, sign)
#   HARNESS_ARG        - Argument for the operation
#   HARNESS_CLEANUP    - If true, cleanup temp branch after success
#   HARNESS_FORCE      - If true, proceed despite existing tmp branches
#   REPORT_DIR         - Directory for harness reports
#   RESTORE_LIST_N     - Number of commits to show in logs
#   TEMP_BACKUP        - Path to backup bundle
#
# Required functions (from parent script):
#   drop_single_commit()  - Drop a commit from history
#   sign_mode()           - Sign commits in range
#   backup_repo()         - Create backup bundle
#
# Required functions (from lib/output.sh):
#   print_info(), print_success(), print_warning(), print_error()
# ============================================================================

# Ensure we're being sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This script should be sourced, not executed directly." >&2
    exit 1
fi

# ============================================================================
# POST-OPERATION VERIFICATION
# ============================================================================

# Verify operation results after harness run
# Checks: commit absent from history, clean working tree, diff summary
harness_post_checks() {
    local target_hash="$1"
    local rf="$2"

    echo "Post-operation checks:" | tee -a "$rf"

    # 1) Commit absent? Use git rev-parse to detect short or full SHAs and refs
    if git rev-parse --quiet --verify "$target_hash" >/dev/null 2>&1; then
        echo "ERROR: Commit $target_hash still present in the history" | tee -a "$rf"
        # Also print the resolved full SHA for debugging
        full_sha=$(git rev-parse --verify "$target_hash" 2>/dev/null || true)
        echo "Found as: ${full_sha:-<none>}" | tee -a "$rf"
        return 1
    else
        echo "OK: Commit $target_hash absent from history" | tee -a "$rf"
    fi

    # 2) Clean working tree?
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "WARNING: Working tree not clean after operation" | tee -a "$rf"
        git status --porcelain | tee -a "$rf"
        return 1
    else
        echo "OK: Working tree clean" | tee -a "$rf"
    fi

    # 3) Diff summary vs origin/Main (if exists)
    if git rev-parse --verify origin/Main >/dev/null 2>&1; then
        echo "Diff summary (origin/Main..HEAD):" | tee -a "$rf"
        git diff --name-status origin/Main..HEAD | tee -a "$rf"
    else
        echo "origin/Main not found, skipping diff summary" | tee -a "$rf"
    fi

    return 0
}

# ============================================================================
# CLEANUP AND RESTORATION
# ============================================================================

# Cleanup after successful harness run
harness_finish_success() {
    local tmp_branch="$1"
    local rf="$2"

    echo "" | tee -a "$rf"
    echo "Harness completed successfully." | tee -a "$rf"
    echo "Report saved: $rf" | tee -a "$rf"

    if [[ "$HARNESS_CLEANUP" == "true" ]]; then
        git checkout - || true
        git branch -D "$tmp_branch" || true
        echo "Cleaned up temp branch $tmp_branch" | tee -a "$rf"
    else
        echo "Temp branch retained: $tmp_branch" | tee -a "$rf"
    fi
}

# Restore repository state from backup bundle
harness_restore_backup() {
    local bundle="$1"
    local rf="$2"
    echo "Restoring from backup bundle: $bundle" | tee -a "$rf"
    git bundle unbundle "$bundle" || true
    git reset --hard origin/Main || git reset --hard HEAD || true
}

# ============================================================================
# MAIN HARNESS EXECUTION
# ============================================================================

# Main harness execution entry point
# Creates temp branch, runs operation, verifies results, handles cleanup
harness_run() {
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMP_BRANCH="tmp/harness-${TIMESTAMP}"
    REPORT_FILE="$REPORT_DIR/report-${TIMESTAMP}.txt"

    echo "Harness report: $REPORT_FILE"

    echo "Operation: ${HARNESS_OP} ${HARNESS_ARG}" | tee "$REPORT_FILE"

    # Capture pre-op log snapshot (limit by RESTORE_LIST_N)
    PRE_LOG="$REPORT_DIR/pre-${TIMESTAMP}.log"
    git --no-pager log --oneline -n "${RESTORE_LIST_N}" > "$PRE_LOG"
    echo "Pre-op log (last ${RESTORE_LIST_N} commits):" | tee -a "$REPORT_FILE"
    sed 's/^/  /' "$PRE_LOG" | tee -a "$REPORT_FILE"

    # Bail if a previous tmp/remove attempt for this commit exists to avoid repetition
    if [[ "${HARNESS_FORCE:-false}" != "true" ]]; then
        if git for-each-ref --format='%(refname:short)' refs/heads | grep -q "^tmp/remove-${HARNESS_ARG}-"; then
            echo "ERROR: Found existing tmp/remove-${HARNESS_ARG}-* branches. Aborting to avoid repeated failed attempts." | tee -a "$REPORT_FILE"
            return 1
        fi
    else
        echo "WARNING: HARNESS_FORCE=true - proceeding despite existing tmp/remove branches" | tee -a "$REPORT_FILE"
    fi

    # Create temp branch
    git checkout -b "$TMP_BRANCH" | tee -a "$REPORT_FILE"
    echo "Created temp branch: $TMP_BRANCH" | tee -a "$REPORT_FILE"

    # Create local bundle backup
    BUNDLE="/tmp/harness-backup-${TIMESTAMP}.bundle"
    git bundle create "$BUNDLE" --all
    echo "Backup bundle: $BUNDLE" | tee -a "$REPORT_FILE"

    # honour global DRY_RUN
    PREV_DRY_RUN="$DRY_RUN"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Running harness in DRY-RUN mode" | tee -a "$REPORT_FILE"
    fi

    case "$HARNESS_OP" in
        drop)
            echo "Running drop for commit: $HARNESS_ARG" | tee -a "$REPORT_FILE"
            # Capture exit code so we can differentiate conflict-stops and hard failures
            drop_single_commit "$HARNESS_ARG" 2>&1 | tee -a "$REPORT_FILE"
            rc=${PIPESTATUS[0]:-1}

            # If this was a dry-run and drop_single_commit printed the DRY-RUN marker, consider the dry-run simulated
            if [[ "$PREV_DRY_RUN" == "true" ]] && grep -q "DRY RUN: would drop commit" "$REPORT_FILE"; then
                echo "DRY-RUN: drop operation simulated (no changes applied)" | tee -a "$REPORT_FILE"
                # Capture post-op log snapshot
                POST_LOG="$REPORT_DIR/post-${TIMESTAMP}.log"
                git --no-pager log --oneline -n "${RESTORE_LIST_N}" > "$POST_LOG"
                echo "Post-op log (last ${RESTORE_LIST_N} commits):" | tee -a "$REPORT_FILE"
                sed 's/^/  /' "$POST_LOG" | tee -a "$REPORT_FILE"

                echo "DRY-RUN mode: skipping post-op verification checks (no changes were applied)" | tee -a "$REPORT_FILE"
                DRY_RUN="$PREV_DRY_RUN"
                return 0
            fi

            if [[ $rc -eq 0 ]]; then
                # Success
                :
            elif [[ $rc -eq 2 ]]; then
                echo "CONFLICT: Rebase stopped due to conflicts during drop; leaving temp branch for manual resolution" | tee -a "$REPORT_FILE"
                echo "Temp branch: $TMP_BRANCH" | tee -a "$REPORT_FILE"
                DRY_RUN="$PREV_DRY_RUN"
                return 1
            else
                echo "Drop failed" | tee -a "$REPORT_FILE"
                harness_restore_backup "$BUNDLE" "$REPORT_FILE"
                DRY_RUN="$PREV_DRY_RUN"
                return 1
            fi

            # Capture post-op log snapshot
            POST_LOG="$REPORT_DIR/post-${TIMESTAMP}.log"
            git --no-pager log --oneline -n "${RESTORE_LIST_N}" > "$POST_LOG"
            echo "Post-op log (last ${RESTORE_LIST_N} commits):" | tee -a "$REPORT_FILE"
            sed 's/^/  /' "$POST_LOG" | tee -a "$REPORT_FILE"

            if ! harness_post_checks "$HARNESS_ARG" "$REPORT_FILE"; then
                harness_restore_backup "$BUNDLE" "$REPORT_FILE"
                DRY_RUN="$PREV_DRY_RUN"
                return 1
            fi
            ;;
        sign)
            echo "Running sign for range: $HARNESS_ARG" | tee -a "$REPORT_FILE"
            # set RANGE for sign_mode and let sign_mode use DRY_RUN as appropriate
            OLD_RANGE="$RANGE"
            RANGE="$HARNESS_ARG"
            if ! sign_mode 2>&1 | tee -a "$REPORT_FILE"; then
                echo "Sign failed" | tee -a "$REPORT_FILE"
                harness_restore_backup "$BUNDLE" "$REPORT_FILE"
                RANGE="$OLD_RANGE"
                DRY_RUN="$PREV_DRY_RUN"
                return 1
            fi
            RANGE="$OLD_RANGE"
            ;;
        *)
            echo "Unknown harness operation: $HARNESS_OP" | tee -a "$REPORT_FILE"
            DRY_RUN="$PREV_DRY_RUN"
            return 1
            ;;
    esac

    DRY_RUN="$PREV_DRY_RUN"

    harness_finish_success "$TMP_BRANCH" "$REPORT_FILE"
    return 0
}
