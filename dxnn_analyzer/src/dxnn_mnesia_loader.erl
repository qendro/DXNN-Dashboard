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
                    case mnesia:wait_for_tables(ExistingTables, 5000) of
                        ok ->
                            %% Copy all data to ETS tables
                            {Tables, LoadErrors} = copy_to_ets(ContextName, ExistingTables),
                            
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
                            
                            case LoadErrors of
                                [] ->
                                    ok;
                                _ ->
                                    io:format("WARNING: Loaded with table read errors: ~p~n", [LoadErrors])
                            end,
                            
                            io:format("Context '~p' loaded successfully~n", [ContextName]),
                            io:format("  Agents: ~w, Species: ~w, Populations: ~w~n",
                                     [AgentCount, SpecieCount, PopCount]),
                            {ok, Context};
                        {timeout, TimedOutTables} ->
                            Mismatch = detect_schema_node_mismatch(TimedOutTables),
                            application:stop(mnesia),
                            cleanup_temp_dir(TempDir),
                            case Mismatch of
                                {true, OwnerNodes} ->
                                    {error, {schema_node_mismatch, OwnerNodes, node()}};
                                false ->
                                    {error, {table_load_timeout, TimedOutTables}}
                            end
                    end
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
    lists:foldl(fun(TableName, {TableAcc, ErrAcc}) ->
        EtsName = table_name(ContextName, TableName),
        % Use keypos 2 for all tables since record format is {RecordName, Id, ...}
        ets:new(EtsName, [named_table, public, bag, {keypos, 2}]),
        
        %% Copy all records from Mnesia to ETS
        TableErrors =
            try
                AllKeys = mnesia:dirty_all_keys(TableName),
                lists:foldl(fun(Key, KeyErrAcc) ->
                    try
                        Records = mnesia:dirty_read(TableName, Key),
                        lists:foreach(fun(Record) ->
                            try
                                ets:insert(EtsName, Record)
                            catch
                                error:Reason ->
                                    io:format("WARNING: Failed to insert record ~p from table ~p: ~p~n", 
                                             [Record, TableName, Reason])
                            end
                        end, Records),
                        KeyErrAcc
                    catch
                        error:ReadReason ->
                            io:format("WARNING: Failed to read key ~p from table ~p: ~p~n", 
                                     [Key, TableName, ReadReason]),
                            [{TableName, {read_key_failed, Key, ReadReason}} | KeyErrAcc];
                        exit:ReadReason ->
                            io:format("WARNING: Failed to read key ~p from table ~p: ~p~n", 
                                     [Key, TableName, ReadReason]),
                            [{TableName, {read_key_failed, Key, ReadReason}} | KeyErrAcc];
                        throw:ReadReason ->
                            io:format("WARNING: Failed to read key ~p from table ~p: ~p~n", 
                                     [Key, TableName, ReadReason]),
                            [{TableName, {read_key_failed, Key, ReadReason}} | KeyErrAcc]
                    end
                end, [], AllKeys)
            catch
                error:KeyReason ->
                    io:format("WARNING: Failed to get keys from table ~p: ~p~n", 
                             [TableName, KeyReason]),
                    [{TableName, {read_keys_failed, KeyReason}}];
                exit:KeyReason ->
                    io:format("WARNING: Failed to get keys from table ~p: ~p~n", 
                             [TableName, KeyReason]),
                    [{TableName, {read_keys_failed, KeyReason}}];
                throw:KeyReason ->
                    io:format("WARNING: Failed to get keys from table ~p: ~p~n", 
                             [TableName, KeyReason]),
                    [{TableName, {read_keys_failed, KeyReason}}]
            end,
        
        {[EtsName | TableAcc], TableErrors ++ ErrAcc}
    end, {[], []}, ExistingTables).

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

detect_schema_node_mismatch(Tables) ->
    OwnerNodes = lists:usort(lists:flatmap(fun(Table) ->
        case catch mnesia:table_info(Table, disc_copies) of
            {'EXIT', _} -> [];
            Nodes when is_list(Nodes) -> Nodes;
            _ -> []
        end
    end, Tables)),
    
    case OwnerNodes of
        [] ->
            false;
        _ ->
            case lists:member(node(), OwnerNodes) of
                true -> false;
                false -> {true, OwnerNodes}
            end
    end.
