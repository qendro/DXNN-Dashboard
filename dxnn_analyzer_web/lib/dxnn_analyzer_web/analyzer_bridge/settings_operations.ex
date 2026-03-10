defmodule DxnnAnalyzerWeb.AnalyzerBridge.SettingsOperations do
  @moduledoc """
  Handles settings operations for database folders and experiments.
  """

  @doc """
  Gets all configured database folders.
  """
  def get_database_folders do
    :database_settings.init()
    :database_settings.get_folders()
  end

  @doc """
  Adds a database folder to settings.
  """
  def add_database_folder(folder) do
    folder_binary = :erlang.list_to_binary(String.to_charlist(folder))
    :database_settings.add_folder(folder_binary)
  end

  @doc """
  Removes a database folder from settings.
  """
  def remove_database_folder(folder) do
    folder_binary = :erlang.list_to_binary(String.to_charlist(folder))
    :database_settings.remove_folder(folder_binary)
  end

  @doc """
  Sets the default database folder.
  """
  def set_default_folder(folder) do
    folder_binary = :erlang.list_to_binary(String.to_charlist(folder))
    :database_settings.set_default(folder_binary)
  end

  @doc """
  Gets the default database folder.
  """
  def get_default_folder do
    :database_settings.get_default_folder()
  end

  @doc """
  Gets all experiments from settings.
  """
  def get_experiments_from_settings do
    experiments = :experiment_settings.get_experiments()

    Enum.map(experiments, fn exp ->
      %{
        name: to_string(Map.get(exp, "name", "")),
        path: to_string(Map.get(exp, "path", ""))
      }
    end)
  end

  @doc """
  Adds an experiment to settings.
  """
  def add_experiment_to_settings(name, path) do
    name_bin = :erlang.list_to_binary(String.to_charlist(name))
    path_bin = :erlang.list_to_binary(String.to_charlist(path))
    :experiment_settings.add_experiment(name_bin, path_bin)
  end

  @doc """
  Removes an experiment from settings.
  """
  def remove_experiment_from_settings(name) do
    name_bin = :erlang.list_to_binary(String.to_charlist(name))
    :experiment_settings.remove_experiment(name_bin)
  end

  @doc """
  Creates an experiment and adds it to settings.
  """
  def create_experiment_in_settings(name, path) do
    with :ok <- File.mkdir_p(path),
         context_atom = String.to_atom(name),
         {:ok, _} <- :master_database.create_empty(context_atom),
         clean_path = clean_mnesia_path(path),
         {:ok, _} <- :master_database.save(context_atom, String.to_charlist(clean_path)) do
      name_bin = :erlang.list_to_binary(String.to_charlist(name))
      path_bin = :erlang.list_to_binary(String.to_charlist(clean_path))
      :experiment_settings.add_experiment(name_bin, path_bin)
    else
      {:error, reason} -> {:error, "Failed to create directory: #{inspect(reason)}"}
    end
  end

  @doc """
  Gets the S3 auto-download path.
  """
  def get_s3_auto_download_path do
    :s3_settings.init()
    path = :s3_settings.get_auto_download_path()
    to_string(path)
  end

  @doc """
  Sets the S3 auto-download path.
  """
  def set_s3_auto_download_path(path) do
    path_bin = :erlang.list_to_binary(String.to_charlist(path))
    :s3_settings.set_auto_download_path(path_bin)
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
