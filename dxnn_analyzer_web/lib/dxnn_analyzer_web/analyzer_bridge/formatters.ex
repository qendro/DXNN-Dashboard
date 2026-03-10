defmodule DxnnAnalyzerWeb.AnalyzerBridge.Formatters do
  @moduledoc """
  Formats Erlang data structures into Elixir-friendly maps.
  """

  alias DxnnAnalyzerWeb.ContextRegistry

  @doc """
  Formats a generic result tuple.
  """
  def format_result({:ok, _} = result), do: result
  def format_result(:ok), do: {:ok, "Success"}
  def format_result({:error, reason}) when is_binary(reason), do: {:error, reason}
  def format_result({:error, reason}) when is_atom(reason), do: {:error, to_string(reason)}
  def format_result({:error, reason}), do: {:error, inspect(reason)}
  def format_result(other), do: {:ok, other}

  @doc """
  Formats a list of contexts.
  """
  def format_contexts(contexts) when is_list(contexts) do
    Enum.map(contexts, &format_context/1)
  end

  @doc """
  Formats a single context record.
  Record structure: {mnesia_context, name, path, loaded_at, agent_count, population_count, specie_count, tables}
  """
  def format_context(context) when is_tuple(context) do
    context_atom = elem(context, 1)
    record_path = to_string(elem(context, 2))

    display_name =
      ContextRegistry.display_name_for_atom(context_atom) ||
        Atom.to_string(context_atom)

    bundle = ContextRegistry.get_bundle(context_atom) || %{}

    bundle_root = Map.get(bundle, :bundle_root) || Map.get(bundle, "bundle_root")
    mnesia_path = Map.get(bundle, :mnesia_path) || Map.get(bundle, "mnesia_path") || record_path
    logs_path = Map.get(bundle, :logs_path) || Map.get(bundle, "logs_path")
    analytics_path = Map.get(bundle, :analytics_path) || Map.get(bundle, "analytics_path")
    manifest_path = Map.get(bundle, :manifest_path) || Map.get(bundle, "manifest_path")
    success_path = Map.get(bundle, :success_path) || Map.get(bundle, "success_path")
    checkpoint_info_path =
      Map.get(bundle, :checkpoint_info_path) || Map.get(bundle, "checkpoint_info_path")

    %{
      name: display_name,
      path: bundle_root || record_path,
      mnesia_path: mnesia_path,
      bundle_root: bundle_root,
      logs_path: logs_path,
      analytics_path: analytics_path,
      manifest_path: manifest_path,
      success_path: success_path,
      checkpoint_info_path: checkpoint_info_path,
      agent_count: elem(context, 4),
      population_count: elem(context, 5),
      specie_count: elem(context, 6)
    }
  end

  @doc """
  Formats a list of agents.
  """
  def format_agents(agents) when is_list(agents) do
    Enum.map(agents, &format_agent/1)
  end

  @doc """
  Formats a list of agents with topology information.
  """
  def format_agents_with_topology(agents_with_topology) when is_list(agents_with_topology) do
    Enum.map(agents_with_topology, fn {agent, neuron_count, sensors} ->
      format_agent_with_topology(agent, neuron_count, sensors)
    end)
  end

  @doc """
  Formats a single agent record.
  """
  def format_agent(agent) when is_tuple(agent) do
    agent_id = elem(agent, 1)
    encoding_type = elem(agent, 2)
    generation = elem(agent, 3)
    fitness = elem(agent, 10)

    %{
      id: agent_id,
      id_string: inspect(agent_id),
      encoding_type: encoding_type,
      generation: generation,
      fitness: fitness,
      neuron_count: 0,
      sensors: []
    }
  end

  @doc """
  Formats an agent with topology information.
  """
  def format_agent_with_topology(agent, neuron_count, sensors) when is_tuple(agent) do
    agent_id = elem(agent, 1)
    encoding_type = elem(agent, 2)
    generation = elem(agent, 3)
    fitness = elem(agent, 10)

    sensor_names =
      sensors
      |> Enum.filter(fn s -> s != :undefined end)
      |> Enum.map(&to_string/1)

    %{
      id: agent_id,
      id_string: inspect(agent_id),
      encoding_type: encoding_type,
      generation: generation,
      fitness: fitness,
      neuron_count: neuron_count,
      sensors: sensor_names
    }
  end

  @doc """
  Formats agent inspection data.
  """
  def format_inspection({:error, reason}), do: {:error, to_string(reason)}

  def format_inspection(data) when is_map(data) do
    data
    |> Enum.map(fn {k, v} -> {k, format_value(v)} end)
    |> Map.new()
  end

  def format_inspection(_), do: %{}

  @doc """
  Formats topology data.
  """
  def format_topology(data) when is_map(data), do: data
  def format_topology(_), do: %{}

  @doc """
  Formats comparison data.
  """
  def format_comparison(data) when is_map(data), do: data
  def format_comparison(_), do: %{}

  @doc """
  Formats statistics data.
  """
  def format_stats(data) when is_map(data), do: data
  def format_stats(_), do: %{}

  @doc """
  Formats context data (populations, species, etc).
  """
  def format_context_data({:ok, data}) when is_list(data) do
    {:ok, Enum.map(data, &format_value/1)}
  end

  def format_context_data({:ok, data}) when is_map(data) do
    {:ok, format_value(data)}
  end

  def format_context_data({:error, reason}), do: {:error, to_string(reason)}
  def format_context_data(other), do: other

  @doc """
  Recursively formats Erlang values to Elixir-friendly structures.
  """
  def format_value(v) when is_map(v) do
    v |> Enum.map(fn {k, val} -> {k, format_value(val)} end) |> Map.new()
  end

  def format_value(v) when is_list(v) do
    Enum.map(v, &format_value/1)
  end

  def format_value(v) when is_tuple(v) do
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
        v |> Tuple.to_list() |> Enum.map(&format_value/1) |> List.to_tuple()
    end
  end

  def format_value(v) when is_atom(v), do: v
  def format_value(v) when is_number(v), do: v
  def format_value(v) when is_binary(v), do: v
  def format_value(v), do: v
end
