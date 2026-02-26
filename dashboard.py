#!/usr/bin/env python3
"""
NEAT Neural Network Training Dashboard
Real-time monitoring for Erlang NEAT forex trader
"""

import os
import re
import json
from datetime import datetime
from collections import defaultdict
from flask import Flask, render_template, jsonify
from pathlib import Path

app = Flask(__name__)

# Configuration
LOG_DIR = Path("logs")
BENCHMARKER_DIR = LOG_DIR / "Benchmarker"
EXP_RUNNER_DIR = LOG_DIR / "exp_runner"

class LogParser:
    """Efficient log parser with caching"""
    
    def __init__(self):
        self.cache = {
            'trades': [],
            'generations': [],
            'last_modified': {}
        }
    
    def parse_agent_trades(self, filepath):
        """Parse agent_trades.log for profit metrics across all agents"""
        trades_data = []
        
        try:
            # Check if file was modified
            current_mtime = os.path.getmtime(filepath)
            if filepath in self.cache['last_modified']:
                if current_mtime == self.cache['last_modified'][filepath]:
                    return self.cache['trades']
            
            self.cache['last_modified'][filepath] = current_mtime
            
            with open(filepath, 'r') as f:
                for line in f:
                    if 'FITNESS_EVAL' in line:
                        match = re.search(
                            r'fitness=([0-9.e+-]+).*?'
                            r'raw_total_profit=([0-9.e+-]+).*?'
                            r'balance=([0-9.e+-]+).*?'
                            r'realized_pl=([0-9.e+-]+).*?'
                            r'unrealized_pl=([0-9.e+-]+).*?'
                            r'realized_trades=(\d+)',
                            line
                        )
                        if match:
                            trades_data.append({
                                'fitness': float(match.group(1)),
                                'total_profit': float(match.group(2)),
                                'balance': float(match.group(3)),
                                'realized_pl': float(match.group(4)),
                                'unrealized_pl': float(match.group(5)),
                                'realized_trades': int(match.group(6))
                            })
            
            self.cache['trades'] = trades_data
        except FileNotFoundError:
            print(f"Warning: {filepath} not found")
        except Exception as e:
            print(f"Error parsing trades: {e}")
        
        return trades_data
    
    def parse_benchmarker(self, filepath):
        """Parse benchmarker.log for generation stats"""
        gen_data = []
        current_gen = None
        
        try:
            # Check if file was modified
            current_mtime = os.path.getmtime(filepath)
            if filepath in self.cache['last_modified']:
                if current_mtime == self.cache['last_modified'][filepath]:
                    return self.cache['generations']
            
            self.cache['last_modified'][filepath] = current_mtime
            
            with open(filepath, 'r') as f:
                for line in f:
                    if 'GENERATION_START' in line:
                        # Save previous generation if exists
                        if current_gen and 'avg_fitness' in current_gen:
                            gen_data.append(current_gen)
                        
                        match = re.search(r'generation=(\d+).*?total_agents=(\d+)', line)
                        if match:
                            current_gen = {
                                'generation': int(match.group(1)),
                                'total_agents': int(match.group(2)),
                                'timestamp': self._extract_timestamp(line)
                            }
                    
                    elif 'Specie=' in line and current_gen:
                        match = re.search(
                            r'Avg Fitness=([0-9.e+-]+).*?'
                            r'Max=([0-9.e+-]+).*?'
                            r'Min=([0-9.e+-]+)',
                            line
                        )
                        if match:
                            current_gen.update({
                                'avg_fitness': float(match.group(1)),
                                'max_fitness': float(match.group(2)),
                                'min_fitness': float(match.group(3))
                            })
                
                # Don't forget the last generation
                if current_gen and 'avg_fitness' in current_gen:
                    gen_data.append(current_gen)
            
            self.cache['generations'] = gen_data
        except FileNotFoundError:
            print(f"Warning: {filepath} not found")
        except Exception as e:
            print(f"Error parsing benchmarker: {e}")
        
        return gen_data
    
    def parse_exp_runner(self, filepath):
        """Parse exp_runner.log for run information"""
        run_info = {
            'current_run': None,
            'total_runs': 0,
            'status': 'unknown',
            'best_fitness': 0,
            'generations': 0
        }
        
        try:
            with open(filepath, 'r') as f:
                content = f.read()
                
                # Extract experiment info
                exp_match = re.search(r'experiment:.*?tot_runs:\s*(\d+)', content)
                if exp_match:
                    run_info['total_runs'] = int(exp_match.group(1))
                
                # Find latest run
                run_matches = list(re.finditer(r'=== RUN (\d+) ===', content))
                if run_matches:
                    run_info['current_run'] = int(run_matches[-1].group(1))
                
                # Get latest status
                status_match = re.search(
                    r'status: (\w+).*?best_fitness: ([0-9.]+).*?generations: (\d+)',
                    content,
                    re.DOTALL
                )
                if status_match:
                    run_info['status'] = status_match.group(1)
                    run_info['best_fitness'] = float(status_match.group(2))
                    run_info['generations'] = int(status_match.group(3))
        except FileNotFoundError:
            pass
        
        return run_info
    
    def _extract_timestamp(self, line):
        """Extract timestamp from log line"""
        match = re.search(r'\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]', line)
        if match:
            return match.group(1)
        return None

parser = LogParser()

@app.route('/')
def index():
    """Serve the dashboard HTML"""
    return render_template('dashboard.html')

@app.route('/api/data')
def get_data():
    """API endpoint for real-time data"""
    
    # Parse logs
    trades = parser.parse_agent_trades(BENCHMARKER_DIR / "agent_trades.log")
    generations = parser.parse_benchmarker(BENCHMARKER_DIR / "benchmarker.log")
    run_info = parser.parse_exp_runner(EXP_RUNNER_DIR / "exp_runner.log")
    
    # Calculate aggregated metrics
    metrics = calculate_metrics(trades, generations)
    
    return jsonify({
        'metrics': metrics,
        'generations': generations[-20:] if generations else [],  # Last 20 generations
        'run_info': run_info,
        'timestamp': datetime.now().isoformat()
    })

def calculate_metrics(trades, generations):
    """Calculate key metrics from parsed data across all agents"""
    if not trades:
        return {
            'realized_profit': 0,
            'total_profit': 0,
            'best_fitness': 0,
            'avg_balance': 0,
            'total_trades': 0,
            'current_generation': 0,
            'realized_profit_trend': [],
            'total_profit_trend': [],
            'total_agents': 0
        }
    
    # Get all realized profits and total profits
    realized_profits = [t['realized_pl'] for t in trades]
    total_profits = [t['total_profit'] for t in trades]
    balances = [t['balance'] for t in trades]
    
    # Find best metrics across ALL agents
    best_realized = max(realized_profits) if realized_profits else 0
    best_total = max(total_profits) if total_profits else 0
    best_fitness = max([t['fitness'] for t in trades]) if trades else 0
    avg_balance = sum(balances) / len(balances) if balances else 0
    total_trades_count = sum([t['realized_trades'] for t in trades])
    
    # Get trend data (sample every Nth entry for performance with thousands of agents)
    sample_rate = max(1, len(trades) // 50)  # Get ~50 data points
    realized_trend = [realized_profits[i] for i in range(0, len(realized_profits), sample_rate)][-30:]
    total_trend = [total_profits[i] for i in range(0, len(total_profits), sample_rate)][-30:]
    
    metrics = {
        'realized_profit': best_realized,
        'total_profit': best_total,
        'best_fitness': best_fitness,
        'avg_balance': avg_balance,
        'total_trades': total_trades_count,
        'current_generation': generations[-1]['generation'] if generations else 0,
        'realized_profit_trend': realized_trend,
        'total_profit_trend': total_trend,
        'total_agents': len(trades)
    }
    
    return metrics

if __name__ == '__main__':
    print("🚀 NEAT Dashboard Starting...")
    print(f"📁 Monitoring logs in: {LOG_DIR.absolute()}")
    print("🌐 Dashboard: http://localhost:5000")
    print("\nPress Ctrl+C to stop\n")
    
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)
