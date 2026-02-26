#!/usr/bin/env bash
#
# Dev-Control Shared Library: HTML Canvas Tree Renderer
# Renders interactive git tree with animations on hover
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# ============================================================================
# HTML CANVAS RENDERING
# ============================================================================

render_html_tree() {
    local input_json="$1"
    local output_file="${2:-git-tree.html}"
    
    # Get dimensions
    local stats
    stats=$(get_repo_stats)
    local width=$(echo "$stats" | jq -r '.suggested_width')
    local height=$(echo "$stats" | jq -r '.suggested_height')
    
    # Embed JSON data
    local json_data
    json_data=$(cat "$input_json")
    
    # Create HTML with embedded Canvas visualization
    cat > "$output_file" <<-'HTMLEOF'
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
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            padding: 20px;
        }
        
        .container {
            background: white;
            border-radius: 16px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            padding: 30px;
            max-width: 95vw;
        }
        
        h1 {
            color: #1e293b;
            margin-bottom: 10px;
            font-size: 28px;
        }
        
        .info {
            color: #64748b;
            margin-bottom: 20px;
            font-size: 14px;
        }
        
        #treeCanvas {
            border: 2px solid #e2e8f0;
            border-radius: 8px;
            cursor: crosshair;
            display: block;
        }
        
        #tooltip {
            position: absolute;
            background: rgba(15, 23, 42, 0.95);
            color: white;
            padding: 12px 16px;
            border-radius: 8px;
            font-family: monospace;
            font-size: 12px;
            pointer-events: none;
            opacity: 0;
            transition: opacity 0.2s;
            box-shadow: 0 4px 12px rgba(0,0,0,0.4);
            max-width: 400px;
            z-index: 1000;
        }
        
        #tooltip.visible {
            opacity: 1;
        }
        
        .tooltip-sha {
            color: #60a5fa;
            font-weight: bold;
            margin-bottom: 4px;
        }
        
        .tooltip-author {
            color: #a78bfa;
            font-size: 11px;
            margin-bottom: 4px;
        }
        
        .tooltip-date {
            color: #94a3b8;
            font-size: 10px;
        }
        
        .controls {
            margin-top: 15px;
            display: flex;
            gap: 10px;
            flex-wrap: wrap;
        }
        
        button {
            padding: 8px 16px;
            background: #3b82f6;
            color: white;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
            transition: background 0.2s;
        }
        
        button:hover {
            background: #2563eb;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🌳 Git Tree Visualization</h1>
        <p class="info">Hover over leaves (commits) to see details • Click to zoom</p>
        
HTMLEOF

    # Add canvas with dimensions
    cat >> "$output_file" <<-CANVASHTML
        <canvas id="treeCanvas" width="$width" height="$height"></canvas>
        
        <div class="controls">
            <button onclick="resetView()">Reset View</button>
            <button onclick="toggleAnimation()">Toggle Animation</button>
            <button onclick="exportSVG()">Export as SVG</button>
        </div>
    </div>
    
    <div id="tooltip">
        <div class="tooltip-sha"></div>
        <div class="tooltip-msg"></div>
        <div class="tooltip-author"></div>
        <div class="tooltip-date"></div>
    </div>
    
    <script>
        // Embedded git data
        const gitData = 
CANVASHTML

    # Embed JSON data
    cat "$input_json" >> "$output_file"
    
    # Add JavaScript visualization code
    cat >> "$output_file" <<-'JSEOF'
;
        
        const canvas = document.getElementById('treeCanvas');
        const ctx = canvas.getContext('2d');
        const tooltip = document.getElementById('tooltip');
        
        let animationEnabled = true;
        let animationFrame = 0;
        let hoveredCommit = null;
        
        // Draw fractal tree
        function drawTree() {
            ctx.clearRect(0, 0, canvas.width, canvas.height);
            
            // Background
            const gradient = ctx.createLinearGradient(0, 0, canvas.width, canvas.height);
            gradient.addColorStop(0, '#f8fafc');
            gradient.addColorStop(1, '#e2e8f0');
            ctx.fillStyle = gradient;
            ctx.fillRect(0, 0, canvas.width, canvas.height);
            
            // Draw branch connections
            ctx.strokeStyle = 'rgba(100, 116, 139, 0.3)';
            ctx.lineWidth = 2;
            gitData.commits.forEach(commit => {
                if (!commit.position || !commit.parents) return;
                
                const parents = commit.parents.split(' ').filter(p => p);
                parents.forEach(parentSha => {
                    const parent = gitData.commits.find(c => c.sha === parentSha);
                    if (!parent || !parent.position) return;
                    
                    // Curved branch lines
                    ctx.beginPath();
                    ctx.moveTo(commit.position.x, commit.position.y);
                    
                    const midX = (commit.position.x + parent.position .x) / 2;
                    const midY = (commit.position.y + parent.position.y) / 2 - 20;
                    
                    ctx.quadraticCurveTo(midX, midY, parent.position.x, parent.position.y);
                    ctx.stroke();
                });
            });
            
            // Draw commit nodes (leaves)
            gitData.commits.forEach(commit => {
                if (!commit.position) return;
                
                const pos = commit.position;
                const parentCount = (commit.parents || '').split(' ').filter(p => p).length;
                const isMerge = parentCount > 1;
                const isHovered = hoveredCommit === commit;
                
                // Animate leaves gently
                const wobble = animationEnabled ? Math.sin(animationFrame / 30 + pos.x / 50) * 2 : 0;
                const x = pos.x + wobble;
                const y = pos.y;
                
                // Draw leaf
                const radius = isMerge ? 10 : 7;
                const expandedRadius = isHovered ? radius * 1.5 : radius;
                
                // Leaf gradient
                const leafGradient = ctx.createRadialGradient(x, y, 0, x, y, expandedRadius);
                if (isMerge) {
                    leafGradient.addColorStop(0, '#a78bfa');
                    leafGradient.addColorStop(1, '#8b5cf6');
                } else {
                    leafGradient.addColorStop(0, '#4ade80');
                    leafGradient.addColorStop(1, '#22c55e');
                }
                
                ctx.fillStyle = leafGradient;
                ctx.beginPath();
                ctx.arc(x, y, expandedRadius, 0, Math.PI * 2);
                ctx.fill();
                
                // Leaf outline
                ctx.strokeStyle = isHovered ? '#fbbf24' : '#16a34a';
                ctx.lineWidth = isHovered ? 3 : 1.5;
                ctx.stroke();
                
                // Draw glow on hover
                if (isHovered) {
                    ctx.save();
                    ctx.globalAlpha = 0.3;
                    ctx.fillStyle = '#fbbf24';
                    ctx.beginPath();
                    ctx.arc(x, y, expandedRadius * 2, 0, Math.PI * 2);
                    ctx.fill();
                    ctx.restore();
                }
            });
            
            // Draw branch labels
            ctx.font = 'bold 12px sans-serif';
            ctx.fillStyle = '#1e40af';
            gitData.branches.forEach(branch => {
                const commit = gitData.commits.find(c => c.sha === branch.sha);
                if (!commit || !commit.position) return;
                
                const text = branch.name;
                const x = commit.position.x + 14;
                const y = commit.position.y + 5;
                
                // Background for readability
                const metrics = ctx.measureText(text);
                ctx.fillStyle = 'rgba(255, 255, 255, 0.9)';
                ctx.fillRect(x - 2, y - 11, metrics.width + 4, 14);
                
                ctx.fillStyle = '#1e40af';
                ctx.fillText(text, x, y);
            });
            
            if (animationEnabled) {
                animationFrame++;
                requestAnimationFrame(drawTree);
            }
        }
        
        // Handle mouse movement for hover
        canvas.addEventListener('mousemove', (e) => {
            const rect = canvas.getBoundingClientRect();
            const mouseX = e.clientX - rect.left;
            const mouseY = e.clientY - rect.top;
            
            let found = null;
            gitData.commits.forEach(commit => {
                if (!commit.position) return;
                
                const dx = mouseX - commit.position.x;
                const dy = mouseY - commit.position.y;
                const distance = Math.sqrt(dx * dx + dy * dy);
                
                if (distance < 15) {
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
                tooltip.querySelector('.tooltip-author').textContent = `by ${hoveredCommit.author} <${hoveredCommit.email}>`;
                tooltip.querySelector('.tooltip-date').textContent = new Date(hoveredCommit.date).toLocaleString();
                
                tooltip.style.left = e.clientX + 15 + 'px';
                tooltip.style.top = e.clientY - 10 + 'px';
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
        
        function resetView() {
            animationFrame = 0;
            hoveredCommit = null;
            drawTree();
        }
        
        function toggleAnimation() {
            animationEnabled = !animationEnabled;
            if (animationEnabled) {
                drawTree();
            }
        }
        
        function exportSVG() {
            alert('SVG export will save the current view as git-tree.svg');
            // TODO: Implement canvas-to-SVG export
        }
        
        // Initial draw
        drawTree();
    </script>
</body>
</html>
JSEOF

    echo "$output_file"
}
