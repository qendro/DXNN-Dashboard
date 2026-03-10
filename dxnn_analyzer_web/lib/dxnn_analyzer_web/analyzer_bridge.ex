defmodule DxnnAnalyzerWeb.AnalyzerBridge do
  @moduledoc """
  Bridge module to interface with the Erlang DXNN Analyzer.
  Provides Elixir-friendly wrappers around Erlang analyzer functions.
  
  This module acts as a GenServer coordinator that delegates to specialized
  operation modules for better organization and maintainability.
  """
  use GenServer

  alias DxnnAnalyzerWeb.AnalyzerBridge.{
    AgentOperations,
    ContextManager,
    DatabaseOperations,
    ExperimentOperations,
    Formatters,
    PopulationOperations,
    SettingsOperations,
    StatisticsOperations,
    TopologyFormatter
  }

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # Analyzer Control

  def start_analyzer do
    GenServer.call(__MODULE__, :start_analyzer)
  end

  def stop_analyzer do
    GenServer.call(__MODULE__, :stop_analyzer)
  end

  # Context Management

  def load_context(path, context_name) do
    GenServer.call(__MODULE__, {:load_context, path, context_name}, 30_000)
  end

  def unload_context(context_name) do
    GenServer.call(__MODULE__, {:unload_context, context_name})
  end

  def list_contexts do
    GenServer.call(__MODULE__, :list_contexts)
  end

  def list_master_contexts do
    GenServer.call(__MODULE__, :list_master_contexts, 30_000)
  end

  # Agent Operations

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

  def delete_agents(agent_ids, context) do
    GenServer.call(__MODULE__, {:delete_agents, agent_ids, context}, 60_000)
  end

  # Population Operations

  def create_population(agent_ids, pop_name, output_path, opts \\ []) do
    GenServer.call(
      __MODULE__,
      {:create_population, agent_ids, pop_name, output_path, opts},
      60_000
    )
  end

  # Statistics Operations

  def get_stats(context) do
    GenServer.call(__MODULE__, {:get_stats, context}, 30_000)
  end

  def get_populations(context) do
    GenServer.call(__MODULE__, {:get_populations, context}, 30_000)
  end

  def get_species(context) do
    GenServer.call(__MODULE__, {:get_species, context}, 30_000)
  end

  def get_population(population_id, context) do
    GenServer.call(__MODULE__, {:get_population, population_id, context}, 30_000)
  end

  def get_specie(specie_id, context) do
    GenServer.call(__MODULE__, {:get_specie, specie_id, context}, 30_000)
  end

  # Database Operations

  def create_empty_master(master_context) do
    GenServer.call(__MODULE__, {:create_empty_master, master_context}, 30_000)
  end

  def load_master(master_path, master_context) do
    GenServer.call(__MODULE__, {:load_master, master_path, master_context}, 30_000)
  end

  def add_to_master(agent_ids, source_context, master_context) do
    GenServer.call(
      __MODULE__,
      {:add_to_master, agent_ids, source_context, master_context},
      60_000
    )
  end

  def save_master(master_context, output_path) do
    GenServer.call(__MODULE__, {:save_master, master_context, output_path}, 60_000)
  end

  def export_for_deployment(agent_ids, population_id, output_path) do
    GenServer.call(
      __MODULE__,
      {:export_for_deployment, agent_ids, population_id, output_path},
      60_000
    )
  end

  def create_database(name) do
    GenServer.call(__MODULE__, {:create_database, name}, 30_000)
  end

  def list_databases do
    GenServer.call(__MODULE__, :list_databases)
  end

  def save_database_to_disk(context, path \\ nil) do
    GenServer.call(__MODULE__, {:save_database_to_disk, context, path}, 60_000)
  end

  def scan_all_databases do
    GenServer.call(__MODULE__, :scan_all_databases, 30_000)
  end

  # Settings Operations

  def get_database_folders do
    GenServer.call(__MODULE__, :get_database_folders)
  end

  def add_database_folder(folder) do
    GenServer.call(__MODULE__, {:add_database_folder, folder})
  end

  def remove_database_folder(folder) do
    GenServer.call(__MODULE__, {:remove_database_folder, folder})
  end

  def set_default_folder(folder) do
    GenServer.call(__MODULE__, {:set_default_folder, folder})
  end

  def get_default_folder do
    GenServer.call(__MODULE__, :get_default_folder)
  end

  def get_experiments_from_settings do
    GenServer.call(__MODULE__, :get_experiments_from_settings)
  end

  def add_experiment_to_settings(name, path) do
    GenServer.call(__MODULE__, {:add_experiment_to_settings, name, path})
  end

  def remove_experiment_from_settings(name) do
    GenServer.call(__MODULE__, {:remove_experiment_from_settings, name})
  end

  def create_experiment_in_settings(name, path) do
    GenServer.call(__MODULE__, {:create_experiment_in_settings, name, path}, 30_000)
  end

  def get_s3_auto_download_path do
    GenServer.call(__MODULE__, :get_s3_auto_download_path)
  end

  def set_s3_auto_download_path(path) do
    GenServer.call(__MODULE__, {:set_s3_auto_download_path, path})
  end

  # Experiment Operations

  def scan_all_experiments do
    GenServer.call(__MODULE__, :scan_all_experiments, 30_000)
  end

  def create_experiment(name) do
    GenServer.call(__MODULE__, {:create_experiment, name}, 30_000)
  end

  def copy_agents_to_experiment(agent_ids, source_context, target_context) do
    GenServer.call(
      __MODULE__,
      {:copy_agents_to_experiment, agent_ids, source_context, target_context},
      60_000
    )
  end

  def save_experiment(experiment_name, experiment_path) do
    GenServer.call(__MODULE__, {:save_experiment, experiment_name, experiment_path}, 60_000)
  end

  def create_empty_experiment(name) do
    GenServer.call(__MODULE__, {:create_empty_experiment, name})
  end

  # Server Callbacks

  @impl true
  def init(state) do
    IO.puts("=== AnalyzerBridge init starting ===")

    setup_erlang_code_paths()
    start_analyzer_if_available()

    IO.puts("=== AnalyzerBridge init complete ===")
    {:ok, state}
  end

  # Analyzer Control Handlers

  @impl true
  def handle_call(:start_analyzer, _from, state) do
    result = safe_start_analyzer()
    {:reply, result, state}
  end

  @impl true
  def handle_call(:stop_analyzer, _from, state) do
    result = :analyzer.stop()
    {:reply, result, state}
  end

  # Context Management Handlers

  @impl true
  def handle_call({:load_context, path, context_name}, _from, state) do
    result = ContextManager.load_context(path, context_name)
    {:reply, Formatters.format_result(result), state}
  end

  @impl true
  def handle_call({:unload_context, context_name}, _from, state) do
    result = ContextManager.unload_context(context_name)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_contexts, _from, state) do
    result = ContextManager.list_contexts()
    {:reply, Formatters.format_contexts(result), state}
  end

  @impl true
  def handle_call(:list_master_contexts, _from, state) do
    result = ContextManager.list_master_contexts()
    {:reply, Formatters.format_contexts(result), state}
  end

  # Agent Operations Handlers

  @impl true
  def handle_call({:list_agents, opts}, _from, state) do
    case AgentOperations.list_agents(opts) do
      {:ok, result} -> {:reply, Formatters.format_agents_with_topology(result), state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:find_best, count, opts}, _from, state) do
    {:ok, result} = AgentOperations.find_best(count, opts)
    {:reply, Formatters.format_agents(result), state}
  end

  @impl true
  def handle_call({:inspect_agent, agent_id, context}, _from, state) do
    case AgentOperations.inspect_agent(agent_id, context) do
      {:ok, result} -> {:reply, Formatters.format_inspection(result), state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_topology, agent_id, context}, _from, state) do
    case AgentOperations.get_topology(agent_id, context) do
      {:ok, result} -> {:reply, Formatters.format_topology(result), state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_topology_graph, agent_id, context}, _from, state) do
    case AgentOperations.get_topology(agent_id, context) do
      {:ok, result} -> {:reply, TopologyFormatter.format_topology_graph(result), state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:compare_agents, agent_ids, context}, _from, state) do
    case AgentOperations.compare_agents(agent_ids, context) do
      {:ok, result} -> {:reply, Formatters.format_comparison(result), state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:delete_agents, agent_ids, context}, _from, state) do
    result = AgentOperations.delete_agents(agent_ids, context)
    {:reply, result, state}
  end

  # Population Operations Handlers

  @impl true
  def handle_call({:create_population, agent_ids, pop_name, output_path, opts}, _from, state) do
    result = PopulationOperations.create_population(agent_ids, pop_name, output_path, opts)
    {:reply, Formatters.format_result(result), state}
  end

  # Statistics Operations Handlers

  @impl true
  def handle_call({:get_stats, context}, _from, state) do
    case StatisticsOperations.get_stats(context) do
      {:ok, result} -> {:reply, Formatters.format_stats(result), state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_populations, context}, _from, state) do
    result = StatisticsOperations.get_populations(context)
    {:reply, Formatters.format_context_data(result), state}
  end

  @impl true
  def handle_call({:get_species, context}, _from, state) do
    result = StatisticsOperations.get_species(context)
    {:reply, Formatters.format_context_data(result), state}
  end

  @impl true
  def handle_call({:get_population, population_id, context}, _from, state) do
    result = StatisticsOperations.get_population(population_id, context)
    {:reply, Formatters.format_context_data(result), state}
  end

  @impl true
  def handle_call({:get_specie, specie_id, context}, _from, state) do
    result = StatisticsOperations.get_specie(specie_id, context)
    {:reply, Formatters.format_context_data(result), state}
  end

  # Database Operations Handlers

  @impl true
  def handle_call({:create_empty_master, master_context}, _from, state) do
    result = DatabaseOperations.create_empty_master(master_context)
    {:reply, Formatters.format_result(result), state}
  end

  @impl true
  def handle_call({:load_master, master_path, master_context}, _from, state) do
    result = DatabaseOperations.load_master(master_path, master_context)
    {:reply, Formatters.format_result(result), state}
  end

  @impl true
  def handle_call({:add_to_master, agent_ids, source_context, master_context}, _from, state) do
    case DatabaseOperations.add_to_master(agent_ids, source_context, master_context) do
      {:ok, result} -> {:reply, Formatters.format_result(result), state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:save_master, master_context, output_path}, _from, state) do
    result = DatabaseOperations.save_master(master_context, output_path)
    {:reply, Formatters.format_result(result), state}
  end

  @impl true
  def handle_call({:export_for_deployment, agent_ids, population_id, output_path}, _from, state) do
    result = DatabaseOperations.export_for_deployment(agent_ids, population_id, output_path)
    {:reply, Formatters.format_result(result), state}
  end

  @impl true
  def handle_call({:create_database, name}, _from, state) do
    result = DatabaseOperations.create_database(name)
    {:reply, Formatters.format_result(result), state}
  end

  @impl true
  def handle_call(:list_databases, _from, state) do
    result = DatabaseOperations.list_databases()
    {:reply, Formatters.format_contexts(result), state}
  end

  @impl true
  def handle_call({:save_database_to_disk, context, path}, _from, state) do
    result = DatabaseOperations.save_database_to_disk(context, path)
    {:reply, Formatters.format_result(result), state}
  end

  @impl true
  def handle_call(:scan_all_databases, _from, state) do
    result = DatabaseOperations.scan_all_databases()
    {:reply, result, state}
  end

  # Settings Operations Handlers

  @impl true
  def handle_call(:get_s3_auto_download_path, _from, state) do
    path = SettingsOperations.get_s3_auto_download_path()
    {:reply, path, state}
  end

  @impl true
  def handle_call({:set_s3_auto_download_path, path}, _from, state) do
    result = SettingsOperations.set_s3_auto_download_path(path)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_database_folders, _from, state) do
    folders = SettingsOperations.get_database_folders()
    {:reply, folders, state}
  end

  @impl true
  def handle_call({:add_database_folder, folder}, _from, state) do
    result = SettingsOperations.add_database_folder(folder)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:remove_database_folder, folder}, _from, state) do
    result = SettingsOperations.remove_database_folder(folder)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:set_default_folder, folder}, _from, state) do
    result = SettingsOperations.set_default_folder(folder)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_default_folder, _from, state) do
    result = SettingsOperations.get_default_folder()
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_experiments_from_settings, _from, state) do
    result = SettingsOperations.get_experiments_from_settings()
    {:reply, result, state}
  end

  @impl true
  def handle_call({:add_experiment_to_settings, name, path}, _from, state) do
    result = SettingsOperations.add_experiment_to_settings(name, path)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:remove_experiment_from_settings, name}, _from, state) do
    result = SettingsOperations.remove_experiment_from_settings(name)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:create_experiment_in_settings, name, path}, _from, state) do
    result = SettingsOperations.create_experiment_in_settings(name, path)
    {:reply, result, state}
  end

  # Experiment Operations Handlers

  @impl true
  def handle_call(:scan_all_experiments, _from, state) do
    result = ExperimentOperations.scan_all_experiments()
    {:reply, result, state}
  end

  @impl true
  def handle_call({:create_experiment, name}, _from, state) do
    result = ExperimentOperations.create_experiment(name)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:copy_agents_to_experiment, agent_ids, source_context, target_context}, _from, state) do
    case ExperimentOperations.copy_agents_to_experiment(agent_ids, source_context, target_context) do
      {:ok, result} -> {:reply, Formatters.format_result(result), state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:save_experiment, experiment_name, experiment_path}, _from, state) do
    result = ExperimentOperations.save_experiment(experiment_name, experiment_path)
    {:reply, Formatters.format_result(result), state}
  end

  @impl true
  def handle_call({:create_empty_experiment, name}, _from, state) do
    result = ExperimentOperations.create_empty_experiment(name)
    {:reply, result, state}
  end

  # Private Helper Functions

  defp setup_erlang_code_paths do
    analyzer_paths = [
      Path.expand("../../dxnn_analyzer/_build/default/lib/dxnn_analyzer/ebin"),
      Path.expand("../dxnn_analyzer/_build/default/lib/dxnn_analyzer/ebin"),
      Path.expand("../../dxnn_analyzer/ebin"),
      Path.expand("../dxnn_analyzer/ebin"),
      "/app/dxnn_analyzer/_build/default/lib/dxnn_analyzer/ebin",
      "/app/dxnn_analyzer/ebin"
    ]

    jsx_paths = [
      Path.expand("../../dxnn_analyzer/_build/default/lib/jsx/ebin"),
      Path.expand("../dxnn_analyzer/_build/default/lib/jsx/ebin"),
      "/app/dxnn_analyzer/_build/default/lib/jsx/ebin"
    ]

    Enum.each(analyzer_paths ++ jsx_paths, fn path ->
      if File.exists?(path) do
        :code.add_pathz(String.to_charlist(path))
        IO.puts("Added Erlang code path: #{path}")
      end
    end)
  end

  defp start_analyzer_if_available do
    case :code.which(:analyzer) do
      :non_existing ->
        IO.puts("WARNING: analyzer module not found in code path")

      path ->
        IO.puts("Found analyzer module at: #{path}")
        IO.puts("Attempting to start analyzer...")

        try do
          result = :analyzer.start()
          IO.puts("Analyzer start result: #{inspect(result)}")
          IO.puts("Analyzer started successfully")
        catch
          kind, reason ->
            IO.puts("ERROR starting analyzer: #{inspect(kind)} - #{inspect(reason)}")

            case :ets.info(:analyzer_contexts) do
              :undefined -> IO.puts("ERROR: Failed to create ETS table")
              _ -> IO.puts("Analyzer ETS table already exists")
            end
        end
    end
  end

  defp safe_start_analyzer do
    try do
      :analyzer.start()
    catch
      :error, :badarg ->
        case :ets.info(:analyzer_contexts) do
          :undefined -> {:error, "Failed to create ETS table"}
          _ -> :ok
        end
    end
  end
end
