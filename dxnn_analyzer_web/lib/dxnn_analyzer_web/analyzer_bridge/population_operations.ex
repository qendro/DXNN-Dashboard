defmodule DxnnAnalyzerWeb.AnalyzerBridge.PopulationOperations do
  @moduledoc """
  Handles population creation and management.
  """

  alias DxnnAnalyzerWeb.AnalyzerBridge.ContextManager

  @doc """
  Creates a new population from selected agents.
  """
  def create_population(agent_ids, pop_name, output_path, opts \\ []) do
    with {:ok, context_atom, _} <- validate_context_from_opts(opts) do
      pop_name_atom = String.to_atom(pop_name)
      output_charlist = String.to_charlist(output_path)
      erlang_opts = convert_opts_to_erlang(opts, context_atom)

      :analyzer.create_population(agent_ids, pop_name_atom, output_charlist, erlang_opts)
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
