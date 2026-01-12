# Git-Control Shared Libraries

This directory contains shared shell libraries that provide reusable functionality across all git-control scripts.

## Libraries

### colors.sh
ANSI color definitions for terminal output.

| Variable | Description |
|----------|-------------|
| `RED`, `GREEN`, `YELLOW`, `BLUE`, `CYAN` | Basic colors |
| `BOLD`, `NC` | Bold and reset |

### print.sh
Consistent terminal output formatting.

| Function | Description |
|----------|-------------|
| `print_header "Title"` | Blue header box |
| `print_header_success "Title"` | Green header box |
| `print_header_warning "Title"` | Yellow header box |
| `print_info "message"` | Info message |
| `print_success "message"` | Success message |
| `print_warning "message"` | Warning message |
| `print_error "message"` | Error message (stderr) |
| `print_debug "message"` | Debug message (if DEBUG=true) |
| `print_step "Step"` | Step indicator |
| `print_separator [width]` | Separator line |
| `print_kv "Key" "Value"` | Key-value pair |
| `print_list_item "Item"` | Bullet list item |
| `print_detail "Label" "Value"` | Indented detail |
| `print_menu_item "1" "Desc"` | Numbered menu item |
| `print_section "Title"` | Section header |
| `print_command_hint "desc" "cmd"` | Command hint |
| `print_box "text"` | Simple box |
| `confirm "Proceed?"` | Yes/no prompt |
| `read_input "Prompt" "default"` | Input with default |
| `run_with_spinner "cmd" "msg"` | Spinner animation |

### git-utils.sh
Git repository utilities and requirement checks.

| Function | Description |
|----------|-------------|
| `is_git_repo [dir]` | Check if directory is git repo |
| `in_git_worktree` | Check if in git worktree |
| `git_root` | Get repo root directory |
| `require_git_repo` | Exit if not in git repo |
| `require_clean_worktree` | Exit if uncommitted changes |
| `require_gh_cli` | Exit if gh not installed |
| `require_git` | Exit if git not installed |
| `get_remote_url [dir]` | Get remote origin URL |
| `parse_github_url "url"` | Extract owner/repo from URL |
| `get_repo_owner [dir]` | Get owner from remote |
| `get_repo_name [dir]` | Get repo name from remote |
| `get_current_branch` | Get current branch name |
| `get_default_branch` | Get default branch |
| `branch_exists "branch"` | Check if local branch exists |
| `remote_branch_exists "branch"` | Check if remote branch exists |
| `require_feature_branch` | Exit if on default branch |
| `has_uncommitted_changes` | Check for uncommitted changes |
| `has_staged_changes` | Check for staged changes |
| `has_untracked_files` | Check for untracked files |
| `get_status_summary` | Get status counts |
| `get_relative_path "parent" "child"` | Get relative path |
| `list_submodules [dir]` | List submodules |
| `is_submodule "path"` | Check if path is submodule |
| `get_short_hash "ref"` | Get short commit hash |
| `get_commit_subject "ref"` | Get commit subject |
| `get_commit_author "ref"` | Get commit author |
| `get_commit_date "ref"` | Get commit date |

### cli.sh
CLI argument parsing and script utilities.

| Function | Description |
|----------|-------------|
| `resolve_script_path "path"` | Resolve symlinks |
| `get_script_dir "path"` | Get script directory |
| `is_flag "arg"` | Check if argument is a flag |
| `flag_has_value "next"` | Check if flag has value |
| `parse_common_flags "$@"` | Parse -h, -v, -n, --debug |
| `dispatch_command "cmd"` | Run cmd_* function |
| `is_devcontainer` | Check if in devcontainer |
| `is_interactive` | Check if interactive terminal |
| `should_use_colors` | Check if colors enabled |
| `version_gte "v1" "v2"` | Compare versions |
| `get_git_version` | Get git version |
| `git_version_at_least "v"` | Check git version |

### validation.sh
Input validation and sanitization.

| Function | Description |
|----------|-------------|
| `is_empty "string"` | Check if empty/whitespace |
| `is_valid_identifier "str"` | Check valid identifier |
| `is_valid_slug "str"` | Check valid slug |
| `to_slug "string"` | Convert to slug |
| `is_directory "path"` | Check if directory exists |
| `is_file "path"` | Check if file exists |
| `is_readable "path"` | Check if readable |
| `is_writable "path"` | Check if writable |
| `to_absolute_path "path"` | Resolve to absolute |
| `is_url "string"` | Check if URL |
| `is_git_url "string"` | Check if git URL |
| `is_github_url "string"` | Check if GitHub URL |
| `is_positive_integer "n"` | Check positive integer |
| `is_non_negative_integer "n"` | Check non-negative |
| `in_range "val" "min" "max"` | Check value in range |
| `is_iso_date "str"` | Check ISO date format |
| `is_iso_datetime "str"` | Check ISO datetime |
| `require_var "name" "val"` | Exit if var empty |
| `require_file "path"` | Exit if file missing |
| `require_directory "path"` | Exit if dir missing |
| `require_command "cmd"` | Exit if cmd missing |

### config.sh
Configuration loading utilities.

### license.sh
License handling utilities.

## Usage

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/print.sh"
source "$SCRIPT_DIR/lib/git-utils.sh"
source "$SCRIPT_DIR/lib/cli.sh"
source "$SCRIPT_DIR/lib/validation.sh"

# Now use shared functions
require_git_repo
print_header "My Script"
if confirm "Continue?"; then
    print_success "Done!"
fi
```

## Function Usage Statistics

After PR #4 refactoring:

| Function | Usage Count | Scripts |
|----------|-------------|----------|
| `print_header` | 15+ | All scripts |
| `print_menu_item` | 40+ | All interactive scripts |
| `print_section` | 25+ | All scripts |
| `print_command_hint` | 20+ | Help functions |
| `print_detail` | 30+ | fix-history, template-loading |
| `confirm` | 10+ | Interactive scripts |
| `require_git_repo` | 5 | create-pr, fix-history, etc. |
| `is_file` / `is_directory` | 25+ | template-loading, module-nesting |
| `is_empty` | 15+ | module-nesting, validation |

## Estimated Line Savings

| Pattern | Lines Saved |
|---------|-------------|
| Hardcoded print_* functions | ~100 lines |
| Hardcoded header boxes | ~60 lines |
| Git repo checks | ~100 lines |
| Validation checks | ~80 lines |
| Menu item formatting | ~50 lines |
| **Total** | **~390+ lines** |

## SPDX Compliance

All libraries include SPDX headers:
```bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024-2026 xaoscience
```
