%% Read a transactional Mnesia backup directly into analysis ETS tables.
%% No schema/node migration and no live Mnesia shutdown are needed for analysis.
-module(dxnn_backup_loader).
-export([load/2]).
-include("../include/analyzer_records.hrl").

load(Path, ContextName) ->
    Tables = [agent, cortex, neuron, sensor, actuator, substrate, population, specie],
    Names = [{T, dxnn_mnesia_loader:table_name(ContextName, T)} || T <- Tables],
    Temp = filename:join("/tmp", "dxnn-backup-" ++ integer_to_list(erlang:unique_integer([positive]))),
    try
        lists:foreach(fun({_, Name}) -> ets:new(Name, [named_table, public, bag, {keypos, 2}]) end, Names),
        Reader = fun(Item, Count) ->
            case is_tuple(Item) andalso tuple_size(Item) >= 2 of
                true ->
                    case lists:keyfind(element(1, Item), 1, Names) of
                        {_, Name} -> ets:insert(Name, Item), {[Item], Count + 1};
                        false -> {[Item], Count}
                    end;
                false -> {[Item], Count}
            end
        end,
        {ok, Count} = mnesia:traverse_backup(Path, Temp, Reader, 0),
        true = Count > 0,
        Context = #mnesia_context{name=ContextName, path=filename:dirname(Path),
            loaded_at=erlang:timestamp(),
            agent_count=ets:info(proplists:get_value(agent, Names), size),
            population_count=ets:info(proplists:get_value(population, Names), size),
            specie_count=ets:info(proplists:get_value(specie, Names), size),
            tables=[Name || {_, Name} <- Names]},
        ets:insert(analyzer_contexts, Context),
        {ok, Context}
    catch
        _:Reason ->
            lists:foreach(fun({_, Name}) -> catch ets:delete(Name) end, Names),
            {error, {invalid_backup, Reason}}
    after
        file:delete(Temp)
    end.
