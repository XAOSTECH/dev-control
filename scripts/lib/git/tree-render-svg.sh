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
    local width=$(echo "$stats" | jq -r '.suggested_width // 1600')
    local height=$(echo "$stats" | jq -r '.suggested_height // 1200')
    
    # Validate JSON
    if ! jq empty "$input_json" 2>/dev/null; then
        echo "ERROR: Invalid JSON in $input_json" >&2
        return 1
    fi
    
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
      <stop offset="0%" style="stop-color:#22c55e;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#16a34a;stop-opacity:0.8" />
    </radialGradient>
    
    <radialGradient id="mergeGradient">
      <stop offset="0%" style="stop-color:#a78bfa;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#7c3aed;stop-opacity:0.8" />
    </radialGradient>
    
    <!-- Branch line style -->
    <style>
      .branch-line { stroke: #64748b; stroke-width: 2; fill: none; opacity: 0.7; }
      .commit-leaf { cursor: pointer; }
      .commit-leaf:hover { filter: brightness(1.5); }
      .commit-text { font-family: monospace; font-size: 11px; fill: #1e293b; }
      .branch-label { font-family: sans-serif; font-size: 12px; font-weight: bold; fill: #0f172a; }
    </style>
  </defs>
  
  <!-- Background -->
  <rect width="$width" height="$height" fill="#f8fafc"/>
  
  <!-- Grid pattern for depth visualization -->
  <defs>
    <pattern id="grid" width="100" height="100" patternUnits="userSpaceOnUse">
      <path d="M 100 0 L 0 0 0 100" fill="none" stroke="#e2e8f0" stroke-width="0.5" opacity="0.3"/>
    </pattern>
  </defs>
  <rect width="$width" height="$height" fill="url(#grid)"/>
  
  <!-- Branch lines -->
  <g id="branches" class="branch-line">
SVGHEADER

    # Generate SVG paths for branches using simpler approach
    # Use a Python-free method: just iterate commits and plot them
    jq -r '.commits[] | select(.position) | 
      "    <circle cx=\"\(.position.x)\" cy=\"\(.position.y)\" r=\"6\" fill=\"url(#leafGradient)\" stroke=\"#16a34a\" stroke-width=\"1.5\" title=\"\(.short): \(.subject)\"/>"' \
      "$input_json" 2>/dev/null >> "$output_file" || {
        # Fallback if jq fails
        echo "    <!-- SVG generation requires jq -->" >> "$output_file"
    }
    
    cat >> "$output_file" <<-SVGFOOTER
  </g>
  
  <!-- Legend -->
  <g id="legend" transform="translate(20, 20)">
    <rect width="200" height="80" fill="white" stroke="#cbd5e1" stroke-width="1" rx="4"/>
    <circle cx="20" cy="25" r="5" fill="url(#leafGradient)" stroke="#16a34a"/>
    <text x="32" y="30" class="branch-label" font-size="12">Regular Commit</text>
    
    <circle cx="20" cy="55" r="6" fill="url(#mergeGradient)" stroke="#7c3aed"/>
    <text x="32" y="60" class="branch-label" font-size="12">Merge Commit</text>
  </g>
  
  <!-- Repository info -->
  <g id="info" transform="translate(20, $((height - 40)))">
    <text x="0" y="0" class="branch-label" font-size="12" fill="#666">
      Repository: $(git rev-parse --show-toplevel 2>/dev/null | xargs basename)
    </text>
    <text x="0" y="20" class="branch-label" font-size="10" fill="#999">
      Generated: $(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)
    </text>
  </g>
</svg>
SVGFOOTER

    echo "$output_file"
}
