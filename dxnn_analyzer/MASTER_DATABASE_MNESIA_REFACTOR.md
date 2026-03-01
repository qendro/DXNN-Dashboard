# Master Database: ETS-Based Implementation with Mnesia Persistence

## ✅ IMPLEMENTATION COMPLETE

This refactor has been successfully implemented. The master database now uses:
- ETS contexts for in-memory operations (fast)
- Explicit save to Mnesia for persistence (.DCD/.DCL files)
- Support for multiple master contexts simultaneously
- Consistent API with other contexts

## Why ETS with Mnesia Persistence

### The Problem with Active Mnesia
- Can only run one Mnesia instance at a time
- Switching directories is slow and disruptive
- Can't work with multiple masters simultaneously

### The Solution: ETS + Mnesia
**Master databases are ETS contexts (in-memory) with explicit save to Mnesia (on-disk)**

**Benefits:**
- ✅ Multiple master databases simultaneously (elite, production, experimental)
- ✅ Fast operations (all in ETS memory)
- ✅ Consistent API (same as other contexts)
- ✅ Flexible persistence (save when ready, where you want)
- ✅ Can merge/combine masters easily
- ✅ Can export subsets without complexity
- ✅ Mnesia format on disk (.DCD/.DCL) for DXNN-Trader compatibility

## Proposed Mnesia Approach

### Architecture: Master as ETS Context with Mnesia Persistence

```
Master Database = ETS Context (in-memory) + Mnesia (on-disk)
├── Multiple master contexts supported (master_elite, master_production, etc.)
├── Fast operations (all in ETS)
├── Explicit save to Mnesia for persistence
└── Load from Mnesia on startup
```

**Key Benefits:**
- ✅ Multiple master databases (elite agents, production agents, experimental, etc.)
- ✅ Fast reads/writes (ETS in-memory)
- ✅ Consistent API (same as other contexts)
- ✅ Flexible persistence (save when ready)
- ✅ Can merge/combine masters
- ✅ Can export subsets easily

### How It Works with Multiple Contexts

```
┌─────────────────────────────────────────────────────────┐
│  Source Contexts (ETS - Read Only)                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐             │
│  │Context A │  │Context B │  │Context C │             │
│  │(ETS)     │  │(ETS)     │  │(ETS)     │             │
│  └──────────┘  └──────────┘  └──────────┘             │
│       │              │              │                   │
│       └──────────────┴──────────────┘                   │
│                      │                                   │
│                      ▼ Copy to master ETS               │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Master Contexts (ETS - Read/Write)             │   │
│  │  ┌──────────────┐  ┌──────────────┐            │   │
│  │  │master_elite  │  │master_prod   │            │   │
│  │  │(ETS)         │  │(ETS)         │            │   │
│  │  └──────────────┘  └──────────────┘            │   │
│  └─────────────────────────────────────────────────┘   │
│                      │                                   │
│                      ▼ Explicit save                     │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Mnesia Persistence (on-disk)                   │   │
│  │  ./data/elite/Mnesia.nonode@nohost/             │   │
│  │  ./data/production/Mnesia.nonode@nohost/        │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

**Workflow:**
```erlang
%% Load multiple masters
master_database:load("./data/elite", master_elite).
master_database:load("./data/production", master_prod).

%% Add agents to different masters
master_database:add_to_context(AgentIds1, ctx1, master_elite).
master_database:add_to_context(AgentIds2, ctx2, master_prod).

%% Work with masters (all in ETS - fast!)
analyzer:list_agents([{context, master_elite}]).
analyzer:compare(AgentIds, master_elite).

%% Save when ready
master_database:save(master_elite, "./data/elite").
master_database:save(master_prod, "./data/production").

%% Or save to new location
master_database:save(master_elite, "./data/elite_backup").
```

### Key Changes

#### 1. **Initialize Master as Mnesia (Creates .DCD/.DCL files)**

**Implementation:**
```erlang
%% Initialize master database with Mnesia disc_copies format
init(BasePath) ->
    MasterPath = filename:join(BasePath, "MasterDatabase"),
    MnesiaDir = filename:join(MasterPath, "Mnesia.nonode@nohost"),
    filelib:ensure_dir(MnesiaDir ++ "/"),
    
    io:format("Initializing master database at: ~s~n", [MnesiaDir]),
    
    %% Check if already initialized
    SchemaFile = filename:join(MnesiaDir, "schema.DAT"),
    case filelib:is_file(SchemaFile) of
        true ->
            %% Already exists, just ensure Mnesia is pointing here
            io:format("Master database already exists~n"),
            ensure_mnesia_running(MnesiaDir),
            {ok, MasterPath};
        false ->
            %% Create new master database
            create_master_database(MnesiaDir),
            {ok, MasterPath}
    end.

create_master_database(MnesiaDir) ->
    %% Stop Mnesia if running
    application:stop(mnesia),
    
    %% Set Mnesia directory to master location
    application:set_env(mnesia, dir, MnesiaDir),
    
    %% Create schema
    io:format("Creating Mnesia schema...~n"),
    case mnesia:create_schema([node()]) of
        ok -> ok;
        {error, {_, {already_exists, _}}} -> ok
    end,
    
    %% Start Mnesia
    mnesia:start(),
    
    %% Create tables with disc_copies (creates .DCD/.DCL files)
    create_tables(),
    
    io:format("Master database initialized successfully~n"),
    ok.

create_tables() ->
    Tables = [
        {agent, record_info(fields, agent)},
        {cortex, record_info(fields, cortex)},
        {neuron, record_info(fields, neuron)},
        {sensor, record_info(fields, sensor)},
        {actuator, record_info(fields, actuator)},
        {substrate, record_info(fields, substrate)},
        {population, record_info(fields, population)},
        {specie, record_info(fields, specie)}
    ],
    
    lists:foreach(fun({TableName, Fields}) ->
        case mnesia:create_table(TableName, [
            {disc_copies, [node()]},      % Creates .DCD/.DCL files
            {attributes, Fields},
            {type, bag},                  % Allow duplicate keys
            {record_name, TableName}
        ]) of
            {atomic, ok} -> 
                io:format("  Created table: ~p~n", [TableName]);
            {aborted, {already_exists, _}} ->
                io:format("  Table exists: ~p~n", [TableName]);
            {aborted, Reason} ->
                io:format("  Error creating table ~p: ~p~n", [TableName, Reason])
        end
    end, Tables),
    
    %% Wait for tables to be ready
    mnesia:wait_for_tables([agent, cortex, neuron, sensor, actuator, 
                           substrate, population, specie], 5000).

ensure_mnesia_running(MnesiaDir) ->
    %% Check if Mnesia is already running with correct directory
    CurrentDir = case application:get_env(mnesia, dir) of
        {ok, Dir} -> Dir;
        undefined -> undefined
    end,
    
    IsRunning = mnesia:system_info(is_running) =:= yes,
    
    if
        CurrentDir =:= MnesiaDir andalso IsRunning ->
            %% Already running with correct directory, no action needed
            ok;
        true ->
            %% Need to switch to master directory
            application:stop(mnesia),
            application:set_env(mnesia, dir, MnesiaDir),
            mnesia:start(),
            mnesia:wait_for_tables([agent, cortex, neuron, sensor, actuator,
                                   substrate, population, specie], 5000)
    end.
```

**Key improvement:** Avoids unnecessary Mnesia restarts when already pointing to master.

**What this creates:**
```
./data/MasterDatabase/Mnesia.nonode@nohost/
├── agent.DCD       ← Disc copies data
├── agent.DCL       ← Disc copies log  
├── cortex.DCD
├── neuron.DCD
├── sensor.DCD
├── actuator.DCD
├── substrate.DCD
├── population.DCD
├── specie.DCD
├── schema.DAT      ← Mnesia schema
├── LATEST.LOG      ← Transaction log
└── DECISION_TAB.LOG
```

**Identical to DXNN-Trader format!**

#### 2. **Add Agents to Master Context (ETS)**

**Fast in-memory operations, save to disk when ready.**

```erlang
%% Add agents from source context to master context (ETS → ETS)
add_to_context(AgentIds, SourceContext, MasterContext) ->
    io:format("Adding ~w agents from ~p to ~p~n", 
              [length(AgentIds), SourceContext, MasterContext]),
    
    %% Verify master context exists
    case get_context(MasterContext) of
        {error, context_not_found} ->
            {error, {master_context_not_loaded, MasterContext}};
        {ok, _} ->
            %% Fetch and validate from source
            io:format("Fetching agents from source context (ETS)...~n"),
            AgentData = lists:map(fun(AgentId) ->
                case agent_inspector:get_full_topology(AgentId, SourceContext) of
                    {error, Reason} ->
                        io:format("  Error fetching agent ~p: ~p~n", [AgentId, Reason]),
                        {error, AgentId, Reason};
                    Topology ->
                        case validate_topology(AgentId, Topology) of
                            [] ->
                                io:format("  Fetched agent ~p: valid~n", [AgentId]),
                                {ok, AgentId, Topology};
                            Errors ->
                                io:format("  Agent ~p has errors: ~p~n", [AgentId, Errors]),
                                {error, AgentId, {validation_failed, Errors}}
                        end
                end
            end, AgentIds),
            
            %% Check for errors
            Errors = [{Id, R} || {error, Id, R} <- AgentData],
            case Errors of
                [] ->
                    ValidTopologies = [{Id, T} || {ok, Id, T} <- AgentData],
                    write_to_ets_context(ValidTopologies, MasterContext);
                _ ->
                    io:format("Failed to fetch/validate ~w agents~n", [length(Errors)]),
                    {error, {fetch_failed, Errors}}
            end
    end.

write_to_ets_context(AgentData, MasterContext) ->
    io:format("Writing ~w agents to master context (ETS)...~n", [length(AgentData)]),
    
    lists:foreach(fun({AgentId, Topology}) ->
        %% Check if already exists
        AgentTable = dxnn_mnesia_loader:table_name(MasterContext, agent),
        case ets:lookup(AgentTable, AgentId) of
            [_|_] ->
                io:format("  Agent ~p already exists, skipping~n", [AgentId]);
            [] ->
                %% Write all components to ETS
                Agent = maps:get(agent, Topology),
                Cortex = maps:get(cortex, Topology),
                Neurons = filter_undefined(maps:get(neurons, Topology)),
                Sensors = filter_undefined(maps:get(sensors, Topology)),
                Actuators = filter_undefined(maps:get(actuators, Topology)),
                
                ets:insert(AgentTable, Agent),
                ets:insert(dxnn_mnesia_loader:table_name(MasterContext, cortex), Cortex),
                
                NeuronTable = dxnn_mnesia_loader:table_name(MasterContext, neuron),
                lists:foreach(fun(N) -> ets:insert(NeuronTable, N) end, Neurons),
                
                SensorTable = dxnn_mnesia_loader:table_name(MasterContext, sensor),
                lists:foreach(fun(S) -> ets:insert(SensorTable, S) end, Sensors),
                
                ActuatorTable = dxnn_mnesia_loader:table_name(MasterContext, actuator),
                lists:foreach(fun(A) -> ets:insert(ActuatorTable, A) end, Actuators),
                
                case maps:get(substrate, Topology) of
                    undefined -> ok;
                    Sub -> 
                        SubTable = dxnn_mnesia_loader:table_name(MasterContext, substrate),
                        ets:insert(SubTable, Sub)
                end,
                
                io:format("  Wrote agent ~p: ~w neurons, ~w sensors, ~w actuators~n",
                         [AgentId, length(Neurons), length(Sensors), length(Actuators)])
        end
    end, AgentData),
    
    io:format("Successfully added ~w agents to master context~n", [length(AgentData)]),
    {ok, length(AgentData)}.

filter_undefined(List) ->
    [X || X <- List, X =/= undefined].
```

**Key benefits:**
- Fast ETS operations (no disk I/O)
- Can add from multiple sources
- Can work with multiple masters simultaneously

#### 3. **Validation Before Save**

**Critical:** Detect data integrity issues before writing.

```erlang
validate_topologies(Topologies) ->
    Errors = lists:flatmap(fun({AgentId, Topology}) ->
        validate_topology(AgentId, Topology)
    end, Topologies),
    
    case Errors of
        [] -> ok;
        _ -> {error, {validation_failed, Errors}}
    end.

validate_topology(AgentId, Topology) ->
    Errors = [],
    
    %% Check for undefined components
    Neurons = maps:get(neurons, Topology),
    UndefinedNeurons = [N || N <- Neurons, N =:= undefined],
    Errors1 = case UndefinedNeurons of
        [] -> Errors;
        _ -> [{AgentId, {undefined_neurons, length(UndefinedNeurons)}} | Errors]
    end,
    
    %% Check for duplicate component IDs
    NeuronIds = [N#neuron.id || N <- Neurons, N =/= undefined],
    Duplicates = NeuronIds -- lists:usort(NeuronIds),
    Errors2 = case Duplicates of
        [] -> Errors1;
        _ -> [{AgentId, {duplicate_neuron_ids, Duplicates}} | Errors1]
    end,
    
    %% Check cortex references match actual components
    Cortex = maps:get(cortex, Topology),
    ExpectedNeuronIds = Cortex#cortex.neuron_ids,
    ActualNeuronIds = lists:usort(NeuronIds),
    Missing = ExpectedNeuronIds -- ActualNeuronIds,
    Errors3 = case Missing of
        [] -> Errors2;
        _ -> [{AgentId, {missing_neurons, Missing}} | Errors2]
    end,
    
    Errors3.
```

#### 4. **Save Master Context to Mnesia (Persistence)**

**Explicit save from ETS to Mnesia on disk.**

```erlang
%% Save master context to Mnesia on disk
save(MasterContext, OutputPath) ->
    io:format("Saving master context ~p to ~s~n", [MasterContext, OutputPath]),
    
    %% Verify context exists
    case get_context(MasterContext) of
        {error, context_not_found} ->
            {error, {context_not_found, MasterContext}};
        {ok, Context} ->
            MnesiaDir = filename:join(OutputPath, "Mnesia.nonode@nohost"),
            filelib:ensure_dir(MnesiaDir ++ "/"),
            
            %% Create/update Mnesia database
            save_ets_to_mnesia(Context, MnesiaDir)
    end.

save_ets_to_mnesia(Context, MnesiaDir) ->
    %% Stop current Mnesia, point to output directory
    application:stop(mnesia),
    application:set_env(mnesia, dir, MnesiaDir),
    
    %% Create schema if doesn't exist
    SchemaFile = filename:join(MnesiaDir, "schema.DAT"),
    case filelib:is_file(SchemaFile) of
        false ->
            mnesia:create_schema([node()]);
        true ->
            ok
    end,
    
    mnesia:start(),
    
    %% Create tables if don't exist
    create_mnesia_tables(),
    
    %% Copy all data from ETS to Mnesia in transaction
    Tables = [agent, cortex, neuron, sensor, actuator, substrate, population, specie],
    
    F = fun() ->
        lists:foreach(fun(TableName) ->
            %% Clear existing data
            mnesia:clear_table(TableName),
            
            %% Copy from ETS
            EtsTable = dxnn_mnesia_loader:table_name(Context#mnesia_context.name, TableName),
            Count = ets:foldl(fun(Record, Acc) ->
                mnesia:write(Record),
                Acc + 1
            end, 0, EtsTable),
            
            io:format("  Saved ~w records to ~p~n", [Count, TableName])
        end, Tables)
    end,
    
    case mnesia:transaction(F) of
        {atomic, _} ->
            application:stop(mnesia),
            io:format("Master context saved successfully to: ~s~n", [MnesiaDir]),
            {ok, MnesiaDir};
        {aborted, Reason} ->
            application:stop(mnesia),
            {error, {save_failed, Reason}}
    end.

create_mnesia_tables() ->
    Tables = [
        {agent, record_info(fields, agent)},
        {cortex, record_info(fields, cortex)},
        {neuron, record_info(fields, neuron)},
        {sensor, record_info(fields, sensor)},
        {actuator, record_info(fields, actuator)},
        {substrate, record_info(fields, substrate)},
        {population, record_info(fields, population)},
        {specie, record_info(fields, specie)}
    ],
    
    lists:foreach(fun({TableName, Fields}) ->
        case mnesia:create_table(TableName, [
            {disc_copies, [node()]},
            {attributes, Fields},
            {type, bag},
            {record_name, TableName}
        ]) of
            {atomic, ok} -> ok;
            {aborted, {already_exists, _}} -> ok;
            {aborted, Reason} ->
                io:format("  Error creating table ~p: ~p~n", [TableName, Reason])
        end
    end, Tables),
    
    mnesia:wait_for_tables([agent, cortex, neuron, sensor, actuator,
                           substrate, population, specie], 5000).
```

**Usage:**
```erlang
%% Save to original location
master_database:save(master_elite, "./data/elite").

%% Save to new location (backup)
master_database:save(master_elite, "./data/elite_backup").

%% Save to deployment location
master_database:save(master_prod, "./deployment/production").
```

#### 5. **Direct Deployment to DXNN-Trader**

**Critical:** Master database is already in DXNN-Trader format!

**Simple approach - Copy entire master database:**
```bash
# Master database IS deployment-ready
cp -r ./data/MasterDatabase/Mnesia.nonode@nohost /path/to/DXNN-Trader/
```

**Advanced approach - Export subset with population/specie records:**
```erlang
%% Export specific agents to new Mnesia database for deployment
export_for_deployment(AgentIds, PopulationId, OutputPath) ->
    io:format("Exporting ~w agents for deployment...~n", [length(AgentIds)]),
    
    %% 1. Ensure master is loaded as ETS context for reading
    case get_context(master) of
        {error, context_not_found} ->
            io:format("Loading master as context for export...~n"),
            load_as_context("./data/MasterDatabase", master);
        {ok, _} ->
            io:format("Master context already loaded~n")
    end,
    
    %% 2. Fetch agent topologies from master ETS context
    io:format("Fetching ~w agents from master context...~n", [length(AgentIds)]),
    Topologies = lists:map(fun(AgentId) ->
        case agent_inspector:get_full_topology(AgentId, master) of
            {error, Reason} ->
                io:format("  Error fetching agent ~p: ~p~n", [AgentId, Reason]),
                {error, AgentId, Reason};
            Topology ->
                {ok, AgentId, Topology}
        end
    end, AgentIds),
    
    %% Check for errors
    Errors = [{Id, R} || {error, Id, R} <- Topologies],
    case Errors of
        [] ->
            ValidTopologies = [{Id, T} || {ok, Id, T} <- Topologies],
            create_deployment_database(ValidTopologies, PopulationId, OutputPath);
        _ ->
            {error, {fetch_failed, Errors}}
    end.

create_deployment_database(Topologies, PopulationId, OutputPath) ->
    %% Create new Mnesia database for deployment
    DeployDir = filename:join(OutputPath, "Mnesia.nonode@nohost"),
    filelib:ensure_dir(DeployDir ++ "/"),
    
    io:format("Creating deployment database at: ~s~n", [DeployDir]),
    
    %% Stop current Mnesia, create new deployment database
    application:stop(mnesia),
    application:set_env(mnesia, dir, DeployDir),
    mnesia:create_schema([node()]),
    mnesia:start(),
    create_tables(),
    
    %% Write all agents with population/specie records in transaction
    AgentIds = [Id || {Id, _} <- Topologies],
    
    F = fun() ->
        %% Create population record
        Population = #population{
            id = PopulationId,
            specie_ids = [PopulationId],
            morphologies = [xor_mimic],
            innovation_factor = {0, 0}
        },
        mnesia:write(Population),
        
        %% Create specie record  
        Specie = #specie{
            id = PopulationId,
            population_id = PopulationId,
            agent_ids = AgentIds,
            fingerprint = undefined
        },
        mnesia:write(Specie),
        
        %% Write all agents and their components
        lists:foreach(fun({AgentId, Topology}) ->
            %% Update agent with new population/specie IDs
            Agent = maps:get(agent, Topology),
            UpdatedAgent = Agent#agent{
                population_id = PopulationId,
                specie_id = PopulationId
            },
            
            %% Write agent and all components
            mnesia:write(UpdatedAgent),
            mnesia:write(maps:get(cortex, Topology)),
            
            Neurons = filter_undefined(maps:get(neurons, Topology)),
            Sensors = filter_undefined(maps:get(sensors, Topology)),
            Actuators = filter_undefined(maps:get(actuators, Topology)),
            
            lists:foreach(fun(N) -> mnesia:write(N) end, Neurons),
            lists:foreach(fun(S) -> mnesia:write(S) end, Sensors),
            lists:foreach(fun(A) -> mnesia:write(A) end, Actuators),
            
            case maps:get(substrate, Topology) of
                undefined -> ok;
                Sub -> mnesia:write(Sub)
            end,
            
            io:format("  Exported agent ~p~n", [AgentId])
        end, Topologies)
    end,
    
    case mnesia:transaction(F) of
        {atomic, _} ->
            application:stop(mnesia),
            io:format("Deployment database created successfully~n"),
            io:format("Ready to deploy: ~s~n", [DeployDir]),
            {ok, DeployDir};
        {aborted, Reason} ->
            application:stop(mnesia),
            {error, {export_failed, Reason}}
    end.
```

**Key improvements:**
- Reads from master ETS context (no Mnesia switching during read)
- Creates clean deployment database with proper population/specie records
- Updates agent population/specie IDs for deployment
- All operations in single transaction

## Example Workflows

### Workflow 1: Build Elite Agent Collection
```erlang
%% 1. Load experiments
analyzer:load("./exp1/Mnesia.nonode@nohost", exp1).
analyzer:load("./exp2/Mnesia.nonode@nohost", exp2).
analyzer:load("./exp3/Mnesia.nonode@nohost", exp3).

%% 2. Create new master for elite agents
master_database:load("./data/elite", master_elite).  % Creates empty

%% 3. Add best agents from each experiment
Best1 = analyzer:find_best(5, [{context, exp1}, {min_fitness, 0.8}]).
Best2 = analyzer:find_best(5, [{context, exp2}, {min_fitness, 0.8}]).
Best3 = analyzer:find_best(5, [{context, exp3}, {min_fitness, 0.8}]).

Ids1 = [A#agent.id || A <- Best1].
Ids2 = [A#agent.id || A <- Best2].
Ids3 = [A#agent.id || A <- Best3].

master_database:add_to_context(Ids1, exp1, master_elite).
master_database:add_to_context(Ids2, exp2, master_elite).
master_database:add_to_context(Ids3, exp3, master_elite).

%% 4. Analyze elite collection
analyzer:list_agents([{context, master_elite}]).  % 15 agents
analyzer:compare(Ids1 ++ Ids2, master_elite).

%% 5. Save to disk
master_database:save(master_elite, "./data/elite").
```

### Workflow 2: Multiple Master Databases
```erlang
%% Load multiple masters
master_database:load("./data/elite", master_elite).
master_database:load("./data/production", master_prod).
master_database:load("./data/experimental", master_exp).

%% Work with each independently
analyzer:list_agents([{context, master_elite}]).
analyzer:list_agents([{context, master_prod}]).
analyzer:list_agents([{context, master_exp}]).

%% Promote agents from experimental to production
PromoteIds = [...],
master_database:add_to_context(PromoteIds, master_exp, master_prod).

%% Save changes
master_database:save(master_prod, "./data/production").
```

### Workflow 3: Backup and Versioning
```erlang
%% Load current production
master_database:load("./data/production", master_prod).

%% Save backup before changes
master_database:save(master_prod, "./data/production_backup_2024_03_01").

%% Make changes
master_database:add_to_context(NewIds, exp1, master_prod).

%% Save updated version
master_database:save(master_prod, "./data/production").
```

### Workflow 4: Deploy to DXNN-Trader
```erlang
%% Load master
master_database:load("./data/elite", master_elite).

%% Option 1: Deploy entire master
master_database:save(master_elite, "/path/to/DXNN-Trader").

%% Option 2: Export subset with population records
TopIds = [...],
master_database:export_for_deployment(TopIds, prod_pop_1, "./deployment").

%% Copy to DXNN-Trader
%% cp -r ./deployment/Mnesia.nonode@nohost /path/to/DXNN-Trader/
```

## Benefits Summary

### Immediate
- **No file size limits** - Scale to thousands of agents
- **Data integrity** - Transactions prevent corruption
- **Better performance** - Faster reads/writes
- **Consistency** - Same storage as rest of system

### Long-term
- **Direct deployment** - Copy master database to DXNN-Trader
- **Query capability** - Use QLC for complex queries
- **Distributed** - Can replicate across nodes
- **Validation** - Catch data issues before save

## Risks & Mitigation

### Risk: Mnesia context switching overhead
**Mitigation:** Keep master loaded as persistent context

### Risk: Transaction conflicts with concurrent writes
**Mitigation:** Master database is write-rarely, read-often (low conflict)

### Risk: Migration from DETS
**Mitigation:** Provide migration script, test thoroughly

### Risk: Mnesia directory management
**Mitigation:** Clear documentation, helper functions

## Testing Strategy

1. **Unit tests**: Validate each operation in isolation
2. **Integration tests**: Full workflow (load → save → deploy)
3. **Data integrity tests**: Verify all components present
4. **Performance tests**: Compare DETS vs Mnesia speed
5. **Deployment tests**: Deploy to DXNN-Trader and run

## Conclusion

Switching to Mnesia is the right architectural choice:
- Eliminates DETS limitations
- Provides transaction safety
- Enables direct deployment
- Maintains consistency with existing system

The current DETS approach works but will cause problems at scale. Better to refactor now while the codebase is small.
