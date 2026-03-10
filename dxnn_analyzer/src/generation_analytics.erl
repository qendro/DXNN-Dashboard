-module(generation_analytics).
-export([generate_report/2, generate_report/3]).

-include("records.hrl").
-include("../include/analyzer_records.hrl").

-record(metrics, {
    realized_pl = 0.0,
    unrealized_pl = 0.0,
    trades = 0
}).

generate_report(ContextName, OutputFormat) ->
    generate_report(ContextName, OutputFormat, []).

generate_report(ContextName, OutputFormat, Opts) when is_atom(ContextName), is_list(Opts) ->
    try
        case collect_context_agents(ContextName) of
            {ok, _Context, []} ->
                {error, no_agents};
            {ok, Context, Agents} ->
                GenerationData = group_by_generation(Agents),
                Stats = calculate_generation_stats(GenerationData),

                case determine_output_path(Context, Opts) of
                    {ok, OutputPath} ->
                        write_report(Stats, OutputPath, OutputFormat);
                    {error, Reason} ->
                        {error, Reason}
                end;
            {error, Reason} ->
                {error, Reason}
        end
    catch
        _:Error ->
            {error, Error}
    end;
generate_report(_ContextName, _OutputFormat, _Opts) ->
    {error, invalid_context}.

collect_context_agents(ContextName) ->
    case dxnn_mnesia_loader:get_context(ContextName) of
        {ok, Context} ->
            AgentTable = dxnn_mnesia_loader:table_name(Context#mnesia_context.name, agent),
            case ets:info(AgentTable) of
                undefined ->
                    {error, {agent_table_not_found, AgentTable}};
                _ ->
                    {ok, Context, ets:tab2list(AgentTable)}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

group_by_generation(Agents) ->
    Dict = lists:foldl(fun(Agent, Acc) ->
        Gen = Agent#agent.generation,
        dict:append(Gen, Agent, Acc)
    end, dict:new(), Agents),

    Generations = dict:to_list(Dict),
    lists:keysort(1, Generations).

calculate_generation_stats(GenerationData) ->
    lists:map(fun({Generation, Agents}) ->
        Fitnesses = [A#agent.fitness || A <- Agents],

        Metrics = lists:map(fun(Agent) ->
            extract_metrics(Agent)
        end, Agents),

        #{
            generation => Generation,
            agent_count => length(Agents),
            fitness_avg => safe_avg(Fitnesses),
            fitness_high => safe_max(Fitnesses),
            fitness_low => safe_min(Fitnesses),
            realized_pl_avg => safe_avg([M#metrics.realized_pl || M <- Metrics]),
            realized_pl_high => safe_max([M#metrics.realized_pl || M <- Metrics]),
            realized_pl_low => safe_min([M#metrics.realized_pl || M <- Metrics]),
            unrealized_pl_avg => safe_avg([M#metrics.unrealized_pl || M <- Metrics]),
            unrealized_pl_high => safe_max([M#metrics.unrealized_pl || M <- Metrics]),
            unrealized_pl_low => safe_min([M#metrics.unrealized_pl || M <- Metrics]),
            trades_avg => safe_avg([M#metrics.trades || M <- Metrics]),
            trades_high => safe_max([M#metrics.trades || M <- Metrics]),
            trades_low => safe_min([M#metrics.trades || M <- Metrics])
        }
    end, GenerationData).

extract_metrics(Agent) ->
    #metrics{
        realized_pl = get_agent_metric(Agent, realized_pl, 0.0),
        unrealized_pl = get_agent_metric(Agent, unrealized_pl, 0.0),
        trades = get_agent_metric(Agent, trades, 0)
    }.

get_agent_metric(Agent, MetricName, Default) ->
    case Agent#agent.constraint of
        undefined -> Default;
        Constraint when is_list(Constraint) ->
            proplists:get_value(MetricName, Constraint, Default);
        _ -> Default
    end.

safe_avg([]) -> 0.0;
safe_avg(List) ->
    lists:sum(List) / length(List).

safe_max([]) -> 0.0;
safe_max(List) -> lists:max(List).

safe_min([]) -> 0.0;
safe_min(List) -> lists:min(List).

determine_output_path(Context, Opts) ->
    CustomPath = proplists:get_value(output_path, Opts),

    OutputPath =
        case CustomPath of
            undefined ->
                default_analytics_path(Context#mnesia_context.path);
            Path ->
                normalize_path(Path)
        end,

    case filelib:ensure_dir(filename:join(OutputPath, "dummy")) of
        ok ->
            {ok, OutputPath};
        {error, Reason} ->
            {error, Reason}
    end.

default_analytics_path(MnesiaPath) ->
    NormalizedPath = normalize_path(MnesiaPath),
    BundleRoot =
        case filename:basename(NormalizedPath) of
            "Mnesia.nonode@nohost" ->
                filename:dirname(NormalizedPath);
            _ ->
                NormalizedPath
        end,
    filename:join(BundleRoot, "analytics").

normalize_path(Path) when is_list(Path) ->
    Path;
normalize_path(Path) when is_binary(Path) ->
    binary_to_list(Path).

write_report(Stats, OutputPath, csv) ->
    Timestamp = format_timestamp(erlang:timestamp()),
    Filename = filename:join(OutputPath, "generation_analysis_" ++ Timestamp ++ ".csv"),

    case file:open(Filename, [write]) of
        {ok, File} ->
            io:format(File, "Generation,Agent_Count,Fitness_Avg,Fitness_High,Fitness_Low,"
                            "Realized_PL_Avg,Realized_PL_High,Realized_PL_Low,"
                            "Unrealized_PL_Avg,Unrealized_PL_High,Unrealized_PL_Low,"
                            "Trades_Avg,Trades_High,Trades_Low~n", []),

            lists:foreach(fun(Stat) ->
                io:format(File, "~w,~w,~.2f,~.2f,~.2f,~.2f,~.2f,~.2f,~.2f,~.2f,~.2f,~.2f,~w,~w~n", [
                    maps:get(generation, Stat),
                    maps:get(agent_count, Stat),
                    maps:get(fitness_avg, Stat),
                    maps:get(fitness_high, Stat),
                    maps:get(fitness_low, Stat),
                    maps:get(realized_pl_avg, Stat),
                    maps:get(realized_pl_high, Stat),
                    maps:get(realized_pl_low, Stat),
                    maps:get(unrealized_pl_avg, Stat),
                    maps:get(unrealized_pl_high, Stat),
                    maps:get(unrealized_pl_low, Stat),
                    maps:get(trades_avg, Stat),
                    maps:get(trades_high, Stat),
                    maps:get(trades_low, Stat)
                ])
            end, Stats),

            file:close(File),
            {ok, Filename};
        {error, Reason} ->
            {error, Reason}
    end;

write_report(Stats, OutputPath, md) ->
    Timestamp = format_timestamp(erlang:timestamp()),
    Filename = filename:join(OutputPath, "generation_analysis_" ++ Timestamp ++ ".md"),

    case file:open(Filename, [write]) of
        {ok, File} ->
            io:format(File, "# Generation Analysis Report~n~n", []),
            io:format(File, "Generated: ~s~n~n", [Timestamp]),
            io:format(File, "Total Generations: ~w~n~n", [length(Stats)]),

            io:format(File, "| Gen | Agents | Fitness (Avg/High/Low) | Realized P/L (Avg/High/Low) | Unrealized P/L (Avg/High/Low) | Trades (Avg/High/Low) |~n", []),
            io:format(File, "|-----|--------|------------------------|------------------------------|--------------------------------|-----------------------|~n", []),

            lists:foreach(fun(Stat) ->
                io:format(File, "| ~w | ~w | ~.2f / ~.2f / ~.2f | ~.2f / ~.2f / ~.2f | ~.2f / ~.2f / ~.2f | ~.2f / ~w / ~w |~n", [
                    maps:get(generation, Stat),
                    maps:get(agent_count, Stat),
                    maps:get(fitness_avg, Stat),
                    maps:get(fitness_high, Stat),
                    maps:get(fitness_low, Stat),
                    maps:get(realized_pl_avg, Stat),
                    maps:get(realized_pl_high, Stat),
                    maps:get(realized_pl_low, Stat),
                    maps:get(unrealized_pl_avg, Stat),
                    maps:get(unrealized_pl_high, Stat),
                    maps:get(unrealized_pl_low, Stat),
                    maps:get(trades_avg, Stat),
                    maps:get(trades_high, Stat),
                    maps:get(trades_low, Stat)
                ])
            end, Stats),

            file:close(File),
            {ok, Filename};
        {error, Reason} ->
            {error, Reason}
    end;

write_report(Stats, OutputPath, log) ->
    Timestamp = format_timestamp(erlang:timestamp()),
    Filename = filename:join(OutputPath, "generation_analysis_" ++ Timestamp ++ ".log"),

    case file:open(Filename, [write]) of
        {ok, File} ->
            io:format(File, "=== Generation Analysis Report ===~n", []),
            io:format(File, "Generated: ~s~n", [Timestamp]),
            io:format(File, "Total Generations: ~w~n~n", [length(Stats)]),

            lists:foreach(fun(Stat) ->
                io:format(File, "--- Generation ~w ---~n", [maps:get(generation, Stat)]),
                io:format(File, "  Agents: ~w~n", [maps:get(agent_count, Stat)]),
                io:format(File, "  Fitness: Avg=~.2f, High=~.2f, Low=~.2f~n", [
                    maps:get(fitness_avg, Stat),
                    maps:get(fitness_high, Stat),
                    maps:get(fitness_low, Stat)
                ]),
                io:format(File, "  Realized P/L: Avg=~.2f, High=~.2f, Low=~.2f~n", [
                    maps:get(realized_pl_avg, Stat),
                    maps:get(realized_pl_high, Stat),
                    maps:get(realized_pl_low, Stat)
                ]),
                io:format(File, "  Unrealized P/L: Avg=~.2f, High=~.2f, Low=~.2f~n", [
                    maps:get(unrealized_pl_avg, Stat),
                    maps:get(unrealized_pl_high, Stat),
                    maps:get(unrealized_pl_low, Stat)
                ]),
                io:format(File, "  Trades: Avg=~.2f, High=~w, Low=~w~n~n", [
                    maps:get(trades_avg, Stat),
                    maps:get(trades_high, Stat),
                    maps:get(trades_low, Stat)
                ])
            end, Stats),

            file:close(File),
            {ok, Filename};
        {error, Reason} ->
            {error, Reason}
    end;

write_report(_Stats, _OutputPath, UnsupportedFormat) ->
    {error, {unsupported_format, UnsupportedFormat}}.

format_timestamp({MegaSecs, Secs, _MicroSecs}) ->
    DateTime = calendar:now_to_datetime({MegaSecs, Secs, 0}),
    {{Year, Month, Day}, {Hour, Min, Sec}} = DateTime,
    lists:flatten(io_lib:format("~4..0w~2..0w~2..0w_~2..0w~2..0w~2..0w",
                                [Year, Month, Day, Hour, Min, Sec])).
