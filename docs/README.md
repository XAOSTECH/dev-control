# Dev-Control

<!-- Project Shields/Badges -->
<p align="center">
  <a href="https://github.com/xaostech/dev-control">
    <img alt="GitHub repo" src="https://img.shields.io/badge/GitHub-xaostech%2Fdev--control-181717?style=for-the-badge&logo=github">
  </a>
  <a href="https://github.com/xaostech/dev-control/releases">
    <img alt="GitHub release" src="https://img.shields.io/github/v/release/xaostech/dev-control?style=for-the-badge&logo=semantic-release&color=blue">
  </a>
  <a href="https://github.com/xaostech/dev-control/blob/main/LICENSE">
    <img alt="License" src="https://img.shields.io/github/license/xaostech/dev-control?style=for-the-badge&color=green">
  </a>
</p>

<p align="center">
  <a href="https://github.com/xaostech/dev-control/actions/workflows/bash-lint.yml">
    <img alt="CI Status" src="https://github.com/xaostech/dev-control/actions/workflows/bash-lint.yml/badge.svg?branch=Main">
  </a>
  <a href="https://github.com/xaostech/dev-control/issues">
    <img alt="Issues" src="https://img.shields.io/github/issues/xaostech/dev-control?style=flat-square&logo=github&color=yellow">
  </a>
  <a href="https://github.com/xaostech/dev-control/pulls">
    <img alt="Pull Requests" src="https://img.shields.io/github/issues-pr/xaostech/dev-control?style=flat-square&logo=github&color=purple">
  </a>
  <a href="https://github.com/xaostech/dev-control/stargazers">
    <img alt="Stars" src="https://img.shields.io/github/stars/xaostech/dev-control?style=flat-square&logo=github&color=gold">
  </a>
</p>

<p align="center">
  <img alt="Last Commit" src="https://img.shields.io/github/last-commit/xaostech/dev-control?style=flat-square&logo=git&colour=blue">
  <img alt="Shell" src="https://img.shields.io/badge/shell-bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white">
  <img alt="Stability" src="https://img.shields.io/badge/stability-experimental-orange?style=flat-square">
  <img alt="Maintenance" src="https://img.shields.io/maintenance/yes/2026?style=flat-square">
</p>

---

**Dev-Control** is a modular CLI toolkit that automates customising and setting up repos (100% community standards), nested gitmodules, centralised and cleaned up .tmp and .bak folders, nested rootless podman docker containers, vscode mcp-servers, GitHub release (with lib tarbal, re-releases, automated version tagging and signed latest + version tag) and app packages.

This attempts to make arduous CLI and Git tasks (such as signing woktrees with topology and surgically dropping commits) easy and robust, so you can focus on your code - while, ironically, I focus on optimising this. All functions have a --dry-run option, so test it out and feel free to let me know of any issues or requests! Contributions are also lauded!  

```bash
# Install
git clone https://github.com/xaostech/dev-control.git && cd dev-control && ./install.sh

# Use
dc init          # Set up a repo with templates, license, docs
dc repo          # Create a GitHub repo from your local project
dc pr            # Open a pull request in seconds
dc fix           # Rewrite/sign/clean commit history safely
dc modules       # Manage nested submodules automatically
dc licenses      # Audit license compliance across repos
dc mcp           # Configure AI coding assistants (MCP servers)
dc contain       # Generate devcontainer.json for VS Code
dc package       # Build tarballs, Homebrew, Snap, Deb, Nix, Docker
dca-alias        # Sync (all) new alias and reload bashrc

```

---

## 📋 Table of Contents

- [Why Dev-Control?](#-why-dev-control)
- [Features at a Glance](#-features-at-a-glance)
- [Quick Start](#-quick-start)
- [Core Commands](#-core-commands)
- [Plugin System](#-plugin-system)
- [Configuration](#-configuration)
- [Documentation](#-documentation)
- [Contributing](#-contributing)
- [Roadmap](#-roadmap)
- [License](#-license)

---

## 💡 Why Dev-Control?

Managing modern software projects involves a lot of repetitive housekeeping:

- Initialising repos with consistent templates, licenses, and docs
- Keeping submodules in sync across complex monorepos
- Rewriting commit history to fix author dates or add GPG signatures
- Auditing license compliance when you have dozens of dependencies
- Making devcontainers with the right mounts and settings and reusable category images
- Packaging your tool for multiple platforms (Homebrew, Snap, Nix, Docker…)

**Dev-Control bundles all of this into a single, modular CLI.** Each command is designed to be:

| Principle | How |
|-----------|-----|
| **Safe** | Dry-run modes, automatic backup bundles, harness wrappers |
| **Fast** | Batch processing, parallel operations, minimal dependencies |
| **Extensible** | Plugin system, YAML config, themeable TUI |
| **Portable** | Pure Bash 4+, no exotic runtime, runs anywhere Git runs |

---

## ✨ Features at a Glance

| Category | What You Get |
|----------|--------------|
| **Repo Setup** | Template loading, license selection, README/CONTRIBUTING/SECURITY scaffolding, GitHub Actions workflows |
| **Git Ops** | History rewriting with GPG signing, date preservation, conflict auto-resolution, worktree sync |
| **Submodules** | Auto-generated `.gitmodules`, temp-folder consolidation, symlink pruning |
| **Licensing** | SPDX detection, compatibility checking, bulk apply, JSON export |
| **DevEx** | Devcontainer generation, MCP server setup (GitHub, StackOverflow, Firecrawl) |
| **Packaging** | Tarball + SHA256, Homebrew formula, Snap YAML, Debian `.deb`, Nix flake, Docker + ttyd web terminal |
| **TUI Themes** | Matrix, Hacker, Cyber aesthetics powered by [Charmbracelet Gum](https://github.com/charmbracelet/gum) |

---

## 🚀 Quick Start

### Prerequisites

- **Bash 4.0+** or Zsh
- **Git 2.0+**
- **GitHub CLI** (`gh`) for repo/PR commands
- Optional: `gum` or `fzf` for interactive TUI; GPG for signing

### Install

```bash
git clone https://github.com/xaostech/dev-control.git
cd dev-control
./install.sh          # Adds `dc` to your PATH and installs aliases
source ~/.bashrc      # Or restart your shell
```

### Verify

```bash
dc --version          # Should print v2.x.x
dc --help             # List all commands
```

---

## 🔧 Core Commands

Below is a quick reference. Run `dc <command> --help` for full options.

### `dc aliases` — Shell Alias Installer

Add productivity aliases for Git, Docker, system monitoring, and more.

```bash
dc alias    # Interactive category selection
source ~/.bashrc
```

#### Example aliases

```bash
gpf         # git push --force-with-lease
dca-alias   # Apply and source all aliases
gcda        # Stage, amend and push with preserved author date
gcda        # Restore original author date
```

### `dc init` — Repository Initialisation

Populate a repo with docs, license, workflows, and GitHub templates.

```bash
dc init                     # Interactive mode
dc init --defaults          # Skip repo owner/slug and envVars prompts
dc init -f docs/SECURITY.md # Update a specific file
dc init --batch /projects/* # Initialise multiple repos
```

### `dc repo` — Create GitHub Repository

Push your local project to a new GitHub repo in one step.

```bash
dc repo                     # Interactive prompts
dc repo --private --topics cli,bash
```

### `dc pr` — Pull Request Creator

Open a PR from your current branch with auto-detected metadata.

```bash
dc pr                       # Interactive
dc pr --draft --label bug
```

### `dc fix` — History Rewriting

Safely rewrite commits—edit messages, sign, fix dates, drop commits.

```bash
dc fix                                                          # Interactive (last 10 commits)
dc fix --sign --range HEAD=all                                  # GPG-sign entire branch
dc fix --dry-run --range main..HEAD                             # Preview changes
dc fix --restore                                                # Recover from backup bundle
dc fix --drop hash                                              # Surgically drop commit by hash
dc fix --sign --atomic-preserve --auto-resolve --range HEAD=5   # Preserve merge topology and autoresolve merge conflicts
```

### `dc modules` — Submodule Management

Auto-generate `.gitmodules` for nested repos; consolidate temp folders.

```bash
dc modules /path/to/monorepo
dc modules --aggressive --dry-run   # Preview symlink + .gitignore changes
```

### `dc licenses` — License Auditor

Detect, check compatibility, and apply licenses across repos.

```bash
dc licenses                         # Scan current repo
dc licenses --deep                  # Include submodules
dc licenses --check GPL-3.0         # Verify compatibility
dc licenses --apply MIT             # Apply license template
```

### `dc mcp` — MCP Server Setup

Configure Model Context Protocol servers for AI coding assistants.

```bash
dc mcp                              # Interactive server selection
dc mcp --test                       # Verify GitHub MCP connection
dc mcp --create-pat                 # Interactive Github PAT creation
dc mcp --config                     # Only generate .vscode/mcp.json
```

### `dc container` — Devcontainer Generator

Generate a complete `.devcontainer/` setup for VS Code.

```bash
dc contain                                                        # Interactive
dc contain --image mcr.microsoft.com/devcontainers/base:ubuntu    
dc contain --base --dev-tools --defaults && \
  cd subfolder && dc contain --img --dev-tools                    # Use the previous container image (tag=dev-tools) as a base
dc contain --nest  <<< y                                          # Discover, update and rebuild all containers recursively
dc contain --nest --regen                                         # Agressively do same (remove config files and containers)
dc contain --nest --regen .                                       # Include root in same
```

### `dc package` — Multi-Platform Packaging

Build distribution packages with a single command.

```bash
dc package --init                   # Create .dc-package.yaml
dc package --all                    # Build everything
dc package --docker --theme cyber   # Docker image with ttyd + theme
```
---

## 🔌 Plugin System

Extend Dev-Control with custom commands.

```
plugins/
└── my-plugin/
    ├── plugin.yaml       # name, version, description, commands
    └── commands/
        └── greet.sh      # becomes `dc greet`
```

```bash
dc plugin list                      # Show installed plugins
dc plugin install gh:user/repo      # Install from GitHub
dc plugin remove my-plugin
```

---

## ⚙️ Configuration

Dev-Control uses a layered config system (highest priority first):

1. **Environment variables** (`DC_*`)
2. **Project config** (`.dc-init.yaml` in repo root)
3. **Global config** (`~/.config/dev-control/config.yaml`)
4. **Built-in defaults**

Example `.dc-init.yaml`:

```yaml
project-name: my-project
default-license: MIT
default-branch: main
auto-sign-commits: true
github-org: my-org
```

See [config/example.dc-init.yaml](../config/example.dc-init.yaml) for all options.

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [Installation Guide](INSTALL.md) | Detailed install & upgrade instructions |
| [Contributing](CONTRIBUTING.md) | How to contribute |
| [Code of Conduct](CODE_OF_CONDUCT.md) | Community guidelines |
| [Security Policy](SECURITY.md) | Reporting vulnerabilities |
| [Testing Guide](TESTING.md) | Running and writing tests |

### Script Reference

| Script | Purpose |
|--------|---------|
| [dev-control.sh](../scripts/dev-control.sh) | Interactive main menu |
| [template-loading.sh](../scripts/template-loading.sh) | Template init logic |
| [fix-history.sh](../scripts/fix-history.sh) | History rewriting engine |
| [module-nesting.sh](../scripts/module-nesting.sh) | Submodule management |
| [licenses.sh](../scripts/licenses.sh) | License auditing |
| [containerise.sh](../scripts/containerise.sh) | Devcontainer generator |
| [packaging.sh](../scripts/packaging.sh) | Multi-platform packaging |
| [mcp-setup.sh](../scripts/mcp-setup.sh) | MCP server configuration |

### Shared Libraries

Located in `scripts/lib/`:

| Library | Purpose |
|---------|---------|
| `colours.sh` | ANSI terminal colours |
| `print.sh` | Formatted output (headers, boxes, spinners) |
| `config.sh` | YAML config parsing |
| `tui.sh` | Gum/fzf interactive prompts |
| `validation.sh` | Input validation |
| `git/*.sh` | Git utilities (dates, topology, worktrees, etc.) |

---

## 🤝 Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

```bash
# Fork → Clone → Branch → Commit → PR
git checkout -b feature/amazing-feature
git commit -m "Add amazing feature"
git push origin feature/amazing-feature
```

---

## 🗺️ Roadmap

- [x] Unified `dc` CLI with command registry
- [x] Plugin system with GitHub install support
- [x] Multi-platform packaging (tarball, Homebrew, Snap, Deb, Nix, Docker)
- [x] MCP server configuration for AI assistants
- [x] License auditing with SPDX detection
- [x] Devcontainer generator
- [ ] Zsh compatibility layer
- [ ] Fish shell support
- [ ] GUI wrapper (Bubble Tea / Tauri)
- [ ] Remote plugin registry

See [open issues](https://github.com/xaostech/dev-control/issues) for more.

---

## 📄 License

GPL-3.0. See [LICENSE](../LICENSE).

---

<p align="center">
  <a href="https://github.com/xaostech">
    <img src="https://img.shields.io/badge/Made%20with%20%E2%9D%A4%EF%B8%8F%20by-xaostech-red?style=for-the-badge">
  </a>
</p>

<p align="center">
  <a href="#dev-control">⬆️ Back to Top</a>
</p>

<!-- TREE-VIZ-START -->

## Git Tree Visualization

![Git Tree Visualization](../.github/tree-viz/git-tree.svg)

[Interactive version](../.github/tree-viz/git-tree.html) • [View data](../.github/tree-viz/git-tree-data.json)

<!-- TREE-VIZ-END -->
