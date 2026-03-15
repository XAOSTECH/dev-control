#!/usr/bin/env bash
#
# Dev-Control Shared Library: HTML Canvas Tree Renderer
# Renders interactive git tree with organic waving leaf animations
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# ============================================================================
# HTML CANVAS RENDERING
# ============================================================================

render_html_tree() {
    local input_json="$1"
    local output_file="${2:-git-tree.html}"

    # Get dimensions from data
    local commit_count
    commit_count=$(jq '.commits | length' "$input_json" 2>/dev/null || echo 100)
    local width=1200
    local height=$(( 120 + commit_count * 80 ))
    [[ $height -lt 800 ]] && height=800

    # Embed JSON data
    local json_data
    json_data=$(cat "$input_json")

    # Create HTML with embedded Canvas visualization
    cat > "$output_file" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Git Tree Visualization</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }

        body {
            font-family: system-ui, -apple-system, sans-serif;
            background: linear-gradient(160deg, #0f0c29 0%, #302b63 50%, #24243e 100%);
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            padding: 20px;
            color: #e0e0e0;
        }

        .container {
            background: rgba(15, 15, 35, 0.85);
            border-radius: 16px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.5), 0 0 40px rgba(100, 60, 200, 0.15);
            padding: 30px;
            max-width: 95vw;
            width: 100%;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(100, 100, 200, 0.15);
        }

        h1 {
            color: #c0a0ff;
            margin-bottom: 8px;
            font-size: 28px;
            text-shadow: 0 0 20px rgba(160, 100, 255, 0.4);
        }

        .info {
            color: #8888aa;
            margin-bottom: 20px;
            font-size: 14px;
        }

        .canvas-viewport {
            position: relative;
            width: 100%;
            overflow: auto;
            border: 1px solid rgba(100, 100, 200, 0.2);
            border-radius: 8px;
            background: #0a0a1a;
            max-height: 80vh;
        }

        #treeCanvas {
            display: block;
            cursor: crosshair;
        }

        #tooltip {
            position: fixed;
            background: rgba(20, 10, 40, 0.96);
            color: white;
            padding: 14px 18px;
            border-radius: 10px;
            font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;
            font-size: 12px;
            pointer-events: none;
            opacity: 0;
            transition: opacity 0.15s ease;
            box-shadow: 0 8px 24px rgba(0,0,0,0.6), 0 0 12px rgba(120, 80, 200, 0.3);
            max-width: 420px;
            z-index: 1000;
            border: 1px solid rgba(140, 100, 240, 0.3);
        }

        #tooltip.visible { opacity: 1; }

        .tooltip-sha {
            color: #60a5fa;
            font-weight: bold;
            margin-bottom: 6px;
            font-size: 13px;
        }
        .tooltip-msg {
            color: #e2e8f0;
            margin-bottom: 6px;
            line-height: 1.4;
            word-break: break-word;
        }
        .tooltip-author {
            color: #a78bfa;
            font-size: 11px;
            margin-bottom: 4px;
        }
        .tooltip-date {
            color: #64748b;
            font-size: 10px;
        }
        .tooltip-refs {
            color: #34d399;
            font-size: 11px;
            margin-top: 4px;
            font-weight: bold;
        }

        .controls {
            margin-top: 15px;
            display: flex;
            gap: 10px;
            flex-wrap: wrap;
            align-items: center;
        }

        button {
            padding: 8px 16px;
            background: rgba(80, 50, 160, 0.6);
            color: #c0b0e8;
            border: 1px solid rgba(120, 80, 220, 0.4);
            border-radius: 6px;
            cursor: pointer;
            font-size: 13px;
            transition: all 0.2s;
        }
        button:hover {
            background: rgba(100, 60, 200, 0.8);
            color: white;
            box-shadow: 0 0 12px rgba(120, 80, 220, 0.4);
        }

        .stats {
            margin-left: auto;
            font-size: 12px;
            color: #6b6b8a;
        }

        .legend {
            display: flex;
            gap: 16px;
            margin-top: 12px;
            flex-wrap: wrap;
        }
        .legend-item {
            display: flex;
            align-items: center;
            gap: 6px;
            font-size: 12px;
            color: #8888aa;
        }
        .legend-dot {
            width: 12px;
            height: 12px;
            border-radius: 50%;
            display: inline-block;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🌳 Git Tree Visualization</h1>
        <p class="info">Hover over leaves to see commit details · Scroll to explore the full tree · Click a leaf to highlight its ancestry</p>

        <div class="canvas-viewport" id="viewport">
HTMLEOF

    # Add canvas with dimensions
    cat >> "$output_file" <<CANVASHTML
            <canvas id="treeCanvas" width="$width" height="$height"></canvas>
CANVASHTML

    cat >> "$output_file" <<'HTMLEOF2'
        </div>

        <div class="controls">
            <button onclick="toggleAnimation()">⏯ Animation</button>
            <button onclick="toggleWind()">🌬 Wind</button>
            <button onclick="resetView()">↺ Reset</button>
            <span class="stats" id="stats"></span>
        </div>

        <div class="legend">
            <div class="legend-item"><span class="legend-dot" style="background:#4ade80"></span> Commit</div>
            <div class="legend-item"><span class="legend-dot" style="background:#c084fc"></span> Merge</div>
            <div class="legend-item"><span class="legend-dot" style="background:#fb923c"></span> Fork point</div>
            <div class="legend-item"><span class="legend-dot" style="background:#38bdf8"></span> Tagged</div>
        </div>
    </div>

    <div id="tooltip">
        <div class="tooltip-sha"></div>
        <div class="tooltip-msg"></div>
        <div class="tooltip-author"></div>
        <div class="tooltip-date"></div>
        <div class="tooltip-refs"></div>
    </div>

    <script>
        // Embedded git data
        const gitData =
HTMLEOF2

    # Embed JSON data
    cat "$input_json" >> "$output_file"

    # Add JavaScript visualization code
    cat >> "$output_file" <<'JSEOF'
;

        const canvas = document.getElementById('treeCanvas');
        const ctx = canvas.getContext('2d');
        const tooltip = document.getElementById('tooltip');
        const viewport = document.getElementById('viewport');
        const statsEl = document.getElementById('stats');

        let animationEnabled = true;
        let windEnabled = true;
        let frame = 0;
        let hoveredCommit = null;
        let selectedCommit = null;

        // Build lookup maps
        const commitBySha = {};
        gitData.commits.forEach(c => { commitBySha[c.sha] = c; });

        // Build tag lookup
        const tagsBySha = {};
        (gitData.tags || []).forEach(t => {
            if (!tagsBySha[t.sha]) tagsBySha[t.sha] = [];
            tagsBySha[t.sha].push(t.name);
        });

        // Build branch lookup
        const branchBySha = {};
        (gitData.branches || []).forEach(b => {
            if (!branchBySha[b.sha]) branchBySha[b.sha] = [];
            branchBySha[b.sha].push(b.name);
        });

        // Stats
        const mergeCount = gitData.commits.filter(c => c.position && c.position.is_merge).length;
        const forkCount = gitData.commits.filter(c => c.position && c.position.is_fork).length;
        statsEl.textContent = `${gitData.commits.length} commits · ${mergeCount} merges · ${forkCount} forks · ${(gitData.tags || []).length} tags`;

        // Branch colours (consistent per lane)
        const LANE_COLOURS = [
            '#4ade80', '#60a5fa', '#f472b6', '#fb923c', '#a78bfa',
            '#34d399', '#fbbf24', '#f87171', '#38bdf8', '#c084fc',
            '#2dd4bf', '#e879f9', '#facc15', '#818cf8', '#fb7185'
        ];
        function laneColour(lane) {
            if (lane === 0) return '#4ade80'; // trunk green
            const idx = ((Math.abs(lane) - 1) % (LANE_COLOURS.length - 1)) + 1;
            return LANE_COLOURS[idx];
        }

        // Get ancestry chain for highlighting
        function getAncestry(commit) {
            const shas = new Set();
            const queue = [commit.sha];
            let limit = 500;
            while (queue.length > 0 && limit-- > 0) {
                const sha = queue.shift();
                if (shas.has(sha)) continue;
                shas.add(sha);
                const c = commitBySha[sha];
                if (c && c.parents) {
                    c.parents.split(' ').filter(Boolean).forEach(p => queue.push(p));
                }
            }
            return shas;
        }

        let ancestryHighlight = null;

        // Wind simulation
        function windOffset(x, y, t) {
            if (!windEnabled) return 0;
            // Perlin-ish multi-frequency wind
            const w1 = Math.sin(t * 0.02 + x * 0.008 + y * 0.003) * 3;
            const w2 = Math.sin(t * 0.035 + x * 0.012 - y * 0.005) * 1.5;
            const w3 = Math.cos(t * 0.015 + y * 0.007) * 2;
            return w1 + w2 + w3;
        }

        function drawTree() {
            ctx.clearRect(0, 0, canvas.width, canvas.height);

            // Dark background with subtle gradient
            const bg = ctx.createLinearGradient(0, 0, 0, canvas.height);
            bg.addColorStop(0, '#0a0a1a');
            bg.addColorStop(0.5, '#0d0d20');
            bg.addColorStop(1, '#080818');
            ctx.fillStyle = bg;
            ctx.fillRect(0, 0, canvas.width, canvas.height);

            // Subtle grid
            ctx.strokeStyle = 'rgba(60, 60, 100, 0.08)';
            ctx.lineWidth = 0.5;
            for (let y = 0; y < canvas.height; y += 80) {
                ctx.beginPath();
                ctx.moveTo(0, y);
                ctx.lineTo(canvas.width, y);
                ctx.stroke();
            }

            // ---- Draw branch connection lines ----
            gitData.commits.forEach(commit => {
                if (!commit.position || !commit.parents) return;
                const parents = commit.parents.split(' ').filter(Boolean);
                parents.forEach(parentSha => {
                    const parent = commitBySha[parentSha];
                    if (!parent || !parent.position) return;

                    const cx = commit.position.x + windOffset(commit.position.x, commit.position.y, frame);
                    const cy = commit.position.y;
                    const px = parent.position.x + windOffset(parent.position.x, parent.position.y, frame);
                    const py = parent.position.y;

                    const colour = laneColour(commit.position.lane);
                    const isHighlighted = ancestryHighlight && ancestryHighlight.has(commit.sha) && ancestryHighlight.has(parentSha);

                    ctx.strokeStyle = isHighlighted ? colour : (colour + '40');
                    ctx.lineWidth = isHighlighted ? 2.5 : 1.5;

                    ctx.beginPath();
                    ctx.moveTo(cx, cy);

                    if (commit.position.lane !== parent.position.lane) {
                        // Curved branch/merge line
                        const cpx1 = cx;
                        const cpy1 = cy + (py - cy) * 0.4;
                        const cpx2 = px;
                        const cpy2 = cy + (py - cy) * 0.6;
                        ctx.bezierCurveTo(cpx1, cpy1, cpx2, cpy2, px, py);
                    } else {
                        // Straight trunk line
                        ctx.lineTo(px, py);
                    }
                    ctx.stroke();
                });
            });

            // ---- Draw commit nodes (leaves) ----
            gitData.commits.forEach(commit => {
                if (!commit.position) return;
                const pos = commit.position;
                const isHovered = hoveredCommit === commit;
                const isSelected = selectedCommit === commit;
                const isInAncestry = ancestryHighlight && ancestryHighlight.has(commit.sha);
                const hasTags = tagsBySha[commit.sha];
                const hasBranch = branchBySha[commit.sha];

                // Wind wobble on leaves
                const wobble = windOffset(pos.x, pos.y, frame);
                const x = pos.x + wobble;
                const y = pos.y;

                let baseRadius = pos.radius || 6;
                if (hasTags) baseRadius = Math.max(baseRadius, 9);
                const radius = isHovered ? baseRadius * 1.8 : (isSelected ? baseRadius * 1.5 : baseRadius);

                // Choose colour
                let fillColour;
                if (hasTags) fillColour = '#38bdf8';
                else if (pos.is_merge) fillColour = '#c084fc';
                else if (pos.is_fork) fillColour = '#fb923c';
                else fillColour = laneColour(pos.lane);

                const dimmed = ancestryHighlight && !isInAncestry;
                const alpha = dimmed ? 0.15 : 1;

                // Glow for hovered/selected
                if ((isHovered || isSelected) && !dimmed) {
                    ctx.save();
                    ctx.globalAlpha = 0.25;
                    ctx.shadowColor = fillColour;
                    ctx.shadowBlur = 20;
                    ctx.fillStyle = fillColour;
                    ctx.beginPath();
                    ctx.arc(x, y, radius * 2.2, 0, Math.PI * 2);
                    ctx.fill();
                    ctx.restore();
                }

                // Leaf shape: draw a tiny leaf silhouette for non-merge commits
                ctx.save();
                ctx.globalAlpha = alpha;

                if (!pos.is_merge && !hasTags && animationEnabled) {
                    // Organic leaf shape
                    const leafAngle = Math.sin(frame * 0.025 + pos.x * 0.01) * 0.3 + wobble * 0.05;
                    ctx.save();
                    ctx.translate(x, y);
                    ctx.rotate(leafAngle);

                    // Leaf body
                    ctx.beginPath();
                    ctx.moveTo(0, -radius * 1.2);
                    ctx.bezierCurveTo(radius * 0.8, -radius * 0.4, radius * 0.8, radius * 0.6, 0, radius * 1.2);
                    ctx.bezierCurveTo(-radius * 0.8, radius * 0.6, -radius * 0.8, -radius * 0.4, 0, -radius * 1.2);
                    ctx.fillStyle = fillColour;
                    ctx.fill();

                    // Leaf vein
                    ctx.strokeStyle = 'rgba(255,255,255,0.2)';
                    ctx.lineWidth = 0.5;
                    ctx.beginPath();
                    ctx.moveTo(0, -radius * 0.8);
                    ctx.lineTo(0, radius * 0.8);
                    ctx.stroke();

                    ctx.restore();
                } else {
                    // Circle for merges, tags, or when animation is off
                    const grad = ctx.createRadialGradient(x - radius * 0.3, y - radius * 0.3, 0, x, y, radius);
                    grad.addColorStop(0, fillColour);
                    grad.addColorStop(1, fillColour + 'aa');
                    ctx.fillStyle = grad;
                    ctx.beginPath();
                    ctx.arc(x, y, radius, 0, Math.PI * 2);
                    ctx.fill();

                    // Outline
                    ctx.strokeStyle = isHovered ? '#fbbf24' : 'rgba(255,255,255,0.15)';
                    ctx.lineWidth = isHovered ? 2 : 1;
                    ctx.stroke();
                }

                ctx.restore();

                // Tag/branch labels
                if (!dimmed && (hasTags || hasBranch)) {
                    ctx.save();
                    ctx.globalAlpha = alpha;
                    const labels = [];
                    if (hasTags) hasTags.forEach(t => labels.push({ text: '🏷 ' + t, colour: '#38bdf8' }));
                    if (hasBranch) hasBranch.forEach(b => labels.push({ text: '⎇ ' + b, colour: '#34d399' }));

                    labels.forEach((lbl, li) => {
                        const lx = x + radius + 8;
                        const ly = y + 4 + li * 16;
                        ctx.font = 'bold 10px system-ui, sans-serif';
                        const metrics = ctx.measureText(lbl.text);
                        // Label background
                        ctx.fillStyle = 'rgba(10, 10, 30, 0.85)';
                        ctx.beginPath();
                        ctx.roundRect(lx - 4, ly - 11, metrics.width + 8, 15, 3);
                        ctx.fill();
                        ctx.fillStyle = lbl.colour;
                        ctx.fillText(lbl.text, lx, ly);
                    });
                    ctx.restore();
                }
            });

            if (animationEnabled) {
                frame++;
                requestAnimationFrame(drawTree);
            }
        }

        // Handle mouse movement for tooltip — positioned close to cursor
        canvas.addEventListener('mousemove', (e) => {
            const rect = canvas.getBoundingClientRect();
            // Account for scroll within viewport
            const scaleX = canvas.width / rect.width;
            const scaleY = canvas.height / rect.height;
            const mouseX = (e.clientX - rect.left) * scaleX;
            const mouseY = (e.clientY - rect.top) * scaleY;

            let found = null;
            let bestDist = Infinity;
            gitData.commits.forEach(commit => {
                if (!commit.position) return;
                const wx = windOffset(commit.position.x, commit.position.y, frame);
                const dx = mouseX - (commit.position.x + wx);
                const dy = mouseY - commit.position.y;
                const distance = Math.sqrt(dx * dx + dy * dy);
                const hitRadius = Math.max((commit.position.radius || 6) * 2, 12);
                if (distance < hitRadius && distance < bestDist) {
                    bestDist = distance;
                    found = commit;
                }
            });

            if (found !== hoveredCommit) {
                hoveredCommit = found;
                if (!animationEnabled) drawTree();
            }

            if (hoveredCommit) {
                tooltip.querySelector('.tooltip-sha').textContent = hoveredCommit.short;
                tooltip.querySelector('.tooltip-msg').textContent = hoveredCommit.subject;
                tooltip.querySelector('.tooltip-author').textContent = `by ${hoveredCommit.author}`;
                tooltip.querySelector('.tooltip-date').textContent = new Date(hoveredCommit.date).toLocaleString();

                const refs = [];
                if (tagsBySha[hoveredCommit.sha]) refs.push(...tagsBySha[hoveredCommit.sha].map(t => '🏷 ' + t));
                if (branchBySha[hoveredCommit.sha]) refs.push(...branchBySha[hoveredCommit.sha].map(b => '⎇ ' + b));
                tooltip.querySelector('.tooltip-refs').textContent = refs.join('  ');

                // Position tooltip near cursor but keep within viewport
                let tx = e.clientX + 16;
                let ty = e.clientY + 16;
                const tw = tooltip.offsetWidth || 300;
                const th = tooltip.offsetHeight || 100;
                if (tx + tw > window.innerWidth - 10) tx = e.clientX - tw - 16;
                if (ty + th > window.innerHeight - 10) ty = e.clientY - th - 16;
                if (tx < 10) tx = 10;
                if (ty < 10) ty = 10;
                tooltip.style.left = tx + 'px';
                tooltip.style.top = ty + 'px';
                tooltip.classList.add('visible');
            } else {
                tooltip.classList.remove('visible');
            }
        });

        canvas.addEventListener('mouseleave', () => {
            hoveredCommit = null;
            tooltip.classList.remove('visible');
            if (!animationEnabled) drawTree();
        });

        // Click to highlight ancestry
        canvas.addEventListener('click', (e) => {
            if (hoveredCommit) {
                if (selectedCommit === hoveredCommit) {
                    selectedCommit = null;
                    ancestryHighlight = null;
                } else {
                    selectedCommit = hoveredCommit;
                    ancestryHighlight = getAncestry(hoveredCommit);
                }
            } else {
                selectedCommit = null;
                ancestryHighlight = null;
            }
            if (!animationEnabled) drawTree();
        });

        function resetView() {
            frame = 0;
            hoveredCommit = null;
            selectedCommit = null;
            ancestryHighlight = null;
            viewport.scrollTop = 0;
            drawTree();
        }

        function toggleAnimation() {
            animationEnabled = !animationEnabled;
            if (animationEnabled) drawTree();
        }

        function toggleWind() {
            windEnabled = !windEnabled;
            if (!animationEnabled) drawTree();
        }

        // Initial draw
        drawTree();
    </script>
</body>
</html>
JSEOF

    echo "$output_file"
}
