// Agent Performance Dashboard with uPlot

let uplotChart = null;
let currentMetric = 'fitness';
let globalAgentsData = [];
let globalTradesData = [];
let lastMetric = null;

const metricConfig = {
    'fitness': { label: 'Fitness', color: '#667eea' },
    'raw_total_profit': { label: 'Raw Total Profit', color: '#10b981' },
    'realized_pl': { label: 'Realized P/L', color: '#10b981' },
    'unrealized_pl': { label: 'Unrealized P/L', color: '#f59e0b' },
    'realized_trades': { label: 'Realized Trades', color: '#667eea' }
};

function initChart() {
    const container = document.getElementById('agentChart');
    if (!container) {
        console.error('Chart container not found!');
        return;
    }
    
    console.log('Initializing chart in container:', container);
    console.log('Container dimensions:', container.clientWidth, 'x', container.clientHeight);
    console.log('Container computed style:', window.getComputedStyle(container).width, window.getComputedStyle(container).height);
    
    const opts = {
        width: container.clientWidth || 800,  // Fallback to 800 if clientWidth is 0
        height: 400,
        scales: {
            x: { 
                time: false,
                auto: true
            },
            y: { 
                auto: true
            }
        },
        series: [
            { label: "Index" },
            {
                label: metricConfig[currentMetric].label,
                stroke: metricConfig[currentMetric].color,
                width: 2,
                points: { show: false },
                spanGaps: false,
                show: true  // Explicitly show the series
            },
            {
                label: "SMA (200)",
                stroke: 'rgba(255, 0, 0, 0.5)',
                width: 2,
                dash: [10, 5],
                points: { show: false },
                spanGaps: true,
                show: true  // Explicitly show the series
            }
        ],
        axes: [
            { label: "Trade Index" },
            { label: metricConfig[currentMetric].label }
        ],
        cursor: {
            drag: { x: true, y: false },
            focus: { prox: 30 }
        },
        hooks: {
            setSelect: [
                u => {
                    const sel = u.select;
                    if (sel.width > 5) {
                        const xMin = u.posToVal(sel.left, 'x');
                        const xMax = u.posToVal(sel.left + sel.width, 'x');
                        u.setScale('x', { min: Math.min(xMin, xMax), max: Math.max(xMin, xMax) });
                        // Clear selection without triggering hook again
                        u.select.left = 0;
                        u.select.width = 0;
                        u.select.top = 0;
                        u.select.height = 0;
                    }
                }
            ]
        }
    };
    
    // Initialize with minimal empty data
    uplotChart = new uPlot(opts, [[], [], []], container);
    lastMetric = currentMetric;
    
    console.log('Chart initialized:', uplotChart);
    console.log('Initial series count:', uplotChart.series.length);
    
    // Mouse wheel zoom
    uplotChart.root.addEventListener('wheel', e => {
        e.preventDefault();
        const xScale = uplotChart.scales.x;
        const xRange = xScale.max - xScale.min;
        const rect = uplotChart.root.getBoundingClientRect();
        const mouseRatio = ((e.clientX - rect.left) - uplotChart.bbox.left) / uplotChart.bbox.width;
        const mouseVal = xScale.min + xRange * mouseRatio;
        const zoomFactor = e.deltaY < 0 ? 0.85 : 1.15;
        const newRange = xRange * zoomFactor;
        let newMin = mouseVal - newRange * mouseRatio;
        let newMax = mouseVal + newRange * (1 - mouseRatio);
        const dataLength = uplotChart.data[0].length;
        if (newMin < 0) { newMin = 0; newMax = newRange; }
        if (newMax > dataLength - 1) { newMax = dataLength - 1; newMin = newMax - newRange; }
        uplotChart.setScale('x', { min: newMin, max: newMax });
    }, { passive: false });
    
    // Keyboard controls
    document.addEventListener('keydown', e => {
        if (!uplotChart || !uplotChart.data[0].length) return;
        const xScale = uplotChart.scales.x;
        const xRange = xScale.max - xScale.min;
        const panAmount = xRange * 0.1;
        const dataLength = uplotChart.data[0].length;
        let handled = false;
        if (e.key === 'ArrowLeft') {
            const newMin = Math.max(0, xScale.min - panAmount);
            uplotChart.setScale('x', { min: newMin, max: newMin + xRange });
            handled = true;
        } else if (e.key === 'ArrowRight') {
            const newMax = Math.min(dataLength - 1, xScale.max + panAmount);
            uplotChart.setScale('x', { min: newMax - xRange, max: newMax });
            handled = true;
        } else if (e.key === 'Home') {
            uplotChart.setScale('x', { min: 0, max: dataLength - 1 });
            handled = true;
        } else if (e.key === 'End') {
            uplotChart.setScale('x', { min: Math.max(0, dataLength - xRange), max: dataLength - 1 });
            handled = true;
        }
        if (handled) e.preventDefault();
    });
    
    window.addEventListener('resize', () => {
        if (uplotChart) uplotChart.setSize({ width: container.clientWidth, height: 400 });
    });
}

async function fetchAgentData() {
    try {
        const [agentsResponse, tradesResponse] = await Promise.all([
            fetch('/api/agents'),
            fetch('/api/agents/trades')
        ]);
        globalAgentsData = (await agentsResponse.json()).agents || [];
        globalTradesData = (await tradesResponse.json()).trades || [];
        console.log('Fetched:', globalAgentsData.length, 'agents,', globalTradesData.length, 'trades');
        updateDisplay();
        updateStatus(`Live - ${globalAgentsData.length} agents, ${globalTradesData.length} trades`);
    } catch (error) {
        console.error('Error fetching agent data:', error);
        updateStatus('Error loading data');
    }
}

function updateDisplay() {
    console.log('updateDisplay called - agents:', globalAgentsData.length, 'trades:', globalTradesData.length);
    
    // Always update the chart with trades data
    updateChart(globalTradesData, currentMetric);
    
    // Update the table with agents
    if (!globalAgentsData || globalAgentsData.length === 0) {
        updateTable([]);
        document.getElementById('agent-count').textContent = 
            `Total Agents: 0 | Total Trades: ${globalTradesData.length}`;
        return;
    }
    
    const sortedAgents = [...globalAgentsData].sort((a, b) => (b[currentMetric] || 0) - (a[currentMetric] || 0));
    updateTable(sortedAgents.slice(0, 50));
    document.getElementById('agent-count').textContent = 
        `Total Agents: ${globalAgentsData.length} | Total Trades: ${globalTradesData.length}`;
}

function calculateSMA(yData, period = 200) {
    const sma = [];
    for (let i = 0; i < yData.length; i++) {
        if (i < period - 1) {
            sma.push(null);
        } else {
            let sum = 0;
            for (let j = 0; j < period; j++) sum += yData[i - j];
            sma.push(sum / period);
        }
    }
    return sma;
}

function updateChart(trades, metric) {
    if (!uplotChart) {
        console.log('updateChart skipped - chart not initialized');
        return;
    }
    
    if (trades.length === 0) {
        console.log('updateChart skipped - no trades data');
        // Set empty data to clear the chart
        uplotChart.setData([[], [], []]);
        return;
    }
    
    console.log('Updating chart with', trades.length, 'trades, metric:', metric);
    console.log('Sample trade data:', trades[0]);
    
    const xData = trades.map((_, index) => index);
    const yData = trades.map(trade => {
        const value = trade[metric];
        return value !== undefined && value !== null ? value : 0;
    });
    const smaData = calculateSMA(yData, 200);
    
    console.log('Data ranges - x:', xData[0], 'to', xData[xData.length-1]);
    console.log('Data ranges - y:', Math.min(...yData), 'to', Math.max(...yData));
    console.log('First 5 y values:', yData.slice(0, 5));
    console.log('yData has', yData.filter(v => v !== 0 && v !== null).length, 'non-zero values');
    
    // Store zoom state
    const xScale = uplotChart.scales.x;
    const currentMin = xScale.min;
    const currentMax = xScale.max;
    // Only consider it zoomed if we have meaningful data and the scale is actually restricted
    // Ignore the initial [0, 1] range from initialization
    const hasData = xData.length > 2;
    const wasZoomed = hasData && currentMin !== undefined && currentMax !== undefined && 
                      currentMax > 2 &&  // Ignore initial [0, 1] range
                      (currentMin > 0 || currentMax < xData.length - 1);
    
    // Update series configuration if metric changed
    if (lastMetric !== metric) {
        console.log('Metric changed from', lastMetric, 'to', metric);
        
        // Remove old series (in reverse order to maintain indices)
        while (uplotChart.series.length > 1) {
            uplotChart.delSeries(uplotChart.series.length - 1);
        }
        
        // Add new series
        uplotChart.addSeries({
            label: metricConfig[metric].label,
            stroke: metricConfig[metric].color,
            width: 2,
            points: { show: false },
            spanGaps: false,
            show: true  // Explicitly show the series
        });
        uplotChart.addSeries({
            label: "SMA (200)",
            stroke: 'rgba(255, 0, 0, 0.5)',
            width: 2,
            dash: [10, 5],
            points: { show: false },
            spanGaps: true,
            show: true  // Explicitly show the series
        });
        
        // Update axis label
        uplotChart.axes[1].label = metricConfig[metric].label;
        
        lastMetric = metric;
        console.log('Series updated. New series count:', uplotChart.series.length);
    }
    
    console.log('Setting data - xData length:', xData.length, 'yData length:', yData.length, 'smaData length:', smaData.length);
    uplotChart.setData([xData, yData, smaData]);
    console.log('Data set successfully');
    
    // Restore zoom if it was zoomed, otherwise let auto-scaling handle it
    if (wasZoomed) {
        console.log('Restoring zoom state:', currentMin, 'to', currentMax);
        uplotChart.setScale('x', { min: currentMin, max: currentMax });
    }
    // If not zoomed, setData with auto:true scales should handle it automatically
    
    console.log('Final x scale - min:', uplotChart.scales.x.min, 'max:', uplotChart.scales.x.max);
    console.log('Final y scale - min:', uplotChart.scales.y.min, 'max:', uplotChart.scales.y.max);
    console.log('Chart bbox:', uplotChart.bbox);
    console.log('Series 1 show:', uplotChart.series[1].show, 'stroke:', uplotChart.series[1].stroke);
    console.log('Series 2 show:', uplotChart.series[2].show, 'stroke:', uplotChart.series[2].stroke);
    console.log('Chart width:', uplotChart.width, 'height:', uplotChart.height);
    console.log('Chart root element:', uplotChart.root);
    console.log('Canvas elements:', uplotChart.root.querySelectorAll('canvas').length);
}

function updateTable(agents) {
    const tbody = document.getElementById('agentTableBody');
    if (!agents || agents.length === 0) {
        tbody.innerHTML = '<tr><td colspan="9" class="loading">No agent data available</td></tr>';
        return;
    }
    const rows = agents.map((agent, index) => {
        const rank = index + 1;
        const rankClass = rank === 1 ? 'rank-1' : rank === 2 ? 'rank-2' : rank === 3 ? 'rank-3' : '';
        const pidDisplay = agent.pid.length > 12 ? agent.pid.substring(0, 10) + '...' : agent.pid;
        const agentIdDisplay = agent.agent_id.length > 15 ? agent.agent_id.substring(0, 12) + '...' : agent.agent_id;
        return `
            <tr>
                <td class="rank ${rankClass}">${rank}</td>
                <td><a href="#" class="pid-link" data-pid="${agent.pid}" title="${agent.pid}">${pidDisplay}</a></td>
                <td><a href="/agent/${encodeURIComponent(agent.agent_id)}" class="agent-link" title="${agent.agent_id}">${agentIdDisplay}</a></td>
                <td>${agent.row_number || 'N/A'}</td>
                <td>${formatNumber(agent.fitness)}</td>
                <td class="${getValueClass(agent.raw_total_profit)}">${formatNumber(agent.raw_total_profit)}</td>
                <td class="${getValueClass(agent.realized_pl)}">${formatNumber(agent.realized_pl)}</td>
                <td class="${getValueClass(agent.unrealized_pl)}">${formatNumber(agent.unrealized_pl)}</td>
                <td>${agent.realized_trades || 0}</td>
            </tr>
        `;
    }).join('');
    tbody.innerHTML = rows;
    document.querySelectorAll('.pid-link').forEach(link => {
        link.addEventListener('click', (e) => {
            e.preventDefault();
            showPidDetails(e.target.getAttribute('data-pid'));
        });
    });
}

function formatNumber(value) {
    return typeof value === 'number' ? value.toFixed(2) : '0.00';
}

function getValueClass(value) {
    if (value > 0) return 'positive';
    if (value < 0) return 'negative';
    return 'neutral';
}

function updateStatus(text) {
    document.getElementById('status-text').textContent = text;
}

document.addEventListener('DOMContentLoaded', () => {
    initChart();
    fetchAgentData();
    setInterval(fetchAgentData, 5000);
    
    // Add event listener after DOM is loaded
    document.getElementById('metric-select').addEventListener('change', (e) => {
        currentMetric = e.target.value;
        updateDisplay();
    });
});

async function showPidDetails(pid) {
    const modal = document.getElementById('pid-modal');
    const modalBody = document.getElementById('pid-modal-body');
    modal.style.display = 'block';
    modalBody.innerHTML = '<p>Loading...</p>';
    try {
        const response = await fetch(`/api/pid/${encodeURIComponent(pid)}`);
        const data = await response.json();
        if (data.error) {
            modalBody.innerHTML = `<p class="error">${data.error}</p>`;
            return;
        }
        let historyHTML = '';
        if (data.history && data.history.length > 0) {
            historyHTML = `
                <div class="detail-section">
                    <h3>Evaluation History (${data.history.length} evaluations)</h3>
                    <div class="history-table-container">
                        <table class="history-table">
                            <thead>
                                <tr>
                                    <th>#</th><th>Row</th><th>Timestamp</th><th>Fitness</th>
                                    <th>Total Profit</th><th>Realized P/L</th><th>Unrealized P/L</th><th>Trades</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${data.history.map((h, i) => `
                                    <tr>
                                        <td>${i + 1}</td>
                                        <td>${h.row_number || 'N/A'}</td>
                                        <td>${h.timestamp || 'N/A'}</td>
                                        <td>${formatNumber(h.fitness)}</td>
                                        <td class="${getValueClass(h.raw_total_profit)}">${formatNumber(h.raw_total_profit)}</td>
                                        <td class="${getValueClass(h.realized_pl)}">${formatNumber(h.realized_pl)}</td>
                                        <td class="${getValueClass(h.unrealized_pl)}">${formatNumber(h.unrealized_pl)}</td>
                                        <td>${h.realized_trades}</td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    </div>
                </div>
            `;
        }
        modalBody.innerHTML = `
            <div class="detail-section">
                <h3>Instance Information</h3>
                <div class="detail-grid">
                    <div class="detail-item"><span class="detail-label">PID:</span><span class="detail-value">${data.pid}</span></div>
                    <div class="detail-item"><span class="detail-label">Agent ID:</span><span class="detail-value"><a href="/agent/${encodeURIComponent(data.agent_id)}" class="agent-link">${data.agent_id}</a></span></div>
                    <div class="detail-item"><span class="detail-label">Run:</span><span class="detail-value">${data.run}</span></div>
                    <div class="detail-item"><span class="detail-label">Generation:</span><span class="detail-value">${data.generation}</span></div>
                    <div class="detail-item"><span class="detail-label">Encoding:</span><span class="detail-value">${data.encoding}</span></div>
                    <div class="detail-item"><span class="detail-label">Neurons:</span><span class="detail-value">${data.neurons}</span></div>
                    <div class="detail-item"><span class="detail-label">Sensors:</span><span class="detail-value">${data.sensors}</span></div>
                </div>
            </div>
            <div class="detail-section">
                <h3>Latest Performance</h3>
                <div class="detail-grid">
                    <div class="detail-item"><span class="detail-label">Fitness:</span><span class="detail-value">${formatNumber(data.latest_fitness)}</span></div>
                    <div class="detail-item"><span class="detail-label">Total Profit:</span><span class="detail-value ${getValueClass(data.latest_raw_total_profit)}">${formatNumber(data.latest_raw_total_profit)}</span></div>
                    <div class="detail-item"><span class="detail-label">Realized P/L:</span><span class="detail-value ${getValueClass(data.latest_realized_pl)}">${formatNumber(data.latest_realized_pl)}</span></div>
                    <div class="detail-item"><span class="detail-label">Unrealized P/L:</span><span class="detail-value ${getValueClass(data.latest_unrealized_pl)}">${formatNumber(data.latest_unrealized_pl)}</span></div>
                    <div class="detail-item"><span class="detail-label">Realized Trades:</span><span class="detail-value">${data.latest_realized_trades}</span></div>
                </div>
            </div>
            ${historyHTML}
        `;
    } catch (error) {
        console.error('Error fetching PID details:', error);
        modalBody.innerHTML = '<p class="error">Error loading PID details</p>';
    }
}

function closePidModal() {
    document.getElementById('pid-modal').style.display = 'none';
}

window.onclick = function(event) {
    const modal = document.getElementById('pid-modal');
    if (event.target === modal) closePidModal();
}
