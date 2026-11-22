defmodule DxnnAnalyzerWeb.AgentId do
  @moduledoc "Parses displayed agent IDs as literal data, without evaluating URL input."

  def parse(value) when is_binary(value) and byte_size(value) <= 1024 do
    with {:ok, ast} <- Code.string_to_quoted(value, existing_atoms_only: true),
         {:ok, id} <- literal(ast),
         true <- is_tuple(id) do
      {:ok, id}
    else
      _ -> {:error, "Invalid agent ID"}
    end
  end

  def parse(_), do: {:error, "Invalid agent ID"}

  def parse_many(value) when is_binary(value) and byte_size(value) <= 10_240 do
    # Existing comparison URLs contain comma-separated tuples, including commas inside each ID.
    with {:ok, entries} when is_list(entries) <-
           Code.string_to_quoted("[" <> value <> "]", existing_atoms_only: true),
         true <- length(entries) in 2..10 do
      Enum.reduce_while(entries, {:ok, []}, fn ast, {:ok, ids} ->
        case literal(ast) do
          {:ok, id} when is_tuple(id) -> {:cont, {:ok, [id | ids]}}
          _ -> {:halt, {:error, "Invalid agent IDs"}}
        end
      end)
      |> case do
        {:ok, ids} -> {:ok, Enum.reverse(ids)}
        error -> error
      end
    else
      _ -> {:error, "Select between 2 and 10 valid agents to compare"}
    end
  end

  def parse_many(_), do: {:error, "Invalid agent IDs"}

  defp literal(value) when is_number(value) or is_atom(value), do: {:ok, value}

  defp literal({sign, _, [number]}) when sign in [:+, :-] and is_number(number),
    do: {:ok, if(sign == :-, do: -number, else: number)}

  defp literal({:{}, _, entries}), do: tuple(entries)
  defp literal({left, right}), do: tuple([left, right])
  defp literal(_), do: {:error, :not_literal}

  defp tuple(entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, values} ->
      case literal(entry) do
        {:ok, value} -> {:cont, {:ok, [value | values]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, values |> Enum.reverse() |> List.to_tuple()}
      error -> error
    end
  end
end
