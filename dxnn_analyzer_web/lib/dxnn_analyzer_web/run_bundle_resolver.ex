defmodule DxnnAnalyzerWeb.RunBundleResolver do
  @moduledoc """
  Resolves a user-provided filesystem path into a DXNN run bundle.

  Supports:
  - Direct Mnesia directory paths
  - Run root directories that contain `Mnesia.nonode@nohost`
  - Parent folders containing one (or many) run directories
  """

  @mnesia_dir_name "Mnesia.nonode@nohost"
  @mnesia_suffixes [".DCD", ".DCL", ".DAT"]

  @doc """
  Resolves a path to a run bundle map.

  Returns `{:ok, bundle}` on success where bundle contains:
  - `:source_path`
  - `:bundle_root`
  - `:mnesia_path`
  - `:logs_path`
  - `:analytics_path`
  - `:manifest_path`
  - `:success_path`
  - `:checkpoint_info_path`

  Errors:
  - `{:error, {:multiple_runs_found, [paths...]}}`
  - `{:error, :no_mnesia_files}`
  - `{:error, {:path_not_accessible, [candidates...]}}`
  """
  def resolve(path, opts \\ [])

  def resolve(path, opts) when is_binary(path) do
    candidates = candidate_paths(path, opts)

    results =
      Enum.map(candidates, fn candidate ->
        {candidate, resolve_candidate(candidate, opts)}
      end)

    case Enum.find(results, fn {_candidate, result} -> match?({:ok, _}, result) end) do
      {_candidate, {:ok, bundle}} ->
        {:ok, bundle}

      nil ->
        multiple_error =
          Enum.find_value(results, fn
            {_candidate, {:error, {:multiple_runs_found, _} = reason}} -> reason
            _ -> nil
          end)

        cond do
          multiple_error ->
            {:error, multiple_error}

          Enum.any?(results, fn {_candidate, result} -> result == {:error, :no_mnesia_files} end) ->
            {:error, :no_mnesia_files}

          true ->
            {:error, {:path_not_accessible, candidates}}
        end
    end
  end

  def resolve(_path, _opts), do: {:error, :invalid_path}

  @doc """
  Determines whether a directory looks like a run root.
  """
  def run_root?(path) when is_binary(path) do
    File.dir?(path) and mnesia_dir?(Path.join(path, @mnesia_dir_name))
  end

  def run_root?(_), do: false

  defp resolve_candidate(candidate, opts) do
    if !File.dir?(candidate) do
      {:error, :path_not_accessible}
    else
      cond do
        mnesia_dir?(candidate) ->
          bundle_from_mnesia_path(candidate)

        mnesia_dir?(Path.join(candidate, @mnesia_dir_name)) ->
          bundle_from_run_root(candidate)

        true ->
          nested_candidates = discover_nested_run_roots(candidate)

          case nested_candidates do
            [] ->
              {:error, :no_mnesia_files}

            [single] ->
              if Keyword.get(opts, :allow_single_nested, true) do
                bundle_from_run_root(single)
              else
                {:error, {:multiple_runs_found, [single]}}
              end

            many ->
              {:error, {:multiple_runs_found, many}}
          end
      end
    end
  end

  defp bundle_from_mnesia_path(mnesia_path) do
    bundle_root =
      if mnesia_path |> Path.basename() |> String.starts_with?("Mnesia") do
        Path.dirname(mnesia_path)
      else
        mnesia_path
      end

    build_bundle(bundle_root, mnesia_path)
  end

  defp bundle_from_run_root(bundle_root) do
    mnesia_path = Path.join(bundle_root, @mnesia_dir_name)
    build_bundle(bundle_root, mnesia_path)
  end

  defp build_bundle(bundle_root, mnesia_path) do
    bundle_root = Path.expand(bundle_root)
    mnesia_path = Path.expand(mnesia_path)

    {:ok,
     %{
       source_path: bundle_root,
       bundle_root: bundle_root,
       mnesia_path: mnesia_path,
       logs_path: existing_dir_or_nil(Path.join(bundle_root, "logs")),
       analytics_path: existing_dir_or_nil(Path.join(bundle_root, "analytics")),
       manifest_path: existing_file_or_nil(Path.join(bundle_root, "_MANIFEST")),
       success_path: existing_file_or_nil(Path.join(bundle_root, "_SUCCESS")),
       checkpoint_info_path: existing_file_or_nil(Path.join(bundle_root, "_CHECKPOINT_INFO"))
     }}
  end

  defp discover_nested_run_roots(parent_path) do
    case File.ls(parent_path) do
      {:ok, entries} ->
        entries
        |> Enum.map(&Path.join(parent_path, &1))
        |> Enum.filter(&File.dir?/1)
        |> Enum.filter(&run_root?/1)
        |> Enum.map(&Path.expand/1)
        |> Enum.sort()

      {:error, _reason} ->
        []
    end
  end

  defp candidate_paths(path, _opts) do
    [path | container_candidates(path)]
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
  end

  defp container_candidates(path) do
    case String.split(path, "/Documents/", parts: 2) do
      ["/Users" <> _prefix, suffix] ->
        [Path.join("/app/Documents", suffix)]

      _ ->
        []
    end
  end

  defp mnesia_dir?(path) do
    File.dir?(path) and has_mnesia_files?(path)
  end

  defp has_mnesia_files?(path) do
    case File.ls(path) do
      {:ok, files} ->
        Enum.any?(files, fn file ->
          Enum.any?(@mnesia_suffixes, &String.ends_with?(file, &1))
        end)

      {:error, _reason} ->
        false
    end
  end

  defp existing_dir_or_nil(path) do
    if File.dir?(path), do: Path.expand(path), else: nil
  end

  defp existing_file_or_nil(path) do
    if File.regular?(path), do: Path.expand(path), else: nil
  end
end
