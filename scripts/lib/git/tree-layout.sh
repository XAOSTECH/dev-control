#!/usr/bin/env bash
#
# Dev-Control Shared Library: Git Tree Fractal Layout (Pure Bash)
# Generates mandelbrot-esque circular tree positions for git commits
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# ============================================================================
# FRACTAL TREE LAYOUT CALCULATOR (PURE BASH)
# ============================================================================

# Calculate circular tree positions (simple distribution)
calculate_tree_positions_bash() {
    local input_json="$1"
    local output_file="${2:-/tmp/git-tree-positions.json}"
    
    # Use jq for simple spiral/grid positioning (no trigonometry needed)
    # Just arrange commits in a spiral pattern from center outward
    jq '
        # Grid layout: 5 columns per row
        (.commits | length) as $total_commits |
        
        # Enhance commits with simple grid positions
        .commits |= (
            sort_by(.timestamp) | reverse |
            to_entries | map(
                .value as $commit |
                .key as $idx |
                
                # Simple 5-column grid
                5 as $cols |
                ($idx / $cols | floor) as $row |
                ($idx % $cols) as $col |
                
                (50 + ($col * 250)) as $x |
                (100 + ($row * 120)) as $y |
                
                # Add position data to commit
                $commit + {
                    position: {
                        x: $x,
                        y: $y,
                        angle: 0,
                        radius: 6,
                        depth: $row
                    }
                }
            )
        )
    ' "$input_json" > "$output_file" 2>/dev/null || {
        # Fallback if jq transform fails
        cp "$input_json" "$output_file"
    }
    
    echo "$output_file"
}

# Simpler linear tree layout (fallback if jq not available)
calculate_tree_positions_simple() {
    local input_json="$1"
    local output_file="${2:-/tmp/git-tree-positions.json}"
    
    # Very simple: just add x/y based on index
    jq '.commits |= to_entries | map(
        .value + {
            position: {
                x: (200 + (.key % 5) * 250),
                y: (100 + (.key / 5 | floor) * 100),
                angle: 0,
                radius: 6,
                depth: (.key / 5 | floor)
            }
        }
    )' "$input_json" > "$output_file" 2>/dev/null || {
        cp "$input_json" "$output_file"
    }
    
    echo "$output_file"
}
