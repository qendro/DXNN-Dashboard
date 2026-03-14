-module(generation_analytics).
-export([generate_report/2, generate_report/3]).

-include("../include/records.hrl").
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
                % Parse agent_trades.log to get trading metrics
                TradesMap = parse_agent_trades_log(Context),
                
                GenerationData = group_by_generation(Agents),
                Stats = calculate_generation_stats(GenerationData, TradesMap),

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

calculate_generation_stats(GenerationData, TradesMap) ->
    lists:map(fun({Generation, Agents}) ->
        Fitnesses = [A#agent.fitness || A <- Agents],

        % Get all metrics for this generation from the log
        GenMetrics = maps:get(Generation, TradesMap, []),
        
        % Extract P/L and trade data
        RealizedPLs = [M#metrics.realized_pl || M <- GenMetrics],
        UnrealizedPLs = [M#metrics.unrealized_pl || M <- GenMetrics],
        Trades = [M#metrics.trades || M <- GenMetrics],

        #{
            generation => Generation,
            agent_count => length(Agents),
            fitness_avg => safe_avg(Fitnesses),
            fitness_high => safe_max(Fitnesses),
            fitness_low => safe_min(Fitnesses),
            realized_pl_avg => safe_avg(RealizedPLs),
            realized_pl_high => safe_max(RealizedPLs),
            realized_pl_low => safe_min(RealizedPLs),
            unrealized_pl_avg => safe_avg(UnrealizedPLs),
            unrealized_pl_high => safe_max(UnrealizedPLs),
            unrealized_pl_low => safe_min(UnrealizedPLs),
            trades_avg => safe_avg([float(T) || T <- Trades]),
            trades_high => safe_max(Trades),
            trades_low => safe_min(Trades)
        }
    end, GenerationData).

extract_metrics_from_trades(Agent, TradesMap) ->
    % This function is no longer used - keeping for compatibility
    #metrics{realized_pl = 0.0, unrealized_pl = 0.0, trades = 0}.

parse_agent_trades_log(Context) ->
    % Find the logs/Benchmarker/agent_trades.log file
    MnesiaPath = Context#mnesia_context.path,
    BundleRoot = case filename:basename(MnesiaPath) of
        "Mnesia.nonode@nohost" -> filename:dirname(MnesiaPath);
        _ -> MnesiaPath
    end,
    
    LogPath = filename:join([BundleRoot, "logs", "Benchmarker", "agent_trades.log"]),
    
    io:format("DEBUG: Looking for log at: ~s~n", [LogPath]),
    
    case filelib:is_file(LogPath) of
        true ->
            case file:read_file(LogPath) of
                {ok, Binary} ->
                    Lines = binary:split(Binary, <<"\n">>, [global]),
                    io:format("DEBUG: Read ~p lines from log~n", [length(Lines)]),
                    % Simply parse all FITNESS_EVAL lines and group by generation number from the line itself
                    % This is more robust than trying to track run boundaries
                    Result = parse_all_fitness_lines(Lines, maps:new(), 0),
                    io:format("DEBUG: Parsed metrics for generations: ~p~n", [maps:keys(Result)]),
                    lists:foreach(fun(Gen) ->
                        Metrics = maps:get(Gen, Result),
                        io:format("DEBUG: Generation ~p has ~p metrics~n", [Gen, length(Metrics)])
                    end, maps:keys(Result)),
                    Result;
                {error, Reason} ->
                    io:format("DEBUG: Failed to read log: ~p~n", [Reason]),
                    maps:new()
            end;
        false ->
            io:format("DEBUG: Log file not found~n"),
            maps:new()
    end.

parse_all_fitness_lines(Lines, Acc) ->
    parse_all_fitness_lines(Lines, Acc, 0).

parse_all_fitness_lines([], Acc, _) ->
    Acc;
parse_all_fitness_lines([Line | Rest], Acc, CurrentGen) ->
    % Check for generation_start to track current generation
    NewGen = case parse_generation_start(Line) of
        {ok, Gen} -> 
            if Gen =< 5 -> io:format("DEBUG: Found generation_start for gen ~p~n", [Gen]);
               true -> ok
            end,
            Gen;
        error -> CurrentGen
    end,
    
    % Try to parse FITNESS_EVAL line
    NewAcc = case parse_fitness_eval_line(Line, NewGen) of
        {ok, Metrics} ->
            % Add metrics to the list for this generation
            GenMetrics = maps:get(NewGen, Acc, []),
            if NewGen =< 5 andalso length(GenMetrics) < 3 -> 
                io:format("DEBUG: Adding metrics to gen ~p: ~p~n", [NewGen, Metrics]);
               true -> ok
            end,
            maps:put(NewGen, GenMetrics ++ [Metrics], Acc);
        error ->
            Acc
    end,
    parse_all_fitness_lines(Rest, NewAcc, NewGen).

parse_generation_start(Line) ->
    try
        BinLine = case is_binary(Line) of
            true -> Line;
            false -> list_to_binary(Line)
        end,
        
        case re:run(BinLine, <<"generation_start.*generation:\\s*([0-9]+)">>, [{capture, all_but_first, binary}]) of
            {match, [GenBin]} ->
                {ok, binary_to_integer(GenBin)};
            _ ->
                error
        end
    catch
        _:_ -> error
    end.

parse_fitness_eval_line(Line, Generation) ->
    % Parse lines like: [2026-03-10 17:21:17] | [AGENT:<0.483.0>] FITNESS_EVAL | fitness=51.30547769909516 | ... | realized_pl=0 | unrealized_pl=18.328889999999767 | realized_trades=0 | ...
    try
        BinLine = case is_binary(Line) of
            true -> Line;
            false -> list_to_binary(Line)
        end,
        
        case binary:match(BinLine, <<"FITNESS_EVAL">>) of
            nomatch ->
                error;
            _ ->
                % Extract realized_pl
                RealizedPL = case re:run(BinLine, <<"realized_pl=([0-9.-]+)">>, [{capture, all_but_first, binary}]) of
                    {match, [RPL]} -> binary_to_float_safe(RPL);
                    _ -> 0.0
                end,
                
                % Extract unrealized_pl
                UnrealizedPL = case re:run(BinLine, <<"unrealized_pl=([0-9.-]+)">>, [{capture, all_but_first, binary}]) of
                    {match, [UPL]} -> binary_to_float_safe(UPL);
                    _ -> 0.0
                end,
                
                % Extract realized_trades
                Trades = case re:run(BinLine, <<"realized_trades=([0-9]+)">>, [{capture, all_but_first, binary}]) of
                    {match, [T]} -> binary_to_integer(T);
                    _ -> 0
                end,
                
                Metrics = #metrics{
                    realized_pl = RealizedPL,
                    unrealized_pl = UnrealizedPL,
                    trades = Trades
                },
                {ok, Metrics}
        end
    catch
        _:_ -> error
    end.

binary_to_float_safe(Bin) ->
    try
        Str = binary_to_list(Bin),
        case string:to_float(Str) of
            {error, no_float} ->
                % Try as integer first
                case string:to_integer(Str) of
                    {Int, _} -> float(Int);
                    _ -> 0.0
                end;
            {Float, _} ->
                Float
        end
    catch
        _:_ -> 0.0
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
