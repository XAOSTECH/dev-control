# Dev-Control Plugins

This directory contains plugins that extend dev-control functionality.

## Plugin Structure

Each plugin is a directory with the following structure:

```
plugins/
└── my-plugin/
    ├── plugin.yaml      # Plugin metadata (required)
    ├── commands/         # Command scripts
    │   └── my-cmd.sh    # Becomes: gc my-cmd
    └── lib/              # Shared libraries (optional)
```

## plugin.yaml Format

```yaml
name: my-plugin
version: 1.0.0
description: A plugin that does something useful
author: Your Name
url: https://github.com/user/dc-plugin-example

# Required dev-control version
requires: ">=2.0.0"

# Dependencies (other plugins)
depends: []

# Commands provided
commands:
  - name: my-cmd
    description: Does something useful
```

## Creating a Plugin

1. Create a directory in `plugins/`
2. Add `plugin.yaml` with metadata
3. Add command scripts in `commands/`
4. Scripts automatically become available as `gc <command>`

## Command Script Requirements

```bash
#!/usr/bin/env bash
set -e

# DC_ROOT is available - use it for shared libraries
source "$DC_ROOT/scripts/lib/colors.sh"
source "$DC_ROOT/scripts/lib/print.sh"

# Respect global options
[[ "$DC_QUIET" == "true" ]] && exec &>/dev/null

# Support --help
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    cat << 'EOF'
My Command - Does something useful

Usage: gc my-cmd [options]

Options:
  -h, --help    Show this help
EOF
    exit 0
fi

# Your command logic here
print_info "Hello from my plugin!"
```

## Installing Plugins

### From GitHub
```bash
gc plugin install gh:user/dc-plugin-name
```

### From Local Path
```bash
gc plugin install /path/to/plugin
```

### Manual
Clone or copy the plugin directory to `plugins/`

## Built-in Plugin Commands

```bash
gc plugin list           # List installed plugins
gc plugin install <src>  # Install a plugin
gc plugin remove <name>  # Remove a plugin
gc plugin update <name>  # Update a plugin
gc plugin info <name>    # Show plugin details
```
