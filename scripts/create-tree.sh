#!/usr/bin/env bash
#
# Dev-Control Git Tree Visualizer
# Creates fractal/mandelbrot-style git tree visualization
#
# Generates:
#   - SVG for static embedding in README
#   - HTML with Canvas for interactive hover animations
#   - Auto-injects into README.md or docs/README.md
#
# Usage:
#   ./scripts/create-tree.sh                    # Generate all formats
#   ./scripts/create-tree.sh --svg-only         # SVG only
#   ./scripts/create-tree.sh --html-only        # HTML only
#   ./scripts/create-tree.sh --no-embed         # Don't modify README
#   ./scripts/create-tree.sh --max-commits 200  # Limit commits
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/colours.sh"
source "$SCRIPT_DIR/lib/print.sh"
source "$SCRIPT_DIR/lib/git/tree-viz.sh"

# Configuration
OUTPUT_DIR="${REPO_ROOT}/.github/tree-viz"
MAX_COMMITS=500
GENERATE_SVG=true
GENERATE_HTML=true
EMBED_README=true

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --svg-only)
            GENERATE_HTML=false
            shift
            ;;
        --html-only)
            GENERATE_SVG=false
            shift
            ;;
        --no-embed)
            EMBED_README=false
            shift
            ;;
        --max-commits)
            MAX_COMMITS="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            cat <<-EOF
Git Tree Visualizer - Fractal/Mandelbrot-style git history visualization

Usage: create-tree.sh [OPTIONS]

Options:
  --svg-only              Generate only SVG (static, README-compatible)
  --html-only             Generate only HTML (interactive with animations)
  --no-embed              Don't auto-inject into README
  --max-commits N         Limit visualization to N commits (default: 500)
  --output-dir DIR        Output directory (default: .github/tree-viz)
  -h, --help              Show this help

Generated files:
  - git-tree.svg          Static SVG for embedding
  - git-tree.html         Interactive HTML with Canvas animations
  - git-tree-data.json    Git data (commits, branches, tags)

The SVG is automatically embedded in README.md or docs/README.md if found.
EOF
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# MAIN EXECUTION
# ============================================================================

print_header
print_info "Git Tree Visualizer - Creating fractal tree visualization"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Step 1: Extract git data
print_info "Extracting git data (max $MAX_COMMITS commits)..."
DATA_FILE=$(generate_tree_data_json "$OUTPUT_DIR/git-tree-data.json" "$MAX_COMMITS")
print_success "Git data extracted: $DATA_FILE"

# Step 2: Calculate positions
print_info "Calculating fractal tree positions..."
POSITIONS_FILE=$(calculate_tree_positions "$DATA_FILE" "$OUTPUT_DIR/git-tree-positions.json")
print_success "Positions calculated: $POSITIONS_FILE"

# Step 3: Generate SVG
if [[ "$GENERATE_SVG" == "true" ]]; then
    print_info "Generating static SVG..."
    source "$SCRIPT_DIR/lib/git/tree-render-svg.sh"
    SVG_FILE=$(render_svg_tree "$POSITIONS_FILE" "$OUTPUT_DIR/git-tree.svg")
    print_success "SVG generated: $SVG_FILE"
fi

# Step 4: Generate HTML
if [[ "$GENERATE_HTML" == "true" ]]; then
    print_info "Generating interactive HTML..."
    source "$SCRIPT_DIR/lib/git/tree-render-html.sh"
    HTML_FILE=$(render_html_tree "$POSITIONS_FILE" "$OUTPUT_DIR/git-tree.html")
    print_success "HTML generated: $HTML_FILE"
fi

# Step 5: Embed in README
if [[ "$EMBED_README" == "true" && "$GENERATE_SVG" == "true" ]]; then
    print_info "Embedding visualization in README..."
    
    # Find README
    README=""
    README_REL_PATH=".github/tree-viz"  # Default: from repo root
    
    if [[ -f "$REPO_ROOT/README.md" ]]; then
        README="$REPO_ROOT/README.md"
        README_REL_PATH=".github/tree-viz"
    elif [[ -f "$REPO_ROOT/docs/README.md" ]]; then
        README="$REPO_ROOT/docs/README.md"
        README_REL_PATH="../.github/tree-viz"  # One level up from docs/
    fi
    
    if [[ -n "$README" ]]; then
        # Check if tree-viz section already exists
        if grep -q "<!-- TREE-VIZ-START -->" "$README"; then
            # Replace existing section
            print_info "Updating existing tree visualization in README..."
            # Create temp file with new content
            awk -v path="$README_REL_PATH" '
                /<!-- TREE-VIZ-START -->/ {
                    print $0
                    print ""
                    print "![Git Tree Visualization](" path "/git-tree.svg)"
                    print ""
                    in_tree=1
                    next
                }
                /<!-- TREE-VIZ-END -->/ {
                    in_tree=0
                }
                !in_tree {print}
            ' "$README" > "$README.tmp"
            mv "$README.tmp" "$README"
        else
            # Append new section
            print_info "Adding tree visualization section to README..."
            cat >> "$README" <<-EOF

<!-- TREE-VIZ-START -->

## Git Tree Visualization

![Git Tree Visualization]($README_REL_PATH/git-tree.svg)

[Interactive version]($README_REL_PATH/git-tree.html) • [View data]($README_REL_PATH/git-tree-data.json)

<!-- TREE-VIZ-END -->
EOF
        fi
        print_success "README updated: $README"
    else
        print_warning "No README.md found - skipping embed"
    fi
fi

# Summary
echo ""
print_success "Visualization complete!"
echo ""
echo "Generated files:"
[[ "$GENERATE_SVG" == "true" ]] && echo "  • SVG:  $OUTPUT_DIR/git-tree.svg"
[[ "$GENERATE_HTML" == "true" ]] && echo "  • HTML: $OUTPUT_DIR/git-tree.html"
echo "  • Data: $OUTPUT_DIR/git-tree-data.json"
echo ""

[[ "$GENERATE_HTML" == "true" ]] && {
    echo "To view interactive version, open:"
    echo "  file://$OUTPUT_DIR/git-tree.html"
    echo ""
}
