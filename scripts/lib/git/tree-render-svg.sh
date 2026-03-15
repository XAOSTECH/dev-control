#!/usr/bin/env bash
#
# Dev-Control Shared Library: SVG Tree Renderer
# Renders git tree as static SVG with fractal styling
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# ============================================================================
# SVG RENDERING
# ============================================================================

render_svg_tree() {
    local input_json="$1"
    local output_file="${2:-git-tree.svg}"
    
    # Get dimensions from actual position data
    local max_y max_x min_x
    max_y=$(jq '[.commits[].position.y // 0] | max' "$input_json" 2>/dev/null || echo 800)
    max_x=$(jq '[.commits[].position.x // 600] | max' "$input_json" 2>/dev/null || echo 600)
    min_x=$(jq '[.commits[].position.x // 600] | min' "$input_json" 2>/dev/null || echo 600)
    local width=$(( max_x - min_x + 400 ))
    [[ $width -lt 1200 ]] && width=1200
    local height=$(( max_y + 120 ))
    [[ $height -lt 800 ]] && height=800
    
    # Validate JSON
    if ! jq empty "$input_json" 2>/dev/null; then
        echo "ERROR: Invalid JSON in $input_json" >&2
        return 1
    fi

    local repo_name
    repo_name=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" || echo "repository")
    
    # Start SVG
    cat > "$output_file" <<-SVGHEADER
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" 
     xmlns:xlink="http://www.w3.org/1999/xlink"
     width="$width" height="$height" 
     viewBox="0 0 $width $height">
  <defs>
    <radialGradient id="leafGradient">
      <stop offset="0%" style="stop-color:#22c55e;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#16a34a;stop-opacity:0.8" />
    </radialGradient>
    <radialGradient id="mergeGradient">
      <stop offset="0%" style="stop-color:#a78bfa;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#7c3aed;stop-opacity:0.8" />
    </radialGradient>
    <radialGradient id="forkGradient">
      <stop offset="0%" style="stop-color:#fb923c;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#ea580c;stop-opacity:0.8" />
    </radialGradient>
    <radialGradient id="tagGradient">
      <stop offset="0%" style="stop-color:#38bdf8;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#0284c7;stop-opacity:0.8" />
    </radialGradient>
    <style>
      .branch-line { stroke: #64748b; stroke-width: 2; fill: none; opacity: 0.7; }
      .trunk-line { stroke: #22c55e; stroke-width: 2.5; fill: none; opacity: 0.6; }
      .commit-leaf { cursor: pointer; }
      .commit-leaf:hover { filter: brightness(1.5); }
      .branch-label { font-family: sans-serif; font-size: 12px; font-weight: bold; fill: #0f172a; }
    </style>
  </defs>
  
  <rect width="$width" height="$height" fill="#f8fafc"/>
  <defs>
    <pattern id="grid" width="100" height="100" patternUnits="userSpaceOnUse">
      <path d="M 100 0 L 0 0 0 100" fill="none" stroke="#e2e8f0" stroke-width="0.5" opacity="0.3"/>
    </pattern>
  </defs>
  <rect width="$width" height="$height" fill="url(#grid)"/>
  
  <!-- Branch connection lines -->
  <g id="branches">
SVGHEADER

    # Generate branch connection lines
    jq -r '
        # Build sha→position lookup
        (.commits | map({(.sha): .position}) | add // {}) as $positions |
        # Build tag sha lookup
        ([.tags[]? | .sha] | map({(.): true}) | add // {}) as $tag_shas |
        .commits[] |
        select(.position) |
        .sha as $sha |
        .position as $pos |
        (.parents // "" | split(" ") | map(select(. != "")))[] |
        . as $parent_sha |
        ($positions[$parent_sha] // null) |
        select(. != null) |
        . as $pp |
        (if $pos.lane == $pp.lane then "trunk-line" else "branch-line" end) as $class |
        if $pos.lane != $pp.lane then
            # Curved line for branches
            (($pos.y + ($pp.y - $pos.y) * 0.4) | floor) as $cy1 |
            (($pos.y + ($pp.y - $pos.y) * 0.6) | floor) as $cy2 |
            "    <path class=\"\($class)\" d=\"M \($pos.x) \($pos.y) C \($pos.x) \($cy1), \($pp.x) \($cy2), \($pp.x) \($pp.y)\"/>"
        else
            "    <line class=\"\($class)\" x1=\"\($pos.x)\" y1=\"\($pos.y)\" x2=\"\($pp.x)\" y2=\"\($pp.y)\"/>"
        end
    ' "$input_json" 2>/dev/null >> "$output_file"

    echo '  </g>' >> "$output_file"
    echo '  <!-- Commit nodes -->' >> "$output_file"
    echo '  <g id="commits">' >> "$output_file"

    # Generate commit circles with XML-escaped titles and correct gradients
    jq -r '
        # Build tag sha lookup
        ([.tags[]? | .sha] | map({(.): true}) | add // {}) as $tag_shas |
        .commits[] | select(.position) |
        # XML-escape the subject
        (.subject // "" |
            gsub("&"; "&amp;") | gsub("\""; "&quot;") |
            gsub("<"; "&lt;") | gsub(">"; "&gt;")
        ) as $safe_subj |
        (.short // .sha[:7]) as $short |
        # Pick gradient
        (
            if $tag_shas[.sha] then "tagGradient"
            elif .position.is_merge then "mergeGradient"
            elif .position.is_fork then "forkGradient"
            else "leafGradient"
            end
        ) as $grad |
        # Pick stroke
        (
            if $tag_shas[.sha] then "#0284c7"
            elif .position.is_merge then "#7c3aed"
            elif .position.is_fork then "#ea580c"
            else "#16a34a"
            end
        ) as $stroke |
        "    <circle class=\"commit-leaf\" cx=\"\(.position.x)\" cy=\"\(.position.y)\" r=\"\(.position.radius // 6)\" fill=\"url(#\($grad))\" stroke=\"\($stroke)\" stroke-width=\"1.5\"><title>\($short): \($safe_subj)</title></circle>"
    ' "$input_json" 2>/dev/null >> "$output_file"

    cat >> "$output_file" <<-SVGFOOTER
  </g>
  
  <!-- Legend -->
  <g id="legend" transform="translate(20, 20)">
    <rect width="200" height="110" fill="white" stroke="#cbd5e1" stroke-width="1" rx="4"/>
    <circle cx="20" cy="25" r="5" fill="url(#leafGradient)" stroke="#16a34a"/>
    <text x="32" y="30" class="branch-label" font-size="12">Regular Commit</text>
    <circle cx="20" cy="50" r="6" fill="url(#mergeGradient)" stroke="#7c3aed"/>
    <text x="32" y="55" class="branch-label" font-size="12">Merge Commit</text>
    <circle cx="20" cy="75" r="6" fill="url(#forkGradient)" stroke="#ea580c"/>
    <text x="32" y="80" class="branch-label" font-size="12">Fork Point</text>
    <circle cx="20" cy="100" r="6" fill="url(#tagGradient)" stroke="#0284c7"/>
    <text x="32" y="105" class="branch-label" font-size="12">Tagged</text>
  </g>
  
  <!-- Repository info -->
  <g id="info" transform="translate(20, $((height - 40)))">
    <text x="0" y="0" class="branch-label" font-size="12" fill="#666">
      Repository: $repo_name
    </text>
    <text x="0" y="20" class="branch-label" font-size="10" fill="#999">
      Generated: $(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)
    </text>
  </g>
</svg>
SVGFOOTER

    echo "$output_file"
}

# ============================================================================
# MINI SVG RENDERING (for README inline embedding)
# ============================================================================

# Renders a simplified, miniaturised SVG with CSS sway animation.
# Meant to be embedded inline in Markdown via <img> or raw SVG include.
render_mini_svg_tree() {
    local input_json="$1"
    local output_file="${2:-git-tree-mini.svg}"

    # Compute bounding box from actual positions
    local max_y max_x min_x min_y commit_count
    max_y=$(jq '[.commits[].position.y // 0] | max' "$input_json" 2>/dev/null || echo 400)
    min_y=$(jq '[.commits[].position.y // 0] | min' "$input_json" 2>/dev/null || echo 0)
    max_x=$(jq '[.commits[].position.x // 600] | max' "$input_json" 2>/dev/null || echo 600)
    min_x=$(jq '[.commits[].position.x // 600] | min' "$input_json" 2>/dev/null || echo 600)
    commit_count=$(jq '.commits | length' "$input_json" 2>/dev/null || echo 0)

    # Scale to fit within ~300px wide, proportional height
    local data_w=$(( max_x - min_x + 40 ))
    local data_h=$(( max_y - min_y + 40 ))
    [[ $data_w -lt 200 ]] && data_w=200

    # Viewbox covers data bounds with padding
    local vb_x=$(( min_x - 20 ))
    local vb_y=$(( min_y - 20 ))

    # Displayed width, capped for README readability
    local display_w=300
    local display_h=$(( display_w * data_h / data_w ))
    [[ $display_h -lt 100 ]] && display_h=100
    [[ $display_h -gt 600 ]] && display_h=600

    cat > "$output_file" <<-MINIHEADER
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg"
     width="$display_w" height="$display_h"
     viewBox="$vb_x $vb_y $data_w $data_h">
  <style>
    @keyframes sway {
      0%   { transform: translateX(0); }
      25%  { transform: translateX(3px); }
      50%  { transform: translateX(-2px); }
      75%  { transform: translateX(4px); }
      100% { transform: translateX(0); }
    }
    .mini-node { animation: sway 4s ease-in-out infinite; }
    .mini-line { stroke-width: 1.5; fill: none; opacity: 0.5; }
  </style>
  <rect width="100%" height="100%" fill="#0a0a1a" rx="6"/>
  <g class="mini-node">
MINIHEADER

    # Draw branch connections (simplified — thin lines)
    jq -r '
        (.commits | map({(.sha): .position}) | add // {}) as $positions |
        .commits[] | select(.position) |
        .position as $pos |
        (.parents // "" | split(" ") | map(select(. != "")))[] |
        ($positions[.] // null) | select(. != null) |
        . as $pp |
        (if $pos.lane == $pp.lane then "#4ade80" else "#64748b" end) as $col |
        if $pos.lane != $pp.lane then
            (($pos.y + ($pp.y - $pos.y) * 0.4) | floor) as $cy1 |
            (($pos.y + ($pp.y - $pos.y) * 0.6) | floor) as $cy2 |
            "    <path class=\"mini-line\" stroke=\"\($col)\" d=\"M \($pos.x) \($pos.y) C \($pos.x) \($cy1), \($pp.x) \($cy2), \($pp.x) \($pp.y)\"/>"
        else
            "    <line class=\"mini-line\" stroke=\"\($col)\" x1=\"\($pos.x)\" y1=\"\($pos.y)\" x2=\"\($pp.x)\" y2=\"\($pp.y)\"/>"
        end
    ' "$input_json" 2>/dev/null >> "$output_file"

    # Draw commit dots (small, colour-coded)
    jq -r '
        ([.tags[]? | .sha] | map({(.): true}) | add // {}) as $tag_shas |
        .commits[] | select(.position) |
        (
            if $tag_shas[.sha] then "#38bdf8"
            elif .position.is_merge then "#c084fc"
            elif .position.is_fork then "#fb923c"
            else "#4ade80"
            end
        ) as $fill |
        "    <circle cx=\"\(.position.x)\" cy=\"\(.position.y)\" r=\"\((.position.radius // 6) * 0.7 | floor | if . < 3 then 3 else . end)\" fill=\"\($fill)\" opacity=\"0.9\"/>"
    ' "$input_json" 2>/dev/null >> "$output_file"

    cat >> "$output_file" <<-'MINIFOOTER'
  </g>
</svg>
MINIFOOTER

    echo "$output_file"
}
