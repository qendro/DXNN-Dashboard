defmodule DxnnAnalyzerWeb.AWS.S3Explorer do
  @moduledoc """
  S3 Explorer module for browsing, downloading, and deleting S3 objects.
  """

  @doc """
  List objects in an S3 bucket at the given prefix/path.
  Returns folders and files separately.
  """
  def list_objects(bucket, prefix \\ "") do
    # Ensure prefix ends with / if not empty
    prefix =
      if prefix != "" && !String.ends_with?(prefix, "/") do
        prefix <> "/"
      else
        prefix
      end

    case System.cmd(
           "aws",
           [
             "s3api",
             "list-objects-v2",
             "--bucket",
             bucket,
             "--prefix",
             prefix,
             "--delimiter",
             "/",
             "--output",
             "json"
           ],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        parse_s3_listing(output, prefix)

      {error, _} ->
        {:error, error}
    end
  end

  @doc """
  Download selected S3 objects to local path.
  Handles both individual files and folders.
  """
  def download_objects(bucket, keys, local_path) do
    File.mkdir_p!(local_path)

    results =
      Enum.map(keys, fn key ->
        s3_uri = "s3://#{bucket}/#{key}"
        target_path = Path.join(local_path, Path.basename(key))

        # Check if it's a folder (ends with /)
        if String.ends_with?(key, "/") do
          # Sync entire folder
          case System.cmd(
                 "aws",
                 [
                   "s3",
                   "sync",
                   s3_uri,
                   target_path,
                   "--no-progress"
                 ],
                 stderr_to_stdout: true
               ) do
            {_, 0} -> {:ok, target_path}
            {error, _} -> {:error, error}
          end
        else
          # Copy single file
          case System.cmd(
                 "aws",
                 [
                   "s3",
                   "cp",
                   s3_uri,
                   target_path
                 ],
                 stderr_to_stdout: true
               ) do
            {_, 0} -> {:ok, target_path}
            {error, _} -> {:error, error}
          end
        end
      end)

    # Check if all succeeded
    errors =
      Enum.filter(results, fn
        {:error, _} -> true
        _ -> false
      end)

    if length(errors) > 0 do
      {:error, "Some downloads failed"}
    else
      {:ok, local_path}
    end
  end

  @doc """
  Build a ZIP archive for selected S3 keys and return the local archive path.
  Preserves folder structure relative to the current path in S3 Explorer.
  """
  def build_download_archive(bucket, keys, current_path \\ "") when is_list(keys) do
    unique_id = System.unique_integer([:positive, :monotonic])
    workspace = Path.join(System.tmp_dir!(), "dxnn_s3_download_#{unique_id}")
    content_dir = Path.join(workspace, "content")

    with :ok <- File.mkdir_p(content_dir),
         :ok <- download_keys_to_content(bucket, keys, current_path, content_dir),
         {:ok, archive_path, archive_name} <- create_archive(workspace, content_dir) do
      {:ok,
       %{
         archive_path: archive_path,
         archive_name: archive_name,
         cleanup_path: workspace
       }}
    else
      {:error, reason} ->
        File.rm_rf(workspace)
        {:error, reason}
    end
  end

  @doc """
  Delete selected S3 objects.
  Handles both individual files and folders (recursive delete).
  """
  def delete_objects(bucket, keys) do
    results =
      Enum.map(keys, fn key ->
        s3_uri = "s3://#{bucket}/#{key}"

        # Check if it's a folder (ends with /)
        if String.ends_with?(key, "/") do
          # Recursive delete for folder
          case System.cmd(
                 "aws",
                 [
                   "s3",
                   "rm",
                   s3_uri,
                   "--recursive"
                 ],
                 stderr_to_stdout: true
               ) do
            {_, 0} -> {:ok, key}
            {error, _} -> {:error, error}
          end
        else
          # Delete single file
          case System.cmd(
                 "aws",
                 [
                   "s3",
                   "rm",
                   s3_uri
                 ],
                 stderr_to_stdout: true
               ) do
            {_, 0} -> {:ok, key}
            {error, _} -> {:error, error}
          end
        end
      end)

    # Check if all succeeded
    errors =
      Enum.filter(results, fn
        {:error, _} -> true
        _ -> false
      end)

    if length(errors) > 0 do
      {:error, "Some deletions failed: #{inspect(errors)}"}
    else
      {:ok, "Deleted #{length(keys)} item(s)"}
    end
  end

  @doc """
  Get metadata for a specific S3 object.
  """
  def get_object_metadata(bucket, key) do
    case System.cmd(
           "aws",
           [
             "s3api",
             "head-object",
             "--bucket",
             bucket,
             "--key",
             key,
             "--output",
             "json"
           ],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, metadata} -> {:ok, metadata}
          {:error, _} -> {:error, "Invalid metadata format"}
        end

      {error, _} ->
        {:error, error}
    end
  end

  @doc """
  List all available buckets.
  """
  def list_buckets do
    case System.cmd(
           "aws",
           [
             "s3api",
             "list-buckets",
             "--output",
             "json"
           ],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, %{"Buckets" => buckets}} ->
            bucket_list =
              Enum.map(buckets, fn bucket ->
                %{
                  name: bucket["Name"],
                  created_at: bucket["CreationDate"]
                }
              end)

            {:ok, bucket_list}

          {:error, _} ->
            {:error, "Invalid response format"}
        end

      {error, _} ->
        {:error, error}
    end
  end

  @doc """
  Generate a presigned URL for direct browser download.
  """
  def generate_download_url(bucket, key, expires_in \\ 3600) do
    case System.cmd(
           "aws",
           [
             "s3",
             "presign",
             "s3://#{bucket}/#{key}",
             "--expires-in",
             "#{expires_in}"
           ],
           stderr_to_stdout: true
         ) do
      {url, 0} -> {:ok, String.trim(url)}
      {error, _} -> {:error, error}
    end
  end

  @doc """
  Download S3 objects directly to local filesystem without zipping.
  Preserves folder structure relative to current path.
  """
  def download_to_local(bucket, keys, target_path, current_path \\ "") when is_list(keys) do
    with :ok <- validate_target_path(target_path),
         :ok <- File.mkdir_p(target_path) do
      base_prefix = normalize_prefix(current_path)
      
      results = Enum.map(keys, fn key ->
        relative_key = relative_key(key, base_prefix)
        download_key_to_local(bucket, key, relative_key, target_path)
      end)
      
      errors = Enum.filter(results, &match?({:error, _}, &1))
      
      if length(errors) > 0 do
        {:error, "Some downloads failed: #{inspect(errors)}"}
      else
        success_count = length(results)
        {:ok, %{count: success_count, path: target_path}}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Upload a temporary file to S3 for download (used for zips).
  Returns a presigned URL.
  """
  def upload_temp_file(local_path, s3_key, bucket \\ "dxnn-checkpoints") do
    s3_uri = "s3://#{bucket}/#{s3_key}"

    case System.cmd(
           "aws",
           [
             "s3",
             "cp",
             local_path,
             s3_uri
           ],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        # Generate presigned URL
        generate_download_url(bucket, s3_key)

      {error, _} ->
        {:error, error}
    end
  end

  # Private helper functions

  defp parse_s3_listing(json, prefix) do
    case Jason.decode(json) do
      {:ok, data} ->
        folders = parse_common_prefixes(data["CommonPrefixes"] || [], prefix)
        files = parse_contents(data["Contents"] || [], prefix)

        # Combine and sort: folders first, then files
        items = folders ++ files
        {:ok, items}

      {:error, _} ->
        {:error, "Failed to parse S3 response"}
    end
  end

  defp parse_common_prefixes(prefixes, current_prefix) do
    Enum.map(prefixes, fn %{"Prefix" => prefix} ->
      # Extract just the folder name (remove current prefix and trailing /)
      name =
        prefix
        |> String.replace_prefix(current_prefix, "")
        |> String.trim_trailing("/")

      %{
        key: prefix,
        name: name,
        type: :folder,
        size: nil,
        last_modified: nil
      }
    end)
  end

  defp parse_contents(contents, current_prefix) do
    contents
    |> Enum.reject(fn item ->
      # Skip the prefix itself if it appears as an object
      item["Key"] == current_prefix
    end)
    |> Enum.map(fn item ->
      # Extract just the file name (remove current prefix)
      name = String.replace_prefix(item["Key"], current_prefix, "")

      # Parse last modified date
      last_modified =
        case DateTime.from_iso8601(item["LastModified"]) do
          {:ok, dt, _} -> dt
          _ -> nil
        end

      %{
        key: item["Key"],
        name: name,
        type: :file,
        size: item["Size"],
        last_modified: last_modified
      }
    end)
  end

  defp download_keys_to_content(bucket, keys, current_path, content_dir) do
    base_prefix = normalize_prefix(current_path)

    keys
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn key, :ok ->
      relative_key = relative_key(key, base_prefix)

      case download_key(bucket, key, relative_key, content_dir) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp download_key(bucket, key, relative_key, content_dir) do
    s3_uri = "s3://#{bucket}/#{key}"

    if String.ends_with?(key, "/") do
      folder_relative = String.trim_trailing(relative_key, "/")

      with {:ok, folder_path} <- safe_join(content_dir, folder_relative),
           :ok <- File.mkdir_p(folder_path) do
        case System.cmd("aws", ["s3", "sync", s3_uri, folder_path, "--no-progress"],
               stderr_to_stdout: true
             ) do
          {_, 0} -> :ok
          {error, _} -> {:error, "Failed to sync #{key}: #{String.trim(error)}"}
        end
      end
    else
      with {:ok, file_path} <- safe_join(content_dir, relative_key),
           :ok <- File.mkdir_p(Path.dirname(file_path)) do
        case System.cmd("aws", ["s3", "cp", s3_uri, file_path, "--no-progress"],
               stderr_to_stdout: true
             ) do
          {_, 0} -> :ok
          {error, _} -> {:error, "Failed to copy #{key}: #{String.trim(error)}"}
        end
      end
    end
  end

  defp create_archive(workspace, content_dir) do
    files =
      content_dir
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: true)
      |> Enum.reject(&File.dir?/1)
      |> Enum.map(&Path.relative_to(&1, content_dir))

    if files == [] do
      {:error, "Selected items contain no files to download"}
    else
      timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d_%H%M%S")
      archive_name = "s3_download_#{timestamp}.zip"
      archive_path = Path.join(workspace, archive_name)

      zip_files = Enum.map(files, &String.to_charlist/1)
      zip_path = String.to_charlist(archive_path)
      zip_cwd = String.to_charlist(content_dir)

      case :zip.create(zip_path, zip_files, [{:cwd, zip_cwd}]) do
        {:ok, _archive_file} -> {:ok, archive_path, archive_name}
        {:error, reason} -> {:error, "Failed to create ZIP archive: #{inspect(reason)}"}
      end
    end
  end

  defp normalize_prefix(""), do: ""

  defp normalize_prefix(prefix) when is_binary(prefix) do
    trimmed = String.trim_leading(prefix, "/")

    if String.ends_with?(trimmed, "/") do
      trimmed
    else
      trimmed <> "/"
    end
  end

  defp relative_key(key, ""), do: String.trim_leading(key, "/")

  defp relative_key(key, base_prefix) do
    cleaned_key = String.trim_leading(key, "/")

    relative =
      if String.starts_with?(cleaned_key, base_prefix) do
        String.replace_prefix(cleaned_key, base_prefix, "")
      else
        cleaned_key
      end

    if relative == "" do
      Path.basename(String.trim_trailing(cleaned_key, "/"))
    else
      relative
    end
  end

  defp safe_join(base_dir, relative_path) do
    safe_relative =
      relative_path
      |> String.replace("\\", "/")
      |> String.trim_leading("/")

    expanded_base = Path.expand(base_dir)
    expanded = Path.expand(safe_relative, expanded_base)

    if expanded == expanded_base || String.starts_with?(expanded, expanded_base <> "/") do
      {:ok, expanded}
    else
      {:error, "Invalid key path: #{relative_path}"}
    end
  end

  defp validate_target_path(path) do
    cond do
      !File.dir?(path) && !File.exists?(path) ->
        # Path doesn't exist, will try to create it
        :ok
      
      File.dir?(path) ->
        # Path exists and is a directory
        case File.stat(path) do
          {:ok, %{access: access}} when access in [:read_write, :write] ->
            :ok
          {:ok, _} ->
            {:error, "Path is not writable: #{path}"}
          {:error, reason} ->
            {:error, "Cannot access path: #{inspect(reason)}"}
        end
      
      true ->
        {:error, "Path exists but is not a directory: #{path}"}
    end
  end

  defp download_key_to_local(bucket, key, relative_key, target_path) do
    s3_uri = "s3://#{bucket}/#{key}"

    if String.ends_with?(key, "/") do
      # Download folder
      folder_relative = String.trim_trailing(relative_key, "/")
      
      with {:ok, folder_path} <- safe_join(target_path, folder_relative),
           :ok <- File.mkdir_p(folder_path) do
        case System.cmd("aws", ["s3", "sync", s3_uri, folder_path, "--no-progress"],
               stderr_to_stdout: true
             ) do
          {_, 0} -> {:ok, folder_path}
          {error, _} -> {:error, "Failed to sync #{key}: #{String.trim(error)}"}
        end
      end
    else
      # Download file
      with {:ok, file_path} <- safe_join(target_path, relative_key),
           :ok <- File.mkdir_p(Path.dirname(file_path)) do
        case System.cmd("aws", ["s3", "cp", s3_uri, file_path, "--no-progress"],
               stderr_to_stdout: true
             ) do
          {_, 0} -> {:ok, file_path}
          {error, _} -> {:error, "Failed to copy #{key}: #{String.trim(error)}"}
        end
      end
    end
  end
end
