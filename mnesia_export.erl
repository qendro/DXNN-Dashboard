#!/usr/bin/env escript
%% -*- erlang -*-
%%! -smp enable

%% Script to export Mnesia agent data to JSON format
%% Usage: escript mnesia_export.erl <mnesia_dir> <output_json>

main([MnesiaDir, OutputFile]) ->
    io:format("Exporting agents from: ~s~n", [MnesiaDir]),
    
    %% Set Mnesia directory
    application:set_env(mnesia, dir, MnesiaDir),
    
    %% Start Mnesia
    case mnesia:start() of
        ok -> 
            io:format("Mnesia started successfully~n"),
            export_agents(OutputFile);
        {error, Reason} ->
            io:format("Failed to start Mnesia: ~p~n", [Reason]),
            halt(1)
    end;

main(_) ->
    io:format("Usage: escript mnesia_export.erl <mnesia_dir> <output_json>~n"),
    io:format("Example: escript mnesia_export.erl ./Mnesia.nonode@nohost ./agents.json~n"),
    halt(1).

export_agents(OutputFile) ->
    %% Wait for tables to load
    timer:sleep(1000),
    
    %% Check if agent table exists
    Tables = mnesia:system_info(tables),
    io:format("Available tables: ~p~n", [Tables]),
    
    case lists:member(agent, Tables) of
        true ->
            %% Get all agent keys
            AgentKeys = mnesia:dirty_all_keys(agent),
            io:format("Found ~p agent keys~n", [length(AgentKeys)]),
            
            %% Read each agent
            Agents = lists:filtermap(fun(Key) ->
                case mnesia:dirty_read(agent, Key) of
                    [Agent] ->
                        {true, agent_to_map(Agent)};
                    [] ->
                        false
                end
            end, AgentKeys),
            
            io:format("Successfully read ~p agents~n", [length(Agents)]),
            
            %% Convert to JSON
            Json = encode_json(Agents),
            
            %% Write to file
            case file:write_file(OutputFile, Json) of
                ok ->
                    io:format("Exported ~p agents to ~s~n", [length(Agents), OutputFile]),
                    halt(0);
                {error, Reason} ->
                    io:format("Failed to write file: ~p~n", [Reason]),
                    halt(1)
            end;
        false ->
            io:format("Agent table not found in database~n"),
            io:format("Creating empty export file~n"),
            file:write_file(OutputFile, "[]"),
            halt(0)
    end.

agent_to_map(Agent) ->
    %% Extract agent record fields
    %% Agent record structure: {agent, Id, EncodingType, Generation, PopulationId, SpecieId, CxId, Fingerprint, Constraint, EvoHist, Fitness, InnovationFactor, Pattern, TuningSelectionF, AnnealingParameter, TuningDurationF, PerturbationRange, MutationOperators, TotTopologicalMutationsF, HeredityType, SubstrateId}
    
    [RecordName, Id, EncodingType, Generation, PopulationId, SpecieId, CxId, _Fingerprint, _Constraint, _EvoHist, Fitness, _InnovationFactor, Pattern, _TuningSelectionF, _AnnealingParameter, _TuningDurationF, _PerturbationRange, _MutationOperators, _TotTopologicalMutationsF, _HeredityType, SubstrateId | _Rest] = tuple_to_list(Agent),
    
    %% Get cortex info for neuron/sensor/actuator counts
    {Neurons, Sensors, Actuators} = case mnesia:dirty_read(cortex, CxId) of
        [Cortex] ->
            CortexList = tuple_to_list(Cortex),
            %% Cortex record: {cortex, Id, AgentId, NeuronIds, SensorIds, ActuatorIds}
            case length(CortexList) >= 6 of
                true ->
                    NeuronIds = lists:nth(4, CortexList),
                    SensorIds = lists:nth(5, CortexList),
                    ActuatorIds = lists:nth(6, CortexList),
                    {length(NeuronIds), length(SensorIds), length(ActuatorIds)};
                false ->
                    {0, 0, 0}
            end;
        [] ->
            {0, 0, 0}
    end,
    
    #{
        <<"agent_id">> => format_id(Id),
        <<"encoding">> => atom_to_binary(EncodingType, utf8),
        <<"generation">> => Generation,
        <<"population_id">> => format_id(PopulationId),
        <<"specie_id">> => format_id(SpecieId),
        <<"fitness">> => format_float(Fitness),
        <<"pattern">> => format_pattern(Pattern),
        <<"neurons">> => Neurons,
        <<"sensors">> => Sensors,
        <<"actuators">> => Actuators,
        <<"substrate_id">> => format_id(SubstrateId),
        <<"table">> => <<"agent">>
    }.

format_id({Float, Type}) when is_float(Float), is_atom(Type) ->
    list_to_binary(float_to_list(Float, [{decimals, 20}, compact]));
format_id(undefined) ->
    <<"undefined">>;
format_id(Other) ->
    list_to_binary(io_lib:format("~p", [Other])).

format_float(Float) when is_float(Float) ->
    Float;
format_float(Int) when is_integer(Int) ->
    float(Int);
format_float(_) ->
    0.0.

format_pattern(Pattern) when is_atom(Pattern) ->
    atom_to_binary(Pattern, utf8);
format_pattern(Pattern) when is_list(Pattern) ->
    %% Check if it's a printable string
    case io_lib:printable_unicode_list(Pattern) of
        true -> list_to_binary(Pattern);
        false -> <<"complex_pattern">>
    end;
format_pattern(Pattern) when is_tuple(Pattern) ->
    <<"tuple_pattern">>;
format_pattern(_) ->
    <<"unknown">>.

%% Simple JSON encoder (no external dependencies)
encode_json(Data) ->
    iolist_to_binary(encode_value(Data)).

encode_value(Map) when is_map(Map) ->
    Pairs = maps:fold(fun(K, V, Acc) ->
        Key = encode_string(K),
        Value = encode_value(V),
        [io_lib:format("~s:~s", [Key, Value]) | Acc]
    end, [], Map),
    ["{", string:join(lists:reverse(Pairs), ","), "}"];

encode_value(List) when is_list(List) ->
    case io_lib:printable_unicode_list(List) of
        true ->
            encode_string(List);
        false ->
            Values = [encode_value(V) || V <- List],
            ["[", string:join(Values, ","), "]"]
    end;

encode_value(Binary) when is_binary(Binary) ->
    encode_string(binary_to_list(Binary));

encode_value(Atom) when is_atom(Atom) ->
    encode_string(atom_to_list(Atom));

encode_value(Int) when is_integer(Int) ->
    integer_to_list(Int);

encode_value(Float) when is_float(Float) ->
    float_to_list(Float, [{decimals, 10}, compact]);

encode_value(null) ->
    "null";

encode_value(_) ->
    "null".

encode_string(Str) when is_binary(Str) ->
    encode_string(binary_to_list(Str));
encode_string(Str) when is_list(Str) ->
    Escaped = lists:flatmap(fun
        ($") -> "\\\"";
        ($\\) -> "\\\\";
        ($\n) -> "\\n";
        ($\r) -> "\\r";
        ($\t) -> "\\t";
        (C) when C >= 32, C =< 126 -> [C];
        (C) -> io_lib:format("\\u~4.16.0B", [C])
    end, Str),
    [$", Escaped, $"].
