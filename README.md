# 🧠 NEAT Neural Network Training Dashboard

Real-time monitoring dashboard for your Erlang NEAT forex trader neural network training.

## ✨ Features

### Main Dashboard
- **Real-time Updates**: Auto-refreshes every 2 seconds with minimal overhead
- **Key Metrics Focus**: 
  - 💰 Realized Profit (primary metric)
  - 📈 Total Profit (secondary metric)
  - 🎯 Best Fitness Score
  - 🔄 Current Generation
  - 💵 Average Balance
  - 📊 Total Trades
- **Visual Charts**:
  - Realized Profit Trend
  - Total Profit Trend
  - Fitness Evolution (Max & Avg)
- **Experiment Tracking**: Monitor current run, total runs, and status
- **Beautiful UI**: Modern, gradient-based design with smooth animations

### Agent Performance Dashboard
- **Individual Agent Tracking**: Monitor performance of each agent over time
- **Interactive Chart**: Visualize top 50 agents with selectable metrics
- **Metric Selection**: Switch between:
  - 🎯 Fitness
  - 💰 Raw Total Profit
  - ✅ Realized P/L
  - ⏳ Unrealized P/L
  - 📊 Realized Trades
- **Top 50 Leaderboard**: Sortable table showing best performing agents
- **Real-time Updates**: Auto-refreshes every 5 seconds
- **Color-coded Values**: Positive (green), negative (red), neutral (gray)
- **PID Instance Details**: Click any PID to see detailed information about that specific run instance
  - View metadata (run, generation, encoding, neurons, sensors)
  - See complete evaluation history
  - Link to full Agent ID details
- **Agent ID Details Page**: Click any Agent ID to see all instances across all runs
  - View aggregate statistics (best fitness, best profit, total evaluations)
  - Compare performance across different runs
  - Track evolution of the same agent across multiple experiments

### Lineage Visualization Dashboard
- **Evolutionary Tree**: Interactive visualization of agent lineage and ancestry
- **Multiple View Modes**:
  - 🌳 Tree View: Hierarchical parent-child relationships
  - ⏱️ Timeline View: Generation-based horizontal layout
- **Color Coding Options**:
  - By Fitness: See performance at a glance
  - By Generation: Track evolutionary progress
  - By Species: Identify speciation patterns
- **Interactive Features**:
  - Click agents to see detailed information
  - Hover for quick stats
  - Zoom and pan to explore large lineages
  - Export visualizations as SVG
- **Population Tracking**: Switch between different experimental runs
- **Lineage Statistics**: View depth, breadth, and best performers

### Mnesia Database Browser
- **Database Selection**: Browse and select Mnesia directories from your filesystem
- **Agent Inventory**: View all agents stored in the Mnesia database
- **Database Statistics**: 
  - Total agents count
  - Max and average fitness scores
  - Average neuron count
  - Maximum generation reached
  - Encoding types used
- **Sortable Agent Table**: Sort by fitness, generation, neurons, or agent ID
- **Agent Details**: View complete agent information including:
  - Agent ID (genetic identifier)
  - Fitness score
  - Generation number
  - Neural network encoding type
  - Neuron, sensor, and actuator counts
  - Database table location
- **Multi-Database Support**: Switch between different Mnesia databases to compare experiments

## 🚀 Quick Start

### Option 1: Docker (Recommended)
```bash
# Start dashboard in Docker
./docker-start.sh

# Stop dashboard
./docker-stop.sh

# View logs
docker-compose logs -f
```

### Option 2: Using the startup script
```bash
./start_dashboard.sh
```

### Option 3: Manual start
```bash
# Install dependencies
pip3 install -r requirements.txt

# Start dashboard
python3 dashboard.py
```

## 📊 Access Dashboard

Once started, open your browser and navigate to:

**Main Dashboard:**
```
http://localhost:5000
```

**Agent Performance Dashboard:**
```
http://localhost:5000/agents
```

**Agent Detail Page (for specific Agent ID):**
```
http://localhost:5000/agent/{agent_id}
```

**Lineage Visualization:**
```
http://localhost:5000/lineage
```

**Mnesia Database Browser:**
```
http://localhost:5000/mnesia
```

The dashboard will automatically start monitoring your logs in the `logs/` directory.

You can navigate between dashboards using the navigation links in the header.

## 📁 Log Structure

The dashboard monitors these log files:
```
logs/
├── Benchmarker/
│   ├── agent_meta.log      # Agent metadata (PID to Agent ID mapping)
│   ├── agent_trades.log    # Trading performance (main data source)
│   ├── benchmarker.log     # Generation statistics
│   └── pid_map.log
├── exp_runner/
│   └── exp_runner.log      # Experiment tracking
└── System/
    └── qStatus.log         # System status
```

## 🔗 Understanding PIDs and Agent IDs

The system tracks two types of identifiers:

- **PID (Process ID)**: Like `<0.486.0>` - Unique to each instance/run of an agent
  - Each time an agent is evaluated, it gets a new PID
  - PIDs are temporary and specific to that execution
  - Click a PID in the table to see instance-specific details

- **Agent ID**: Like `{5.644213002572617e-10,agent}` - The permanent genetic identifier
  - Remains constant across multiple runs
  - One Agent ID can have multiple PIDs (multiple evaluations)
  - Click an Agent ID to see all instances and compare performance across runs

## 🎯 Key Metrics Explained

- **Realized Profit**: Actual profit from closed trades (most important)
- **Total Profit**: Combined realized + unrealized profit
- **Best Fitness**: Highest fitness score achieved
- **Generation**: Current evolutionary generation
- **Avg Balance**: Average account balance across recent evaluations
- **Total Trades**: Cumulative number of realized trades

## 🔧 Configuration

Edit `dashboard.py` to customize:
- `LOG_DIR`: Change log directory path
- Update interval: Modify `setInterval(fetchData, 2000)` in `static/js/dashboard.js`
- Port: Change `port=5000` in `dashboard.py`

## 💡 Tips

- Keep the dashboard open while training to monitor progress
- The dashboard uses efficient incremental log parsing (low overhead)
- Charts show the last 20 data points for clarity
- Profit changes are highlighted in green (positive) or red (negative)

## 🛑 Stopping the Dashboard

Press `Ctrl+C` in the terminal to stop the server.

## 📝 Requirements

### Docker (Recommended)
- Docker Desktop for Mac
- Docker Compose (included with Docker Desktop)

### Local Installation
- Python 3.7+
- Flask 3.0.0

## 🎨 Design

The dashboard features:
- Gradient purple/blue theme
- Responsive design (works on mobile)
- Smooth animations and transitions
- Real-time pulse indicator
- Color-coded metrics

Enjoy monitoring your NEAT training! 🚀
