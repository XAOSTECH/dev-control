# Dev-Control

<!-- Project Shields/Badges -->
<p align="center">
  <a href="https://github.com/xaoscience/dev-control">
    <img alt="GitHub repo" src="https://img.shields.io/badge/GitHub-xaoscience%2Fdev--control-181717?style=for-the-badge&logo=github">
  </a>
  <a href="https://github.com/xaoscience/dev-control/releases">
    <img alt="GitHub release" src="https://img.shields.io/github/v/release/xaoscience/dev-control?style=for-the-badge&logo=semantic-release&color=blue">
  </a>
  <a href="https://github.com/xaoscience/dev-control/blob/main/LICENSE">
    <img alt="License" src="https://img.shields.io/github/license/xaoscience/dev-control?style=for-the-badge&color=green">
  </a>
</p>

<p align="center">
  <a href="https://github.com/xaoscience/dev-control/actions/workflows/bash-lint.yml">
    <img alt="CI Status" src="https://github.com/xaoscience/dev-control/actions/workflows/bash-lint.yml/badge.svg?branch=Main">
  </a>
  <a href="https://github.com/xaoscience/dev-control/issues">
    <img alt="Issues" src="https://img.shields.io/github/issues/xaoscience/dev-control?style=flat-square&logo=github&color=yellow">
  </a>
  <a href="https://github.com/xaoscience/dev-control/pulls">
    <img alt="Pull Requests" src="https://img.shields.io/github/issues-pr/xaoscience/dev-control?style=flat-square&logo=github&color=purple">
  </a>
  <a href="https://github.com/xaoscience/dev-control/stargazers">
    <img alt="Stars" src="https://img.shields.io/github/stars/xaoscience/dev-control?style=flat-square&logo=github&color=gold">
  </a>
</p>

<p align="center">
  <img alt="Last Commit" src="https://img.shields.io/github/last-commit/xaoscience/dev-control?style=flat-square&logo=git&color=blue">
  <img alt="Shell" src="https://img.shields.io/badge/shell-bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white">
  <img alt="Stability" src="https://img.shields.io/badge/stability-experimental-orange?style=flat-square">
  <img alt="Maintenance" src="https://img.shields.io/maintenance/yes/2026?style=flat-square">
</p>

---

## TL;DR

**Dev-Control** is a modular CLI toolkit that automates the tedious parts of your Git workflow—so you can focus on code, not config.

```bash
# Install
git clone https://github.com/xaoscience/dev-control.git && cd dev-control && ./install.sh

# Use
dc init          # Set up a repo with templates, license, docs
dc repo          # Create a GitHub repo from your local project
dc pr            # Open a pull request in seconds
dc fix           # Rewrite/sign/clean commit history safely
dc modules       # Manage nested submodules automatically
dc licenses      # Audit license compliance across repos
dc mcp           # Configure AI coding assistants (MCP servers)
dc container     # Generate devcontainer.json for VS Code
dc package       # Build tarballs, Homebrew, Snap, Deb, Nix, Docker
```

If you've ever spent more time wrestling Git or setting up yet another repo than actually writing code—this is for you.

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
- Spinning up devcontainers with the right mounts and settings
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
git clone https://github.com/xaoscience/dev-control.git
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

### `dc init` — Repository Initialisation

Populate a repo with docs, license, workflows, and GitHub templates.

```bash
dc init                     # Interactive mode
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
dc fix                              # Interactive (last 10 commits)
dc fix --sign --range HEAD=all      # GPG-sign entire branch
dc fix --dry-run --range main..HEAD # Preview changes
dc fix --restore                    # Recover from backup bundle
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
```

### `dc container` — Devcontainer Generator

Generate a complete `.devcontainer/` setup for VS Code.

```bash
dc container                        # Interactive
dc container --image mcr.microsoft.com/devcontainers/base:ubuntu
```

### `dc package` — Multi-Platform Packaging

Build distribution packages with a single command.

```bash
dc package --init                   # Create .dc-package.yaml
dc package --all                    # Build everything
dc package --docker --theme cyber   # Docker image with ttyd + theme
```

### `dc aliases` — Shell Alias Installer

Add productivity aliases for Git, Docker, system monitoring, and more.

```bash
dc aliases                          # Interactive category selection
source ~/.bashrc
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
| `colors.sh` | ANSI terminal colours |
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

See [open issues](https://github.com/xaoscience/dev-control/issues) for more.

---

## 📄 License

GPL-3.0. See [LICENSE](../LICENSE).

---

<p align="center">
  <a href="https://github.com/xaoscience">
    <img src="https://img.shields.io/badge/Made%20with%20%E2%9D%A4%EF%B8%8F%20by-xaoscience-red?style=for-the-badge">
  </a>
</p>

<p align="center">
  <a href="#dev-control">⬆️ Back to Top</a>
</p>
