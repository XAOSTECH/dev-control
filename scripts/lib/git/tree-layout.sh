#!/usr/bin/env bash
#
# Dev-Control Shared Library: Git Tree Fractal Layout (Pure Bash)
# Generates mandelbrot-esque circular tree positions for git commits
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# ============================================================================
# FRACTAL TREE LAYOUT CALCULATOR (PURE BASH)
# ============================================================================

# Calculate circular tree positions using bc for math
calculate_tree_positions_bash() {
    local input_json="$1"
    local output_file="${2:-/tmp/git-tree-positions.json}"
    
    local width=1600
    local height=1200
    local center_x=800
    local center_y=1100
    
    # Use jq to process and add positions
    # We'll use a simpler radial layout that doesn't require complex parent traversal
    # Commits are positioned in concentric circles based on their timestamp (depth)
    
    jq --argjson width "$width" \
       --argjson height "$height" \
       --argjson cx "$center_x" \
       --argjson cy "$center_y" '
    # Get min/max timestamps for normalization
    ((.commits | map(.timestamp) | min) // 0) as $min_ts |
    ((.commits | map(.timestamp) | max) // 1) as $max_ts |
    ($max_ts - $min_ts) as $ts_range |
    
    # Enhance commits with positions
    .commits |= (
        # Sort by timestamp (oldest first)
        sort_by(.timestamp) |
        
        # Calculate positions
        to_entries | map(
            .value as $commit |
            .key as $idx |
            
            # Normalize timestamp to 0-1 range (depth)
            (if $ts_range > 0 then 
                (($commit.timestamp - $min_ts) / $ts_range) 
             else 0.5 end) as $depth_norm |
            
            # Calculate radius (small at root, large at leaves)
            # Reverse: newer commits (higher depth) closer to center
            (50 + ((1 - $depth_norm) * 500)) as $radius |
            
            # Calculate angle based on index and parent count
            # Creates spiral/mandelbrot effect
            (($idx / (. | length)) * 6.28318530718) as $base_angle |
            
            # Add fractal curve based on commit message hash (deterministic)
            (($commit.short | ascii_downcase | explode | add) % 100) as $hash_seed |
            ($base_angle + (($hash_seed / 100) * 0.6)) as $angle |
            
            # Calculate x, y positions
            ($cx + ($radius * ($angle | cos))) as $x |
            ($cy - ($radius * ($angle | sin))) as $y |
            
            # Add position data to commit
            $commit + {
                position: {
                    x: $x,
                    y: $y,
                    angle: $angle,
                    radius: $radius,
                    depth: $depth_norm
                }
            }
        ) | map(.value)
    )
    ' "$input_json" > "$output_file"
    
    echo "$output_file"
}

# Simpler linear tree layout (fallback if jq not available)
calculate_tree_positions_simple() {
    local input_json="$1"
    local output_file="${2:-/tmp/git-tree-positions.json}"
    
    # Very simple: just add x=400, y based on index
    local idx=0
    local result='{"commits":['
    
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        if [[ $idx -gt 0 ]]; then
            result+=","
        fi
        
        # Add position to commit JSON
        local y=$((50 + idx * 40))
        echo "$line" | jq ". + {position: {x: 400, y: $y, angle: 0, radius: 0, depth: $idx}}"
        
        ((idx++))
    done < <(jq -c '.commits[]' "$input_json")
    
    result+=']}'
    echo "$result" > "$output_file"
    echo "$output_file"
}
