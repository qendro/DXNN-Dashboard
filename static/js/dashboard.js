// Dashboard JavaScript - Real-time updates
let charts = {};
let previousData = {
    realizedProfit: 0,
    totalProfit: 0
};

// Initialize charts
function initCharts() {
    const chartConfig = {
        type: 'line',
        options: {
            responsive: true,
            maintainAspectRatio: true,
            plugins: {
                legend: {
                    display: false
                }
            },
            scales: {
                y: {
                    beginAtZero: false,
                    grid: {
                        color: 'rgba(0, 0, 0, 0.05)'
                    }
                },
                x: {
                    grid: {
                        display: false
                    }
                }
            },
            animation: {
                duration: 750,
                easing: 'easeInOutQuart'
            }
        }
    };

    // Realized Profit Chart
    charts.realizedProfit = new Chart(
        document.getElementById('realizedProfitChart'),
        {
            ...chartConfig,
            data: {
                labels: [],
                datasets: [{
                    label: 'Realized Profit',
                    data: [],
                    borderColor: '#10b981',
                    backgroundColor: 'rgba(16, 185, 129, 0.1)',
                    borderWidth: 3,
                    fill: true,
                    tension: 0.4
                }]
            }
        }
    );

    // Total Profit Chart
    charts.totalProfit = new Chart(
        document.getElementById('totalProfitChart'),
        {
            ...chartConfig,
            data: {
                labels: [],
                datasets: [{
                    label: 'Total Profit',
                    data: [],
                    borderColor: '#f5576c',
                    backgroundColor: 'rgba(245, 87, 108, 0.1)',
                    borderWidth: 3,
                    fill: true,
                    tension: 0.4
                }]
            }
        }
    );

    // Fitness Chart
    charts.fitness = new Chart(
        document.getElementById('fitnessChart'),
        {
            ...chartConfig,
            data: {
                labels: [],
                datasets: [
                    {
                        label: 'Max Fitness',
                        data: [],
                        borderColor: '#6366f1',
                        backgroundColor: 'rgba(99, 102, 241, 0.1)',
                        borderWidth: 3,
                        fill: true,
                        tension: 0.4
                    },
                    {
                        label: 'Avg Fitness',
                        data: [],
                        borderColor: '#8b5cf6',
                        backgroundColor: 'rgba(139, 92, 246, 0.1)',
                        borderWidth: 2,
                        fill: false,
                        tension: 0.4
                    }
                ]
            },
            options: {
                ...chartConfig.options,
                plugins: {
                    legend: {
                        display: true,
                        position: 'top'
                    }
                }
            }
        }
    );
}

// Update metrics display
function updateMetrics(data) {
    const metrics = data.metrics;
    
    // Update realized profit
    const realizedProfit = metrics.realized_profit || 0;
    document.getElementById('realized-profit').textContent = `$${realizedProfit.toFixed(2)}`;
    
    // Calculate and show change
    const realizedChange = realizedProfit - previousData.realizedProfit;
    const realizedChangeEl = document.getElementById('realized-change');
    if (realizedChange !== 0) {
        const sign = realizedChange > 0 ? '+' : '';
        realizedChangeEl.textContent = `${sign}$${realizedChange.toFixed(2)}`;
        realizedChangeEl.className = `metric-change ${realizedChange > 0 ? 'positive' : 'negative'}`;
    }
    previousData.realizedProfit = realizedProfit;
    
    // Update total profit
    const totalProfit = metrics.total_profit || 0;
    document.getElementById('total-profit').textContent = `$${totalProfit.toFixed(2)}`;
    
    const totalChange = totalProfit - previousData.totalProfit;
    const totalChangeEl = document.getElementById('total-change');
    if (totalChange !== 0) {
        const sign = totalChange > 0 ? '+' : '';
        totalChangeEl.textContent = `${sign}$${totalChange.toFixed(2)}`;
        totalChangeEl.className = `metric-change ${totalChange > 0 ? 'positive' : 'negative'}`;
    }
    previousData.totalProfit = totalProfit;
    
    // Update other metrics
    document.getElementById('best-fitness').textContent = (metrics.best_fitness || 0).toFixed(2);
    document.getElementById('generation').textContent = metrics.current_generation || 0;
    document.getElementById('avg-balance').textContent = `$${(metrics.avg_balance || 0).toFixed(2)}`;
    document.getElementById('total-trades').textContent = metrics.total_trades || 0;
    document.getElementById('total-agents').textContent = metrics.total_agents || 0;
    
    // Update profit trends
    if (metrics.realized_profit_trend && metrics.realized_profit_trend.length > 0) {
        const labels = metrics.realized_profit_trend.map((_, i) => i + 1);
        charts.realizedProfit.data.labels = labels;
        charts.realizedProfit.data.datasets[0].data = metrics.realized_profit_trend;
        charts.realizedProfit.update('none');
    }
    
    if (metrics.total_profit_trend && metrics.total_profit_trend.length > 0) {
        const labels = metrics.total_profit_trend.map((_, i) => i + 1);
        charts.totalProfit.data.labels = labels;
        charts.totalProfit.data.datasets[0].data = metrics.total_profit_trend;
        charts.totalProfit.update('none');
    }
}

// Update generation charts
function updateGenerations(generations) {
    if (!generations || generations.length === 0) return;
    
    const labels = generations.map(g => `Gen ${g.generation}`);
    const maxFitness = generations.map(g => g.max_fitness || 0);
    const avgFitness = generations.map(g => g.avg_fitness || 0);
    
    charts.fitness.data.labels = labels;
    charts.fitness.data.datasets[0].data = maxFitness;
    charts.fitness.data.datasets[1].data = avgFitness;
    charts.fitness.update('none');
}

// Update run info
function updateRunInfo(runInfo) {
    document.getElementById('current-run').textContent = runInfo.current_run || '-';
    document.getElementById('total-runs').textContent = runInfo.total_runs || '-';
    
    const statusEl = document.getElementById('run-status');
    statusEl.textContent = runInfo.status || 'unknown';
    statusEl.className = `info-value status-badge ${runInfo.status || 'unknown'}`;
}

// Fetch and update data
async function fetchData() {
    try {
        const response = await fetch('/api/data');
        const data = await response.json();
        
        updateMetrics(data);
        updateGenerations(data.generations);
        updateRunInfo(data.run_info);
        
        // Update timestamp
        const timestamp = new Date(data.timestamp);
        document.getElementById('last-update').textContent = timestamp.toLocaleTimeString();
        
        // Update status indicator
        document.getElementById('status-text').textContent = 'Live';
        document.querySelector('.pulse').style.background = '#10b981';
        
    } catch (error) {
        console.error('Error fetching data:', error);
        document.getElementById('status-text').textContent = 'Connection Error';
        document.querySelector('.pulse').style.background = '#ef4444';
    }
}

// Initialize dashboard
document.addEventListener('DOMContentLoaded', () => {
    initCharts();
    fetchData();
    
    // Update every 2 seconds (low overhead)
    setInterval(fetchData, 2000);
});
