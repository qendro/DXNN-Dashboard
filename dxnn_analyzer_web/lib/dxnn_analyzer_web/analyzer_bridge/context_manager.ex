defmodule DxnnAnalyzerWeb.AnalyzerBridge.ContextManager do
  @moduledoc """
  Handles context loading, unloading, and validation operations.
  """

  alias DxnnAnalyzerWeb.{ContextRegistry, RunBundleResolver}

  @doc """
  Validates that a context exists in the analyzer ETS table.
  Returns {:ok, context_atom} or {:error, reason}.
  """
  def validate_context(context) when is_binary(context) or is_atom(context) do
    with {:ok, context_atom, display_name} <- resolve_context_ref(context),
         :ok <- ensure_analyzer_started() do
      case :ets.lookup(:analyzer_contexts, context_atom) do
        [] -> {:error, "Context '#{display_name}' not loaded"}
        [record] -> {:ok, context_atom, record}
      end
    end
  end

  @doc """
  Validates that two contexts exist.
  """
  def validate_contexts(source_context, target_context) do
    with {:ok, source_atom, _} <- validate_context(source_context),
         {:ok, target_atom, _} <- validate_context(target_context) do
      {:ok, source_atom, target_atom}
    end
  end

  @doc """
  Allocates or returns a bounded internal atom for a user-visible context name.
  """
  def ensure_context_alias(context_name) when is_binary(context_name) or is_atom(context_name) do
    display_name = normalize_context_name(context_name)

    case ContextRegistry.register(display_name) do
      {:ok, context_atom, _status} ->
        {:ok, context_atom, display_name}

      {:error, :context_limit_reached} ->
        {:error, "Context limit reached. Unload existing contexts before loading more."}

      {:error, :invalid_context_name} ->
        {:error, "Context name cannot be empty"}

      {:error, reason} ->
        {:error, "Failed to allocate context alias: #{inspect(reason)}"}
    end
  end

  @doc """
  Resolves a context to internal atom and display name.
  """
  def resolve_context_ref(context) when is_binary(context) or is_atom(context) do
    do_resolve_context_ref(context)
  end

  @doc """
  Loads a context from a Mnesia database path or run bundle root path.
  """
  def load_context(path, context_name) do
    with {:ok, bundle} <- RunBundleResolver.resolve(path, allow_single_nested: true),
         {:ok, context_atom, display_name} <- ensure_context_alias(context_name) do
      case ensure_analyzer_started() do
        :ok ->
          if loaded?(context_atom) do
            context_bundle = Map.put(bundle, :context_name, display_name)
            :ok = ContextRegistry.put_bundle(display_name, context_bundle)
            {:error, {:already_loaded, context_atom}}
          else
            path_charlist = String.to_charlist(bundle.mnesia_path)
            result = :analyzer.load(path_charlist, context_atom)

            case result do
              {:ok, _context} ->
                context_bundle = Map.put(bundle, :context_name, display_name)
                :ok = ContextRegistry.put_bundle(display_name, context_bundle)
                result

              {:error, reason} ->
                :ok = ContextRegistry.release(display_name)
                {:error, reason}
            end
          end

        {:error, reason} ->
          :ok = ContextRegistry.release(display_name)
          {:error, reason}
      end
    end
  end

  @doc """
  Unloads a context from memory.
  """
  def unload_context(context_name) do
    with {:ok, context_atom, display_name} <- do_resolve_context_ref(context_name) do
      result = :analyzer.unload(context_atom)

      case result do
        :ok ->
          :ok = ContextRegistry.release(display_name)
          :ok

        {:error, _context_not_found} ->
          :ok = ContextRegistry.release(display_name)
          :ok

        other ->
          other
      end
    end
  end

  @doc """
  Lists all loaded contexts.
  """
  def list_contexts do
    :analyzer.list_contexts()
  end

  @doc """
  Lists all master database contexts.
  """
  def list_master_contexts do
    :master_database.list_contexts()
  end

  @doc """
  Gets artifact metadata (logs/analytics/manifest pointers) for a loaded context.
  """
  def get_context_artifacts(context) do
    with {:ok, context_atom, record} <- validate_context(context) do
      existing_bundle = ContextRegistry.get_bundle(context_atom) || %{}
      inferred_bundle = infer_bundle_from_record(context_atom, record)

      bundle =
        inferred_bundle
        |> maybe_restore_source_path(existing_bundle)

      :ok = ContextRegistry.put_bundle(context_atom, bundle)

      {:ok, bundle}
    end
  end

  defp do_resolve_context_ref(context) do
    case ContextRegistry.resolve(normalize_context_name(context)) do
      {:ok, context_atom, display_name} ->
        {:ok, context_atom, display_name}

      {:error, :context_not_registered} ->
        resolve_context_from_ets(context)

      {:error, reason} ->
        {:error, "Failed to resolve context: #{inspect(reason)}"}
    end
  end

  defp resolve_context_from_ets(context) do
    with :ok <- ensure_analyzer_started() do
      display_name = normalize_context_name(context)

      contexts = :ets.tab2list(:analyzer_contexts)

      match =
        Enum.find(contexts, fn record ->
          context_atom = elem(record, 1)
          Atom.to_string(context_atom) == display_name
        end)

      case match do
        nil ->
          {:error, "Context '#{display_name}' not loaded"}

        record ->
          context_atom = elem(record, 1)
          {:ok, context_atom, display_name}
      end
    end
  end

  defp infer_bundle_from_record(context_atom, record) do
    mnesia_path = record |> elem(2) |> to_string()

    bundle_root =
      if mnesia_path |> Path.basename() |> String.starts_with?("Mnesia") do
        Path.dirname(mnesia_path)
      else
        mnesia_path
      end

    inferred_bundle = %{
      context_name: ContextRegistry.display_name_for_atom(context_atom) || Atom.to_string(context_atom),
      source_path: bundle_root,
      bundle_root: bundle_root,
      mnesia_path: mnesia_path,
      logs_path: existing_dir_or_nil(Path.join(bundle_root, "logs")),
      analytics_path: existing_dir_or_nil(Path.join(bundle_root, "analytics")),
      manifest_path: existing_file_or_nil(Path.join(bundle_root, "_MANIFEST")),
      success_path: existing_file_or_nil(Path.join(bundle_root, "_SUCCESS")),
      checkpoint_info_path: existing_file_or_nil(Path.join(bundle_root, "_CHECKPOINT_INFO"))
    }

    :ok = ContextRegistry.put_bundle(context_atom, inferred_bundle)
    inferred_bundle
  end

  defp maybe_restore_source_path(bundle, existing_bundle) do
    source_path = Map.get(existing_bundle, :source_path) || Map.get(existing_bundle, "source_path")

    case source_path do
      nil -> bundle
      path -> Map.put(bundle, :source_path, path)
    end
  end

  defp normalize_context_name(context_name) when is_binary(context_name), do: String.trim(context_name)
  defp normalize_context_name(context_name) when is_atom(context_name), do: Atom.to_string(context_name)

  defp loaded?(context_atom) do
    case :ets.info(:analyzer_contexts) do
      :undefined -> false
      _ -> :ets.lookup(:analyzer_contexts, context_atom) != []
    end
  end

  defp ensure_analyzer_started do
    case :ets.info(:analyzer_contexts) do
      :undefined -> {:error, "Analyzer not started"}
      _ -> :ok
    end
  end

  defp existing_dir_or_nil(path) do
    if File.dir?(path), do: Path.expand(path), else: nil
  end

  defp existing_file_or_nil(path) do
    if File.regular?(path), do: Path.expand(path), else: nil
  end
end
