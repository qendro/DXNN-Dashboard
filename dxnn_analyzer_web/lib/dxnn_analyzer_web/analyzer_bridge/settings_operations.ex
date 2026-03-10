defmodule DxnnAnalyzerWeb.AnalyzerBridge.SettingsOperations do
  @moduledoc """
  Handles settings operations for database folders and experiments.
  """

  alias DxnnAnalyzerWeb.{ContextRegistry, RunBundleResolver}
  alias DxnnAnalyzerWeb.AnalyzerBridge.ContextManager

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
      base = %{
        name: to_string(Map.get(exp, "name", "")),
        path: to_string(Map.get(exp, "path", ""))
      }

      persisted = bundle_metadata_from_settings(exp)

      merged =
        base
        |> Map.merge(persisted)
        |> maybe_derive_bundle_metadata()

      merged
    end)
  end

  @doc """
  Adds an experiment to settings.
  """
  def add_experiment_to_settings(name, path) do
    name_bin = :erlang.list_to_binary(String.to_charlist(name))
    path_bin = :erlang.list_to_binary(String.to_charlist(path))

    metadata =
      case RunBundleResolver.resolve(path, allow_single_nested: true) do
        {:ok, bundle} -> bundle_metadata_for_settings(bundle)
        {:error, _reason} -> %{}
      end

    if map_size(metadata) == 0 do
      :experiment_settings.add_experiment(name_bin, path_bin)
    else
      :experiment_settings.add_experiment(name_bin, path_bin, metadata)
    end
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
         {:ok, context_atom, display_name} <- ContextManager.ensure_context_alias(name),
         {:ok, _} <- :master_database.create_empty(context_atom),
         clean_path = clean_mnesia_path(path),
         {:ok, _} <- :master_database.save(context_atom, String.to_charlist(clean_path)) do
      :analyzer.unload(context_atom)
      :ok = ContextRegistry.release(display_name)
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

  defp maybe_derive_bundle_metadata(experiment) do
    already_has_bundle? =
      Enum.any?(
        [:bundle_root, :mnesia_path, :logs_path, :analytics_path, :manifest_path, :success_path],
        &Map.has_key?(experiment, &1)
      )

    if already_has_bundle? do
      experiment
    else
      case RunBundleResolver.resolve(experiment.path, allow_single_nested: true) do
        {:ok, bundle} ->
          Map.merge(experiment, bundle_metadata_for_runtime(bundle))

        {:error, _reason} ->
          experiment
      end
    end
  end

  defp bundle_metadata_from_settings(exp) do
    %{}
    |> maybe_put(:bundle_root, Map.get(exp, "bundle_root"))
    |> maybe_put(:mnesia_path, Map.get(exp, "mnesia_path"))
    |> maybe_put(:logs_path, Map.get(exp, "logs_path"))
    |> maybe_put(:analytics_path, Map.get(exp, "analytics_path"))
    |> maybe_put(:manifest_path, Map.get(exp, "manifest_path"))
    |> maybe_put(:success_path, Map.get(exp, "success_path"))
    |> maybe_put(:checkpoint_info_path, Map.get(exp, "checkpoint_info_path"))
  end

  defp bundle_metadata_for_runtime(bundle) do
    %{}
    |> maybe_put(:bundle_root, Map.get(bundle, :bundle_root))
    |> maybe_put(:mnesia_path, Map.get(bundle, :mnesia_path))
    |> maybe_put(:logs_path, Map.get(bundle, :logs_path))
    |> maybe_put(:analytics_path, Map.get(bundle, :analytics_path))
    |> maybe_put(:manifest_path, Map.get(bundle, :manifest_path))
    |> maybe_put(:success_path, Map.get(bundle, :success_path))
    |> maybe_put(:checkpoint_info_path, Map.get(bundle, :checkpoint_info_path))
  end

  defp bundle_metadata_for_settings(bundle) do
    %{}
    |> maybe_put_bin(<<"bundle_root">>, Map.get(bundle, :bundle_root))
    |> maybe_put_bin(<<"mnesia_path">>, Map.get(bundle, :mnesia_path))
    |> maybe_put_bin(<<"logs_path">>, Map.get(bundle, :logs_path))
    |> maybe_put_bin(<<"analytics_path">>, Map.get(bundle, :analytics_path))
    |> maybe_put_bin(<<"manifest_path">>, Map.get(bundle, :manifest_path))
    |> maybe_put_bin(<<"success_path">>, Map.get(bundle, :success_path))
    |> maybe_put_bin(<<"checkpoint_info_path">>, Map.get(bundle, :checkpoint_info_path))
  end

  defp maybe_put(map, _key, nil), do: map

  defp maybe_put(map, key, value) when is_binary(value) do
    Map.put(map, key, value)
  end

  defp maybe_put_bin(map, _key, nil), do: map

  defp maybe_put_bin(map, key, value) when is_binary(value) do
    Map.put(map, key, :erlang.list_to_binary(String.to_charlist(value)))
  end
end
