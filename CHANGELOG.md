# Changelog

All notable changes to Dev-Control will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.5] - 2026-02-20

### Fixed
- correct shields.io badge parameters and refine anglicise exclusions
- pre-create ~/.devcontainer so postCreateCommand marker can be written
- bust permissions layer cache with BUILD_DATE ARG
- remove --userns=keep-id from runArgs + prune before nest loop
- prune stale vsc-*-uid wrapper images after base build

### Changed
- Add bot-email input and template-loading integration for bot values
- Replace xaos-bot specific values with placeholders in action template
- chore: update CHANGELOG for v0.5.5 (re-release)
- docs(readme): readability
- chore: update CHANGELOG for v0.5.5

## [0.5.4] - 2026-02-18

### Added
- automate re-release and smart CHANGELOG handling
- auto-generate CHANGELOG.md in release workflow
- extract bot identity into composite action
- attribute bot commits/merges to GitHub App identity
- auto-merge any xaos[bot] PRs without requiring automerge label
- add text replacement workflow

### Fixed
- fix user setup and switch to wget
- remove GPG_TTY literal and conflicting socket bind mount
- pre-create .ssh/.cache/.config in image; restore .gnupg chown in postCreateCommand; add --no-cache to dc-contain --base
- support v-prefixed version input, strip if present
- normalise CHANGELOG blank lines with cat -s after each edit
- add per-tag concurrency and idempotent release creation
- use GITHUB_TOKEN to push tag in dispatch path to prevent re-trigger
- skip GPG re-registration if key already present
- prevent set -e crash in GPG registration step
- use machine user (xaos-bot) identity for GPG signing and git attribution
- use personal PAT (XB_UT) for GPG key registration, fix check logic
- expose GPG key registration failures and attribute release to bot
- generate app token before checkout so credential helper uses app identity
- configure app token remote once at workflow start for all pushes
- remove invalid workflows permission key from release workflow
- workflows permission, app token push, and auto-version for release
- set git identity in Update latest tag step
- correct latest tag creation in release workflow
- apply bot identity and GPG verification to release workflow
- correct bot display name and GPG commit verification
- correct single-quote escaping in anglicise grep patterns
- use perl negative lookahead instead of whole-line filename skip
- use app display name for git user.name instead of ASCII slug
- support --auto-resolve=value and AUTO_RESOLVE=THEIRS in fix-history
- register bot GPG key unconditionally on every workflow run
- use gpg-connect-agent PRESET_PASSPHRASE for correct CI/CD signing
- use absolute PATH and ensure wrapper is accessible in commit step
- replace heredoc with printf for YAML compliance
- create GPG wrapper script for pinentry mode
- simplify GPG signing and remove .git default from exclude paths
- pass GPG environment variables to commit step
- replace heredoc with printf for valid YAML syntax
- implement proper GPG signing with passphrase caching
- add GPG_PINENTRY_MODE=loopback to enable non-interactive signing
- enable GPG signing in CI/CD with loopback pinentry mode

### Changed
- docs(readme): update command examples
- chore: update CHANGELOG for v0.5.4 (re-release)
- chore: update CHANGELOG for v0.5.4 (re-release)
- chore: update CHANGELOG for v0.5.4 (re-release)
- perf: skip build steps on duplicate run via early release check
- chore: update CHANGELOG for v0.5.4
- refactor: deduplicate commit-fetching into shared gather step
- docs(readme): update intro + usage
- Merge pull request #33 from XAOSTECH/anglicise/20260218-003720
- chore: convert American spellings to British English
- Merge pull request #32 from XAOSTECH/anglicise/20260218-001511
- chore: convert American spellings to British English
- Merge pull request #31 from XAOSTECH/replace/20260217-235313
- refactor: use xxd -p -u for cleaner hex passphrase encoding
- chore: replace text across repository
- chore: update workflows with GitHub App token integration
- chore: change anglicise workflow to run monthly and on-demand only
- docs(security): version

## [0.5.2] - 2026-02-11

### Fixed
- **Devcontainer UID mismatch with `--userns=keep-id`**:
  - Added `-u 1000` flag to `usermod` when renaming ubuntu user in Dockerfile
  - Ensures dev-tools user UID matches host UID 1000 from `--userns=keep-id` remapping
  - Fixes "Permission denied" errors on `.gnupg`, `.ssh`, `.gitconfig` during container initialisation
- **GPG directory pre-creation removed**:
  - Removed `.gnupg` pre-creation from `footer.Dockerfile` and `containerise.sh`
  - Let VS Code create `.gnupg` during initialisation with correct user ownership
  - Prevents permission mismatches when `--userns=keep-id` remaps UIDs at runtime

### Added
- **Debugging guide for conditional code paths**:
  - New lesson documenting how to identify and fix conditional branch issues in generated Dockerfiles
  - Explains how layer cache changes prove edits are recognised
  - Guidance on tracing which conditional branch executes based on STEP output

## [0.5.0] - 2026-02-08

### Added
- **Containerization modularization complete**:
  - Extracted category Dockerfile generation to `lib/container.sh`
  - Template files: `common.Dockerfile`, `footer.Dockerfile`, per-category Dockerfiles
  - `generate_category_dockerfile()` function for DRY base image building
- **Dynamic locale and timezone support**:
  - Locale and timezone now configurable from user config (not hardcoded)
  - `${LOCALE}` and `${TZ}` template variables in `common.Dockerfile`
  - Defaults to `en_US.UTF-8` and `UTC` if not specified
- **npx PATH for MCP servers**:
  - `ENV PATH` set globally in `common.Dockerfile` for Node.js binaries
  - Firecrawl and other npx-based MCP servers work out-of-the-box
  - No shell initialisation required for IDE integrations
- **Web-dev category enhancements**:
  - Wrangler (Cloudflare Workers CLI) installed globally via npm
  - Verification step added to confirm Wrangler installation
- **Config variant generation**:
  - `_example` and `_minimal` variants for tracked reference configs
  - Personal configs (Dockerfile, devcontainer.json) gitignored
  - Tracked variants use placeholder values or omit personal config

### Fixed
- **GPG signing restored**:
  - `postCreateCommand` now creates `/run/user/${uid}/gnupg` for socket mount
  - `.gnupg` directory permissions fixed (`chmod 700`, proper ownership)
  - GPG agent socket properly accessible in containers
- **dc-fix auto-push**:
  - Automatic force-push after signing operations
  - Prevents divergent branch issues requiring manual push
  - Uses `--force-with-lease` for safety
- **Sed escaping bug**:
  - Git config commands now properly escape `&` characters for sed
  - Fixes template variable substitution in footer.Dockerfile
- **Locale sed pattern**:
  - Changed from `/${LOCALE%.*}/` to `/${LOCALE}/` (parameter expansion doesn't work in templates)
  - Correctly matches `/etc/locale.gen` entries

### Changed
- **Reduced containerise.sh complexity**:
  - Line count: 1532 → 1419 (7.4% reduction)
  - Duplicate 113-line function removed (now in `lib/container.sh`)
- **Improved .gitignore handling**:
  - Personal devcontainer configs excluded from version control
  - Tracked reference variants (_example, _minimal) committed

### Technical Details
- **Code changes**: Refactored ~200 lines from monolithic script to modular library
- **New functions**:
  - `generate_category_dockerfile()`: Concatenate templates with variable substitution
  - `generate_git_config_dockerfile()`: Build git config for Dockerfile RUN
  - `generate_git_config_postcreate()`: Build git config for postCreateCommand
- **Template architecture**:
  - `common.Dockerfile`: Base layer (Ubuntu, tools, locale, nvm, Node.js)
  - `{category}.Dockerfile`: Category-specific installations
  - `footer.Dockerfile`: User setup, dev-control install, git config

### Backward Compatibility
- ✓ All existing flows functional (--base, --img, interactive)
- ✓ Legacy interactive mode unchanged
- ✓ Existing .devcontainer configurations work as before

## [0.4.0] - 2026-02-04

### Added
- **Multi-category base image support** with specialised development environments
  - Categories: game-dev, art, data-science, streaming, web-dev, dev-tools
  - Feature descriptions and GitHub source references for each category
- **Dual-mode operation**:
  - `--base --CATEGORY`: Build pre-configured category base images
  - `--img --CATEGORY`: Generate devcontainers from category base images
- **GPU acceleration & streaming features**:
  - CUDA Toolkit 13.1 support with NVIDIA hardware integration
  - FFmpeg compilation from source with NVENC/NVDEC hardware encoding
  - NGINX-RTMP streaming server integration with SRT protocol support
  - ONNX Runtime GPU acceleration for ML inference
  - YOLOv8 export and inference capabilities
- **Enhanced configuration**:
  - New options: `use_base_category`, `base_category`, `mount_wrangler`
  - Streaming options: `install_cuda`, `install_ffmpeg`, `install_nginx_rtmp`,
    `install_streaming_utils`, `enable_nvidia_devices`
  - Configuration via new YAML keys in container configuration files
- **Improved help & documentation**:
  - Category descriptions with tools and versions
  - Mode-specific usage examples
  - GitHub source paths for category base images

### Changed
- `containerise.sh` help text completely restructured for multi-category architecture
- Configuration loading refactored to support base category selection
- Command-line parsing enhanced with MODE and CATEGORY_FLAG support
- File permission: `containerise.sh` now executable (+x)

### Technical Details
- **Code changes**: +1026 lines (1080 insertions, 54 deletions)
- **New functions**:
  - `generate_category_dockerfile()`: Build category base images
  - `build_base_image()`: Execute category base image builds
  - `generate_image_devcontainer()`: Generate devcontainers from base images
- **New data structures**:
  - `BASE_IMAGE_CATEGORIES[]`: Category-to-image mappings
  - `CATEGORY_FEATURES[]`: Feature descriptions per category
  - `CATEGORY_GITHUB_PATHS[]`: Source code references

### Backward Compatibility
- ✓ Legacy interactive mode fully preserved
- ✓ Existing .devcontainer configurations unaffected
- ✓ `--defaults` and `--config FILE` options functional
- ✓ Non-category configurations work as before

### Use Cases Enabled
- **Game Development**: Godot 4.x + Vulkan SDK + SDL2 + GLFW 3.4 + CUDA
- **3D/2D Art**: Krita, GIMP, Inkscape, Blender, ImageMagick
- **Data Science**: CUDA + FFmpeg + NVIDIA acceleration
- **Live Streaming**: FFmpeg (NVENC/NVDEC) + NGINX-RTMP + ONNX Runtime
- **Web Development**: Node.js 25 (nvm) + npm + Wrangler
- **General Development**: GCC + build-essential + standard compilers

## [0.3.0] - 2026-01-26

### Fixed
- License detection now correctly identifies GPL-3.0 when version number is on a separate line
- Debian package Depends field now properly formatted (comma+space separated)
- Fixed library path in licenses.sh (was lib/license.sh, now lib/git/license.sh)

### Improved
- Documentation updated with concise introduction for new users
- README.md restructured for better readability while maintaining template design

## [0.2.2] - 2026-01-24

### Changed
- Refactored release workflow to separate template from dev-control-specific workflow
- Converted American spellings to British English

### Fixed
- Expanded exclusions in anglicise workflow for CLI flags and code patterns

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

[Unreleased]: https://github.com/xaoscience/dev-control/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/xaoscience/dev-control/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/xaoscience/dev-control/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/xaoscience/dev-control/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/xaoscience/dev-control/compare/v1.0.0...v0.2.2
[1.0.0]: https://github.com/xaoscience/dev-control/releases/tag/v1.0.0

