# Dev-Control Shared Libraries

This directory contains shared Bash libraries that provide common functionality
across all Dev-Control scripts. Using these libraries ensures consistency,
reduces code duplication, and makes maintenance easier.

## Libraries

### colours.sh
ANSI colour code definitions for terminal output.

```bash
source "$SCRIPT_DIR/lib/colours.sh"
echo -e "${GREEN}Success!${NC}"
```

**Exports:** `RED`, `GREEN`, `YELLOW`, `BLUE`, `CYAN`, `MAGENTA`, `WHITE`, `BOLD`, `DIM`, `NC`, `RESET`, background colours, etc.

### print.sh
Consistent print functions for headers, messages, and formatting.

```bash
source "$SCRIPT_DIR/lib/colours.sh"  # Required first
source "$SCRIPT_DIR/lib/print.sh"

print_header "My Tool"
print_info "Starting..."
print_success "Done!"
print_header_success "Completed!"
```

**Functions:**
- `print_header "title"` - Blue header box
- `print_header_success "title"` - Green header box
- `print_header_warning "title"` - Yellow header box
- `print_info "msg"` - [INFO] message
- `print_success "msg"` - [SUCCESS] message
- `print_warning "msg"` - [WARNING] message
- `print_error "msg"` - [ERROR] message (stderr)
- `print_debug "msg"` - [DEBUG] message (if DEBUG=true)
- `print_step "msg"` - Step indicator
- `print_separator [width]` - Horizontal line
- `print_kv "key" "value"` - Key-value pair
- `print_section "title"` - Section header
- `print_menu_item "num" "desc"` - Numbered menu item
- `print_list_item "text"` - Bullet list item
- `print_detail "label" "value"` - Indented detail
- `print_command_hint "desc" "cmd"` - Command suggestion
- `print_box "text"` - Simple box around text
- `confirm "prompt" [default]` - Yes/no confirmation
- `read_input "prompt" "default"` - Input with default

### git-utils.sh
Git repository utilities and checks.

```bash
source "$SCRIPT_DIR/lib/git-utils.sh"

require_git_repo           # Exit if not in git repo
require_gh_cli             # Exit if gh not installed/authenticated
require_feature_branch     # Exit if on main/master

branch=$(get_current_branch)
owner=$(get_repo_owner)
```

**Functions:**
- `is_git_repo [dir]` - Check if directory is a git repo
- `in_git_worktree` - Check if in git worktree
- `git_root` - Get repository root path
- `require_git_repo` - Exit with error if not in repo
- `require_clean_worktree` - Exit if uncommitted changes
- `require_git` - Exit if git not installed
- `require_gh_cli` - Exit if gh not installed/authenticated
- `require_feature_branch` - Exit if on default branch
- `get_remote_url [dir]` - Get origin URL
- `parse_github_url "url"` - Extract owner/repo from URL
- `get_repo_owner [dir]` - Get GitHub owner
- `get_repo_name [dir]` - Get repository name
- `get_current_branch` - Get current branch name
- `get_default_branch` - Get main/master/Main
- `branch_exists "name"` - Check if local branch exists
- `remote_branch_exists "name"` - Check if remote branch exists
- `has_uncommitted_changes` - Check for uncommitted changes
- `has_staged_changes` - Check for staged changes
- `has_untracked_files` - Check for untracked files
- `list_submodules [dir]` - List all submodules
- `get_short_hash "ref"` - Get short commit hash
- `get_commit_subject "ref"` - Get commit message

### config.sh
Git-control metadata management via `dc-init.*` git config.

```bash
source "$SCRIPT_DIR/lib/config.sh"

load_gc_metadata  # Sets PROJECT_NAME, REPO_SLUG, etc.
save_gc_metadata "licence-type" "MIT"
```

**Functions:**
- `load_gc_metadata` - Load all dc-init.* values into variables
- `save_gc_metadata "key" "value"` - Save single value
- `save_all_gc_metadata` - Save all metadata variables
- `clear_gc_metadata` - Remove all dc-init.* config
- `get_gc_metadata "key"` - Get single value
- `has_gc_metadata` - Check if any metadata exists
- `show_gc_metadata` - Display all metadata

### licence.sh
Licence detection and management.

```bash
source "$SCRIPT_DIR/lib/licence.sh"

licence_info=$(detect_licence "/path/to/repo")
spdx=$(detect_spdx_from_content "/path/to/LICENSE")
```

**Functions:**
- `find_licence_file "dir"` - Find LICENSE file
- `detect_spdx_from_content "file"` - Detect SPDX ID from content
- `detect_local_licence "dir"` - Detect licence from local files
- `detect_github_licence "owner" "repo"` - Detect via GitHub API
- `detect_licence "dir"` - Full detection (local + remote)
- `scan_submodule_licences "dir" [recursive]` - Scan all submodules
- `check_licence_compatibility "target" "licences..."` - Check compatibility

### cli.sh
CLI argument parsing and script utilities.

```bash
source "$SCRIPT_DIR/lib/cli.sh"

SCRIPT_DIR=$(get_script_dir "${BASH_SOURCE[0]}")
parse_common_flags "$@"

if [[ "$SHOW_HELP" == "true" ]]; then
    show_help
    exit 0
fi
```

**Functions:**
- `resolve_script_path "path"` - Resolve symlinks
- `get_script_dir "path"` - Get directory containing script
- `is_flag "arg"` - Check if argument is a flag
- `parse_common_flags "args..."` - Parse -h, -v, --debug, --dry-run
- `dispatch_command "cmd" "args..."` - Run cmd_* function
- `is_devcontainer` - Check if running in devcontainer
- `is_interactive` - Check if running interactively
- `version_gte "v1" "v2"` - Compare semantic versions
- `git_version_at_least "version"` - Check git version

### validation.sh
Input validation helpers.

```bash
source "$SCRIPT_DIR/lib/validation.sh"

require_var "REPO_NAME" "$REPO_NAME"
require_command "jq"

if is_valid_slug "my-repo"; then
    echo "Valid!"
fi
```

**Functions:**
- `is_empty "str"` - Check if empty/whitespace
- `is_valid_identifier "str"` - Check alphanumeric+underscore
- `is_valid_slug "str"` - Check lowercase-with-hyphens
- `to_slug "str"` - Convert to slug
- `is_directory "path"` - Check if directory exists
- `is_file "path"` - Check if file exists
- `is_readable/is_writable "path"` - Check permissions
- `to_absolute_path "path"` - Convert to absolute
- `is_url/is_git_url/is_github_url "str"` - URL validation
- `is_positive_integer "str"` - Number validation
- `is_iso_date "str"` - Date validation
- `require_var "name" "value"` - Exit if empty
- `require_file "path"` - Exit if missing
- `require_directory "path"` - Exit if missing
- `require_command "cmd"` - Exit if not available

## Usage Pattern

All scripts should follow this pattern:

```bash
#!/usr/bin/env bash
set -e

# Get script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"

# Source shared libraries
source "$SCRIPT_DIR/lib/colours.sh"
source "$SCRIPT_DIR/lib/print.sh"
source "$SCRIPT_DIR/lib/git-utils.sh"  # Optional

# Your script code...
main() {
    print_header "My Tool"
    require_git_repo
    # ...
    print_header_success "Complete!"
}

main "$@"
```

## Line Savings Estimate

By using shared libraries, we eliminate redundant code across all scripts:

| Pattern | Occurrences | Lines Saved |
|---------|-------------|-------------|
| Hardcoded print_* functions | 3 scripts | ~60 lines |
| Hardcoded header boxes | 10 occurrences | ~40 lines |
| Git repo checks | 8 scripts | ~80 lines |
| URL parsing | 5 scripts | ~50 lines |
| Colour definitions | Previously inline | ~40 lines |
| Input validation | Various | ~30 lines |
| **Total** | | **~300 lines** |

More importantly, changes to common functionality now only need to be made in one place.
