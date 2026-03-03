defmodule DxnnAnalyzerWeb.AnalyzerBridge.StatisticsOperations do
  @moduledoc """
  Handles statistics and context inspection operations.
  """

  alias DxnnAnalyzerWeb.AnalyzerBridge.ContextManager

  @doc """
  Collects statistics for a context.
  """
  def get_stats(context) do
    with {:ok, context_atom, _} <- ContextManager.validate_context(context) do
      result = :stats_collector.collect_stats(context_atom)
      {:ok, result}
    end
  end

  @doc """
  Gets all populations in a context.
  """
  def get_populations(context) do
    with {:ok, context_atom, _} <- ContextManager.validate_context(context) do
      case :context_inspector.get_populations(context_atom) do
        {:ok, populations} -> {:ok, populations}
        {:error, reason} -> {:error, reason}
        other -> {:error, "Unexpected result: #{inspect(other)}"}
      end
    end
  end

  @doc """
  Gets all species in a context.
  """
  def get_species(context) do
    with {:ok, context_atom, _} <- ContextManager.validate_context(context) do
      case :context_inspector.get_species(context_atom) do
        {:ok, species} -> {:ok, species}
        {:error, reason} -> {:error, reason}
        other -> {:error, "Unexpected result: #{inspect(other)}"}
      end
    end
  end

  @doc """
  Gets a specific population.
  """
  def get_population(population_id, context) do
    with {:ok, context_atom, _} <- ContextManager.validate_context(context) do
      result = :context_inspector.get_population(population_id, context_atom)
      {:ok, result}
    end
  end

  @doc """
  Gets a specific specie.
  """
  def get_specie(specie_id, context) do
    with {:ok, context_atom, _} <- ContextManager.validate_context(context) do
      result = :context_inspector.get_specie(specie_id, context_atom)
      {:ok, result}
    end
  end
end
