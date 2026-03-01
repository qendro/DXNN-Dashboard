#!/usr/bin/env escript
%% Verification script to check Master Database contents (Mnesia format)

-module(verify_master_db).
-export([main/1]).

-include("include/records.hrl").

main([MasterPath]) ->
    io:format("~n=== Verifying Master Database (Mnesia) ===~n"),
    io:format("Path: ~s~n~n", [MasterPath]),
    
    MnesiaDir = filename:join(MasterPath, "Mnesia.nonode@nohost"),
    
    case filelib:is_dir(MnesiaDir) of
        false ->
            io:format("ERROR: Mnesia directory not found: ~s~n", [MnesiaDir]),
            halt(1);
        true ->
            verify_mnesia_database(MnesiaDir)
    end;

main(_) ->
    io:format("Usage: ./verify_master_db.erl <master_database_path>~n"),
    io:format("Example: ./verify_master_db.erl ./data/MasterDatabase~n").

verify_mnesia_database(MnesiaDir) ->
    %% Stop any running Mnesia
    application:stop(mnesia),
    
    %% Set Mnesia directory
    application:set_env(mnesia, dir, MnesiaDir),
    
    %% Start Mnesia
    case mnesia:start() of
        ok ->
            io:format("Mnesia started successfully~n~n"),
            
            %% Wait for tables
            Tables = [agent, cortex, neuron, sensor, actuator, substrate, population, specie],
            mnesia:wait_for_tables(Tables, 5000),
            
            %% Check each table
            lists:foreach(fun(Table) ->
                Count = mnesia:table_info(Table, size),
                io:format("Table ~p: ~w records~n", [Table, Count]),
                
                %% Show sample records
                case Table of
                    agent ->
                        Agents = mnesia:dirty_match_object({agent, '_', '_', '_', '_', '_', '_', '_', '_', '_', '_', '_', '_', '_', '_', '_', '_', '_', '_'}),
                        lists:foreach(fun(Agent) ->
                            io:format("  Agent ID: ~p~n", [Agent#agent.id]),
                            io:format("    Cortex ID: ~p~n", [Agent#agent.cx_id]),
                            io:format("    Fitness: ~.6f~n", [Agent#agent.fitness]),
                            io:format("    Generation: ~p~n~n", [Agent#agent.generation])
                        end, lists:sublist(Agents, 3));
                    cortex ->
                        Cortices = mnesia:dirty_match_object({cortex, '_', '_', '_', '_', '_'}),
                        lists:foreach(fun(Cortex) ->
                            io:format("  Cortex ID: ~p~n", [Cortex#cortex.id]),
                            io:format("    Neurons: ~w~n", [length(Cortex#cortex.neuron_ids)]),
                            io:format("    Sensors: ~w~n", [length(Cortex#cortex.sensor_ids)]),
                            io:format("    Actuators: ~w~n~n", [length(Cortex#cortex.actuator_ids)])
                        end, lists:sublist(Cortices, 3));
                    _ -> ok
                end
            end, Tables),
            
            application:stop(mnesia),
            io:format("~n=== Verification Complete ===~n");
        {error, Reason} ->
            io:format("ERROR: Failed to start Mnesia: ~p~n", [Reason]),
            halt(1)
    end.

