defmodule DxnnAnalyzerWeb.ExperimentCopier do
  @moduledoc """
  Handles copying DXNN-Trader-v2 experiments to the dashboard database.
  
  Copies the following from source:
  - Mnesia.nonode@nohost/ (complete database)
  - logs/ (all experiment logs)
  - config.erl (experiment configuration)
  - exp_runner.erl (experiment runner)
  
  Creates a timestamped folder in the destination directory.
  """

  require Logger

  @doc """
  Copies an experiment from source to destination.
  
  Returns:
  - {:ok, new_path} on success
  - {:error, reason} on failure
  """
  def copy_experiment(source_path, destination_base) do
    with :ok <- validate_source_directory(source_path),
         :ok <- validate_source_files(source_path),
         {:ok, destination_path} <- create_destination_directory(destination_base),
         :ok <- copy_all_files(source_path, destination_path),
         :ok <- create_metadata_files(destination_path, source_path) do
      Logger.info("Successfully copied experiment from #{source_path} to #{destination_path}")
      {:ok, destination_path}
    else
      {:error, reason} ->
        Logger.error("Copy failed: #{inspect(reason)}")
        {:error, format_error(reason)}
    end
  rescue
    e in File.Error ->
      Logger.error("File error during copy: #{inspect(e)}")
      {:error, "File operation failed: #{e.reason}"}
    
    e ->
      Logger.error("Unexpected error during copy: #{inspect(e)}")
      {:error, "Unexpected error occurred"}
  end

  # Private functions

  defp validate_source_directory(path) do
    if File.dir?(path), do: :ok, else: {:error, "Source path is not a directory"}
  end

  defp validate_source_files(source_path) do
    required = [
      {"Mnesia.nonode@nohost", &File.dir?/1},
      {"logs", &File.dir?/1},
      {"config.erl", &File.exists?/1},
      {"exp_runner.erl", &File.exists?/1}
    ]

    missing = 
      required
      |> Enum.reject(fn {name, check_fn} ->
        source_path |> Path.join(name) |> check_fn.()
      end)
      |> Enum.map(fn {name, _} -> name end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_files, missing}}
    end
  end

  defp copy_all_files(source_path, destination_path) do
    with :ok <- copy_mnesia(source_path, destination_path),
         :ok <- copy_logs(source_path, destination_path),
         :ok <- copy_config_files(source_path, destination_path) do
      :ok
    end
  end

  defp create_destination_directory(base_path) do
    with :ok <- File.mkdir_p(base_path) do
      timestamp = 
        DateTime.utc_now()
        |> DateTime.to_iso8601()
        |> String.replace(":", "-")
        |> String.split(".")
        |> List.first()

      folder_name = "#{timestamp}_experiment_run1"
      destination_path = Path.join(base_path, folder_name)
      final_path = ensure_unique_path(destination_path)
      
      case File.mkdir_p(final_path) do
        :ok -> {:ok, final_path}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp ensure_unique_path(path) do
    if File.exists?(path) do
      base = String.replace(path, ~r/_run\d+$/, "")
      
      run_number = 
        2
        |> Stream.iterate(&(&1 + 1))
        |> Enum.find(&(not File.exists?("#{base}_run#{&1}")))
      
      "#{base}_run#{run_number}"
    else
      path
    end
  end

  defp copy_mnesia(source_path, destination_path) do
    Logger.info("Copying Mnesia database...")
    copy_directory(source_path, destination_path, "Mnesia.nonode@nohost")
  end

  defp copy_logs(source_path, destination_path) do
    Logger.info("Copying logs...")
    copy_directory(source_path, destination_path, "logs")
  end

  defp copy_config_files(source_path, destination_path) do
    ["config.erl", "exp_runner.erl"]
    |> Enum.reduce_while(:ok, fn file, :ok ->
      Logger.info("Copying #{file}...")
      source_file = Path.join(source_path, file)
      dest_file = Path.join(destination_path, file)
      
      case File.cp(source_file, dest_file) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp copy_directory(source_path, destination_path, dir_name) do
    source_dir = Path.join(source_path, dir_name)
    dest_dir = Path.join(destination_path, dir_name)
    copy_directory_recursive(source_dir, dest_dir)
  end

  defp copy_directory_recursive(source, destination) do
    with :ok <- File.mkdir_p(destination),
         {:ok, items} <- File.ls(source) do
      Enum.reduce_while(items, :ok, fn item, :ok ->
        source_item = Path.join(source, item)
        dest_item = Path.join(destination, item)

        result = 
          if File.dir?(source_item) do
            copy_directory_recursive(source_item, dest_item)
          else
            File.cp(source_item, dest_item)
          end

        case result do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp create_metadata_files(destination_path, source_path) do
    success_content = Jason.encode!(%{
      status: "copied",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      source: source_path,
      copied_by: "DXNN-Dashboard"
    }, pretty: true)

    manifest_content = """
    Mnesia.nonode@nohost/
    logs/
    config.erl
    exp_runner.erl
    _SUCCESS
    _MANIFEST
    """

    with :ok <- File.write(Path.join(destination_path, "_SUCCESS"), success_content),
         :ok <- File.write(Path.join(destination_path, "_MANIFEST"), manifest_content) do
      Logger.info("Created metadata files")
      :ok
    end
  end

  defp format_error({:missing_files, files}) do
    "Missing required files: #{Enum.join(files, ", ")}"
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
