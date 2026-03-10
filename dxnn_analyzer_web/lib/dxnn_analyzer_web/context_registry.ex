defmodule DxnnAnalyzerWeb.ContextRegistry do
  @moduledoc """
  Keeps a bounded mapping between user-visible context names and internal analyzer atoms.

  This prevents unbounded atom creation by allocating from a fixed slot pool.
  Also stores optional run-bundle metadata (logs/analytics paths, manifest pointers).
  """

  use GenServer

  @name __MODULE__
  @default_max_contexts 512

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  def register(display_name, bundle \\ %{}) when is_binary(display_name) do
    GenServer.call(@name, {:register, display_name, bundle})
  end

  def resolve(context) when is_binary(context) or is_atom(context) do
    GenServer.call(@name, {:resolve, context})
  end

  def release(context) when is_binary(context) or is_atom(context) do
    GenServer.call(@name, {:release, context})
  end

  def put_bundle(context, bundle) when is_map(bundle) do
    GenServer.call(@name, {:put_bundle, context, bundle})
  end

  def get_bundle(context) when is_binary(context) or is_atom(context) do
    GenServer.call(@name, {:get_bundle, context})
  end

  def display_name_for_atom(atom) when is_atom(atom) do
    GenServer.call(@name, {:display_name_for_atom, atom})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    max_contexts = Keyword.get(opts, :max_contexts, @default_max_contexts)

    slots =
      1..max_contexts
      |> Enum.map(&slot_atom/1)

    {:ok,
     %{
       available_slots: slots,
       name_to_atom: %{},
       atom_to_name: %{},
       bundles: %{}
     }}
  end

  @impl true
  def handle_call({:register, display_name, bundle}, _from, state) do
    clean_name = String.trim(display_name)

    cond do
      clean_name == "" ->
        {:reply, {:error, :invalid_context_name}, state}

      Map.has_key?(state.name_to_atom, clean_name) ->
        atom = Map.fetch!(state.name_to_atom, clean_name)

        next_state =
          if map_size(bundle) == 0 do
            state
          else
            put_in(state, [:bundles, clean_name], bundle)
          end

        {:reply, {:ok, atom, :existing}, next_state}

      state.available_slots == [] ->
        {:reply, {:error, :context_limit_reached}, state}

      true ->
        [atom | remaining_slots] = state.available_slots

        next_state =
          state
          |> put_in([:available_slots], remaining_slots)
          |> put_in([:name_to_atom, clean_name], atom)
          |> put_in([:atom_to_name, atom], clean_name)
          |> maybe_put_bundle(clean_name, bundle)

        {:reply, {:ok, atom, :new}, next_state}
    end
  end

  def handle_call({:resolve, context}, _from, state) do
    {:reply, resolve_context(context, state), state}
  end

  def handle_call({:release, context}, _from, state) do
    case resolve_context(context, state) do
      {:ok, atom, display_name} ->
        next_state =
          state
          |> update_in([:name_to_atom], &Map.delete(&1, display_name))
          |> update_in([:atom_to_name], &Map.delete(&1, atom))
          |> update_in([:bundles], &Map.delete(&1, display_name))
          |> update_in([:available_slots], fn slots -> [atom | slots] |> Enum.uniq() end)

        {:reply, :ok, next_state}

      {:error, _reason} ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:put_bundle, context, bundle}, _from, state) do
    case resolve_context(context, state) do
      {:ok, _atom, display_name} ->
        next_state = put_in(state, [:bundles, display_name], bundle)
        {:reply, :ok, next_state}

      {:error, :context_not_registered} when is_binary(context) ->
        case handle_call({:register, context, bundle}, self(), state) do
          {:reply, {:ok, _atom, _status}, updated_state} ->
            {:reply, :ok, updated_state}

          {:reply, {:error, reason}, updated_state} ->
            {:reply, {:error, reason}, updated_state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_bundle, context}, _from, state) do
    bundle =
      case resolve_context(context, state) do
        {:ok, _atom, display_name} -> Map.get(state.bundles, display_name)
        {:error, _reason} -> nil
      end

    {:reply, bundle, state}
  end

  def handle_call({:display_name_for_atom, atom}, _from, state) do
    {:reply, Map.get(state.atom_to_name, atom), state}
  end

  # Internal helpers

  defp resolve_context(context, state) when is_binary(context) do
    case Map.fetch(state.name_to_atom, context) do
      {:ok, atom} -> {:ok, atom, context}
      :error ->
        find_slot_name_match(context, state)
    end
  end

  defp resolve_context(context, state) when is_atom(context) do
    case Map.fetch(state.atom_to_name, context) do
      {:ok, display_name} -> {:ok, context, display_name}
      :error -> {:error, :context_not_registered}
    end
  end

  defp maybe_put_bundle(state, _display_name, bundle) when map_size(bundle) == 0, do: state

  defp maybe_put_bundle(state, display_name, bundle) do
    put_in(state, [:bundles, display_name], bundle)
  end

  defp find_slot_name_match(context, state) do
    match =
      Enum.find(state.atom_to_name, fn {atom, _name} ->
        Atom.to_string(atom) == context
      end)

    case match do
      {atom, display_name} -> {:ok, atom, display_name}
      nil -> {:error, :context_not_registered}
    end
  end

  defp slot_atom(index), do: String.to_atom("ctx_slot_#{index}")
end
