-module(context_inspector).
-export([
    get_populations/1,
    get_species/1,
    get_population/2,
    get_specie/2
]).

-include("../include/records.hrl").
-include("../include/analyzer_records.hrl").

%% @doc Get all populations in a context
get_populations(Context) ->
    TableName = dxnn_mnesia_loader:table_name(Context, population),
    case ets:info(TableName) of
        undefined ->
            {error, context_not_loaded};
        _ ->
            Populations = ets:tab2list(TableName),
            FormattedPops = [format_population(P) || P <- Populations],
            {ok, FormattedPops}
    end.

%% @doc Get all species in a context
get_species(Context) ->
    TableName = dxnn_mnesia_loader:table_name(Context, specie),
    case ets:info(TableName) of
        undefined ->
            {error, context_not_loaded};
        _ ->
            Species = ets:tab2list(TableName),
            FormattedSpecies = [format_specie(S) || S <- Species],
            {ok, FormattedSpecies}
    end.

%% @doc Get a specific population by ID
get_population(PopulationId, Context) ->
    TableName = dxnn_mnesia_loader:table_name(Context, population),
    case ets:lookup(TableName, PopulationId) of
        [] -> {error, not_found};
        [Population] -> {ok, format_population(Population)}
    end.

%% @doc Get a specific specie by ID
get_specie(SpecieId, Context) ->
    TableName = dxnn_mnesia_loader:table_name(Context, specie),
    case ets:lookup(TableName, SpecieId) of
        [] -> {error, not_found};
        [Specie] -> {ok, format_specie(Specie)}
    end.

%% Internal formatting functions

format_population(Pop) when is_record(Pop, population) ->
    #{
        id => Pop#population.id,
        polis_id => Pop#population.polis_id,
        specie_ids => Pop#population.specie_ids,
        morphologies => Pop#population.morphologies,
        innovation_factor => Pop#population.innovation_factor,
        evo_alg_f => Pop#population.evo_alg_f,
        fitness_postprocessor_f => Pop#population.fitness_postprocessor_f,
        selection_f => Pop#population.selection_f,
        trace => format_trace(Pop#population.trace)
    }.

format_specie(Specie) when is_record(Specie, specie) ->
    #{
        id => Specie#specie.id,
        population_id => Specie#specie.population_id,
        fingerprint => Specie#specie.fingerprint,
        constraint => format_constraint(Specie#specie.constraint),
        agent_ids => Specie#specie.agent_ids,
        dead_pool => Specie#specie.dead_pool,
        champion_ids => Specie#specie.champion_ids,
        fitness => Specie#specie.fitness,
        innovation_factor => Specie#specie.innovation_factor,
        stats => Specie#specie.stats,
        agent_count => length(Specie#specie.agent_ids),
        dead_pool_count => length(Specie#specie.dead_pool),
        champion_count => length(Specie#specie.champion_ids)
    }.

format_trace(Trace) when is_record(Trace, trace) ->
    #{
        stats => Trace#trace.stats,
        tot_evaluations => Trace#trace.tot_evaluations,
        step_size => Trace#trace.step_size
    };
format_trace(_) ->
    #{}.

format_constraint(undefined) ->
    undefined;
format_constraint(C) when is_record(C, constraint) ->
    #{
        morphology => C#constraint.morphology,
        connection_architecture => C#constraint.connection_architecture,
        neural_afs => C#constraint.neural_afs,
        neural_pfns => C#constraint.neural_pfns,
        substrate_plasticities => C#constraint.substrate_plasticities,
        substrate_linkforms => C#constraint.substrate_linkforms,
        neural_aggr_fs => C#constraint.neural_aggr_fs,
        tuning_selection_fs => C#constraint.tuning_selection_fs,
        tuning_duration_f => C#constraint.tuning_duration_f,
        annealing_parameters => C#constraint.annealing_parameters,
        perturbation_ranges => C#constraint.perturbation_ranges,
        agent_encoding_types => C#constraint.agent_encoding_types,
        heredity_types => C#constraint.heredity_types,
        mutation_operators => C#constraint.mutation_operators,
        tot_topological_mutations_fs => C#constraint.tot_topological_mutations_fs,
        population_evo_alg_f => C#constraint.population_evo_alg_f,
        population_fitness_postprocessor_f => C#constraint.population_fitness_postprocessor_f,
        population_selection_f => C#constraint.population_selection_f
    };
format_constraint(_) ->
    undefined.
