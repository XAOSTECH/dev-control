# git-control

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
  <a href="https://github.com/xaoscience/git-control/actions">
    <img alt="CI Status" src="https://img.shields.io/github/actions/workflow/status/xaoscience/git-control/ci.yml?branch=main&style=flat-square&logo=github-actions&label=CI">
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
- 📦 **Submodule Management** - Auto-generate and maintain `.gitmodules` for nested repos
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

# Re-run with
gc-alias && reload

# Reinstall all and automatically reload
gc-aalias

# Categories available:
# 1. Git Control (gc-*)   - git-control specific commands (gc-fix, gc-pr, gc-create, gc-mcp, etc.)
# 2. Git Shortcuts        - gs, ga, gc, gp, gl, etc.
# 3. Safety Nets          - rm -i, cp -i, mv -i
# 4. System Monitoring    - ports, meminfo, disk
# 5. Directory Operations - md, rd
# 6. Network Utilities    - myip, ping, fastping
# 7. Container Shortcuts  - dps, dpsa, drm, drmi
# 8. Quick Edits          - bashrc, reload
```

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

### History Fixing

Interactively rewrite commit history with date and message editing:

```bash
# Interactive mode - edit last 10 commits
gc-fix

# Or run directly
./scripts/fix-history.sh

# Specify custom range
./scripts/fix-history.sh --range HEAD~20

# Preview changes without applying
./scripts/fix-history.sh --dry-run

# Skip cleanup prompt at end of operation
./scripts/fix-history.sh --no-cleanup

# Only cleanup tmp/backup tags and branches (no other operations)
./scripts/fix-history.sh --cleanup-only

# Options:
#   -r, --range RANGE       Commit range (default: HEAD~10)
#   -d, --dry-run           Show changes without applying
#   -v, --verbose           Enable verbose output
#   --no-cleanup            Skip interactive cleanup prompt at end
#   --cleanup-only          Only perform cleanup (delete tmp/backup refs)
```

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

# What it does:
#   ✓ Authenticates with your GitHub account
#   ✓ Creates a Personal Access Token (PAT) with minimal required scopes
#   ✓ Sets 90-day expiration for security
#   ✓ Generates VS Code MCP settings with secure variable substitution
#   ✓ Offers interactive server selection:
#     • GitHub MCP (HTTP remote) - GitHub API access
#     • Stack Overflow MCP (HTTP remote) - Search Q&A
#     • Firecrawl MCP (Docker/NPX) - Web scraping and crawling
#   ✓ All servers appear consistently with MCP logo (no extension clutter)
#   ✓ Token is prompted per VS Code session (secure input)
```

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

# What it does:
#   ✓ Checks for rootless podman (installs if needed)
#   ✓ Detects system paths (GPG, podman socket, git config, etc.)
#   ✓ Generates .devcontainer/devcontainer.json with:
#     • Optimal mounts for GPG, docker/podman, git, wrangler
#     • Configured git user and **optional** GPG signing (script prompts for your key ID; no key material is embedded)
#     • Universal devcontainer image
#   ✓ Guides VSCode reopening with devcontainer activation
#   ✓ All configurations persist and work across sessions
```

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

Git-Control provides two ways to initialise templates via GitHub Actions:

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