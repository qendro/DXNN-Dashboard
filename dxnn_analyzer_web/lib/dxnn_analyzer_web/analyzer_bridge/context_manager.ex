defmodule DxnnAnalyzerWeb.AnalyzerBridge.ContextManager do
  @moduledoc """
  Handles context loading, unloading, and validation operations.
  """

  @doc """
  Validates that a context exists in the analyzer ETS table.
  Returns {:ok, context_atom} or {:error, reason}.
  """
  def validate_context(context) when is_binary(context) do
    context_atom = String.to_atom(context)
    validate_context(context_atom)
  end

  def validate_context(context_atom) when is_atom(context_atom) do
    case :ets.info(:analyzer_contexts) do
      :undefined ->
        {:error, "Analyzer not started"}

      _ ->
        case :ets.lookup(:analyzer_contexts, context_atom) do
          [] -> {:error, "Context '#{context_atom}' not loaded"}
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
  Loads a context from a Mnesia database path.
  """
  def load_context(path, context_name) do
    path_charlist = String.to_charlist(path)
    # Handle both string and atom inputs
    context_atom = if is_atom(context_name), do: context_name, else: String.to_atom(context_name)

    :analyzer.load(path_charlist, context_atom)
  end

  @doc """
  Unloads a context from memory.
  """
  def unload_context(context_name) do
    context_atom = String.to_atom(context_name)
    :analyzer.unload(context_atom)
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
end
