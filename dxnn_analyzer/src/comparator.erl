-module(comparator).
-export([
    compare_agents/2,
    calculate_similarity/3
]).

-include("../include/records.hrl").
-include("../include/analyzer_records.hrl").

%% @doc Compare multiple agents
compare_agents(AgentIds, Context) ->
    io:format("~n=== Comparing ~w Agents ===~n~n", [length(AgentIds)]),
    
    Agents = lists:filtermap(fun(Id) ->
        case agent_inspector:get_full_topology(Id, Context) of
            {error, _} -> false;
            Topology -> {true, Topology}
        end
    end, AgentIds),
    
    case length(Agents) of
        0 ->
            io:format("No agents found~n"),
            {error, no_agents};
        1 ->
            io:format("Only one agent provided, nothing to compare~n"),
            {error, insufficient_agents};
        _ ->
            compare_fitness(Agents),
            compare_topology_stats(Agents),
            compare_mutations(Agents),
            
            Similarities = calculate_similarity_matrix(Agents),
            display_similarity_matrix(AgentIds, Similarities),
            
            Comparison = #agent_comparison{
                agents = AgentIds,
                common_mutations = find_common_mutations_internal(Agents),
                topology_diffs = calculate_topology_diffs(Agents),
                fitness_ranking = rank_by_fitness(Agents),
                structural_similarity = average_similarity(Similarities)
            },
            
            {ok, Comparison}
    end.

%% @doc Calculate structural similarity between two agents (0.0 to 1.0)
calculate_similarity(AgentId1, AgentId2, Context) ->
    Topo1 = agent_inspector:get_full_topology(AgentId1, Context),
    Topo2 = agent_inspector:get_full_topology(AgentId2, Context),
    
    case {Topo1, Topo2} of
        {{error, _}, _} -> {error, agent1_not_found};
        {_, {error, _}} -> {error, agent2_not_found};
        _ ->
            NeuronSim = neuron_similarity(Topo1, Topo2),
            ConnectionSim = connection_similarity(Topo1, Topo2),
            StructureSim = structure_similarity(Topo1, Topo2),
            
            Similarity = (NeuronSim * 0.4) + (ConnectionSim * 0.3) + 
                        (StructureSim * 0.3),
            
            {ok, Similarity}
    end.

%% Internal functions

compare_fitness(Agents) ->
    io:format("Fitness Comparison:~n"),
    Sorted = lists:sort(fun(T1, T2) ->
        A1 = maps:get(agent, T1),
        A2 = maps:get(agent, T2),
        A1#agent.fitness >= A2#agent.fitness
    end, Agents),
    
    lists:foreach(fun(Topo) ->
        Agent = maps:get(agent, Topo),
        io:format("  ~p: ~.6f (Gen ~w)~n",
                 [Agent#agent.id, Agent#agent.fitness, Agent#agent.generation])
    end, Sorted),
    io:format("~n").

compare_topology_stats(Agents) ->
    io:format("Topology Statistics:~n"),
    io:format("~-40s ~10s ~10s ~10s ~10s~n",
             ["Agent", "Sensors", "Neurons", "Actuators", "Connections"]),
    io:format("~s~n", [lists:duplicate(80, $-)]),
    
    lists:foreach(fun(Topo) ->
        Agent = maps:get(agent, Topo),
        io:format("~-40s ~10w ~10w ~10w ~10w~n",
                 [lists:flatten(io_lib:format("~p", [Agent#agent.id])),
                  length(maps:get(sensors, Topo)),
                  length(maps:get(neurons, Topo)),
                  length(maps:get(actuators, Topo)),
                  count_connections(Topo)])
    end, Agents),
    io:format("~n").

compare_mutations(Agents) ->
    io:format("Mutation Comparison:~n"),
    
    lists:foreach(fun(Topo) ->
        Agent = maps:get(agent, Topo),
        MutationTypes = count_mutation_types(Agent#agent.evo_hist),
        io:format("  ~p: ~w total mutations~n",
                 [Agent#agent.id, length(Agent#agent.evo_hist)]),
        maps:foreach(fun(Type, Count) ->
            io:format("    ~p: ~w~n", [Type, Count])
        end, MutationTypes)
    end, Agents),
    io:format("~n").

calculate_similarity_matrix(Agents) ->
    AgentList = [{(maps:get(agent, T))#agent.id, T} || T <- Agents],
    
    lists:map(fun({Id1, Topo1}) ->
        lists:map(fun({Id2, Topo2}) ->
            if
                Id1 == Id2 ->
                    1.0;
                true ->
                    calculate_similarity_score(Topo1, Topo2)
            end
        end, AgentList)
    end, AgentList).

display_similarity_matrix(AgentIds, Matrix) ->
    io:format("Structural Similarity Matrix:~n"),
    io:format("(1.0 = identical, 0.0 = completely different)~n~n"),
    
    io:format("~20s", [""]),
    lists:foreach(fun(Id) ->
        IdStr = lists:flatten(io_lib:format("~p", [Id])),
        ShortId = lists:sublist(IdStr, 15),
        io:format("~15s ", [ShortId])
    end, AgentIds),
    io:format("~n"),
    
    lists:foreach(fun({Id, Row}) ->
        IdStr = lists:flatten(io_lib:format("~p", [Id])),
        ShortId = lists:sublist(IdStr, 18),
        io:format("~-20s", [ShortId]),
        lists:foreach(fun(Sim) ->
            io:format("~15.3f ", [Sim])
        end, Row),
        io:format("~n")
    end, lists:zip(AgentIds, Matrix)),
    io:format("~n").

calculate_similarity_score(Topo1, Topo2) ->
    NeuronSim = neuron_similarity(Topo1, Topo2),
    ConnectionSim = connection_similarity(Topo1, Topo2),
    StructureSim = structure_similarity(Topo1, Topo2),
    
    (NeuronSim * 0.4) + (ConnectionSim * 0.3) + (StructureSim * 0.3).

neuron_similarity(Topo1, Topo2) ->
    N1 = length(maps:get(neurons, Topo1)),
    N2 = length(maps:get(neurons, Topo2)),
    
    case max(N1, N2) of
        0 -> 1.0;
        Max -> min(N1, N2) / Max
    end.

connection_similarity(Topo1, Topo2) ->
    C1 = count_connections(Topo1),
    C2 = count_connections(Topo2),
    
    case max(C1, C2) of
        0 -> 1.0;
        Max -> min(C1, C2) / Max
    end.

structure_similarity(Topo1, Topo2) ->
    Layers1 = lists:usort(get_layer_structure(Topo1)),
    Layers2 = lists:usort(get_layer_structure(Topo2)),
    
    CommonLayers = length([L || L <- Layers1, lists:member(L, Layers2)]),
    TotalLayers = length(lists:usort(Layers1 ++ Layers2)),
    
    case TotalLayers of
        0 -> 1.0;
        _ -> CommonLayers / TotalLayers
    end.

count_connections(Topology) ->
    Neurons = maps:get(neurons, Topology),
    lists:sum([length(N#neuron.input_idps) || N <- Neurons]).

get_layer_structure(Topology) ->
    Neurons = maps:get(neurons, Topology),
    [element(1, element(1, N#neuron.id)) || N <- Neurons].

find_common_mutations_internal(Agents) ->
    AllMutations = lists:flatten([
        (maps:get(agent, T))#agent.evo_hist || T <- Agents
    ]),
    
    MutationTypes = [element(1, M) || M <- AllMutations],
    
    lists:foldl(fun(Type, Acc) ->
        maps:update_with(Type, fun(C) -> C + 1 end, 1, Acc)
    end, #{}, MutationTypes).

calculate_topology_diffs(Agents) ->
    [First | Rest] = Agents,
    
    lists:map(fun(Topo) ->
        #{
            neuron_diff => length(maps:get(neurons, Topo)) - 
                          length(maps:get(neurons, First)),
            connection_diff => count_connections(Topo) - 
                              count_connections(First)
        }
    end, Rest).

rank_by_fitness(Agents) ->
    Sorted = lists:sort(fun(T1, T2) ->
        A1 = maps:get(agent, T1),
        A2 = maps:get(agent, T2),
        A1#agent.fitness >= A2#agent.fitness
    end, Agents),
    
    [(maps:get(agent, T))#agent.id || T <- Sorted].

average_similarity(Matrix) ->
    AllValues = lists:flatten(Matrix),
    NonDiagonal = [V || V <- AllValues, V /= 1.0],
    
    case length(NonDiagonal) of
        0 -> 1.0;
        N -> lists:sum(NonDiagonal) / N
    end.

count_mutation_types(EvoHist) ->
    lists:foldl(fun(Mutation, Acc) ->
        Type = element(1, Mutation),
        maps:update_with(Type, fun(C) -> C + 1 end, 1, Acc)
    end, #{}, EvoHist).
