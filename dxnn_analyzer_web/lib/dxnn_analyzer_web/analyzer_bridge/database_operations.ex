defmodule DxnnAnalyzerWeb.AnalyzerBridge.DatabaseOperations do
  @moduledoc """
  Handles database and master database operations.
  """

  alias DxnnAnalyzerWeb.AnalyzerBridge.ContextManager

  @doc """
  Creates an empty master database context.
  """
  def create_empty_master(master_context) do
    with {:ok, master_context_atom, _display_name} <-
           ContextManager.ensure_context_alias(master_context) do
      :master_database.create_empty(master_context_atom)
    end
  end

  @doc """
  Loads a master database from disk.
  """
  def load_master(master_path, master_context) do
    with {:ok, master_context_atom, _display_name} <-
           ContextManager.ensure_context_alias(master_context) do
      master_path_charlist = String.to_charlist(master_path)
      :master_database.load(master_path_charlist, master_context_atom)
    end
  end

  @doc """
  Adds agents from source context to master context.
  """
  def add_to_master(agent_ids, source_context, master_context) do
    with {:ok, source_atom, target_atom} <-
           ContextManager.validate_contexts(source_context, master_context) do
      result = :master_database.add_to_context(agent_ids, source_atom, target_atom)
      {:ok, result}
    end
  end

  @doc """
  Saves a master database to disk.
  """
  def save_master(master_context, output_path) do
    with {:ok, master_context_atom, _record} <- ContextManager.validate_context(master_context) do
      output_path_charlist = String.to_charlist(output_path)
      :master_database.save(master_context_atom, output_path_charlist)
    end
  end

  @doc """
  Exports agents for deployment.
  """
  def export_for_deployment(agent_ids, population_id, output_path) do
    population_id_atom = String.to_atom(population_id)
    output_path_charlist = String.to_charlist(output_path)
    :master_database.export_for_deployment(agent_ids, population_id_atom, output_path_charlist)
  end

  @doc """
  Creates a new database.
  """
  def create_database(name) do
    with {:ok, context_atom, _display_name} <- ContextManager.ensure_context_alias(name) do
      :master_database.create_empty(context_atom)
    end
  end

  @doc """
  Lists all databases.
  """
  def list_databases do
    :master_database.list_contexts()
  end

  @doc """
  Saves a database to disk.
  """
  def save_database_to_disk(context, path) do
    with {:ok, context_atom, _record} <- ContextManager.validate_context(context) do
      save_path = path || "./data/default/#{context}"
      :master_database.save(context_atom, String.to_charlist(save_path))
    end
  end

  @doc """
  Scans all database folders for available databases.
  """
  def scan_all_databases do
    :database_settings.init()
    folders = :database_settings.get_folders()

    :lists.flatmap(
      fn folder ->
        :database_settings.scan_databases(folder)
      end,
      folders
    )
  end
end
