# Git-Control Installation

## Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/xaoscience/git-control/Main/install.sh | bash
```

## Custom Installation

```bash
# Clone and install manually
git clone https://github.com/xaoscience/git-control.git
cd git-control
./install.sh

# Or with custom paths
./install.sh --prefix=/opt/git-control --bin=/usr/local/bin
```

## Options

| Option | Description |
|--------|-------------|
| `--prefix=PATH` | Installation directory (default: ~/.local/share/git-control) |
| `--bin=PATH` | Binary directory for symlink (default: ~/.local/bin) |
| `--uninstall` | Remove git-control |
| `--upgrade` | Update existing installation |
| `--no-aliases` | Skip bash aliases installation |
| `--quiet` | Minimal output |

## Post-Install

After installation, reload your shell:

```bash
source ~/.bashrc
```

Then run:

```bash
gc --help
```

## Upgrading

```bash
gc-upgrade  # or
./install.sh --upgrade
```

## Uninstalling

```bash
./install.sh --uninstall
```

## Requirements

### Required
- git
- bash 4.0+
- curl

### Recommended
- gh (GitHub CLI) - for repo/PR operations
- gpg - for commit signing

### Optional (Enhanced UI)
- gum - for rich interactive menus
- fzf - for fuzzy selection
