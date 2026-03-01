defmodule DxnnAnalyzerWeb.AnalyzerBridge do
  @moduledoc """
  Bridge module to interface with the Erlang DXNN Analyzer.
  Provides Elixir-friendly wrappers around Erlang analyzer functions.
  """
  use GenServer

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def start_analyzer do
    GenServer.call(__MODULE__, :start_analyzer)
  end

  def stop_analyzer do
    GenServer.call(__MODULE__, :stop_analyzer)
  end

  def load_context(path, context_name) do
    GenServer.call(__MODULE__, {:load_context, path, context_name}, 30_000)
  end

  def unload_context(context_name) do
    GenServer.call(__MODULE__, {:unload_context, context_name})
  end

  def list_contexts do
    GenServer.call(__MODULE__, :list_contexts)
  end

  def list_agents(opts \\ []) do
    GenServer.call(__MODULE__, {:list_agents, opts}, 30_000)
  end

  def find_best(count, opts \\ []) do
    GenServer.call(__MODULE__, {:find_best, count, opts}, 30_000)
  end

  def inspect_agent(agent_id, context) do
    GenServer.call(__MODULE__, {:inspect_agent, agent_id, context}, 30_000)
  end

  def get_topology(agent_id, context) do
    GenServer.call(__MODULE__, {:get_topology, agent_id, context}, 30_000)
  end

  def get_topology_graph(agent_id, context) do
    GenServer.call(__MODULE__, {:get_topology_graph, agent_id, context}, 30_000)
  end

  def compare_agents(agent_ids, context) do
    GenServer.call(__MODULE__, {:compare_agents, agent_ids, context}, 30_000)
  end

  def create_population(agent_ids, pop_name, output_path, opts \\ []) do
    GenServer.call(__MODULE__, {:create_population, agent_ids, pop_name, output_path, opts}, 60_000)
  end

  def get_stats(context) do
    GenServer.call(__MODULE__, {:get_stats, context}, 30_000)
  end

  def create_empty_master(master_context) do
    GenServer.call(__MODULE__, {:create_empty_master, master_context}, 30_000)
  end

  def load_master(master_path, master_context) do
    GenServer.call(__MODULE__, {:load_master, master_path, master_context}, 30_000)
  end

  def add_to_master(agent_ids, source_context, master_context) do
    GenServer.call(__MODULE__, {:add_to_master, agent_ids, source_context, master_context}, 60_000)
  end

  def save_master(master_context, output_path) do
    GenServer.call(__MODULE__, {:save_master, master_context, output_path}, 60_000)
  end

  def export_for_deployment(agent_ids, population_id, output_path) do
    GenServer.call(__MODULE__, {:export_for_deployment, agent_ids, population_id, output_path}, 60_000)
  end

  def list_master_contexts do
    GenServer.call(__MODULE__, :list_master_contexts, 30_000)
  end

  # Server Callbacks

  @impl true
  def init(state) do
    IO.puts("=== AnalyzerBridge init starting ===")
    
    # Ensure the analyzer Erlang code is available
    # Add path to compiled analyzer beam files
    analyzer_paths = [
      Path.expand("../../dxnn_analyzer/_build/default/lib/dxnn_analyzer/ebin"),
      Path.expand("../dxnn_analyzer/_build/default/lib/dxnn_analyzer/ebin"),
      Path.expand("../../dxnn_analyzer/ebin"),
      Path.expand("../dxnn_analyzer/ebin"),
      "/app/dxnn_analyzer/_build/default/lib/dxnn_analyzer/ebin",
      "/app/dxnn_analyzer/ebin"
    ]
    
    Enum.each(analyzer_paths, fn path ->
      if File.exists?(path) do
        :code.add_pathz(String.to_charlist(path))
        IO.puts("Added Erlang code path: #{path}")
      end
    end)
    
    # Check if analyzer module is available
    case :code.which(:analyzer) do
      :non_existing ->
        IO.puts("WARNING: analyzer module not found in code path")
        IO.puts("Searched paths: #{inspect(analyzer_paths)}")
      path ->
        IO.puts("Found analyzer module at: #{path}")
        
        # Start the analyzer automatically
        IO.puts("Attempting to start analyzer...")
        try do
          result = :analyzer.start()
          IO.puts("Analyzer start result: #{inspect(result)}")
          IO.puts("Analyzer started successfully")
        catch
          kind, reason ->
            IO.puts("ERROR starting analyzer: #{inspect(kind)} - #{inspect(reason)}")
            # Table might already exist
            case :ets.info(:analyzer_contexts) do
              :undefined -> 
                IO.puts("ERROR: Failed to create ETS table")
              _ -> 
                IO.puts("Analyzer ETS table already exists")
            end
        end
    end
    
    IO.puts("=== AnalyzerBridge init complete ===")
    {:ok, state}
  end

  @impl true
  def handle_call(:start_analyzer, _from, state) do
    result = 
      try do
        :analyzer.start()
      catch
        :error, :badarg ->
          # Table might already exist
          case :ets.info(:analyzer_contexts) do
            :undefined -> {:error, "Failed to create ETS table"}
            _ -> :ok
          end
      end
    {:reply, result, state}
  end

  @impl true
  def handle_call(:stop_analyzer, _from, state) do
    result = :analyzer.stop()
    {:reply, result, state}
  end

  @impl true
  def handle_call({:load_context, path, context_name}, _from, state) do
    path_charlist = String.to_charlist(path)
    context_atom = String.to_atom(context_name)
    
    result = :analyzer.load(path_charlist, context_atom)
    {:reply, format_result(result), state}
  end

  @impl true
  def handle_call({:unload_context, context_name}, _from, state) do
    context_atom = String.to_atom(context_name)
    result = :analyzer.unload(context_atom)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_contexts, _from, state) do
    result = :analyzer.list_contexts()
    {:reply, format_contexts(result), state}
  end

  @impl true
  def handle_call({:list_agents, opts}, _from, state) do
    erlang_opts = convert_opts_to_erlang(opts)
    
    # Check if context exists
    context = Keyword.get(opts, :context)
    if context do
      context_atom = String.to_atom(context)
      case :ets.info(:analyzer_contexts) do
        :undefined ->
          {:reply, {:error, "Analyzer not started"}, state}
        _ ->
          case :ets.lookup(:analyzer_contexts, context_atom) do
            [] ->
              {:reply, {:error, "Context '#{context}' not loaded"}, state}
            _ ->
              try do
                result = :analyzer.list_agents(erlang_opts)
                
                # Debug: print first agent to see structure
                case result do
                  [{first_agent, neuron_count, sensors} | _] ->
                    IO.puts("=== First Agent With Topology Debug ===")
                    IO.puts("Agent tuple size: #{tuple_size(first_agent)}")
                    IO.puts("Neuron count: #{neuron_count}")
                    IO.puts("Sensors: #{inspect(sensors)}")
                  _ -> :ok
                end
                
                {:reply, format_agents_with_topology(result), state}
              catch
                kind, reason ->
                  IO.puts("Error in list_agents: #{inspect(kind)} - #{inspect(reason)}")
                  {:reply, {:error, "Failed to list agents: #{inspect(reason)}"}, state}
              end
          end
      end
    else
      {:reply, {:error, "No context specified"}, state}
    end
  end

  @impl true
  def handle_call({:find_best, count, opts}, _from, state) do
    erlang_opts = convert_opts_to_erlang(opts)
    result = :analyzer.find_best(count, erlang_opts)
    {:reply, format_agents(result), state}
  end

  @impl true
  def handle_call({:inspect_agent, agent_id, context}, _from, state) do
    context_atom = if is_binary(context), do: String.to_atom(context), else: context
    IO.puts("=== inspect_agent Debug ===")
    IO.puts("Agent ID: #{inspect(agent_id)}")
    IO.puts("Context (string): #{inspect(context)}")
    IO.puts("Context (atom): #{inspect(context_atom)}")
    
    # Check if context exists
    case :ets.info(:analyzer_contexts) do
      :undefined ->
        {:reply, {:error, "Analyzer not started"}, state}
      _ ->
        case :ets.lookup(:analyzer_contexts, context_atom) do
          [] ->
            {:reply, {:error, "Context '#{context}' not loaded"}, state}
          _ ->
            try do
              result = :agent_inspector.inspect_agent(agent_id, context_atom)
              {:reply, format_inspection(result), state}
            catch
              kind, reason ->
                IO.puts("Error in inspect_agent: #{inspect(kind)} - #{inspect(reason)}")
                {:reply, {:error, "Failed to inspect agent: #{inspect(reason)}"}, state}
            end
        end
    end
  end

  @impl true
  def handle_call({:get_topology, agent_id, context}, _from, state) do
    context_atom = String.to_atom(context)
    result = :agent_inspector.get_full_topology(agent_id, context_atom)
    {:reply, format_topology(result), state}
  end

  @impl true
  def handle_call({:get_topology_graph, agent_id, context}, _from, state) do
    context_atom = String.to_atom(context)
    result = :agent_inspector.get_full_topology(agent_id, context_atom)
    {:reply, format_topology_graph(result), state}
  end

  @impl true
  def handle_call({:compare_agents, agent_ids, context}, _from, state) do
    context_atom = String.to_atom(context)
    result = :analyzer.compare(agent_ids, context_atom)
    {:reply, format_comparison(result), state}
  end

  @impl true
  def handle_call({:create_population, agent_ids, pop_name, output_path, opts}, _from, state) do
    pop_name_atom = String.to_atom(pop_name)
    output_charlist = String.to_charlist(output_path)
    erlang_opts = convert_opts_to_erlang(opts)
    
    result = :analyzer.create_population(agent_ids, pop_name_atom, output_charlist, erlang_opts)
    {:reply, format_result(result), state}
  end

  @impl true
  def handle_call({:get_stats, context}, _from, state) do
    context_atom = String.to_atom(context)
    result = :stats_collector.collect_stats(context_atom)
    {:reply, format_stats(result), state}
  end

  @impl true
  def handle_call({:create_empty_master, master_context}, _from, state) do
    master_context_atom = String.to_atom(master_context)
    result = :master_database.create_empty(master_context_atom)
    {:reply, format_result(result), state}
  end

  @impl true
  def handle_call({:load_master, master_path, master_context}, _from, state) do
    master_path_charlist = String.to_charlist(master_path)
    master_context_atom = String.to_atom(master_context)
    result = :master_database.load(master_path_charlist, master_context_atom)
    {:reply, format_result(result), state}
  end

  @impl true
  def handle_call({:add_to_master, agent_ids, source_context, master_context}, _from, state) do
    IO.puts("=== Bridge add_to_master ===")
    IO.puts("Agent IDs: #{inspect(agent_ids)}")
    IO.puts("Source context (string): #{inspect(source_context)}")
    IO.puts("Master context: #{inspect(master_context)}")
    
    source_context_atom = String.to_atom(source_context)
    master_context_atom = String.to_atom(master_context)
    
    IO.puts("Source context (atom): #{inspect(source_context_atom)}")
    IO.puts("Master context (atom): #{inspect(master_context_atom)}")
    
    # Check if contexts exist in ETS
    case :ets.info(:analyzer_contexts) do
      :undefined ->
        IO.puts("ERROR: analyzer_contexts table doesn't exist")
        {:reply, {:error, "Analyzer not started"}, state}
      _ ->
        case :ets.lookup(:analyzer_contexts, source_context_atom) do
          [] ->
            IO.puts("ERROR: Source context '#{source_context}' not found in ETS")
            {:reply, {:error, "Context '#{source_context}' not loaded"}, state}
          [_context_record] ->
            case :ets.lookup(:analyzer_contexts, master_context_atom) do
              [] ->
                IO.puts("ERROR: Master context '#{master_context}' not found in ETS")
                {:reply, {:error, "Master context '#{master_context}' not loaded. Create it first with create_empty_master."}, state}
              [_master_record] ->
                IO.puts("Both contexts found, calling add_to_context...")
                result = :master_database.add_to_context(agent_ids, source_context_atom, master_context_atom)
                IO.puts("Result from master_database: #{inspect(result)}")
                {:reply, format_result(result), state}
            end
        end
    end
  end

  @impl true
  def handle_call({:save_master, master_context, output_path}, _from, state) do
    master_context_atom = String.to_atom(master_context)
    output_path_charlist = String.to_charlist(output_path)
    result = :master_database.save(master_context_atom, output_path_charlist)
    {:reply, format_result(result), state}
  end

  @impl true
  def handle_call({:export_for_deployment, agent_ids, population_id, output_path}, _from, state) do
    population_id_atom = String.to_atom(population_id)
    output_path_charlist = String.to_charlist(output_path)
    result = :master_database.export_for_deployment(agent_ids, population_id_atom, output_path_charlist)
    {:reply, format_result(result), state}
  end

  @impl true
  def handle_call(:list_master_contexts, _from, state) do
    result = :master_database.list_contexts()
    {:reply, format_contexts(result), state}
  end

  # Helper Functions

  defp convert_opts_to_erlang(opts) do
    Enum.map(opts, fn
      {:context, val} -> {:context, String.to_atom(val)}
      {key, val} -> {key, val}
    end)
  end

  defp format_result({:ok, _} = result), do: result
  defp format_result(:ok), do: {:ok, "Success"}
  defp format_result({:error, reason}) when is_binary(reason), do: {:error, reason}
  defp format_result({:error, reason}) when is_atom(reason), do: {:error, to_string(reason)}
  defp format_result({:error, reason}), do: {:error, inspect(reason)}
  defp format_result(other), do: {:ok, other}

  defp format_contexts(contexts) when is_list(contexts) do
    Enum.map(contexts, &format_context/1)
  end

  defp format_context(context) when is_tuple(context) do
    # Convert Erlang record to map
    # Record structure: {mnesia_context, name, path, loaded_at, agent_count, population_count, specie_count, tables}
    %{
      name: to_string(elem(context, 1)),  # Convert atom to string
      path: to_string(elem(context, 2)),
      # Skip loaded_at (elem 3) - it's a timestamp tuple
      agent_count: elem(context, 4),
      population_count: elem(context, 5),
      specie_count: elem(context, 6)
    }
  end

  defp format_agents(agents) when is_list(agents) do
    Enum.map(agents, &format_agent/1)
  end

  defp format_agents_with_topology(agents_with_topology) when is_list(agents_with_topology) do
    Enum.map(agents_with_topology, fn {agent, neuron_count, sensors} ->
      format_agent_with_topology(agent, neuron_count, sensors)
    end)
  end

  defp format_agent(agent) when is_tuple(agent) do
    # Agent record structure from records.hrl
    agent_id = elem(agent, 1)
    encoding_type = elem(agent, 2)
    generation = elem(agent, 3)
    fitness = elem(agent, 10)
    
    # Use inspect for URL-safe string representation
    id_string = inspect(agent_id)
    
    %{
      id: agent_id,
      id_string: id_string,
      encoding_type: encoding_type,
      generation: generation,
      fitness: fitness,
      neuron_count: 0,
      sensors: []
    }
  end
  
  defp format_agent_with_topology(agent, neuron_count, sensors) when is_tuple(agent) do
    # Agent record structure from records.hrl
    agent_id = elem(agent, 1)
    encoding_type = elem(agent, 2)
    generation = elem(agent, 3)
    fitness = elem(agent, 10)
    
    # Use inspect for URL-safe string representation
    id_string = inspect(agent_id)
    
    # Filter out undefined sensors
    sensor_names = sensors
    |> Enum.filter(fn s -> s != :undefined end)
    |> Enum.map(&to_string/1)
    
    %{
      id: agent_id,
      id_string: id_string,
      encoding_type: encoding_type,
      generation: generation,
      fitness: fitness,
      neuron_count: neuron_count,
      sensors: sensor_names
    }
  end
  
  defp get_agent_topology_info(_agent_id, _cx_id) do
    {0, []}
  end

  defp format_inspection({:error, reason}), do: {:error, to_string(reason)}
  defp format_inspection(data) when is_map(data) do
    # Recursively convert Erlang data structures to Elixir-friendly format
    data
    |> Enum.map(fn {k, v} -> {k, format_value(v)} end)
    |> Map.new()
  end
  defp format_inspection(_), do: %{}

  defp format_value(v) when is_map(v) do
    v |> Enum.map(fn {k, val} -> {k, format_value(val)} end) |> Map.new()
  end
  defp format_value(v) when is_list(v) do
    Enum.map(v, &format_value/1)
  end
  defp format_value(v) when is_tuple(v) do
    # Check if it's a topo_summary record
    case v do
      {:topo_summary, agent_id, encoding_type, sensor_count, neuron_count, actuator_count, 
       substrate_dimensions, total_connections, depth, width, cycles} ->
        %{
          agent_id: agent_id,
          encoding_type: encoding_type,
          sensor_count: sensor_count,
          neuron_count: neuron_count,
          actuator_count: actuator_count,
          substrate_dimensions: substrate_dimensions,
          total_connections: total_connections,
          depth: depth,
          width: width,
          cycles: cycles
        }
      _ ->
        # Keep other tuples as tuples but format their contents
        v |> Tuple.to_list() |> Enum.map(&format_value/1) |> List.to_tuple()
    end
  end
  defp format_value(v) when is_atom(v), do: v
  defp format_value(v) when is_number(v), do: v
  defp format_value(v) when is_binary(v), do: v
  defp format_value(v), do: v

  defp format_topology(data) when is_map(data), do: data
  defp format_topology(_), do: %{}

  defp format_topology_graph({:error, reason}), do: {:error, to_string(reason)}
  defp format_topology_graph(topology) when is_map(topology) do
    nodes = build_graph_nodes(topology)
    edges = build_graph_edges(topology)
    layers = organize_by_layer(topology)
    
    %{
      nodes: nodes,
      edges: edges,
      layers: layers,
      stats: %{
        sensor_count: length(Map.get(topology, :sensors, [])),
        neuron_count: length(Map.get(topology, :neurons, [])),
        actuator_count: length(Map.get(topology, :actuators, [])),
        connection_count: length(edges)
      }
    }
  end
  defp format_topology_graph(_), do: {:error, "Invalid topology data"}

  defp build_graph_nodes(topology) do
    sensors = Map.get(topology, :sensors, []) |> Enum.reject(&(&1 == :undefined))
    neurons = Map.get(topology, :neurons, []) |> Enum.reject(&(&1 == :undefined))
    actuators = Map.get(topology, :actuators, []) |> Enum.reject(&(&1 == :undefined))
    
    sensor_nodes = Enum.map(sensors, fn sensor ->
      sensor_id = elem(sensor, 1)
      sensor_name = to_string(elem(sensor, 2))
      vl = elem(sensor, 6)
      
      %{
        id: inspect(sensor_id),
        type: "sensor",
        label: "#{sensor_name} #{vl}",
        short_id: extract_last_digits(sensor_id),
        name: sensor_name,
        vl: vl,
        layer: 0,
        fanout_ids: Enum.map(elem(sensor, 7), &inspect/1)
      }
    end)
    
    neuron_nodes = Enum.map(neurons, fn neuron ->
      neuron_id = elem(neuron, 1)
      layer = elem(elem(neuron_id, 0), 0)
      af = elem(neuron, 4)
      pf = elem(neuron, 5)
      aggr_f = elem(neuron, 6)
      input_idps = elem(neuron, 7)
      input_idps_modulation = elem(neuron, 8)
      output_ids = elem(neuron, 9)
      ro_ids = elem(neuron, 10)
      
      %{
        id: inspect(neuron_id),
        type: "neuron",
        label: extract_last_digits(neuron_id),
        short_id: extract_last_digits(neuron_id),
        af: inspect(af),
        pf: inspect(pf),
        aggr_f: inspect(aggr_f),
        layer: layer,
        input_count: length(input_idps),
        output_count: length(output_ids),
        input_ids: Enum.map(input_idps, fn {id, _weights} -> inspect(id) end),
        input_modulation_ids: Enum.map(input_idps_modulation, fn {id, _weights} -> inspect(id) end),
        output_ids: Enum.map(output_ids, &inspect/1),
        ro_ids: Enum.map(ro_ids, &inspect/1)
      }
    end)
    
    actuator_nodes = Enum.map(actuators, fn actuator ->
      max_layer = case neuron_nodes do
        [] -> 1
        _ -> Enum.max_by(neuron_nodes, & &1.layer).layer
      end
      
      actuator_id = elem(actuator, 1)
      actuator_name = to_string(elem(actuator, 2))
      vl = elem(actuator, 6)
      
      %{
        id: inspect(actuator_id),
        type: "actuator",
        label: "#{actuator_name} #{vl}",
        short_id: extract_last_digits(actuator_id),
        name: actuator_name,
        vl: vl,
        layer: max_layer + 1,
        fanin_ids: Enum.map(elem(actuator, 7), &inspect/1)
      }
    end)
    
    sensor_nodes ++ neuron_nodes ++ actuator_nodes
  end
  
  # Extract last 4 digits from the decimal portion of the timestamp
  defp extract_last_digits(id) when is_tuple(id) do
    # ID format: {{layer, timestamp}, :type}
    # Extract timestamp from the tuple
    case elem(id, 0) do
      {_layer, timestamp} when is_float(timestamp) ->
        # Convert timestamp to string
        # Example: 5.644195998970599e-10 -> we want "0599" (last 4 of decimal part)
        timestamp_str = Float.to_string(timestamp)
        
        # Split by 'e' to get the decimal part before scientific notation
        decimal_part = timestamp_str
        |> String.split("e")
        |> List.first()
        |> String.replace(".", "")  # Remove decimal point
        
        # Get last 4 digits of the decimal part
        String.slice(decimal_part, -4..-1) || "0000"
      _ -> "0000"
    end
  end
  defp extract_last_digits(_), do: "0000"

  defp build_graph_edges(topology) do
    neurons = Map.get(topology, :neurons, []) |> Enum.reject(&(&1 == :undefined))
    
    # Build edges from input_idps (captures all incoming connections including recurrent)
    input_edges = Enum.flat_map(neurons, fn neuron ->
      neuron_id = elem(neuron, 1)
      input_idps = elem(neuron, 7)
      
      Enum.map(input_idps, fn {input_id, weights} ->
        # Convert weights to simple list of numbers
        weight_list = cond do
          is_list(weights) -> 
            Enum.map(weights, fn w -> 
              if is_tuple(w), do: elem(w, 0), else: w 
            end)
          is_tuple(weights) -> 
            [elem(weights, 0)]
          is_number(weights) -> 
            [weights]
          true -> 
            []
        end
        
        # Determine if this is a recurrent connection by checking layer indices
        source_layer = get_layer_index(input_id)
        target_layer = get_layer_index(neuron_id)
        is_recurrent = source_layer >= target_layer
        
        %{
          source: inspect(input_id),
          target: inspect(neuron_id),
          weight: length(weight_list),
          weights: Enum.take(weight_list, 5),
          recurrent: is_recurrent
        }
      end)
    end)
    
    # Build edges from ro_ids (explicit recurrent output tracking)
    # These should already be in input_idps, but we check for completeness
    recurrent_edges = Enum.flat_map(neurons, fn neuron ->
      neuron_id = elem(neuron, 1)
      ro_ids = elem(neuron, 9)  # Position 9 is ro_ids
      
      Enum.map(ro_ids, fn target_id ->
        %{
          source: inspect(neuron_id),
          target: inspect(target_id),
          weight: 1,  # ro_ids doesn't store weights
          weights: [],
          recurrent: true
        }
      end)
    end)
    
    # Combine and deduplicate (input_idps should already include most of these)
    all_edges = input_edges ++ recurrent_edges
    Enum.uniq_by(all_edges, fn edge -> {edge.source, edge.target} end)
  end
  
  # Helper to extract layer index from neuron/sensor/actuator ID
  defp get_layer_index(id) when is_tuple(id) do
    case elem(id, 0) do
      {layer, _} when is_integer(layer) -> layer
      _ -> 0
    end
  end
  defp get_layer_index(_), do: 0

  defp organize_by_layer(topology) do
    neurons = Map.get(topology, :neurons, []) |> Enum.reject(&(&1 == :undefined))
    
    neurons
    |> Enum.group_by(fn neuron ->
      neuron_id = elem(neuron, 1)
      elem(elem(neuron_id, 0), 0)
    end)
    |> Enum.map(fn {layer, layer_neurons} ->
      %{
        layer: layer,
        neuron_count: length(layer_neurons),
        neurons: Enum.map(layer_neurons, fn n -> inspect(elem(n, 1)) end)
      }
    end)
    |> Enum.sort_by(& &1.layer)
  end

  defp format_comparison(data) when is_map(data), do: data
  defp format_comparison(_), do: %{}

  defp format_stats(data) when is_map(data), do: data
  defp format_stats(_), do: %{}
end
