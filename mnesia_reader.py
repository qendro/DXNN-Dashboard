#!/usr/bin/env python3
"""
Mnesia Database Reader for DXNN Agents
Reads agent records from Mnesia database files using Erlang export
"""

import struct
import os
import json
import subprocess
from pathlib import Path
from typing import List, Dict, Optional
import re


class MnesiaReader:
    """Read and parse Mnesia database files for agent information
    
    Uses an Erlang script to export Mnesia data to JSON format,
    then parses the JSON for display in the dashboard.
    """
    
    def __init__(self, mnesia_dir: str):
        self.mnesia_dir = Path(mnesia_dir)
        self.agents = []
        self.script_dir = Path(__file__).parent
        
    def list_available_mnesia_dirs(self, base_path: str) -> List[Dict[str, str]]:
        """Find all Mnesia directories in the given path"""
        mnesia_dirs = []
        base = Path(base_path)
        
        if not base.exists():
            return []
        
        # Look for directories matching Mnesia pattern
        for item in base.rglob("Mnesia.*"):
            if item.is_dir():
                # Check if it has schema.DAT or other Mnesia files
                if (item / "schema.DAT").exists() or list(item.glob("*.DAT")):
                    mnesia_dirs.append({
                        'path': str(item),
                        'name': item.name,
                        'parent': str(item.parent)
                    })
        
        return mnesia_dirs
    
    def read_agents(self) -> List[Dict]:
        """Read agent records from Mnesia database
        
        Uses Erlang script to export Mnesia data to JSON, then parses it.
        Falls back to benchmarker logs if Erlang export fails.
        """
        agents = []
        
        # Strategy 1: Use Erlang script to export Mnesia data
        try:
            agents = self._export_with_erlang()
            if agents:
                self.agents = agents
                return agents
        except Exception as e:
            print(f"Erlang export failed: {e}")
        
        # Strategy 2: Check for existing JSON export
        json_file = self.mnesia_dir / "agents.json"
        if json_file.exists():
            try:
                with open(json_file, 'r') as f:
                    agents = json.load(f)
                self.agents = agents
                return agents
            except Exception as e:
                print(f"Warning: Could not parse agents.json: {e}")
        
        # Strategy 3: Check for benchmarker logs
        parent_dir = self.mnesia_dir.parent
        benchmarker_dir = parent_dir / "logs" / "Benchmarker"
        if benchmarker_dir.exists():
            try:
                agents = self._parse_benchmarker_logs(benchmarker_dir)
            except Exception as e:
                print(f"Warning: Could not parse benchmarker logs: {e}")
        
        self.agents = agents
        return agents
    
    def _export_with_erlang(self) -> List[Dict]:
        """Use Erlang script to export Mnesia data to JSON"""
        # Path to the Erlang export script
        script_path = self.script_dir / "mnesia_export.erl"
        output_file = self.mnesia_dir / "agents_export.json"
        
        if not script_path.exists():
            raise FileNotFoundError(f"Erlang export script not found: {script_path}")
        
        # Try to find escript in common locations
        escript_paths = [
            "escript",  # In PATH
            r"C:\Program Files\Erlang OTP\bin\escript.exe",
            r"C:\Program Files\Erlang OTP\erts-16.2.2\bin\escript.exe",
            r"C:\Program Files\erl-26.2.5.2\bin\escript.exe",
            r"C:\Program Files\erl-25.3\bin\escript.exe",
            r"C:\Program Files (x86)\Erlang OTP\bin\escript.exe",
        ]
        
        # Also check for any Erlang installation in Program Files
        import glob
        program_files_paths = [
            r"C:\Program Files\erl*\bin\escript.exe",
            r"C:\Program Files (x86)\erl*\bin\escript.exe",
            r"C:\Program Files\Erlang*\bin\escript.exe",
            r"C:\Program Files (x86)\Erlang*\bin\escript.exe",
        ]
        
        for pattern in program_files_paths:
            escript_paths.extend(glob.glob(pattern))
        
        escript_cmd = None
        for path in escript_paths:
            test_path = Path(path)
            if test_path.exists():
                escript_cmd = str(test_path)
                print(f"Found escript at: {escript_cmd}")
                break
        
        if not escript_cmd:
            raise FileNotFoundError(
                f"escript not found. Searched in: {escript_paths}\n"
                "Please install Erlang and add it to PATH, "
                "or install it to a standard location like 'C:\\Program Files\\Erlang OTP\\bin'"
            )
        
        # Run the Erlang script
        cmd = [
            escript_cmd,
            str(script_path),
            str(self.mnesia_dir),
            str(output_file)
        ]
        
        print(f"Running: {' '.join(cmd)}")
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        print(f"Erlang script output: {result.stdout}")
        if result.stderr:
            print(f"Erlang script errors: {result.stderr}")
        
        if result.returncode != 0:
            raise RuntimeError(f"Erlang script failed with code {result.returncode}: {result.stderr}")
        
        # Read the exported JSON
        if not output_file.exists():
            raise FileNotFoundError(f"Export file not created: {output_file}")
        
        with open(output_file, 'r') as f:
            agents = json.load(f)
        
        # Clean up the export file
        try:
            output_file.unlink()
        except:
            pass
        
        return agents
    
    
    def _parse_benchmarker_logs(self, benchmarker_dir: Path) -> List[Dict]:
        """Parse benchmarker logs to extract agent information"""
        agents = []
        agent_meta_file = benchmarker_dir / "agent_meta.log"
        
        if not agent_meta_file.exists():
            return agents
        
        try:
            with open(agent_meta_file, 'r') as f:
                for line in f:
                    # Extract Agent ID
                    agent_match = re.search(r'\[AGENT:\{([0-9.e+-]+),agent\}\]', line)
                    if not agent_match:
                        continue
                    
                    agent_id = agent_match.group(1)
                    
                    # Extract metadata
                    run_match = re.search(r'run=(\d+|"[^"]*")', line)
                    gen_match = re.search(r'generation=(\d+)', line)
                    encoding_match = re.search(r'encoding=(\w+)', line)
                    neurons_match = re.search(r'neurons=(\d+)', line)
                    sensors_match = re.search(r'sensors=(\d+)', line)
                    actuators_match = re.search(r'actuators=(\d+)', line)
                    
                    # Check if we already have this agent
                    if any(a['agent_id'] == agent_id for a in agents):
                        continue
                    
                    agent_info = {
                        'agent_id': agent_id,
                        'table': 'agent',
                        'encoding': encoding_match.group(1) if encoding_match else 'unknown',
                        'generation': int(gen_match.group(1)) if gen_match else 0,
                        'fitness': 0.0,  # Will be updated from trades log
                        'neurons': int(neurons_match.group(1)) if neurons_match else 0,
                        'sensors': int(sensors_match.group(1)) if sensors_match else 0,
                        'actuators': int(actuators_match.group(1)) if actuators_match else 0,
                        'sensor_list': [],
                        'actuator_list': []
                    }
                    
                    agents.append(agent_info)
            
            # Try to get fitness from trades log
            trades_file = benchmarker_dir / "agent_trades.log"
            if trades_file.exists():
                agent_fitness = {}
                with open(trades_file, 'r') as f:
                    for line in f:
                        if 'FITNESS_EVAL' not in line:
                            continue
                        
                        agent_match = re.search(r'\[AGENT:\{([0-9.e+-]+),agent\}\]', line)
                        fitness_match = re.search(r'fitness=([0-9.e+-]+)', line)
                        
                        if agent_match and fitness_match:
                            agent_id = agent_match.group(1)
                            fitness = float(fitness_match.group(1))
                            # Keep the best fitness
                            if agent_id not in agent_fitness or fitness > agent_fitness[agent_id]:
                                agent_fitness[agent_id] = fitness
                
                # Update agent fitness values
                for agent in agents:
                    if agent['agent_id'] in agent_fitness:
                        agent['fitness'] = agent_fitness[agent['agent_id']]
        
        except Exception as e:
            print(f"Error parsing benchmarker logs: {e}")
        
        return agents
    
    def get_agent_by_id(self, agent_id: str) -> Optional[Dict]:
        """Get specific agent by ID"""
        for agent in self.agents:
            if agent['agent_id'] == agent_id:
                return agent
        return None
    
    def get_agent_full_details(self, agent_id: str) -> Optional[Dict]:
        """Get complete agent details including all related records from Mnesia"""
        script_path = self.script_dir / "mnesia_export_agent.erl"
        output_file = self.mnesia_dir / f"agent_{agent_id.replace('.', '_')}_details.json"
        
        if not script_path.exists():
            raise FileNotFoundError(f"Erlang agent export script not found: {script_path}")
        
        # Try to find escript
        import glob
        escript_paths = [
            "escript",
            r"C:\Program Files\Erlang OTP\bin\escript.exe",
            r"C:\Program Files\Erlang OTP\erts-16.2.2\bin\escript.exe",
        ]
        
        program_files_paths = [
            r"C:\Program Files\erl*\bin\escript.exe",
            r"C:\Program Files (x86)\erl*\bin\escript.exe",
            r"C:\Program Files\Erlang*\bin\escript.exe",
            r"C:\Program Files (x86)\Erlang*\bin\escript.exe",
        ]
        
        for pattern in program_files_paths:
            escript_paths.extend(glob.glob(pattern))
        
        escript_cmd = None
        for path in escript_paths:
            test_path = Path(path)
            if test_path.exists():
                escript_cmd = str(test_path)
                break
        
        if not escript_cmd:
            raise FileNotFoundError("escript not found")
        
        # Run the Erlang script
        cmd = [
            escript_cmd,
            str(script_path),
            str(self.mnesia_dir),
            agent_id,
            str(output_file)
        ]
        
        print(f"Running: {' '.join(cmd)}")
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        print(f"Erlang script output: {result.stdout}")
        if result.stderr:
            print(f"Erlang script errors: {result.stderr}")
        
        if result.returncode != 0:
            raise RuntimeError(f"Erlang script failed: {result.stderr}")
        
        # Read the exported JSON
        if not output_file.exists():
            raise FileNotFoundError(f"Export file not created: {output_file}")
        
        with open(output_file, 'r') as f:
            details = json.load(f)
        
        # Clean up
        try:
            output_file.unlink()
        except:
            pass
        
        return details
    
    def get_agents_sorted(self, sort_by: str = 'fitness', reverse: bool = True) -> List[Dict]:
        """Get agents sorted by specified field"""
        if not self.agents:
            return []
        
        valid_fields = ['fitness', 'generation', 'neurons', 'agent_id']
        if sort_by not in valid_fields:
            sort_by = 'fitness'
        
        return sorted(self.agents, key=lambda x: x.get(sort_by, 0), reverse=reverse)
    
    def get_statistics(self) -> Dict:
        """Get statistics about the agents in the database"""
        if not self.agents:
            return {
                'total_agents': 0,
                'avg_fitness': 0,
                'max_fitness': 0,
                'avg_neurons': 0,
                'max_generation': 0
            }
        
        fitnesses = [a['fitness'] for a in self.agents if a['fitness'] > 0]
        neurons = [a['neurons'] for a in self.agents if a['neurons'] > 0]
        generations = [a['generation'] for a in self.agents]
        
        return {
            'total_agents': len(self.agents),
            'avg_fitness': sum(fitnesses) / len(fitnesses) if fitnesses else 0,
            'max_fitness': max(fitnesses) if fitnesses else 0,
            'avg_neurons': sum(neurons) / len(neurons) if neurons else 0,
            'max_neurons': max(neurons) if neurons else 0,
            'max_generation': max(generations) if generations else 0,
            'encodings': list(set(a['encoding'] for a in self.agents))
        }
