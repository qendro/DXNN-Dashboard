defmodule DxnnAnalyzerWeb.AnalyzerBridge.ExperimentOperations do
  @moduledoc """
  Handles experiment-related operations.
  """

  alias DxnnAnalyzerWeb.ContextRegistry
  alias DxnnAnalyzerWeb.AnalyzerBridge.ContextManager

  @doc """
  Scans all experiment folders.
  """
  def scan_all_experiments do
    :database_settings.init()
    folders = :database_settings.get_folders()

    :lists.flatmap(
      fn folder ->
        :database_settings.scan_databases(folder)
      end,
      folders
    )
  end

  @doc """
  Creates a new experiment.
  """
  def create_experiment(name) do
    with {:ok, default_folder} <- :database_settings.get_default_folder() do
      experiment_path = Path.join([to_string(default_folder), name])

      with :ok <- File.mkdir_p(experiment_path),
           {:ok, context_atom, display_name} <- ContextManager.ensure_context_alias(name),
           {:ok, _} <- :master_database.create_empty(context_atom),
           {:ok, _} <-
             :master_database.save(context_atom, String.to_charlist(experiment_path)) do
        :analyzer.unload(context_atom)
        :ok = ContextRegistry.release(display_name)
        {:ok, experiment_path}
      else
        {:error, reason} -> {:error, "Failed to create experiment: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Copies agents from one experiment to another.
  """
  def copy_agents_to_experiment(agent_ids, source_context, target_context) do
    with {:ok, source_atom, target_atom} <-
           ContextManager.validate_contexts(source_context, target_context) do
      result = :master_database.add_to_context(agent_ids, source_atom, target_atom)
      {:ok, result}
    end
  end

  @doc """
  Saves an experiment to disk.
  """
  def save_experiment(experiment_name, experiment_path) do
    with {:ok, experiment_context_atom, _} <-
           ContextManager.validate_context(experiment_name) do
      clean_path = clean_mnesia_path(experiment_path)
      experiment_path_charlist = String.to_charlist(clean_path)

      :master_database.save(experiment_context_atom, experiment_path_charlist)
    end
  end

  @doc """
  Creates an empty experiment context in memory.
  """
  def create_empty_experiment(name) do
    with {:ok, context_atom, _display_name} <- ContextManager.ensure_context_alias(name) do
      :master_database.create_empty(context_atom)
    end
  end

  # Private helpers

  defp clean_mnesia_path(path) do
    if String.ends_with?(path, "Mnesia.nonode@nohost") do
      Path.dirname(path)
    else
      path
    end
  end
end
