-module(master_database).
-export([
    load/2,
    create_empty/1,
    add_to_context/3,
    save/2,
    export_for_deployment/3,
    list_contexts/0,
    unload/1
]).

-include("../include/records.hrl").
-include("../include/analyzer_records.hrl").

%% @doc Load existing database from Mnesia into ETS context
load(MnesiaPath, Context) ->
    io:format("Loading database from ~s as context ~p~n", [MnesiaPath, Context]),
    
    MnesiaDir = case filename:basename(MnesiaPath) of
        "Mnesia.nonode@nohost" -> MnesiaPath;
        _ -> filename:join(MnesiaPath, "Mnesia.nonode@nohost")
    end,
    
    case filelib:is_dir(MnesiaDir) of
        false ->
            io:format("Database not found, creating empty context~n"),
            create_empty(Context);
        true ->
            dxnn_mnesia_loader:load_folder(MnesiaDir, Context)
    end.

%% @doc Create empty database context (ETS only, no disk)
create_empty(Context) ->
    io:format("Creating empty database context: ~p~n", [Context]),
    
    case dxnn_mnesia_loader:get_context(Context) of
        {ok, ExistingContext} ->
            io:format("Context '~p' already exists~n", [Context]),
            {ok, ExistingContext};
        {error, context_not_found} ->
            Tables = [agent, cortex, neuron, sensor, actuator, substrate, population, specie],
            EtsTables = lists:map(fun(TableName) ->
                EtsName = dxnn_mnesia_loader:table_name(Context, TableName),
                case ets:info(EtsName) of
                    undefined ->
                        ets:new(EtsName, [named_table, public, bag, {keypos, 2}]);
                    _ ->
                        io:format("  Table ~p already exists, reusing~n", [EtsName])
                end,
                EtsName
            end, Tables),
            
            ContextRecord = #mnesia_context{
                name = Context,
                path = undefined,
                loaded_at = erlang:timestamp(),
                agent_count = 0,
                population_count = 0,
                specie_count = 0,
                tables = EtsTables
            },
            
            case ets:info(analyzer_contexts) of
                undefined ->
                    ets:new(analyzer_contexts, [named_table, public, set, {keypos, 2}]);
                _ -> ok
            end,
            
            ets:insert(analyzer_contexts, ContextRecord),
            
            io:format("Empty context '~p' created~n", [Context]),
            {ok, ContextRecord}
    end.

%% @doc Add agents from source context to master context (ETS → ETS)
add_to_context(AgentIds, SourceContext, MasterContext) ->
    io:format("Adding ~w agents from ~p to ~p~n", 
              [length(AgentIds), SourceContext, MasterContext]),
    
    case dxnn_mnesia_loader:get_context(MasterContext) of
        {error, context_not_found} ->
            {error, {master_context_not_loaded, MasterContext}};
        {ok, _} ->
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

%% @doc Save database context to Mnesia on disk
save(Context, OutputPath) ->
    io:format("Saving context ~p to ~s~n", [Context, OutputPath]),
    
    case dxnn_mnesia_loader:get_context(Context) of
        {error, context_not_found} ->
            {error, {context_not_found, Context}};
        {ok, ContextRecord} ->
            MnesiaDir = filename:join(OutputPath, "Mnesia.nonode@nohost"),
            filelib:ensure_dir(MnesiaDir ++ "/"),
            save_ets_to_mnesia(ContextRecord, MnesiaDir)
    end.

%% @doc Export specific agents to new Mnesia database for deployment
export_for_deployment(AgentIds, PopulationId, OutputPath) ->
    io:format("Exporting ~w agents for deployment...~n", [length(AgentIds)]),
    
    MasterContext = master,
    
    case dxnn_mnesia_loader:get_context(MasterContext) of
        {error, context_not_found} ->
            {error, {master_not_loaded, "Load master database first"}};
        {ok, _} ->
            io:format("Fetching ~w agents from master context...~n", [length(AgentIds)]),
            Topologies = lists:map(fun(AgentId) ->
                case agent_inspector:get_full_topology(AgentId, MasterContext) of
                    {error, Reason} ->
                        io:format("  Error fetching agent ~p: ~p~n", [AgentId, Reason]),
                        {error, AgentId, Reason};
                    Topology ->
                        {ok, AgentId, Topology}
                end
            end, AgentIds),
            
            Errors = [{Id, R} || {error, Id, R} <- Topologies],
            case Errors of
                [] ->
                    ValidTopologies = [{Id, T} || {ok, Id, T} <- Topologies],
                    create_deployment_database(ValidTopologies, PopulationId, OutputPath);
                _ ->
                    {error, {fetch_failed, Errors}}
            end
    end.

%% @doc List all master contexts
list_contexts() ->
    case ets:info(analyzer_contexts) of
        undefined -> [];
        _ ->
            AllContexts = ets:tab2list(analyzer_contexts),
            [C || C <- AllContexts, is_master_context(C)]
    end.

%% @doc Unload master context
unload(MasterContext) ->
    dxnn_mnesia_loader:unload_context(MasterContext).

%% ============================================================================
%% Internal Functions
%% ============================================================================

is_master_context(#mnesia_context{path = undefined}) -> true;
is_master_context(#mnesia_context{path = Path}) ->
    PathStr = lists:flatten(io_lib:format("~s", [Path])),
    string:str(PathStr, "data/") > 0;
is_master_context(_) -> false.

validate_topology(AgentId, Topology) ->
    Errors = [],
    
    Neurons = maps:get(neurons, Topology),
    UndefinedNeurons = [N || N <- Neurons, N =:= undefined],
    Errors1 = case UndefinedNeurons of
        [] -> Errors;
        _ -> [{AgentId, {undefined_neurons, length(UndefinedNeurons)}} | Errors]
    end,
    
    NeuronIds = [N#neuron.id || N <- Neurons, N =/= undefined],
    Duplicates = NeuronIds -- lists:usort(NeuronIds),
    Errors2 = case Duplicates of
        [] -> Errors1;
        _ -> [{AgentId, {duplicate_neuron_ids, Duplicates}} | Errors1]
    end,
    
    Cortex = maps:get(cortex, Topology),
    ExpectedNeuronIds = Cortex#cortex.neuron_ids,
    ActualNeuronIds = lists:usort(NeuronIds),
    Missing = ExpectedNeuronIds -- ActualNeuronIds,
    Errors3 = case Missing of
        [] -> Errors2;
        _ -> [{AgentId, {missing_neurons, Missing}} | Errors2]
    end,
    
    Errors3.

filter_undefined(List) ->
    [X || X <- List, X =/= undefined].

write_to_ets_context(AgentData, MasterContext) ->
    io:format("Writing ~w agents to master context (ETS)...~n", [length(AgentData)]),
    
    lists:foreach(fun({AgentId, Topology}) ->
        AgentTable = dxnn_mnesia_loader:table_name(MasterContext, agent),
        case ets:lookup(AgentTable, AgentId) of
            [_|_] ->
                io:format("  Agent ~p already exists, skipping~n", [AgentId]);
            [] ->
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
    
    AgentTable = dxnn_mnesia_loader:table_name(MasterContext, agent),
    NewCount = ets:info(AgentTable, size),
    case ets:lookup(analyzer_contexts, MasterContext) of
        [Context] ->
            UpdatedContext = Context#mnesia_context{agent_count = NewCount},
            ets:insert(analyzer_contexts, UpdatedContext);
        [] -> ok
    end,
    
    io:format("Successfully added ~w agents to master context~n", [length(AgentData)]),
    {ok, length(AgentData)}.

save_ets_to_mnesia(Context, MnesiaDir) ->
    io:format("Saving to Mnesia directory: ~s~n", [MnesiaDir]),
    
    CurrentDir = case application:get_env(mnesia, dir) of
        {ok, Dir} -> Dir;
        undefined -> undefined
    end,
    
    NeedRestart = CurrentDir =/= MnesiaDir,
    
    if
        NeedRestart ->
            application:stop(mnesia),
            application:set_env(mnesia, dir, MnesiaDir);
        true ->
            ok
    end,
    
    SchemaFile = filename:join(MnesiaDir, "schema.DAT"),
    case filelib:is_file(SchemaFile) of
        false ->
            io:format("Creating new Mnesia schema~n"),
            mnesia:create_schema([node()]);
        true ->
            io:format("Using existing Mnesia schema~n")
    end,
    
    if
        NeedRestart ->
            mnesia:start();
        true ->
            ok
    end,
    
    create_mnesia_tables(),
    
    Tables = [agent, cortex, neuron, sensor, actuator, substrate, population, specie],
    
    %% Write data outside of transaction to avoid nested transaction issues
    io:format("Copying data from ETS to Mnesia...~n"),
    lists:foreach(fun(TableName) ->
        mnesia:clear_table(TableName),
        
        EtsTable = dxnn_mnesia_loader:table_name(Context#mnesia_context.name, TableName),
        
        %% Write each record individually using dirty operations
        Count = ets:foldl(fun(Record, Acc) ->
            mnesia:dirty_write(Record),
            Acc + 1
        end, 0, EtsTable),
        
        io:format("  Saved ~w records to ~p~n", [Count, TableName])
    end, Tables),
    
    io:format("Master context saved successfully to: ~s~n", [MnesiaDir]),
    {ok, MnesiaDir}.

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
            {atomic, ok} -> 
                io:format("  Created table: ~p~n", [TableName]);
            {aborted, {already_exists, _}} ->
                ok;
            {aborted, Reason} ->
                io:format("  Error creating table ~p: ~p~n", [TableName, Reason])
        end
    end, Tables),
    
    mnesia:wait_for_tables([agent, cortex, neuron, sensor, actuator,
                           substrate, population, specie], 5000).

create_deployment_database(Topologies, PopulationId, OutputPath) ->
    DeployDir = filename:join(OutputPath, "Mnesia.nonode@nohost"),
    filelib:ensure_dir(DeployDir ++ "/"),
    
    io:format("Creating deployment database at: ~s~n", [DeployDir]),
    
    application:stop(mnesia),
    application:set_env(mnesia, dir, DeployDir),
    mnesia:create_schema([node()]),
    mnesia:start(),
    create_mnesia_tables(),
    
    AgentIds = [Id || {Id, _} <- Topologies],
    
    F = fun() ->
        Population = #population{
            id = PopulationId,
            specie_ids = [PopulationId],
            morphologies = [xor_mimic],
            innovation_factor = {0, 0}
        },
        mnesia:write(Population),
        
        Specie = #specie{
            id = PopulationId,
            population_id = PopulationId,
            agent_ids = AgentIds,
            fingerprint = undefined
        },
        mnesia:write(Specie),
        
        lists:foreach(fun({AgentId, Topology}) ->
            Agent = maps:get(agent, Topology),
            UpdatedAgent = Agent#agent{
                population_id = PopulationId,
                specie_id = PopulationId
            },
            
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
