# Git-Control

<!-- Project Shields/Badges -->
<p align="center">
  <a href="https://github.com/xaoscience/git-control">
    <img alt="GitHub repo" src="https://img.shields.io/badge/GitHub-xaoscience%2Fgit--control-181717?style=for-the-badge&logo=github">
  </a>
  <a href="https://github.com/xaoscience/git-control/releases">
    <img alt="GitHub release" src="https://img.shields.io/github/v/release/xaoscience/git-control?style=for-the-badge&logo=semantic-release&color=blue">
  </a>
  <a href="https://github.com/xaoscience/git-control/blob/main/LICENSE">
    <img alt="License" src="https://img.shields.io/github/license/xaoscience/git-control?style=for-the-badge&color=green">
  </a>
</p>

<p align="center">
  <a href="https://github.com/xaoscience/git-control/actions/workflows/bash-lint.yml">
    <img alt="CI Status" src="https://github.com/xaoscience/git-control/actions/workflows/bash-lint.yml/badge.svg?branch=Main">
  </a>
  <a href="https://github.com/xaoscience/git-control/issues">
    <img alt="Issues" src="https://img.shields.io/github/issues/xaoscience/git-control?style=flat-square&logo=github&color=yellow">
  </a>
  <a href="https://github.com/xaoscience/git-control/pulls">
    <img alt="Pull Requests" src="https://img.shields.io/github/issues-pr/xaoscience/git-control?style=flat-square&logo=github&color=purple">
  </a>
  <a href="https://github.com/xaoscience/git-control/stargazers">
    <img alt="Stars" src="https://img.shields.io/github/stars/xaoscience/git-control?style=flat-square&logo=github&color=gold">
  </a>
  <a href="https://github.com/xaoscience/git-control/network/members">
    <img alt="Forks" src="https://img.shields.io/github/forks/xaoscience/git-control?style=flat-square&logo=github">
  </a>
</p>

<p align="center">
  <img alt="Last Commit" src="https://img.shields.io/github/last-commit/xaoscience/git-control?style=flat-square&logo=git&color=blue">
  <img alt="Repo Size" src="https://img.shields.io/github/repo-size/xaoscience/git-control?style=flat-square&logo=files&color=teal">
  <img alt="Code Size" src="https://img.shields.io/github/languages/code-size/xaoscience/git-control?style=flat-square&logo=files&color=orange">
  <img alt="Contributors" src="https://img.shields.io/github/contributors/xaoscience/git-control?style=flat-square&logo=github&color=green">
</p>

<p align="center">
  <img alt="Stability" src="https://img.shields.io/badge/stability-experimental-orange?style=flat-square">
  <img alt="Maintenance" src="https://img.shields.io/maintenance/yes/2025?style=flat-square">
  <img alt="Shell" src="https://img.shields.io/badge/shell-bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white">
</p>

---

<p align="center">
  <b>🛠️ A collection of powerful CLI tools and scripts for streamlined Git workflow, repository management, and shell productivity.</b>
</p>

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Features](#-features)
- [Installation](#-installation)
- [Usage](#-usage)
- [Scripts](#-scripts)
- [Documentation](#-documentation)
- [Contributing](#-contributing)
- [Roadmap](#-roadmap)
- [Support](#-support)
- [License](#-license)

---

## 🔍 Overview

**Git-Control** is a comprehensive toolkit designed to enhance your Git and shell workflow. It provides:

- **Alias Management**: Interactive setup of productivity-boosting shell aliases
- **Template Loading**: Quick initialisation of new repositories with standardised templates
- **Module Nesting**: Automated management of Git submodules in complex project hierarchies
- **Workflow Templates**: Pre-configured GitHub Actions for common automation tasks

### Why git-control?

Managing multiple repositories, nested submodules, and maintaining consistent configurations across projects is time-consuming and error-prone. Git-Control automates these tasks while remaining portable and easy to share across systems.

---

## ✨ Features

- 🚀 **Interactive Alias Installer** - Dynamically detects script paths and creates portable aliases
- 🔧 **Template System** - Initialise repos with docs, workflows, and configuration templates
- 📦 **Submodule Management** - Auto-generate `.gitmodules` and maintain `.tmp` for nested repos
- 🔒 **Safety Aliases** - Protective wrappers for dangerous commands (`rm`, `mv`, `cp`)
- ⚡ **Git Shortcuts** - Optimised aliases for common Git operations
- 🐳 **Container Shortcuts** - Quick access to Docker/Podman commands
- 🌐 **Network Utilities** - IP checking, port monitoring, and connectivity tools
- 📁 **Directory Operations** - Enhanced navigation and file management
- 🤖 **GitHub MCP Setup** - Automated GitHub MCP server configuration for VS Code with secure token management
- 🐳 **Devcontainer Setup** - Auto-configure rootless podman and generate optimised devcontainer.json with secure mounts

---

## 📥 Installation

### Prerequisites

- Bash 4.0+ or Zsh
- Git 2.0+
- Standard Unix utilities (`find`, `sed`, `grep`)

### Quick Start

```bash
# Clone the repository
git clone https://github.com/xaoscience/git-control.git
cd git-control

# Run the interactive alias installer
./scripts/alias-loading.sh

# Or run individual scripts
./scripts/template-loading.sh
./scripts/module-nesting.sh
```

### Manual Installation

```bash
# Add to your .bashrc or .bash_profile
source /path/to/git-control/scripts/alias-loading.sh --source-only
```

---

## 🚀 Usage

### Main Menu

Use the main `git-control.sh` wrapper to access all tools via interactive menu:

```bash
# Interactive menu - choose any tool
./scripts/git-control.sh

# Or use the alias (after running alias-loading.sh)
gc-control

# Direct command mode - skip the menu
./scripts/git-control.sh repo      # Create repository
./scripts/git-control.sh pr        # Create pull request
./scripts/git-control.sh fix       # Fix commit history
```

### Alias Loading

```bash

# Interactive installation - choose which alias categories to install
./scripts/alias-loading.sh && source ~/.bashrc

# Reinstall all and automatically reload
gc-aalias
```

### Alias Usage

**Categories:**

| Category | Commands / Notes |
| --- | --- |
| **Git Control (gc-*)** | `gc-fix`, `gc-pr`, `gc-create`, `gc-mcp` |
| **Git Shortcuts** | `gs`, `ga`, `gc`, `gp`, `gl` |
| **Safety Nets** | `rm -i`, `cp -i`, `mv -i` under aliases of `rm`, `cp`, `mv`|
| **System Monitoring** | `ports`, `meminfo`, `disk` |
| **Directory Operations** | `md`, `rd`, `..`, `ll` |
| **Network Utilities** | `myip`, `ping`, `fastping` |
| **Container Shortcuts** | `dps`, `dpsa`, `drm`, `drmi` |
| **Quick Edits** | `bashrc`, `reload` |

**Examples**

```bash
# Git commit amend (no edit) and push force
gca

# Similar amend, with original author date (also restores it after gca)
gcda

# Git push force with lease
gcpf

# Decorated, oneline Git log
gl
```

*Tip: run `./scripts/alias-loading.sh` and `source ~/.bashrc` to install or refresh aliases.*
### Template Loading

Allows for creation of new $NAME-templates folders, which will be copied by default.

```bash
# Interactive mode - initialise a new repo with templates
gc-init

# Or run directly
./scripts/template-loading.sh

# CLI mode - update specific files with path support
./scripts/template-loading.sh -f docs/CONTRIBUTING.md,docs/SECURITY.md -o

# CLI options:
#   -f, --files FILE1,FILE2    Process specific files (supports paths like docs/FILE.md)
#   -o, --overwrite            Overwrite existing files without prompting
#   -h, --help                 Show help and list available templates
```

### Repository Creation

```bash
# Interactive creation of new GitHub repository
gc-create

# Or run directly
./scripts/create-repo.sh
```

### Pull Request Creation

```bash
# Interactive creation of pull request from current branch
gc-pr

# Or run directly
./scripts/create-pr.sh
```

### Module Nesting

```bash
# Scan current directory for git repos and generate .gitmodules
gc-modules

# Or run directly
./scripts/module-nesting.sh

# Specify a custom root directory
./scripts/module-nesting.sh /path/to/project
```

#### Extra features

Use the action flags below to manage per-module temporary folders after module-nesting (e.g. `--copy-temp`) or independently (e.g. `--only-copy-temp`). All flows support `--dry-run` for safe previews.

##### Feature breakdown

- `--copy-temp` / `--only-copy-temp`
  - What it does: Collects temporary folders (e.g., `.tmp`, `tmp`, `.temp`) and merges their contents into per-parent directories under `
`$ROOT/.tmp/<parent>` non-destructively (does not overwrite existing files).
  - When to use: Consolidate per-module temporary build outputs for cleanup or archiving.
  - Preview: `./scripts/module-nesting.sh --only-copy-temp --dry-run /path/to/project`

- `--prune` / `--only-prune`
  - What it does: Moves originals to a recycle location (or deletes with `--delete`) and replaces originals with symlinks pointing at `
`$ROOT/.tmp/<parent>`.
  - If no copied record exists, `--only-prune --dry-run` simulates a `--only-copy-temp --dry-run` `
`$ROOT/.tmp/<parent>` destinations rather than ephemeral `/tmp` paths.
  - Preview: `./scripts/module-nesting.sh --only-prune --dry-run /path/to/project`

- `--aggressive`
  - What it does: Merges temp folders into `
`$ROOT/.tmp/<parent>`, removes original temp folders, replaces them with directory symlinks, and appends entries to the nearest `.gitignore` (except for folders named `.tmp`).
  - Preview: `./scripts/module-nesting.sh --aggressive --dry-run /path/to/project` (reports merges, removals, and `.gitignore` changes; reports `already contains` when no change is needed)

- `--dry-run` behavior
  - Use `--dry-run` with any flow to preview actions without modifying your workspace.
  - `.gitmodules` generation now respects `--dry-run` and will report file writes/removals; enable `DEBUG=true` to preview content snippets during a dry-run.

- `--test`
  - Runs a safe `copy-temp` → `prune` → `aggressive` sequence in `--dry-run` mode: `./scripts/module-nesting.sh --test`

Examples:

```bash
# Preview .gitmodules generation without making changes
./scripts/module-nesting.sh --dry-run /path/to/project -y

# Preview copy -> prune -> aggressive sequence
./scripts/module-nesting.sh --test

# Preview aggressive changes (including .gitignore simulation)
./scripts/module-nesting.sh --aggressive --dry-run /path/to/project
```

> Tip: Run with `DEBUG=true` (for example `DEBUG=true ./scripts/module-nesting.sh --dry-run /path -y`) for additional diagnostic output and a content preview of simulated `.gitmodules`.




### History Fixing

Interactively rewrite commit history with fine-grained control over commit messages, author/committer dates, signing and reconstruction strategies.

##### Feature breakdown

- `--range` / `-r`
  - Select a commit range to operate on (default: `HEAD=10`). Examples: `HEAD=5`, `main..HEAD`, `abc123..def456`.

- `--amend` / `-a`
  - Amend a non-tip commit while preserving dates and optionally signing the amended commit. Example: `--amend HEAD=2`.

- `--sign` / `--atomic-preserve`
  - `--sign`: re-sign commits in the selected range (requires GPG).
  - `--atomic-preserve`: recreate commits deterministically (including merges) with `git commit-tree`, sign them and set author/committer dates atomically.

- `--drop`
  - Remove a single non-root commit from history (specify commit hash).

- Harness & safety helpers (`--harness-drop`, `--harness-sign`, `--harness-no-cleanup`)
  - Run minimal harnesses that apply operations safely in a temporary branch and produce a backup bundle for inspection.

- Conflict & reconstruction options (`--auto-resolve`, `--reconstruct-auto`, `--allow-override`)
  - `--auto-resolve <ours|theirs>` will auto-add conflicted files using the chosen strategy during rebase.
  - `--reconstruct-auto` retries reconstruction with common strategies on failure.
  - `--allow-override` skips confirmation when replacing the original branch with a temporary branch.

- Worktree & restore helpers (`--update-worktrees`, `--restore`)
  - `--update-worktrees` detects local worktrees with the branch checked out and updates them safely (creates bundle backup).
  - `--restore` lists and restores backup bundles/tags interactively.

- Dry-run & diagnostic (`-d`, `--dry-run`, `-v`)
  - Use `--dry-run` to preview all changes without applying them; `-v` or `--verbose` increases diagnostic output.

- Stash support (`-s`)
  - `--stash N` lets you selectively apply files from `stash@{N}` into the rewritten commits.

- Cleanup options (`--no-cleanup`, `--only-cleanup`)
  - `--no-cleanup`: skip the interactive cleanup prompt at the end of a run and do not offer to delete temporary backup refs or branches.
  - `--only-cleanup`: only perform cleanup of temporary tags, bundles and backup branches (useful to tidy harness artifacts after a failed run).

##### Env vars vs CLI flags

Most behaviours are available either via environment variables or equivalent CLI flags. Common env vars you may use are: `PRESERVE_TOPOLOGY`, `UPDATE_WORKTREES`, `NO_EDIT_MODE`, `AUTO_FIX_REBASE`, `RECONSTRUCT_AUTO` — you can set these in your shell or pass the corresponding flags when invoking the script.

##### Examples

```bash
# Interactive: edit the last 10 commits
./scripts/fix-history.sh

# Preview changes without applying
./scripts/fix-history.sh --dry-run --range HEAD=20

# Re-sign an entire branch and show verbose output
./scripts/fix-history.sh --sign --range HEAD=all -v

# Use env-vars (equivalent to flags) for a non-interactive run
PRESERVE_TOPOLOGY=TRUE UPDATE_WORKTREES=true NO_EDIT_MODE=true AUTO_FIX_REBASE=true RECONSTRUCT_AUTO=true \
  ./scripts/fix-history.sh --sign --range HEAD=all -v
```

> Tip: When experimenting with large-scale rewrites, prefer `--dry-run` and harness modes to capture backups before making changes.
### GitHub MCP Server Setup

Automatically configure GitHub MCP and additional MCP servers for VS Code with secure token management:

```bash
# Full interactive setup - initialize MCP and configure servers
gc-mcp

# Or run directly
./scripts/mcp-setup.sh

# Configuration-only mode (with existing token)
./scripts/mcp-setup.sh --config-only

# Test existing MCP connection
./scripts/mcp-setup.sh --test

# Show current token info (masked)
./scripts/mcp-setup.sh --show-token

# Options:
#   (no args)           Initialize MCP and select servers to install (DEFAULT)
#   --config-only       Only generate MCP base configuration
#   --test              Test GitHub MCP connection
#   --show-token        Display current token info (masked)
#   --help              Show help message
```
#### What it does:
- ✅ Authenticates with your GitHub account
- ✅ Creates a Personal Access Token (PAT) with minimal required scopes
- ✅ Sets a 90-day expiration policy for security
- ✅ Generates VS Code MCP settings with secure variable substitution:
  - Optimal mounts for GPG, docker/podman, git, wrangler
  - Configured git user and optional GPG signing (script prompts for your key ID; no key material is embedded)
- ✅ Offers interactive server selection:
  - GitHub MCP (HTTP remote) — GitHub API access
  - Stack Overflow MCP (HTTP remote) — Search Q&A
  - Firecrawl MCP (Docker/NPX) — Web scraping and crawling
- ✅ All servers appear consistently as manually installed
- ✅ Token is saved in the system keychain or prompted per VS Code session (secure input)

### Devcontainer Setup

Auto-configure rootless podman and generate optimised `.devcontainer/devcontainer.json`:

```bash
# Interactive setup - detects project path or prompts for input
gc-contain

# Or run directly
./scripts/containerise.sh

# Specify custom project path
./scripts/containerise.sh /path/to/project

# Options:
#   (no args)           Uses current directory
#   /path/to/project    Specify custom project path
#   --help              Show help message
```

#### What it does:
- ✅ Checks for rootless podman (installs if needed)
- ✅ Detects system paths (GPG, podman socket, git config, etc.)
- ✅ Generates `.devcontainer/devcontainer.json` with:
  - Optimal mounts for GPG, docker/podman, git, wrangler
  - Configured git user and optional GPG signing (script prompts for your key ID; no key material is embedded)
  - Universal devcontainer image
- ✅ Guides VS Code reopening with devcontainer activation
- ✅ Ensures configurations persist and work across sessions

---

## 📜 Scripts

| Script | Description |
|--------|-------------|
| [`git-control.sh`](../scripts/git-control.sh) | **Main entry point** - Interactive menu for all tools |
| [`alias-loading.sh`](../scripts/alias-loading.sh) | Interactive alias installer with category selection |
| [`template-loading.sh`](../scripts/template-loading.sh) | Repository template initialisation tool |
| [`create-repo.sh`](../scripts/create-repo.sh) | Interactive GitHub repository creator |
| [`create-pr.sh`](../scripts/create-pr.sh) | Interactive pull request creator |
| [`module-nesting.sh`](../scripts/module-nesting.sh) | Automated `.gitmodules` generator for nested repos |
| [`fix-history.sh`](../scripts/fix-history.sh) | Interactive commit history rewriting tool |
| [`mcp-setup.sh`](../scripts/mcp-setup.sh) | GitHub & additional MCP server setup for VS Code with token management |
| [`containerise.sh`](../scripts/containerise.sh) | Rootless podman setup and devcontainer.json generator with mount configuration |

### Doc Templates

| Template | Description |
|----------|-------------|
| [`README.md`](../docs-templates/README.md) | Full-featured README with badges and sections |
| [`CONTRIBUTING.md`](../docs-templates/CONTRIBUTING.md) | Contribution guidelines template |
| [`CODE_OF_CONDUCT.md`](../docs-templates/CODE_OF_CONDUCT.md) | Community code of conduct |
| [`SECURITY.md`](../docs-templates/SECURITY.md) | Security policy template |

### License Templates

| Template | Description |
|----------|-------------|
| [`Apache License 2.0`](../license-templates/Apache-2.0) | Permissive with explicit patent grant and NOTICE handling |
| [`BSD 3-Clause`](../license-templates/BSD-3-Clause) | Permissive license with non-endorsement clause |
| [`GNU GPL v3.0`](../license-templates/GPL-3.0) | Strong copyleft — modifications must be released under GPLv3 |
| [`MIT License`](../license-templates/MIT) | Very permissive, minimal requirements |

### GitHub Templates

| Template | Description |
|----------|-------------|
| [`ISSUE_TEMPLATE/bug_report.md`](../github-templates/ISSUE_TEMPLATE/bug_report.md) | Bug report issue template |
| [`ISSUE_TEMPLATE/feature_request.md`](../github-templates/ISSUE_TEMPLATE/feature_request.md) | Feature request issue template |
| [`PULL_REQUEST_TEMPLATE.md`](../github-templates/PULL_REQUEST_TEMPLATE.md) | Pull request template |

### Workflow Templates

| Workflow | Description |
|----------|-------------|
| [`dependabot-automerge.yml`](../workflows-templates/dependabot-automerge.yml) | Auto-merge Dependabot PRs |
| [`init.yml`](../workflows-templates/init.yml) | Standalone workflow - copy to any repo |
| [`remote-init.yml`](../workflows-templates/remote-init.yml) | Calls the reusable workflow remotely |

### Workflows

| Workflow | Description |
|----------|-------------|
| [`central-loader.yml`](../.github/workflows/central-loader.yml) | Reusable workflow (call from other repos) |

---

## 🔄 GitHub Actions Workflows

In addition to initialising from local (gc-init), Git-Control provides two ways to initialise templates via GitHub Actions:

### Option 1: Standalone Workflow (Recommended)

Copy `workflows-templates/init.yml` to your repo's `.github/workflows/` folder.

```bash
# From your target repository
mkdir -p .github/workflows
curl -sL https://raw.githubusercontent.com/xaoscience/git-control/main/workflows-templates/init.yml \
  -o .github/workflows/init.yml
git add .github/workflows/init.yml
git commit -m "Add template initialisation workflow"
git push
```

Then go to **Actions** → **Initialise Repository Templates** → **Run workflow**

### Option 2: Reusable Workflow (Remote)

Copy `workflows-templates/remote-init.yml` or call git-control's reusable workflow directly:

```yaml
# .github/workflows/remote-init.yml
name: Initialise Documentation

on:
  workflow_dispatch:

permissions:
  contents: write
  pull-requests: write

jobs:
  init-templates:
    uses: xaoscience/git-control/.github/workflows/central-loader.yml@main
    with:
      project_name: 'My Project'
      short_description: 'A cool project'
      license_type: 'MIT'
      stability: 'experimental'
      templates: 'all'
      create_pr: true
```

### Workflow Features

- ✅ **No PAT required** - Uses standard `GITHUB_TOKEN`
- ✅ **Creates PR by default** - Review before merging
- ✅ **Configurable** - Choose templates, license, stability
- ✅ **Auto-populates** - Fills in repo name, org, URLs automatically
- ✅ **Dynamic folders** - Scans all `*-templates` folders for future expansion

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [📖 README](docs/README.md) | This file - project overview |
| [🤝 Contributing](docs/CONTRIBUTING.md) | How to contribute |
| [📜 Code of Conduct](docs/CODE_OF_CONDUCT.md) | Community guidelines |
| [🔒 Security](docs/SECURITY.md) | Security policy |

---

## 🤝 Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting PRs.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

See also: [Code of Conduct](CODE_OF_CONDUCT.md) | [Security Policy](SECURITY.md)

---

## 🗺️ Roadmap

- [x] Core alias loading script with interactive selection
- [x] Template system for repository documentation
- [x] Submodule nesting management
- [x] Dependabot automerge workflow
- [x] GitHub Actions workflow for remote template initialisation
- [x] Reusable workflow for cross-repo template loading
- [ ] Zsh compatibility layer
- [ ] Fish shell support
- [ ] GUI wrapper (optional)
- [ ] Plugin system for custom alias categories
- [ ] Config file support for persistent preferences

See the [open issues](https://github.com/xaoscience/git-control/issues) for a full list of proposed features and known issues.

---

## 💬 Support

- 💻 **Issues**: [GitHub Issues](https://github.com/xaoscience/git-control/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/xaoscience/git-control/discussions)

---

## 📄 License

Distributed under the GPL-3.0 License. See [`LICENSE`](../LICENSE) for more information.

---

<p align="center">
  <a href="https://github.com/xaoscience">
    <img src="https://img.shields.io/badge/Made%20with%20%E2%9D%A4%EF%B8%8F%20by-xaoscience-red?style=for-the-badge">
  </a>
</p>

<p align="center">
  <a href="#git-control">⬆️ Back to Top</a>
</p>