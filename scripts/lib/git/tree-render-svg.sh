#!/usr/bin/env bash
#
# Dev-Control Shared Library: SVG Tree Renderer
# Renders git tree as static SVG with fractal styling
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# ============================================================================
# SVG RENDERING
# ============================================================================

render_svg_tree() {
    local input_json="$1"
    local output_file="${2:-git-tree.svg}"
    
    # Get dimensions from data
    local stats
    stats=$(get_repo_stats)
    local width=$(echo "$stats" | jq -r '.suggested_width')
    local height=$(echo "$stats" | jq -r '.suggested_height')
    
    # Start SVG
    cat > "$output_file" <<-SVGHEADER
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" 
     xmlns:xlink="http://www.w3.org/1999/xlink"
     width="$width" height="$height" 
     viewBox="0 0 $width $height">
  <defs>
    <!-- Gradients for fractal effect -->
    <radialGradient id="leafGradient">
      <stop offset="0%" style="stop-color:#4ade80;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#22c55e;stop-opacity:0.8" />
    </radialGradient>
    
    <radialGradient id="mergeGradient">
      <stop offset="0%" style="stop-color:#a78bfa;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#8b5cf6;stop-opacity:0.8" />
    </radialGradient>
    
    <!-- Branch line style -->
    <style>
      .branch-line { stroke: #64748b; stroke-width: 2; fill: none; opacity: 0.6; }
      .commit-leaf { cursor: pointer; }
      .commit-leaf:hover { filter: brightness(1.3); }
      .commit-text { font-family: monospace; font-size: 11px; fill: #1e293b; }
      .branch-label { font-family: sans-serif; font-size: 12px; font-weight: bold; fill: #0f172a; }
    </style>
  </defs>
  
  <rect width="$width" height="$height" fill="#f1f5f9"/>
  
  <!-- Background fractal decoration -->
  <g opacity="0.1">
SVGHEADER

    # Add decorative fractal circles in background
    for i in {1..5}; do
        local cx=$((RANDOM % width))
        local cy=$((RANDOM % height))
        local r=$((50 + RANDOM % 100))
        echo "    <circle cx=\"$cx\" cy=\"$cy\" r=\"$r\" fill=\"none\" stroke=\"#cbd5e1\" stroke-width=\"1\"/>" >> "$output_file"
    done
    
    echo "  </g>" >> "$output_file"
    echo "  " >> "$output_file"
    echo "  <!-- Branch lines -->" >> "$output_file"
    echo "  <g id=\"branches\">" >> "$output_file"
    
    # Draw lines between commits (parent-child connections)
    jq -r '
        .commits[] | 
        select(.position and .parents != "") |
        .position as $pos |
        .parents as $parents |
        ($parents | split(" ")) as $parent_list |
        $parent_list[] as $parent_sha |
        (.commits[] | select(.sha == $parent_sha) | .position) as $parent_pos |
        select($parent_pos) |
        "    <path class=\"branch-line\" d=\"M \($pos.x),\($pos.y) Q \(($pos.x + $parent_pos.x) / 2),\(($pos.y + $parent_pos.y) / 2 - 20) \($parent_pos.x),\($parent_pos.y)\"/>"
    ' "$input_json" >> "$output_file" 2>/dev/null || true
    
    echo "  </g>" >> "$output_file"
    echo "  " >> "$output_file"
    echo "  <!-- Commit nodes (leaves) -->" >> "$output_file"
    echo "  <g id=\"commits\">" >> "$output_file"
    
    # Draw commit nodes as "leaves"
    jq -r '
        .commits[] | 
        select(.position) |
        .position as $pos |
        .short as $sha |
        .subject as $msg |
        (.parents | split(" ") | length) as $parent_count |
        if $parent_count > 1 then "mergeGradient" else "leafGradient" end as $gradient |
        if $parent_count > 1 then 8 else 6 end as $radius |
        "    <circle class=\"commit-leaf\" cx=\"\($pos.x)\" cy=\"\($pos.y)\" r=\"\($radius)\" fill=\"url(#\($gradient))\" stroke=\"#16a34a\" stroke-width=\"1.5\">",
        "      <title>\($sha): \($msg)</title>",
        "    </circle>"
    ' "$input_json" >> "$output_file" 2>/dev/null || true
    
    echo "  </g>" >> "$output_file"
    echo "  " >> "$output_file"
    echo "  <!-- Branch labels -->" >> "$output_file"
    echo "  <g id=\"labels\">" >> "$output_file"
    
    # Add branch labels
    jq -r '
        .branches[] |
        select(.sha) |
        (.commits[] | select(.sha == .sha) | .position) as $pos |
        select($pos) |
        .name as $branch |
        "    <text class=\"branch-label\" x=\"\($pos.x + 12)\" y=\"\($pos.y + 4)\" fill=\"#1e40af\">\($branch)</text>"
    ' "$input_json" >> "$output_file" 2>/dev/null || true
    
    echo "  </g>" >> "$output_file"
    echo "</svg>" >> "$output_file"
    
    echo "$output_file"
}
