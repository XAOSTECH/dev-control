# Changelog

All notable changes to Dev-Control will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Renamed project from Git-Control to Dev-Control
- Main command changed from `gc` to `dc`
- Config directory changed from `~/.config/git-control/` to `~/.config/dev-control/`
- Project config file changed from `.gc-init.yaml` to `.dc-init.yaml`
- All aliases now use `gc-` prefix instead of `dc-`

### Added
- Modular CLI framework with `dc` entry point
- Hierarchical configuration system (global + project)
- Plugin architecture with auto-discovery
- Interactive TUI mode with gum/fzf support
- Output format support (--json, --quiet, --verbose)
- Single-file installer script
- Testing framework with bats
- Version management and update checking
- CHANGELOG.md

### Changed
- Restructured commands into commands/ directory
- Libraries moved to scripts/lib/
- Configuration now uses YAML format

## [1.0.0] - 2025-01-15

### Added
- Initial release
- dev-control.sh - main orchestration script
- create-repo.sh - GitHub repository creation
- create-pr.sh - Pull request automation
- template-loading.sh - Template management
- module-nesting.sh - Submodule handling
- fix-history.sh - Git history rewriting
- alias-loading.sh - Shell alias management
- mcp-setup.sh - MCP server configuration
- containerise.sh - Dev container setup
- Shared libraries: common.sh, github.sh, git.sh, signing.sh
- Documentation templates
- GitHub issue/PR templates
- License templates (MIT, GPL-3.0, Apache-2.0, BSD-3-Clause)
- Workflow templates for CI/CD

### Security
- GPG commit signing support
- SSH key management

[Unreleased]: https://github.com/xaoscience/dev-control/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/xaoscience/dev-control/releases/tag/v1.0.0
