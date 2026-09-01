#!/usr/bin/env bash
#
# Dev-Control Shared Library: SVG Tree Renderer
# Renders git tree as static SVG with fractal styling
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# Dual-mode bootstrap. When executed directly (rather than sourced), enable strict mode and pull in the shared colour/print libs so the module's functions can be exercised standalone. When sourced by a master, skip this block — the parent owns those globals.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    DEV_CONTROL_DIR="$(dirname "$SCRIPT_DIR")"
    export DEV_CONTROL_DIR
    # shellcheck source=../colours.sh
    source "$SCRIPT_DIR/lib/colours.sh"
    # shellcheck source=../print.sh
    source "$SCRIPT_DIR/lib/print.sh"
fi

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
        (($tag_shas[.sha]) or ((.refs // "") | contains("tag:"))) as $is_tag |
        # Pick gradient
        (
            if $is_tag then "tagGradient"
            elif .position.is_merge then "mergeGradient"
            elif .position.is_fork then "forkGradient"
            else "leafGradient"
            end
        ) as $grad |
        # Pick stroke
        (
            if $is_tag then "#0284c7"
            elif .position.is_merge then "#7c3aed"
            elif .position.is_fork then "#ea580c"
            else "#16a34a"
            end
        ) as $stroke |
        if (.collapsed // false) then
            "    <g class=\"commit-leaf\"><rect x=\"\(.position.x - 9)\" y=\"\(.position.y - 9)\" width=\"18\" height=\"18\" rx=\"3\" transform=\"rotate(45 \(.position.x) \(.position.y))\" fill=\"#475569\" stroke=\"#cbd5e1\" stroke-width=\"1.5\"/><text x=\"\(.position.x)\" y=\"\(.position.y + 4)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"11\" font-weight=\"bold\" fill=\"#f8fafc\">\(.count // 0)</text><title>\($safe_subj)</title></g>"
        else
            "    <circle class=\"commit-leaf\" cx=\"\(.position.x)\" cy=\"\(.position.y)\" r=\"\(.position.radius // 6)\" fill=\"url(#\($grad))\" stroke=\"\($stroke)\" stroke-width=\"1.5\"><title>\($short): \($safe_subj)</title></circle>"
        end
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
      Generated: $(TZ=UTC git log -1 --format=%cd --date=format-local:'%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || echo unknown)
    </text>
  </g>
</svg>
SVGFOOTER

    echo "$output_file"
}

# ============================================================================
# MINI SVG RENDERING (for README inline embedding)
# ============================================================================

# Renders a compact, bounded horizontal "railway" banner for README embedding.
# History flows left (old) to right (new); lanes are clamped and the height is fixed
# so the frame stays reasonable regardless of history length. Collapsed runs appear as
# grey diamonds; tags, merges and forks are colour-coded.
render_mini_svg_tree() {
    local input_json="$1"
    local output_file="${2:-git-tree-mini.svg}"

    local total max_depth tag_count
    total=$(jq '[.commits[] | select(.position)] | length' "$input_json" 2>/dev/null || echo 1)
    max_depth=$(jq '[.commits[].position.depth // 0] | max' "$input_json" 2>/dev/null || echo 0)
    tag_count=$(jq '[.commits[] | select((.refs // "") | contains("tag:"))] | length' "$input_json" 2>/dev/null || echo 0)
    [[ -z "$total" || "$total" -lt 1 ]] && total=1
    [[ -z "$max_depth" || "$max_depth" -lt 0 ]] && max_depth=0

    # Fixed-height banner; width bounded by MAXW so it never overflows a README frame.
    local pad=20 lanes=2 lane_gap=20 vpad=26 maxw=1000
    local h=$(( vpad * 2 + lanes * lane_gap * 2 ))
    local mid_y=$(( h / 2 ))
    local denom=$(( max_depth > 0 ? max_depth : 1 ))
    local step=$(( (maxw - pad * 2) / denom ))
    [[ $step -gt 18 ]] && step=18
    [[ $step -lt 4 ]] && step=4
    local w=$(( pad * 2 + max_depth * step ))
    [[ $w -gt $maxw ]] && w=$maxw
    [[ $w -lt 240 ]] && w=240

    cat > "$output_file" <<-MINIHEADER
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$h" viewBox="0 0 $w $h">
  <rect width="100%" height="100%" fill="#0d1117" rx="8"/>
  <g id="edges" stroke-linecap="round">
MINIHEADER

    jq -r --argjson pad "$pad" --argjson step "$step" --argjson maxd "$max_depth" \
          --argjson midY "$mid_y" --argjson laneGap "$lane_gap" --argjson lanes "$lanes" '
        def cl($l): if $l > $lanes then $lanes elif $l < (-$lanes) then (-$lanes) else $l end;
        (.commits | map(select(.position)) | map({(.sha): {
            x: ($pad + ($maxd - .position.depth) * $step),
            y: ($midY + (cl(.position.lane)) * $laneGap)
        }}) | add // {}) as $P |
        .commits[] | select(.position) | ($P[.sha]) as $a |
        (.parents // "" | split(" ") | map(select(. != "")))[] |
        ($P[.] // null) | select(. != null) | . as $b |
        if ($a.y == $b.y) then
            "    <line x1=\"\($a.x)\" y1=\"\($a.y)\" x2=\"\($b.x)\" y2=\"\($b.y)\" stroke=\"#2ea043\" stroke-width=\"1.6\" opacity=\"0.7\"/>"
        else
            (($a.x + $b.x) / 2) as $mx |
            "    <path d=\"M \($a.x) \($a.y) C \($mx) \($a.y), \($mx) \($b.y), \($b.x) \($b.y)\" fill=\"none\" stroke=\"#388bfd\" stroke-width=\"1.4\" opacity=\"0.65\"/>"
        end
    ' "$input_json" 2>/dev/null >> "$output_file"

    echo '  </g>' >> "$output_file"
    echo '  <g id="nodes">' >> "$output_file"

    jq -r --argjson pad "$pad" --argjson step "$step" --argjson maxd "$max_depth" \
          --argjson midY "$mid_y" --argjson laneGap "$lane_gap" --argjson lanes "$lanes" '
        def cl($l): if $l > $lanes then $lanes elif $l < (-$lanes) then (-$lanes) else $l end;
        .commits[] | select(.position) |
        ($pad + ($maxd - .position.depth) * $step) as $x |
        ($midY + (cl(.position.lane)) * $laneGap) as $y |
        if (.collapsed // false) then
            "    <rect x=\"\($x - 4)\" y=\"\($y - 4)\" width=\"8\" height=\"8\" rx=\"1.5\" transform=\"rotate(45 \($x) \($y))\" fill=\"#6e7681\" stroke=\"#c9d1d9\" stroke-width=\"0.7\" opacity=\"0.9\"/>"
        else
            (if ((.refs // "") | contains("tag:")) then "#e3b341"
             elif .position.is_merge then "#a371f7"
             elif .position.is_fork then "#f0883e"
             else "#3fb950" end) as $fill |
            (if ((.refs // "") | contains("tag:")) or .position.is_merge or .position.is_fork then 4 else 3 end) as $r |
            "    <circle cx=\"\($x)\" cy=\"\($y)\" r=\"\($r)\" fill=\"\($fill)\" opacity=\"0.95\"/>"
        end
    ' "$input_json" 2>/dev/null >> "$output_file"

    cat >> "$output_file" <<-MINIFOOTER
  </g>
  <text x="$(( w - 8 ))" y="$(( h - 7 ))" text-anchor="end" font-family="sans-serif" font-size="9" fill="#6e7681">${total} nodes &#183; ${tag_count} tags</text>
</svg>
MINIFOOTER

    echo "$output_file"
}
