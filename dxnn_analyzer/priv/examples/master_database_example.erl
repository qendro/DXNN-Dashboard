#!/usr/bin/env escript
%% Example: Using Master Database with ETS contexts

-include("../../include/records.hrl").

main([Exp1Path, Exp2Path]) ->
    io:format("~n=== Master Database Example ===~n~n"),
    
    %% Start analyzer
    io:format("1. Starting analyzer...~n"),
    analyzer:start(),
    
    %% Load two experiment contexts
    io:format("~n2. Loading experiment contexts...~n"),
    {ok, _} = analyzer:load(Exp1Path, exp1),
    {ok, _} = analyzer:load(Exp2Path, exp2),
    
    %% Create empty master context
    io:format("~n3. Creating empty master context 'master_elite'...~n"),
    {ok, _} = master_database:create_empty(master_elite),
    
    %% Find best agents from each experiment
    io:format("~n4. Finding best agents from each experiment...~n"),
    Best1 = analyzer:find_best(3, [{context, exp1}, {min_fitness, 0.5}]),
    Best2 = analyzer:find_best(3, [{context, exp2}, {min_fitness, 0.5}]),
    
    Ids1 = [A#agent.id || A <- Best1],
    Ids2 = [A#agent.id || A <- Best2],
    
    io:format("  Found ~w agents from exp1~n", [length(Ids1)]),
    io:format("  Found ~w agents from exp2~n", [length(Ids2)]),
    
    %% Add to master context (ETS → ETS, fast!)
    io:format("~n5. Adding agents to master context...~n"),
    {ok, Count1} = master_database:add_to_context(Ids1, exp1, master_elite),
    {ok, Count2} = master_database:add_to_context(Ids2, exp2, master_elite),
    
    io:format("  Added ~w agents from exp1~n", [Count1]),
    io:format("  Added ~w agents from exp2~n", [Count2]),
    
    %% Analyze master context using standard analyzer functions
    io:format("~n6. Analyzing master context...~n"),
    AllMasterAgents = analyzer:list_agents([{context, master_elite}]),
    io:format("  Total agents in master: ~w~n", [length(AllMasterAgents)]),
    
    %% Compare agents in master
    io:format("~n7. Comparing agents in master context...~n"),
    CompareIds = lists:sublist(Ids1 ++ Ids2, 3),
    {ok, _Comparison} = analyzer:compare(CompareIds, master_elite),
    
    %% Save master context to disk
    io:format("~n8. Saving master context to disk...~n"),
    OutputPath = "./data/elite",
    {ok, SavedPath} = master_database:save(master_elite, OutputPath),
    io:format("  Saved to: ~s~n", [SavedPath]),
    
    %% Export subset for deployment
    io:format("~n9. Exporting top 2 agents for deployment...~n"),
    DeployIds = lists:sublist(Ids1 ++ Ids2, 2),
    {ok, DeployPath} = master_database:export_for_deployment(
        DeployIds, 
        prod_population, 
        "./deployment"
    ),
    io:format("  Deployment database created: ~s~n", [DeployPath]),
    
    io:format("~n=== Example Complete ===~n"),
    io:format("~nKey Benefits Demonstrated:~n"),
    io:format("  ✓ Multiple master contexts supported~n"),
    io:format("  ✓ Fast ETS operations (no disk I/O during add)~n"),
    io:format("  ✓ Consistent API with other contexts~n"),
    io:format("  ✓ Flexible persistence (save when ready)~n"),
    io:format("  ✓ Can merge agents from multiple experiments~n"),
    io:format("  ✓ Can export subsets for deployment~n~n");

main(_) ->
    io:format("Usage: ./master_database_example.erl <exp1_mnesia_path> <exp2_mnesia_path>~n"),
    io:format("Example: ./master_database_example.erl ./exp1/Mnesia.nonode@nohost ./exp2/Mnesia.nonode@nohost~n").
