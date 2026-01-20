# Dev-Control Installation

## Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/xaoscience/dev-control/Main/install.sh | bash
```

## Custom Installation

```bash
# Clone and install manually
git clone https://github.com/xaoscience/dev-control.git
cd dev-control
./install.sh

# Or with custom paths
./install.sh --prefix=/opt/dev-control --bin=/usr/local/bin
```

## Options

| Option | Description |
|--------|-------------|
| `--prefix=PATH` | Installation directory (default: ~/.local/share/Dev-Control) |
| `--bin=PATH` | Binary directory for symlink (default: ~/.local/bin) |
| `--uninstall` | Remove Dev-Control |
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
dc-upgrade  # or
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
