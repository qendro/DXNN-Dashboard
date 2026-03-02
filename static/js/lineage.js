// NEAT Lineage Visualization
let lineageData = null;
let currentPopulation = null;
let svg = null;
let g = null;
let zoom = null;

// Configuration
const config = {
    nodeRadius: 10,
    levelHeight: 150,
    nodeSpacing: 80,
    margin: { top: 60, right: 60, bottom: 60, left: 60 }
};

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    initializeVisualization();
    loadLineageData();
    setupEventListeners();
});

function setupEventListeners() {
    document.getElementById('population-select').addEventListener('change', (e) => {
        currentPopulation = e.target.value;
        renderVisualization();
    });
    
    document.getElementById('view-mode').addEventListener('change', () => {
        renderVisualization();
    });
    
    document.getElementById('color-by').addEventListener('change', () => {
        renderVisualization();
    });
    
    document.getElementById('zoom-in').addEventListener('click', () => {
        zoomIn();
    });
    
    document.getElementById('zoom-out').addEventListener('click', () => {
        zoomOut();
    });
    
    document.getElementById('zoom-fit').addEventListener('click', () => {
        fitToScreen();
    });
    
    document.getElementById('export-svg').addEventListener('click', () => {
        exportSVG();
    });
    
    document.getElementById('close-details').addEventListener('click', () => {
        document.getElementById('details-panel').classList.add('hidden');
    });
}

function initializeVisualization() {
    const container = document.getElementById('lineage-viz');
    const width = container.clientWidth;
    const height = container.clientHeight;
    
    // Create SVG
    svg = d3.select('#lineage-viz')
        .append('svg')
        .attr('width', width)
        .attr('height', height);
    
    // Add zoom behavior
    zoom = d3.zoom()
        .scaleExtent([0.1, 4])
        .on('zoom', (event) => {
            g.attr('transform', event.transform);
        });
    
    svg.call(zoom);
    
    // Create main group
    g = svg.append('g')
        .attr('transform', `translate(${config.margin.left},${config.margin.top})`);
}

async function loadLineageData() {
    try {
        updateStatus('Loading lineage data...');
        const response = await fetch('/api/lineage');
        const data = await response.json();
        
        lineageData = data;
        populatePopulationSelect(data.populations);
        
        if (data.populations.length > 0) {
            currentPopulation = data.populations[0].id;
            document.getElementById('population-select').value = currentPopulation;
            renderVisualization();
        }
        
        updateStatus('Ready');
    } catch (error) {
        console.error('Error loading lineage data:', error);
        updateStatus('Error loading data');
    }
}

function populatePopulationSelect(populations) {
    const select = document.getElementById('population-select');
    select.innerHTML = populations.map(pop => 
        `<option value="${pop.id}">${pop.id} (${pop.generations} gens, ${pop.agents} agents)</option>`
    ).join('');
}

function renderVisualization() {
    if (!lineageData || !currentPopulation) return;
    
    const viewMode = document.getElementById('view-mode').value;
    const popData = lineageData.populations.find(p => p.id === currentPopulation);
    
    if (!popData) return;
    
    // Clear existing visualization
    g.selectAll('*').remove();
    
    // Update stats
    updateStats(popData);
    
    // Render based on view mode
    if (viewMode === 'tree') {
        renderTreeView(popData);
    } else {
        renderTimelineView(popData);
    }
    
    // Update legend
    updateLegend();
    
    // Auto-fit to screen after rendering
    setTimeout(() => fitToScreen(), 100);
}

function renderTreeView(popData) {
    const width = svg.node().getBoundingClientRect().width - config.margin.left - config.margin.right;
    const height = svg.node().getBoundingClientRect().height - config.margin.top - config.margin.bottom;
    
    // Build hierarchy from parent-child relationships
    const root = buildHierarchy(popData);
    
    // Create tree layout with better spacing
    const treeLayout = d3.tree()
        .size([width, height])
        .separation((a, b) => {
            // More spacing between siblings and cousins
            if (a.parent === b.parent) {
                return 2; // Siblings
            } else {
                return 3; // Cousins
            }
        });
    
    const treeData = treeLayout(root);
    
    // Filter out the virtual root node for rendering
    const nodes = treeData.descendants().filter(d => d.data.id !== 'root');
    const links = treeData.links().filter(d => d.source.data.id !== 'root');
    
    // Draw links with better visibility
    g.selectAll('.link')
        .data(links)
        .enter()
        .append('path')
        .attr('class', 'link')
        .attr('d', d3.linkVertical()
            .x(d => d.x)
            .y(d => d.y))
        .attr('stroke', '#94a3b8')
        .attr('stroke-width', 2.5)
        .attr('fill', 'none');
    
    // Draw nodes
    const nodeGroups = g.selectAll('.node')
        .data(nodes)
        .enter()
        .append('g')
        .attr('class', 'node')
        .attr('transform', d => `translate(${d.x},${d.y})`)
        .on('click', (event, d) => showAgentDetails(d.data))
        .on('mouseover', (event, d) => showTooltip(event, d.data))
        .on('mouseout', hideTooltip);
    
    nodeGroups.append('circle')
        .attr('r', config.nodeRadius)
        .attr('fill', d => getNodeColor(d.data))
        .attr('stroke', '#fff')
        .attr('stroke-width', 3)
        .style('cursor', 'pointer');
    
    // Add fitness labels for high performers - larger and more visible
    nodeGroups.filter(d => d.data.fitness && d.data.fitness > 80)
        .append('text')
        .attr('dy', -config.nodeRadius - 8)
        .attr('text-anchor', 'middle')
        .attr('font-size', '13px')
        .attr('fill', '#10b981')
        .attr('font-weight', 'bold')
        .attr('stroke', '#fff')
        .attr('stroke-width', 3)
        .attr('paint-order', 'stroke')
        .text(d => d.data.fitness.toFixed(1));
    
    // Add population labels - larger and more readable
    nodeGroups.append('text')
        .attr('dy', config.nodeRadius + 20)
        .attr('text-anchor', 'middle')
        .attr('font-size', '12px')
        .attr('fill', '#1e293b')
        .attr('font-weight', '600')
        .attr('stroke', '#fff')
        .attr('stroke-width', 2.5)
        .attr('paint-order', 'stroke')
        .text(d => {
            if (d.data.population) {
                // Extract run number from population ID
                const match = d.data.population.match(/run(\d+)/);
                return match ? `R${match[1]}` : 'R?';
            }
            return '';
        });
}

function renderTimelineView(popData) {
    const width = svg.node().getBoundingClientRect().width - config.margin.left - config.margin.right;
    const height = svg.node().getBoundingClientRect().height - config.margin.top - config.margin.bottom;
    
    // Group agents by generation
    const generations = d3.group(popData.lineage, d => d.generation);
    const maxGen = d3.max(Array.from(generations.keys()));
    
    const xScale = d3.scaleLinear()
        .domain([0, maxGen])
        .range([0, width]);
    
    // Draw generation lines
    g.selectAll('.gen-line')
        .data(Array.from(generations.keys()))
        .enter()
        .append('line')
        .attr('class', 'gen-line')
        .attr('x1', d => xScale(d))
        .attr('x2', d => xScale(d))
        .attr('y1', 0)
        .attr('y2', height)
        .attr('stroke', '#e2e8f0')
        .attr('stroke-width', 1)
        .attr('stroke-dasharray', '4,4');
    
    // Draw generation labels
    g.selectAll('.gen-label')
        .data(Array.from(generations.keys()))
        .enter()
        .append('text')
        .attr('class', 'gen-label')
        .attr('x', d => xScale(d))
        .attr('y', -10)
        .attr('text-anchor', 'middle')
        .attr('font-size', '12px')
        .attr('fill', '#64748b')
        .text(d => `Gen ${d}`);
    
    // Calculate positions for agents in each generation
    const agentPositions = new Map();
    generations.forEach((agents, gen) => {
        const ySpacing = height / (agents.length + 1);
        agents.forEach((agent, i) => {
            agentPositions.set(agent.id, {
                x: xScale(gen),
                y: ySpacing * (i + 1)
            });
        });
    });
    
    // Draw links between parent and child
    const links = [];
    popData.lineage.forEach(agent => {
        if (agent.parent && agentPositions.has(agent.parent)) {
            links.push({
                source: agentPositions.get(agent.parent),
                target: agentPositions.get(agent.id),
                agent: agent
            });
        }
    });
    
    g.selectAll('.link')
        .data(links)
        .enter()
        .append('line')
        .attr('class', 'link')
        .attr('x1', d => d.source.x)
        .attr('y1', d => d.source.y)
        .attr('x2', d => d.target.x)
        .attr('y2', d => d.target.y);
    
    // Draw nodes
    const nodes = g.selectAll('.node')
        .data(popData.lineage)
        .enter()
        .append('g')
        .attr('class', 'node')
        .attr('transform', d => {
            const pos = agentPositions.get(d.id);
            return `translate(${pos.x},${pos.y})`;
        })
        .on('click', (event, d) => showAgentDetails(d))
        .on('mouseover', (event, d) => showTooltip(event, d))
        .on('mouseout', hideTooltip);
    
    nodes.append('circle')
        .attr('r', config.nodeRadius)
        .attr('fill', d => getNodeColor(d));
}

function buildHierarchy(popData) {
    // Create a map of agents by ID
    const agentMap = new Map();
    popData.lineage.forEach(agent => {
        agentMap.set(agent.id, { ...agent, children: [] });
    });
    
    // Build parent-child relationships
    const rootAgents = [];
    agentMap.forEach(agent => {
        if (agent.parent && agentMap.has(agent.parent)) {
            // This agent has a parent, add it as a child
            agentMap.get(agent.parent).children.push(agent);
        } else {
            // This is a root node (no parent)
            rootAgents.push(agent);
        }
    });
    
    // Create a virtual root to hold all root agents
    const root = {
        id: 'root',
        generation: -1,
        fitness: null,
        species: null,
        population: null,
        children: rootAgents
    };
    
    return d3.hierarchy(root);
}

function getNodeColor(agent) {
    const colorBy = document.getElementById('color-by').value;
    
    if (colorBy === 'fitness') {
        const fitness = agent.fitness || 0;
        if (fitness > 80) return '#10b981';
        if (fitness > 60) return '#f59e0b';
        return '#ef4444';
    } else if (colorBy === 'generation') {
        // Color by which population/run they're in
        if (agent.population) {
            const match = agent.population.match(/run(\d+)/);
            if (match) {
                const runNum = parseInt(match[1]);
                const colors = ['#3b82f6', '#8b5cf6', '#ec4899', '#f59e0b', '#10b981'];
                return colors[runNum % colors.length];
            }
        }
        return '#6366f1';
    } else if (colorBy === 'species') {
        // Hash species ID to color
        const hash = hashCode(agent.species || '');
        const hue = hash % 360;
        return `hsl(${hue}, 70%, 60%)`;
    }
    
    return '#6366f1';
}

function hashCode(str) {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
        const char = str.charCodeAt(i);
        hash = ((hash << 5) - hash) + char;
        hash = hash & hash;
    }
    return Math.abs(hash);
}

function showTooltip(event, agent, generation = null) {
    // Don't show tooltip for virtual root
    if (agent.id === 'root') return;
    
    const tooltip = document.getElementById('tooltip');
    const shortId = agent.id.length > 15 ? agent.id.substring(0, 12) + '...' : agent.id;
    const shortParent = agent.parent ? (agent.parent.length > 15 ? agent.parent.substring(0, 12) + '...' : agent.parent) : 'None';
    
    let popLabel = 'Unknown';
    if (agent.population) {
        const match = agent.population.match(/run(\d+)/);
        popLabel = match ? `Run ${match[1]}` : agent.population;
    }
    
    tooltip.innerHTML = `
        <div class="tooltip-title">Agent ${shortId}</div>
        <div class="tooltip-row">
            <span class="tooltip-label">Population:</span>
            <span class="tooltip-value">${popLabel}</span>
        </div>
        <div class="tooltip-row">
            <span class="tooltip-label">Parent:</span>
            <span class="tooltip-value">${shortParent}</span>
        </div>
        <div class="tooltip-row">
            <span class="tooltip-label">Best Fitness:</span>
            <span class="tooltip-value">${agent.best_fitness ? agent.best_fitness.toFixed(2) : 'N/A'}</span>
        </div>
        <div class="tooltip-row">
            <span class="tooltip-label">Evaluations:</span>
            <span class="tooltip-value">${agent.evaluations ? agent.evaluations.length : 0}</span>
        </div>
        <div class="tooltip-row">
            <span class="tooltip-label">Children:</span>
            <span class="tooltip-value">${agent.children ? agent.children.length : 0}</span>
        </div>
        <div style="margin-top: 8px; font-size: 0.75rem; color: #94a3b8; text-align: center;">
            Click for full details
        </div>
    `;
    
    tooltip.style.left = (event.pageX + 10) + 'px';
    tooltip.style.top = (event.pageY + 10) + 'px';
    tooltip.classList.add('visible');
}

function hideTooltip() {
    document.getElementById('tooltip').classList.remove('visible');
}

function showAgentDetails(agent) {
    // Don't show details for virtual root
    if (agent.id === 'root') return;
    
    const panel = document.getElementById('details-panel');
    const content = document.getElementById('details-content');
    
    let popLabel = 'Unknown';
    if (agent.population) {
        const match = agent.population.match(/run(\d+)/);
        popLabel = match ? `Run ${match[1]}` : agent.population;
    }
    
    // Build evaluations table
    let evaluationsHTML = '';
    if (agent.evaluations && agent.evaluations.length > 0) {
        evaluationsHTML = `
            <div class="detail-section">
                <h4>Evaluations (${agent.evaluations.length} total)</h4>
                <div class="evaluations-table">
                    <table>
                        <thead>
                            <tr>
                                <th>Attempt</th>
                                <th>Fitness</th>
                                <th>Cycles</th>
                                <th>Time (ms)</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${agent.evaluations.map(eval => `
                                <tr>
                                    <td>${eval.attempt !== null ? eval.attempt : '-'}</td>
                                    <td class="${eval.fitness > 80 ? 'fitness-high' : eval.fitness > 60 ? 'fitness-medium' : 'fitness-low'}">${eval.fitness.toFixed(2)}</td>
                                    <td>${eval.cycles || '-'}</td>
                                    <td>${eval.time_ms || '-'}</td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    }
    
    content.innerHTML = `
        <div class="detail-section">
            <h4>Basic Info</h4>
            <div class="detail-row">
                <span class="detail-label">Agent ID:</span>
                <span class="detail-value" style="word-break: break-all; font-size: 0.75rem;">${agent.id}</span>
            </div>
            <div class="detail-row">
                <span class="detail-label">Population:</span>
                <span class="detail-value">${popLabel}</span>
            </div>
            <div class="detail-row">
                <span class="detail-label">Generation:</span>
                <span class="detail-value">${agent.generation || 0}</span>
            </div>
            <div class="detail-row">
                <span class="detail-label">Species:</span>
                <span class="detail-value" style="word-break: break-all; font-size: 0.75rem;">${agent.species || 'N/A'}</span>
            </div>
        </div>
        
        <div class="detail-section">
            <h4>Performance</h4>
            <div class="detail-row">
                <span class="detail-label">Best Fitness:</span>
                <span class="detail-value">${agent.best_fitness ? agent.best_fitness.toFixed(2) : 'N/A'}</span>
            </div>
            <div class="detail-row">
                <span class="detail-label">Latest Fitness:</span>
                <span class="detail-value">${agent.fitness ? agent.fitness.toFixed(2) : 'N/A'}</span>
            </div>
            <div class="detail-row">
                <span class="detail-label">Total Evaluations:</span>
                <span class="detail-value">${agent.evaluations ? agent.evaluations.length : 0}</span>
            </div>
        </div>
        
        <div class="detail-section">
            <h4>Lineage</h4>
            <div class="detail-row">
                <span class="detail-label">Parent:</span>
                <span class="detail-value" style="word-break: break-all; font-size: 0.75rem;">${agent.parent || 'None (Root)'}</span>
            </div>
            <div class="detail-row">
                <span class="detail-label">Children:</span>
                <span class="detail-value">${agent.children ? agent.children.length : 0}</span>
            </div>
        </div>
        
        ${evaluationsHTML}
    `;
    
    panel.classList.remove('hidden');
}

function updateStats(popData) {
    document.getElementById('total-generations').textContent = popData.generations;
    document.getElementById('total-agents').textContent = popData.agents;
    document.getElementById('lineage-depth').textContent = popData.generations;
    document.getElementById('best-fitness').textContent = popData.best_fitness ? popData.best_fitness.toFixed(2) : '0';
}

function updateLegend() {
    const colorBy = document.getElementById('color-by').value;
    const legendContent = document.getElementById('legend-content');
    
    let html = '';
    if (colorBy === 'fitness') {
        html = `
            <div class="legend-item">
                <div class="legend-color" style="background: #10b981;"></div>
                <span class="legend-label">High Fitness (>80)</span>
            </div>
            <div class="legend-item">
                <div class="legend-color" style="background: #f59e0b;"></div>
                <span class="legend-label">Medium Fitness (60-80)</span>
            </div>
            <div class="legend-item">
                <div class="legend-color" style="background: #ef4444;"></div>
                <span class="legend-label">Low Fitness (<60)</span>
            </div>
        `;
    } else if (colorBy === 'generation') {
        html = `
            <div class="legend-item">
                <div class="legend-color" style="background: #3b82f6;"></div>
                <span class="legend-label">Run 1</span>
            </div>
            <div class="legend-item">
                <div class="legend-color" style="background: #8b5cf6;"></div>
                <span class="legend-label">Run 2</span>
            </div>
            <div class="legend-item">
                <div class="legend-color" style="background: #ec4899;"></div>
                <span class="legend-label">Run 3</span>
            </div>
            <div class="legend-item">
                <div class="legend-color" style="background: #f59e0b;"></div>
                <span class="legend-label">Run 4</span>
            </div>
            <div class="legend-item">
                <div class="legend-color" style="background: #10b981;"></div>
                <span class="legend-label">Run 5+</span>
            </div>
        `;
    } else {
        html = '<div class="legend-item"><span class="legend-label">Colors represent different species</span></div>';
    }
    
    legendContent.innerHTML = html;
}

function fitToScreen() {
    const bounds = g.node().getBBox();
    const parent = svg.node().getBoundingClientRect();
    const fullWidth = bounds.width;
    const fullHeight = bounds.height;
    const width = parent.width;
    const height = parent.height;
    
    const midX = bounds.x + fullWidth / 2;
    const midY = bounds.y + fullHeight / 2;
    
    const scale = 0.85 / Math.max(fullWidth / width, fullHeight / height);
    const translate = [width / 2 - scale * midX, height / 2 - scale * midY];
    
    svg.transition()
        .duration(750)
        .call(zoom.transform, d3.zoomIdentity.translate(translate[0], translate[1]).scale(scale));
}

function zoomIn() {
    svg.transition()
        .duration(300)
        .call(zoom.scaleBy, 1.3);
}

function zoomOut() {
    svg.transition()
        .duration(300)
        .call(zoom.scaleBy, 0.7);
}

function exportSVG() {
    const svgData = svg.node().outerHTML;
    const blob = new Blob([svgData], { type: 'image/svg+xml' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `lineage_${currentPopulation}_${Date.now()}.svg`;
    link.click();
    URL.revokeObjectURL(url);
}

function updateStatus(text) {
    document.getElementById('status-text').textContent = text;
}
