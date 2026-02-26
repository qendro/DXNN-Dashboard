# 🧠 NEAT Neural Network Training Dashboard

Real-time monitoring dashboard for your Erlang NEAT forex trader neural network training.

## ✨ Features

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
```
http://localhost:5000
```

The dashboard will automatically start monitoring your logs in the `logs/` directory.

## 📁 Log Structure

The dashboard monitors these log files:
```
logs/
├── Benchmarker/
│   ├── agent_meta.log      # Agent metadata
│   ├── agent_trades.log    # Trading performance (main data source)
│   ├── benchmarker.log     # Generation statistics
│   └── pid_map.log
├── exp_runner/
│   └── exp_runner.log      # Experiment tracking
└── System/
    └── qStatus.log         # System status
```

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
