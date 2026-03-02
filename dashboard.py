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
from flask import Flask, render_template, jsonify, request
from pathlib import Path
from mnesia_reader import MnesiaReader

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
    
    def parse_agent_trades_detailed(self, filepath):
        """Parse agent_trades.log with PIDs and row numbers for detailed tracking"""
        agents_data = defaultdict(list)
        
        try:
            with open(filepath, 'r') as f:
                for row_num, line in enumerate(f, start=1):
                    if 'FITNESS_EVAL' in line:
                        # Extract PID (process ID) - this is the ex_pid like <0.490.0>
                        pid_match = re.search(r'\[AGENT:(<[0-9.]+>)\]', line)
                        timestamp_match = re.search(r'\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]', line)
                        
                        # Extract metrics
                        metrics_match = re.search(
                            r'fitness=([0-9.e+-]+).*?'
                            r'raw_total_profit=([0-9.e+-]+).*?'
                            r'balance=([0-9.e+-]+).*?'
                            r'realized_pl=([0-9.e+-]+).*?'
                            r'unrealized_pl=([0-9.e+-]+).*?'
                            r'realized_trades=(\d+)',
                            line
                        )
                        
                        if pid_match and metrics_match:
                            pid = pid_match.group(1)
                            timestamp = timestamp_match.group(1) if timestamp_match else None
                            
                            agents_data[pid].append({
                                'row_number': row_num,
                                'timestamp': timestamp,
                                'fitness': float(metrics_match.group(1)),
                                'raw_total_profit': float(metrics_match.group(2)),
                                'balance': float(metrics_match.group(3)),
                                'realized_pl': float(metrics_match.group(4)),
                                'unrealized_pl': float(metrics_match.group(5)),
                                'realized_trades': int(metrics_match.group(6))
                            })
            
            # Convert to list format with PID and latest metrics
            result = []
            for pid, history in agents_data.items():
                latest = history[-1]  # Get most recent entry
                result.append({
                    'pid': pid,
                    'row_number': latest['row_number'],
                    'fitness': latest['fitness'],
                    'raw_total_profit': latest['raw_total_profit'],
                    'realized_pl': latest['realized_pl'],
                    'unrealized_pl': latest['unrealized_pl'],
                    'realized_trades': latest['realized_trades'],
                    'history': history  # Full history for charting
                })
            
            return result
            
        except FileNotFoundError:
            print(f"Warning: {filepath} not found")
            return []
        except Exception as e:
            print(f"Error parsing detailed trades: {e}")
            return []
    
    def parse_agent_meta(self, filepath):
        """Parse agent_meta.log to build PID to Agent ID mapping
        
        In agent_meta.log:
        - [AGENT:{5.644213021961965e-10,agent}] is the Agent ID (genetic identifier)
        - ex_pid=<0.490.0> is the PID (process ID for this instance)
        """
        pid_to_agent_map = {}
        
        try:
            with open(filepath, 'r') as f:
                for line in f:
                    # Extract Agent ID (the genetic identifier)
                    agent_match = re.search(r'\[AGENT:\{([0-9.e+-]+),agent\}\]', line)
                    # Extract PID (the process ID)
                    pid_match = re.search(r'ex_pid=(<[0-9.]+>)', line)
                    
                    # Extract additional metadata
                    run_match = re.search(r'run=(\d+|"[^"]*")', line)
                    gen_match = re.search(r'generation=(\d+)', line)
                    encoding_match = re.search(r'encoding=(\w+)', line)
                    neurons_match = re.search(r'neurons=(\d+)', line)
                    sensors_match = re.search(r'sensors=([^\s]+)', line)
                    
                    if pid_match and agent_match:
                        pid = pid_match.group(1)  # <0.490.0>
                        agent_id = agent_match.group(1)  # 5.644213021961965e-10
                        
                        pid_to_agent_map[pid] = {
                            'agent_id': agent_id,
                            'run': run_match.group(1).strip('"') if run_match else 'unknown',
                            'generation': int(gen_match.group(1)) if gen_match else 0,
                            'encoding': encoding_match.group(1) if encoding_match else 'unknown',
                            'neurons': int(neurons_match.group(1)) if neurons_match else 0,
                            'sensors': sensors_match.group(1) if sensors_match else 'unknown'
                        }
            
            return pid_to_agent_map
            
        except FileNotFoundError:
            print(f"Warning: {filepath} not found")
            return {}
        except Exception as e:
            print(f"Error parsing agent meta: {e}")
            return {}
    
    def get_pid_details(self, pid, trades_filepath, meta_filepath):
        """Get all details for a specific PID instance"""
        # Get PID to Agent ID mapping
        pid_map = self.parse_agent_meta(meta_filepath)
        
        # Get trade history for this PID
        agents_data = self.parse_agent_trades_detailed(trades_filepath)
        pid_data = next((a for a in agents_data if a['pid'] == pid), None)
        
        if not pid_data:
            return None
        
        # Combine with metadata
        meta = pid_map.get(pid, {})
        
        return {
            'pid': pid,
            'agent_id': meta.get('agent_id', 'unknown'),
            'run': meta.get('run', 'unknown'),
            'generation': meta.get('generation', 0),
            'encoding': meta.get('encoding', 'unknown'),
            'neurons': meta.get('neurons', 0),
            'sensors': meta.get('sensors', 'unknown'),
            'latest_fitness': pid_data['fitness'],
            'latest_raw_total_profit': pid_data['raw_total_profit'],
            'latest_realized_pl': pid_data['realized_pl'],
            'latest_unrealized_pl': pid_data['unrealized_pl'],
            'latest_realized_trades': pid_data['realized_trades'],
            'history': pid_data['history']
        }
    
    def get_agent_details(self, agent_id, trades_filepath, meta_filepath):
        """Get all instances (PIDs) for a specific Agent ID"""
        # Get PID to Agent ID mapping
        pid_map = self.parse_agent_meta(meta_filepath)
        
        # Find all PIDs for this agent
        pids_for_agent = [pid for pid, meta in pid_map.items() if meta['agent_id'] == agent_id]
        
        # Get trade data for each PID
        agents_data = self.parse_agent_trades_detailed(trades_filepath)
        
        instances = []
        for pid in pids_for_agent:
            pid_data = next((a for a in agents_data if a['pid'] == pid), None)
            if pid_data:
                meta = pid_map[pid]
                instances.append({
                    'pid': pid,
                    'run': meta.get('run', 'unknown'),
                    'generation': meta.get('generation', 0),
                    'encoding': meta.get('encoding', 'unknown'),
                    'neurons': meta.get('neurons', 0),
                    'sensors': meta.get('sensors', 'unknown'),
                    'latest_fitness': pid_data['fitness'],
                    'latest_raw_total_profit': pid_data['raw_total_profit'],
                    'latest_realized_pl': pid_data['realized_pl'],
                    'latest_unrealized_pl': pid_data['unrealized_pl'],
                    'latest_realized_trades': pid_data['realized_trades'],
                    'history': pid_data['history']
                })
        
        # Calculate aggregate stats - look at ALL evaluations across ALL instances
        if instances:
            # Find best fitness across all evaluations of all instances
            all_fitness_values = []
            all_realized_pl_values = []
            
            for instance in instances:
                if instance['history']:
                    all_fitness_values.extend([h['fitness'] for h in instance['history']])
                    all_realized_pl_values.extend([h['realized_pl'] for h in instance['history']])
            
            best_fitness = max(all_fitness_values) if all_fitness_values else 0
            best_profit = max(all_realized_pl_values) if all_realized_pl_values else 0
            total_evaluations = sum(len(i['history']) for i in instances)
        else:
            best_fitness = 0
            best_profit = 0
            total_evaluations = 0
        
        return {
            'agent_id': agent_id,
            'total_instances': len(instances),
            'best_fitness': best_fitness,
            'best_profit': best_profit,
            'total_evaluations': total_evaluations,
            'instances': instances
        }
    
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
    
    def parse_lineage(self, filepath):
        """Parse benchmarker.log for cross-population agent cloning lineage"""
        populations = {}
        all_agents = {}  # Track all agents across all populations
        cloning_events = []  # Track parent-child relationships
        current_pop = None
        
        try:
            with open(filepath, 'r') as f:
                content = f.read()
                lines = content.split('\n')
                
                i = 0
                while i < len(lines):
                    line = lines[i]
                    
                    # Detect population creation
                    if 'CREATING_POPULATION' in line:
                        pop_match = re.search(r'population_id=<<"([^"]+)"', line)
                        if pop_match:
                            pop_id = pop_match.group(1)
                            current_pop = pop_id
                            if pop_id not in populations:
                                populations[pop_id] = {
                                    'id': pop_id,
                                    'agents': {},
                                    'generation': 0
                                }
                    
                    # Detect clone population start
                    elif 'CLONE_POPULATION_START' in line:
                        # This marks the beginning of cloning from one pop to another
                        pass
                    
                    # Detect agent cloning (parent-child relationship) - may span multiple lines
                    # Look for both CLONED_AGENT and AGENT_CLONED events
                    elif ('CLONED_AGENT' in line or 'AGENT_CLONED' in line) and current_pop:
                        # The agent IDs might be on the next line, so read ahead
                        full_line = line
                        if i + 1 < len(lines) and 'agent}' in lines[i + 1]:
                            full_line += ' ' + lines[i + 1].strip()
                        if i + 2 < len(lines) and 'agent}' in lines[i + 2]:
                            full_line += ' ' + lines[i + 2].strip()
                        
                        source_match = re.search(r'source=\{([0-9.e+-]+),\s*agent\}', full_line)
                        clone_match = re.search(r'clone=\{([0-9.e+-]+),\s*agent\}', full_line)
                        species_match = re.search(r'specie=([0-9.e+-]+)', full_line)
                        
                        if source_match and clone_match:
                            source_id = source_match.group(1)
                            clone_id = clone_match.group(1)
                            species_id = species_match.group(1) if species_match else None
                            
                            # Record the cloning event
                            cloning_events.append({
                                'parent': source_id,
                                'child': clone_id,
                                'target_population': current_pop,
                                'species': species_id
                            })
                            
                            # Ensure both agents exist in our tracking
                            if source_id not in all_agents:
                                all_agents[source_id] = {
                                    'id': source_id,
                                    'population': None,  # Will be set when we see it summoned
                                    'generation': 0,
                                    'species': species_id,
                                    'fitness': None,
                                    'best_fitness': None,
                                    'evaluations': [],
                                    'children': []
                                }
                            
                            if clone_id not in all_agents:
                                all_agents[clone_id] = {
                                    'id': clone_id,
                                    'population': current_pop,
                                    'generation': 0,
                                    'parent': source_id,
                                    'species': species_id,
                                    'fitness': None,
                                    'best_fitness': None,
                                    'evaluations': [],
                                    'children': []
                                }
                            else:
                                # Update parent if not already set or if this is a more recent cloning
                                all_agents[clone_id]['parent'] = source_id
                                if all_agents[clone_id]['population'] is None:
                                    all_agents[clone_id]['population'] = current_pop
                            
                            # Add child to parent's children list
                            if 'children' not in all_agents[source_id]:
                                all_agents[source_id]['children'] = []
                            if clone_id not in all_agents[source_id]['children']:
                                all_agents[source_id]['children'].append(clone_id)
                    
                    # Detect agent summoning (track which population agents belong to)
                    elif 'SUMMONING_AGENTS' in line and current_pop:
                        # Extract agent IDs - may span multiple lines
                        full_line = line
                        j = i + 1
                        while j < len(lines) and j < i + 20:  # Look ahead up to 20 lines
                            if 'agent}]' in lines[j]:
                                full_line += ' ' + lines[j].strip()
                                break
                            elif 'agent}' in lines[j]:
                                full_line += ' ' + lines[j].strip()
                            j += 1
                        
                        agent_ids = re.findall(r'\{([0-9.e+-]+),\s*agent\}', full_line)
                        for agent_id in agent_ids:
                            if agent_id not in all_agents:
                                all_agents[agent_id] = {
                                    'id': agent_id,
                                    'population': current_pop,
                                    'generation': populations[current_pop]['generation'],
                                    'parent': None,
                                    'species': None,
                                    'fitness': None,
                                    'best_fitness': None,
                                    'evaluations': [],
                                    'children': []
                                }
                            else:
                                # Update population if not set
                                if all_agents[agent_id]['population'] is None:
                                    all_agents[agent_id]['population'] = current_pop
                    
                    # Detect generation changes
                    elif 'GENERATION_START' in line and current_pop:
                        gen_match = re.search(r'generation=(\d+)', line)
                        if gen_match:
                            populations[current_pop]['generation'] = int(gen_match.group(1))
                    
                    # Detect fitness evaluations - track ALL evaluations
                    elif 'TRAIN_EVAL' in line:
                        timestamp_match = re.search(r'\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]', line)
                        agent_match = re.search(r'\{([0-9.e+-]+),agent\}', line)
                        fitness_match = re.search(r'fitness=([0-9.e+-]+)', line)
                        attempt_match = re.search(r'attempt=(\d+)', line)
                        cycles_match = re.search(r'cycles=(\d+)', line)
                        time_match = re.search(r'time=(\d+)', line)
                        
                        if agent_match and fitness_match:
                            agent_id = agent_match.group(1)
                            fitness = float(fitness_match.group(1))
                            
                            if agent_id in all_agents:
                                # Add this evaluation to the list
                                eval_data = {
                                    'timestamp': timestamp_match.group(1) if timestamp_match else None,
                                    'fitness': fitness,
                                    'attempt': int(attempt_match.group(1)) if attempt_match else None,
                                    'cycles': int(cycles_match.group(1)) if cycles_match else None,
                                    'time_ms': int(time_match.group(1)) if time_match else None
                                }
                                all_agents[agent_id]['evaluations'].append(eval_data)
                                
                                # Keep the best fitness
                                if all_agents[agent_id]['best_fitness'] is None or fitness > all_agents[agent_id]['best_fitness']:
                                    all_agents[agent_id]['best_fitness'] = fitness
                                
                                # Set current fitness to latest
                                all_agents[agent_id]['fitness'] = fitness
                    
                    i += 1
            
            # Build the lineage structure
            # Find root agents (those with no parents)
            root_agents = [agent for agent in all_agents.values() if agent.get('parent') is None]
            
            # Create a single lineage structure showing all cloning relationships
            lineage_data = {
                'id': 'cross_population_lineage',
                'generations': len(populations),
                'agents': len(all_agents),
                'populations': len(populations),
                'best_fitness': max([a['best_fitness'] for a in all_agents.values() if a['best_fitness']], default=0),
                'lineage': list(all_agents.values()),
                'cloning_events': cloning_events
            }
            
            return [lineage_data]
            
        except FileNotFoundError:
            print(f"Warning: {filepath} not found")
            return []
        except Exception as e:
            print(f"Error parsing lineage: {e}")
            import traceback
            traceback.print_exc()
            return []

parser = LogParser()

@app.route('/')
def index():
    """Serve the dashboard HTML"""
    return render_template('dashboard.html')

@app.route('/agents')
def agents():
    """Serve the agent performance dashboard"""
    return render_template('agents.html')

@app.route('/test')
def test():
    """Serve test page"""
    return render_template('test.html')

@app.route('/lineage')
def lineage():
    """Serve the lineage visualization page"""
    return render_template('lineage.html')

@app.route('/mnesia')
def mnesia_browser():
    """Serve the Mnesia database browser page"""
    return render_template('mnesia.html')

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

@app.route('/api/agents')
def get_agents():
    """API endpoint for agent performance data (table only - latest values)"""
    
    # Parse agent trades with full detail
    agents_full = parser.parse_agent_trades_detailed(BENCHMARKER_DIR / "agent_trades.log")
    
    # Get PID to Agent ID mapping
    pid_map = parser.parse_agent_meta(BENCHMARKER_DIR / "agent_meta.log")
    
    # Return only latest values for table (no history), include agent_id from mapping
    agents_summary = []
    for agent in agents_full:
        pid = agent['pid']
        meta = pid_map.get(pid, {})
        agents_summary.append({
            'pid': pid,
            'agent_id': meta.get('agent_id', 'unknown'),
            'row_number': agent['row_number'],
            'fitness': agent['fitness'],
            'raw_total_profit': agent['raw_total_profit'],
            'realized_pl': agent['realized_pl'],
            'unrealized_pl': agent['unrealized_pl'],
            'realized_trades': agent['realized_trades']
        })
    
    return jsonify({
        'agents': agents_summary,
        'total_agents': len(agents_summary),
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/agents/trades')
def get_all_trades():
    """API endpoint for all trades chronologically (chart only)"""
    
    # Parse agent trades with full detail
    agents_full = parser.parse_agent_trades_detailed(BENCHMARKER_DIR / "agent_trades.log")
    
    print(f"DEBUG: Parsed {len(agents_full)} agents")
    
    # Flatten all trades with timestamps
    all_trades = []
    for agent in agents_full:
        history = agent.get('history')
        if history:
            print(f"DEBUG: Agent {agent['pid']} has {len(history)} history entries")
            for trade in history:
                all_trades.append({
                    'pid': agent['pid'],
                    'timestamp': trade['timestamp'],
                    'fitness': trade['fitness'],
                    'raw_total_profit': trade['raw_total_profit'],
                    'realized_pl': trade['realized_pl'],
                    'unrealized_pl': trade['unrealized_pl'],
                    'realized_trades': trade['realized_trades']
                })
        else:
            print(f"DEBUG: Agent {agent['pid']} has NO history")
    
    print(f"DEBUG: Total trades collected: {len(all_trades)}")
    
    # Sort by timestamp
    all_trades.sort(key=lambda x: x['timestamp'] if x['timestamp'] else '')
    
    if len(all_trades) > 0:
        print(f"DEBUG: First trade: {all_trades[0]}")
        print(f"DEBUG: Last trade: {all_trades[-1]}")
    
    return jsonify({
        'trades': all_trades,
        'total_trades': len(all_trades),
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/debug/trades')
def debug_trades():
    """Debug endpoint to check raw data"""
    agents_full = parser.parse_agent_trades_detailed(BENCHMARKER_DIR / "agent_trades.log")
    
    # Get a sample of trades data
    all_trades = []
    for agent in agents_full[:5]:  # Just first 5 agents
        history = agent.get('history')
        if history:
            for trade in history[:3]:  # Just first 3 trades per agent
                all_trades.append({
                    'pid': agent['pid'],
                    'timestamp': trade['timestamp'],
                    'fitness': trade['fitness'],
                    'raw_total_profit': trade['raw_total_profit']
                })
    
    return jsonify({
        'agent_count': len(agents_full),
        'sample_agent': agents_full[0] if agents_full else None,
        'agents_with_history': sum(1 for a in agents_full if a.get('history')),
        'sample_trades': all_trades
    })

@app.route('/api/pid/<path:pid>')
def get_pid_details_api(pid):
    """API endpoint to get details for a specific PID instance"""
    details = parser.get_pid_details(
        pid,
        BENCHMARKER_DIR / "agent_trades.log",
        BENCHMARKER_DIR / "agent_meta.log"
    )
    
    if details:
        return jsonify(details)
    else:
        return jsonify({'error': 'PID not found'}), 404

@app.route('/api/agent/<path:agent_id>')
def get_agent_details_api(agent_id):
    """API endpoint to get all instances for a specific Agent ID"""
    details = parser.get_agent_details(
        agent_id,
        BENCHMARKER_DIR / "agent_trades.log",
        BENCHMARKER_DIR / "agent_meta.log"
    )
    
    return jsonify(details)

@app.route('/agent/<path:agent_id>')
def agent_detail_page(agent_id):
    """Serve the agent detail page"""
    return render_template('agent_detail.html', agent_id=agent_id)

@app.route('/api/lineage')
def get_lineage():
    """API endpoint for lineage visualization data"""
    
    # Parse lineage from benchmarker log
    lineage_data = parser.parse_lineage(BENCHMARKER_DIR / "benchmarker.log")
    
    return jsonify({
        'populations': lineage_data,
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/mnesia/scan', methods=['POST'])
def scan_mnesia_directories():
    """API endpoint to scan for Mnesia directories"""
    data = request.get_json()
    base_path = data.get('path', '')
    
    if not base_path:
        return jsonify({'error': 'No path provided'}), 400
    
    try:
        reader = MnesiaReader('')
        mnesia_dirs = reader.list_available_mnesia_dirs(base_path)
        
        return jsonify({
            'mnesia_directories': mnesia_dirs,
            'count': len(mnesia_dirs)
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/mnesia/agents', methods=['POST'])
def get_mnesia_agents():
    """API endpoint to read agents from a Mnesia directory"""
    data = request.get_json()
    mnesia_path = data.get('path', '')
    sort_by = data.get('sort_by', 'fitness')
    
    if not mnesia_path:
        return jsonify({'error': 'No Mnesia path provided'}), 400
    
    try:
        reader = MnesiaReader(mnesia_path)
        agents = reader.read_agents()
        sorted_agents = reader.get_agents_sorted(sort_by=sort_by, reverse=True)
        stats = reader.get_statistics()
        
        return jsonify({
            'agents': sorted_agents,
            'statistics': stats,
            'mnesia_path': mnesia_path,
            'timestamp': datetime.now().isoformat()
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/mnesia/agent/<path:agent_id>', methods=['POST'])
def get_mnesia_agent_detail(agent_id):
    """API endpoint to get detailed info for a specific agent from Mnesia"""
    data = request.get_json()
    mnesia_path = data.get('path', '')
    
    if not mnesia_path:
        return jsonify({'error': 'No Mnesia path provided'}), 400
    
    try:
        reader = MnesiaReader(mnesia_path)
        details = reader.get_agent_full_details(agent_id)
        
        if details:
            return jsonify(details)
        else:
            return jsonify({'error': 'Agent not found'}), 404
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/mnesia/agent/<path:agent_id>')
def mnesia_agent_detail_page(agent_id):
    """Serve the Mnesia agent detail page"""
    return render_template('mnesia_agent_detail.html', agent_id=agent_id)

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
