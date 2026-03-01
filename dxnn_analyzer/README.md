# DXNN Analyzer

A comprehensive Erlang tool for analyzing, inspecting, and managing DXNN trading agents across multiple Mnesia database instances.

## Features

- Load and analyze multiple Mnesia folders simultaneously
- Inspect agent structure, topology, and mutations
- Compare agents across different experiments
- Create elite populations from best performers
- Master database: ETS-based contexts with Mnesia persistence
- Export visualizations and reports
- Pure Erlang implementation with no external dependencies

## Quick Start

### Prerequisites

- Erlang/OTP 26+
- Rebar3

### Installation

```bash
cd dxnn_analyzer
make compile
```

### Basic Usage

```bash
make shell
```

```erlang
%% Start the analyzer
1> analyzer:start().

%% Load a Mnesia folder
2> analyzer:load("../DXNN-Trader-V2/DXNN-Trader-v2/Mnesia.nonode@nohost", exp1).

%% Find top 5 agents
3> BestAgents = analyzer:find_best(5, [{context, exp1}]).

%% Inspect the best agent
4> [FirstAgent|_] = BestAgents.
5> analyzer:inspect(FirstAgent#agent.id, exp1).

%% Show topology
6> analyzer:show_topology(FirstAgent#agent.id, exp1).

%% Create elite population
7> AgentIds = [A#agent.id || A <- BestAgents].
8> analyzer:create_population(AgentIds, elite_traders, "./elite_output/").
```

## Common Commands

### Context Management
```erlang
analyzer:start().                                    % Start analyzer
analyzer:load("./Mnesia.nonode@nohost", exp1).      % Load Mnesia folder
analyzer:list_contexts().                            % Show all contexts
analyzer:unload(exp1).                               % Unload context
```

### Agent Analysis
```erlang
analyzer:list_agents([{context, exp1}]).            % List all agents
analyzer:find_best(10, [{context, exp1}]).          % Find top 10 agents
analyzer:inspect(AgentId, exp1).                     % Inspect agent
analyzer:show_topology(AgentId, exp1).               % Show topology
analyzer:show_mutations(AgentId, exp1).              % Show mutations
```

### Comparison
```erlang
analyzer:compare([Id1, Id2, Id3], exp1).            % Compare agents
stats_collector:generate_summary(exp1).             % Context summary
```

### Population Creation
```erlang
analyzer:create_population(
    [Id1, Id2, Id3],                                % Agent IDs
    elite_traders,                                   % Population name
    "./output/",                                     % Output folder
    [{context, exp1}]                               % Options
).
```

### Master Database (Elite Agent Collection)
```erlang
%% Create empty master context
master_database:create_empty(master_elite).

%% Add agents from multiple experiments
master_database:add_to_context([Id1, Id2], exp1, master_elite).
master_database:add_to_context([Id3, Id4], exp2, master_elite).

%% Analyze master context (uses standard analyzer functions)
analyzer:list_agents([{context, master_elite}]).
analyzer:compare([Id1, Id2, Id3], master_elite).

%% Save to disk when ready
master_database:save(master_elite, "./data/elite").

%% Export subset for deployment
master_database:export_for_deployment([Id1, Id2], prod_pop, "./deployment").
```

### Visualization
```erlang
topology_mapper:export_to_dot(AgentId, exp1, "topology.dot").
%% Then use Graphviz: dot -Tpng topology.dot -o topology.png
```

## Example Scripts

The `priv/examples/` directory contains ready-to-use scripts:

```bash
cd priv/examples

# Basic usage
./basic_usage.erl path/to/Mnesia.nonode@nohost

# Compare experiments
./compare_experiments.erl ./exp1/Mnesia.nonode@nohost ./exp2/Mnesia.nonode@nohost

# Create elite population
./create_elite_population.erl ./source/Mnesia.nonode@nohost ./output 10
```

## Integration with DXNN-Trader

1. Run your DXNN-Trader experiment
2. Copy the Mnesia folder to analyze
3. Use analyzer to select best agents
4. Create new population with analyzer
5. Copy the new Mnesia folder back to DXNN-Trader
6. Continue evolution with elite population

Example workflow:
```bash
# After DXNN experiment
cp -r DXNN-Trader-V2/DXNN-Trader-v2/Mnesia.nonode@nohost ./experiment_backup/

# Analyze and create elite population
cd dxnn_analyzer
make shell
```

```erlang
analyzer:start().
analyzer:load("../experiment_backup/Mnesia.nonode@nohost", exp1).
Best = analyzer:find_best(10, [{context, exp1}]).
Ids = [A#agent.id || A <- Best].
analyzer:create_population(Ids, elite, "./elite_output/").
```

```bash
# Copy back to DXNN-Trader
rm -rf DXNN-Trader-V2/DXNN-Trader-v2/Mnesia.nonode@nohost
cp -r dxnn_analyzer/elite_output/Mnesia.nonode@nohost DXNN-Trader-V2/DXNN-Trader-v2/
```

## Build Commands

```bash
make compile    # Compile the project
make clean      # Remove build artifacts
make test       # Run tests
make shell      # Start Erlang shell
```

## Documentation

- `docs/AI_README.md` - Comprehensive guide for AI agents
- `docs/ARCHITECTURE.md` - Technical architecture and development guide

## Troubleshooting

### Context not found
```erlang
analyzer:list_contexts().  %% Check loaded contexts
```

### Agent not found
```erlang
analyzer:list_agents([{context, exp1}]).  %% List all agents
```

### Validation failures
```erlang
population_builder:validate_population("./output/Mnesia.nonode@nohost").
```

### Memory issues
```erlang
analyzer:unload(old_context).  %% Unload unused contexts
erlang:memory().               %% Check memory usage
```

## License

Apache 2.0

## Version

0.1.0 - Initial Release
