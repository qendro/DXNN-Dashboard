-module(dxnn_mnesia_loader).
-export([
    load_folder/2,
    unload_context/1,
    get_context/1,
    table_name/2
]).

-include("../include/records.hrl").
-include("../include/analyzer_records.hrl").

%% @doc Load a Mnesia folder into a named context using ETS
load_folder(MnesiaPath, ContextName) ->
    io:format("Loading Mnesia folder: ~s~n", [MnesiaPath]),
    
    %% Verify path exists
    case filelib:is_dir(MnesiaPath) of
        false ->
            {error, {invalid_path, MnesiaPath}};
        true ->
            %% Create temporary Mnesia environment
            TempDir = create_temp_dir(),
            copy_mnesia_files(MnesiaPath, TempDir),
            
            %% Start temporary Mnesia instance
            application:stop(mnesia),
            application:set_env(mnesia, dir, TempDir),
            mnesia:start(),
            
            %% Check which tables actually exist
            AllTables = mnesia:system_info(tables),
            RequiredTables = [agent, cortex, neuron, sensor, 
                            actuator, substrate, population, specie],
            ExistingTables = [T || T <- RequiredTables, lists:member(T, AllTables)],
            
            %% If no tables exist, this is an empty checkpoint
            case ExistingTables of
                [] ->
                    application:stop(mnesia),
                    cleanup_temp_dir(TempDir),
                    {error, {empty_checkpoint, "No DXNN tables found. Training may have just started."}};
                _ ->
                    %% Wait only for tables that exist
                    mnesia:wait_for_tables(ExistingTables, 5000),
                    
                    %% Copy all data to ETS tables
                    Tables = copy_to_ets(ContextName, ExistingTables),
                    
                    %% Collect statistics (safely handle missing tables)
                    AgentCount = safe_table_size(table_name(ContextName, agent)),
                    PopCount = safe_table_size(table_name(ContextName, population)),
                    SpecieCount = safe_table_size(table_name(ContextName, specie)),
                    
                    %% Store context metadata
                    Context = #mnesia_context{
                        name = ContextName,
                        path = MnesiaPath,
                        loaded_at = erlang:timestamp(),
                        agent_count = AgentCount,
                        population_count = PopCount,
                        specie_count = SpecieCount,
                        tables = Tables
                    },
                    ets:insert(analyzer_contexts, Context),
                    
                    %% Cleanup
                    application:stop(mnesia),
                    cleanup_temp_dir(TempDir),
                    
                    io:format("Context '~p' loaded successfully~n", [ContextName]),
                    io:format("  Agents: ~w, Species: ~w, Populations: ~w~n",
                             [AgentCount, SpecieCount, PopCount]),
                    {ok, Context}
            end
    end.

%% @doc Unload a context and delete ETS tables
unload_context(ContextName) ->
    case ets:lookup(analyzer_contexts, ContextName) of
        [] ->
            {error, context_not_found};
        [Context] ->
            lists:foreach(fun(Table) ->
                ets:delete(Table)
            end, Context#mnesia_context.tables),
            ets:delete(analyzer_contexts, ContextName),
            io:format("Context '~p' unloaded~n", [ContextName]),
            ok
    end.

%% @doc Get context information
get_context(ContextName) ->
    case ets:lookup(analyzer_contexts, ContextName) of
        [] -> {error, context_not_found};
        [Context] -> {ok, Context}
    end.

%% Internal functions

copy_mnesia_files(Source, Dest) ->
    {ok, Files} = file:list_dir(Source),
    lists:foreach(fun(File) ->
        SourceFile = filename:join(Source, File),
        DestFile = filename:join(Dest, File),
        case filelib:is_regular(SourceFile) of
            true -> {ok, _} = file:copy(SourceFile, DestFile);
            false -> ok  % Skip directories
        end
    end, Files).

copy_to_ets(ContextName, ExistingTables) ->
    lists:map(fun(TableName) ->
        EtsName = table_name(ContextName, TableName),
        % Use keypos 2 for all tables since record format is {RecordName, Id, ...}
        ets:new(EtsName, [named_table, public, bag, {keypos, 2}]),
        
        %% Copy all records from Mnesia to ETS
        AllKeys = mnesia:dirty_all_keys(TableName),
        lists:foreach(fun(Key) ->
            Records = mnesia:dirty_read(TableName, Key),
            lists:foreach(fun(Record) ->
                ets:insert(EtsName, Record)
            end, Records)
        end, AllKeys),
        
        EtsName
    end, ExistingTables).

table_name(ContextName, TableName) ->
    list_to_atom(atom_to_list(ContextName) ++ "_" ++ atom_to_list(TableName)).

create_temp_dir() ->
    TempBase = "/tmp/dxnn_analyzer_" ++ integer_to_list(erlang:system_time()),
    filelib:ensure_dir(TempBase ++ "/"),
    TempBase.

cleanup_temp_dir(Dir) ->
    os:cmd("rm -rf " ++ Dir).

safe_table_size(TableName) ->
    case ets:info(TableName) of
        undefined -> 0;
        _ -> ets:info(TableName, size)
    end.
