defmodule DxnnAnalyzerWeb.AnalyzerBridge.AgentOperations do
  @moduledoc """
  Handles agent-related operations: listing, inspection, comparison, and topology.
  """

  alias DxnnAnalyzerWeb.AnalyzerBridge.ContextManager

  @doc """
  Lists agents with optional filters.
  """
  def list_agents(opts) do
    with {:ok, context_atom, _} <- validate_context_from_opts(opts) do
      erlang_opts = convert_opts_to_erlang(opts, context_atom)
      result = :analyzer.list_agents(erlang_opts)
      {:ok, result}
    end
  end

  @doc """
  Finds the best N agents.
  """
  def find_best(count, opts) do
    if Keyword.has_key?(opts, :context) do
      with {:ok, context_atom, _} <- validate_context_from_opts(opts) do
        erlang_opts = convert_opts_to_erlang(opts, context_atom)
        result = :analyzer.find_best(count, erlang_opts)
        {:ok, result}
      end
    else
      erlang_opts = Enum.reject(opts, fn {key, _value} -> key == :context end)
      result = :analyzer.find_best(count, erlang_opts)
      {:ok, result}
    end
  end

  @doc """
  Inspects a single agent.
  """
  def inspect_agent(agent_id, context) do
    with {:ok, context_atom, _} <- ContextManager.validate_context(context) do
      result = :agent_inspector.inspect_agent(agent_id, context_atom)
      {:ok, result}
    end
  end

  @doc """
  Gets the full topology of an agent.
  """
  def get_topology(agent_id, context) do
    with {:ok, context_atom, _} <- ContextManager.validate_context(context) do
      result = :agent_inspector.get_full_topology(agent_id, context_atom)
      {:ok, result}
    end
  end

  @doc """
  Compares multiple agents.
  """
  def compare_agents(agent_ids, context) do
    with {:ok, context_atom, _} <- ContextManager.validate_context(context) do
      result = :analyzer.compare(agent_ids, context_atom)
      {:ok, result}
    end
  end

  @doc """
  Deletes agents from a context.
  """
  def delete_agents(agent_ids, context) do
    with {:ok, context_atom, context_record} <- ContextManager.validate_context(context) do
      agent_table = String.to_atom("#{context_atom}_agent")

      deleted_count =
        Enum.reduce(agent_ids, 0, fn agent_id, count ->
          if :ets.delete(agent_table, agent_id), do: count + 1, else: count
        end)

      # Update agent count in context record
      old_count = elem(context_record, 4)
      new_count = max(0, old_count - deleted_count)
      updated_context = :erlang.setelement(5, context_record, new_count)
      :ets.insert(:analyzer_contexts, updated_context)

      {:ok, deleted_count}
    end
  end

  # Private helpers

  defp validate_context_from_opts(opts) do
    case Keyword.get(opts, :context) do
      nil -> {:error, "No context specified"}
      context -> ContextManager.validate_context(context)
    end
  end

  defp convert_opts_to_erlang(opts, context_atom) do
    Enum.map(opts, fn
      {:context, _val} -> {:context, context_atom}
      {key, val} -> {key, val}
    end)
  end
end
