#!/usr/bin/env escript
%% -*- erlang -*-
%%! -smp enable

%% Script to export complete agent details including all related records
%% Usage: escript mnesia_export_agent.erl <mnesia_dir> <agent_id> <output_json>

main([MnesiaDir, AgentIdStr, OutputFile]) ->
    io:format("Exporting agent details from: ~s~n", [MnesiaDir]),
    io:format("Agent ID: ~s~n", [AgentIdStr]),
    
    %% Set Mnesia directory
    application:set_env(mnesia, dir, MnesiaDir),
    
    %% Start Mnesia
    case mnesia:start() of
        ok -> 
            io:format("Mnesia started successfully~n"),
            timer:sleep(1000),
            export_agent_details(AgentIdStr, OutputFile);
        {error, Reason} ->
            io:format("Failed to start Mnesia: ~p~n", [Reason]),
            halt(1)
    end;

main(_) ->
    io:format("Usage: escript mnesia_export_agent.erl <mnesia_dir> <agent_id> <output_json>~n"),
    halt(1).

export_agent_details(AgentIdStr, OutputFile) ->
    %% Parse agent ID - handle both scientific notation and decimal format
    AgentIdFloat = case string:to_float(AgentIdStr) of
        {F, _} when is_float(F) -> F;
        {error, no_float} ->
            %% Try as integer first, then convert
            case string:to_integer(AgentIdStr) of
                {I, _} -> float(I);
                _ -> 
                    io:format("Could not parse agent ID: ~s~n", [AgentIdStr]),
                    halt(1)
            end
    end,
    
    AgentId = {AgentIdFloat, agent},
    
    io:format("Looking for agent: ~p~n", [AgentId]),
    io:format("Agent ID float: ~p~n", [AgentIdFloat]),
    
    %% Also try to find by scanning all agents
    AllAgentKeys = mnesia:dirty_all_keys(agent),
    io:format("Total agents in database: ~p~n", [length(AllAgentKeys)]),
    
    %% Try exact match first
    case mnesia:dirty_read(agent, AgentId) of
        [Agent] ->
            io:format("Found agent by exact match~n"),
            export_agent_record(Agent, OutputFile);
        [] ->
            %% Try to find by comparing float values with tolerance
            io:format("Exact match failed, searching all agents...~n"),
            MatchingAgent = lists:foldl(fun(Key, Acc) ->
                case Acc of
                    {found, _} -> Acc;  % Already found, keep it
                    not_found ->
                        {KeyFloat, agent} = Key,
                        %% Compare with small tolerance for floating point
                        Diff = abs(KeyFloat - AgentIdFloat),
                        if 
                            Diff < 1.0e-20 ->
                                io:format("Found matching agent: ~p (diff: ~p)~n", [Key, Diff]),
                                case mnesia:dirty_read(agent, Key) of
                                    [A] -> {found, A};
                                    [] -> not_found
                                end;
                            true -> not_found
                        end
                end
            end, not_found, AllAgentKeys),
            
            case MatchingAgent of
                {found, Agent} ->
                    export_agent_record(Agent, OutputFile);
                _ ->
                    io:format("Agent not found~n"),
                    io:format("Searched for float: ~.20e~n", [AgentIdFloat]),
                    io:format("First 5 agent keys: ~p~n", [lists:sublist(AllAgentKeys, 5)]),
                    file:write_file(OutputFile, "{}"),
                    halt(0)
            end
    end.

export_agent_record(Agent, OutputFile) ->
    io:format("Exporting agent record~n"),
    
    %% Extract agent fields - be flexible with record structure
    AgentList = tuple_to_list(Agent),
    io:format("Agent record has ~p fields~n", [length(AgentList)]),
    
    %% Extract known fields (at least 21 fields expected)
    [RecordName | RestFields] = AgentList,
    io:format("Record name: ~p~n", [RecordName]),
    
    if
        length(RestFields) >= 20 ->
            [Id, EncodingType, Generation, PopulationId, SpecieId, CxId, Fingerprint, 
             Constraint, EvoHist, Fitness, InnovationFactor, Pattern, TuningSelectionF, 
             AnnealingParameter, TuningDurationF, PerturbationRange, MutationOperators, 
             TotTopologicalMutationsF, HeredityType, SubstrateId | _MoreRest] = RestFields,
            
            io:format("Extracted basic fields~n"),
            io:format("Extracted basic fields~n"),
            
            %% Get cortex details
            CortexDetails = get_cortex_details(CxId),
            
            %% Get all neurons
            NeuronIds = maps:get(<<"neuron_ids">>, CortexDetails, []),
            Neurons = lists:map(fun(NId) -> get_neuron_details(NId) end, NeuronIds),
            
            %% Get all sensors
            SensorIds = maps:get(<<"sensor_ids">>, CortexDetails, []),
            Sensors = lists:map(fun(SId) -> get_sensor_details(SId) end, SensorIds),
            
            %% Get all actuators
            ActuatorIds = maps:get(<<"actuator_ids">>, CortexDetails, []),
            Actuators = lists:map(fun(AId) -> get_actuator_details(AId) end, ActuatorIds),
            
            %% Get substrate if exists
            SubstrateDetails = case SubstrateId of
                undefined -> null;
                _ -> get_substrate_details(SubstrateId)
            end,
            
            %% Build complete agent details
            AgentDetails = #{
                <<"agent_id">> => format_id(Id),
                <<"encoding">> => atom_to_binary(EncodingType, utf8),
                <<"generation">> => Generation,
                <<"population_id">> => format_id(PopulationId),
                <<"specie_id">> => format_id(SpecieId),
                <<"fitness">> => format_float(Fitness),
                <<"pattern">> => format_pattern(Pattern),
                <<"fingerprint">> => format_term(Fingerprint),
                <<"constraint">> => format_constraint(Constraint),
                <<"evo_hist">> => format_term(EvoHist),
                <<"innovation_factor">> => format_float(InnovationFactor),
                <<"tuning_selection_f">> => format_term(TuningSelectionF),
                <<"annealing_parameter">> => format_float(AnnealingParameter),
                <<"tuning_duration_f">> => format_term(TuningDurationF),
                <<"perturbation_range">> => format_float(PerturbationRange),
                <<"mutation_operators">> => format_term(MutationOperators),
                <<"tot_topological_mutations_f">> => format_term(TotTopologicalMutationsF),
                <<"heredity_type">> => format_term(HeredityType),
                <<"substrate_id">> => format_id(SubstrateId),
                <<"cortex">> => CortexDetails,
                <<"neurons">> => Neurons,
                <<"sensors">> => Sensors,
                <<"actuators">> => Actuators,
                <<"substrate">> => SubstrateDetails
            },
            
            %% Convert to JSON
            Json = encode_json(AgentDetails),
            
            %% Write to file
            case file:write_file(OutputFile, Json) of
                ok ->
                    io:format("Exported agent details to ~s~n", [OutputFile]),
                    halt(0);
                {error, Reason} ->
                    io:format("Failed to write file: ~p~n", [Reason]),
                    halt(1)
            end;
        true ->
            io:format("Agent record has insufficient fields: ~p~n", [length(RestFields)]),
            file:write_file(OutputFile, "{}"),
            halt(1)
    end.

get_cortex_details(CxId) ->
    case mnesia:dirty_read(cortex, CxId) of
        [Cortex] ->
            CortexList = tuple_to_list(Cortex),
            [_RecordName, Id, AgentId, NeuronIds, SensorIds, ActuatorIds | _] = CortexList,
            #{
                <<"id">> => format_id(Id),
                <<"agent_id">> => format_id(AgentId),
                <<"neuron_ids">> => [format_id(N) || N <- NeuronIds],
                <<"sensor_ids">> => [format_id(S) || S <- SensorIds],
                <<"actuator_ids">> => [format_id(A) || A <- ActuatorIds]
            };
        [] ->
            #{}
    end.

get_neuron_details(NeuronId) ->
    case mnesia:dirty_read(neuron, NeuronId) of
        [Neuron] ->
            NeuronList = tuple_to_list(Neuron),
            [_RecordName, Id, Generation, CxId, AF, PF, AggrF, InputIdPs, InputIdPsModulation, 
             OutputIds, RoIds | _] = NeuronList,
            #{
                <<"id">> => format_id(Id),
                <<"generation">> => Generation,
                <<"cx_id">> => format_id(CxId),
                <<"activation_function">> => atom_to_binary(AF, utf8),
                <<"plasticity_function">> => format_term(PF),
                <<"aggregation_function">> => atom_to_binary(AggrF, utf8),
                <<"input_ids">> => format_term(InputIdPs),
                <<"input_ids_modulation">> => format_term(InputIdPsModulation),
                <<"output_ids">> => [format_id(O) || O <- OutputIds],
                <<"ro_ids">> => format_term(RoIds)
            };
        [] ->
            #{<<"id">> => format_id(NeuronId), <<"error">> => <<"not_found">>}
    end.

get_sensor_details(SensorId) ->
    case mnesia:dirty_read(sensor, SensorId) of
        [Sensor] ->
            SensorList = tuple_to_list(Sensor),
            [_RecordName, Id, Name, Type, CxId, Scape, VL, FanoutIds, Generation, Format, 
             Parameters, GtParameters, PhysRep, VisRep, PreF, PostF | _] = SensorList,
            #{
                <<"id">> => format_id(Id),
                <<"name">> => atom_to_binary(Name, utf8),
                <<"type">> => atom_to_binary(Type, utf8),
                <<"cx_id">> => format_id(CxId),
                <<"scape">> => format_term(Scape),
                <<"vl">> => VL,
                <<"fanout_ids">> => [format_id(F) || F <- FanoutIds],
                <<"generation">> => Generation,
                <<"format">> => atom_to_binary(Format, utf8),
                <<"parameters">> => format_term(Parameters),
                <<"gt_parameters">> => format_term(GtParameters),
                <<"phys_rep">> => format_term(PhysRep),
                <<"vis_rep">> => format_term(VisRep),
                <<"pre_f">> => format_term(PreF),
                <<"post_f">> => format_term(PostF)
            };
        [] ->
            #{<<"id">> => format_id(SensorId), <<"error">> => <<"not_found">>}
    end.

get_actuator_details(ActuatorId) ->
    case mnesia:dirty_read(actuator, ActuatorId) of
        [Actuator] ->
            ActuatorList = tuple_to_list(Actuator),
            [_RecordName, Id, Name, Type, CxId, Scape, VL, FaninIds, Generation, Format, 
             Parameters, GtParameters, PhysRep, VisRep, PreF, PostF | _] = ActuatorList,
            #{
                <<"id">> => format_id(Id),
                <<"name">> => atom_to_binary(Name, utf8),
                <<"type">> => atom_to_binary(Type, utf8),
                <<"cx_id">> => format_id(CxId),
                <<"scape">> => format_term(Scape),
                <<"vl">> => VL,
                <<"fanin_ids">> => [format_id(F) || F <- FaninIds],
                <<"generation">> => Generation,
                <<"format">> => atom_to_binary(Format, utf8),
                <<"parameters">> => format_term(Parameters),
                <<"gt_parameters">> => format_term(GtParameters),
                <<"phys_rep">> => format_term(PhysRep),
                <<"vis_rep">> => format_term(VisRep),
                <<"pre_f">> => format_term(PreF),
                <<"post_f">> => format_term(PostF)
            };
        [] ->
            #{<<"id">> => format_id(ActuatorId), <<"error">> => <<"not_found">>}
    end.

get_substrate_details(SubstrateId) ->
    case mnesia:dirty_read(substrate, SubstrateId) of
        [Substrate] ->
            SubstrateList = tuple_to_list(Substrate),
            [_RecordName, Id, AgentId, Densities, LinkForm, Plasticity, CppIds, CepIds | _] = SubstrateList,
            #{
                <<"id">> => format_id(Id),
                <<"agent_id">> => format_id(AgentId),
                <<"densities">> => format_term(Densities),
                <<"link_form">> => format_term(LinkForm),
                <<"plasticity">> => format_term(Plasticity),
                <<"cpp_ids">> => format_term(CppIds),
                <<"cep_ids">> => format_term(CepIds)
            };
        [] ->
            null
    end.

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
    case io_lib:printable_unicode_list(Pattern) of
        true -> list_to_binary(Pattern);
        false -> <<"complex_pattern">>
    end;
format_pattern(Pattern) when is_tuple(Pattern) ->
    <<"tuple_pattern">>;
format_pattern(_) ->
    <<"unknown">>.

format_constraint(Constraint) when is_tuple(Constraint) ->
    <<"constraint_record">>;
format_constraint(Constraint) ->
    format_term(Constraint).

format_term(Term) when is_atom(Term) ->
    atom_to_binary(Term, utf8);
format_term(Term) when is_list(Term) ->
    case io_lib:printable_unicode_list(Term) of
        true -> list_to_binary(Term);
        false -> list_to_binary(io_lib:format("~p", [Term]))
    end;
format_term(Term) ->
    list_to_binary(io_lib:format("~p", [Term])).

%% Simple JSON encoder
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
