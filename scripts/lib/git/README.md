# Git Library Modules

This directory contains modular bash libraries for git operations, organized by functionality.

## Structure

```
lib/git/
├── utils.sh      # Basic git checks and URL parsing
├── cleanup.sh    # Branch/tag cleanup utilities
├── worktree.sh   # Worktree discovery and sync
├── backup.sh     # Bundle creation and restoration
└── README.md     # This file
```

## Module Overview

### utils.sh
Core git detection and URL parsing functions. Source this first if other modules depend on basic git checks.

- `is_git_repo()` - Check if directory is a git repo
- `in_git_worktree()` - Check if inside git worktree
- `git_root()` - Get repository root
- `require_git_repo()` - Exit if not in repo
- `require_clean_worktree()` - Exit if uncommitted changes
- `require_gh_cli()` - Exit if gh CLI not installed/authed
- `get_remote_url()` - Get remote origin URL
- `parse_github_url()` - Extract owner/repo from URL

### cleanup.sh
Functions for cleaning up temporary branches, tags, and merged branches.

- `get_tmp_backup_tags/branches()` - Find tmp/backup refs
- `get_merged_local/remote_branches()` - Find merged branches
- `delete_local/remote_tags/branches()` - Delete refs
- `cleanup_tmp_backup_refs()` - Interactive cleanup
- `cleanup_merged_branches_interactive()` - Merged branch cleanup

### worktree.sh
Git worktree discovery and synchronization.

- `find_worktree_paths_for_branch()` - Find worktrees using branch
- `list_all_worktrees()` - List all worktree paths
- `get_worktree_branch()` - Get branch for worktree
- `update_worktrees_to_remote()` - Sync worktrees with remote
- `reset_worktree_to_ref()` - Reset worktree with backup

### backup.sh
Git bundle creation and restoration utilities.

- `create_backup_bundle()` - Full repo backup
- `create_branch_bundle()` - Single branch backup
- `list_backup_bundles()` - Find backup files
- `show_bundle_contents()` - List refs in bundle
- `verify_bundle()` - Validate bundle
- `unbundle()` - Restore from bundle
- `create_backup_tag()` - Tag current state
- `push_backup_tag()` - Push tag to remote

## Usage

```bash
# In your script:
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries (order matters)
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/print.sh"
source "$SCRIPT_DIR/lib/git/utils.sh"
source "$SCRIPT_DIR/lib/git/cleanup.sh"  # depends on print.sh
source "$SCRIPT_DIR/lib/git/worktree.sh" # depends on print.sh
source "$SCRIPT_DIR/lib/git/backup.sh"   # depends on print.sh
```

## Dependencies

All modules in this directory depend on:
- `lib/colors.sh` - Color definitions
- `lib/print.sh` - Print functions (`print_info`, `print_error`, etc.)

## Adding New Modules

When adding new modules:
1. Follow the existing naming convention (`lowercase-name.sh`)
2. Include header with usage, license, copyright
3. Document functions with `# Usage:` comments
4. Source print.sh for output functions
5. Update this README
