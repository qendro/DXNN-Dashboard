defmodule DxnnAnalyzerWeb.DashboardLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.AnalyzerBridge

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      case AnalyzerBridge.start_analyzer() do
        :ok -> :ok
        {:error, {:already_started, _}} -> :ok
        _ -> :ok
      end
    end

    socket =
      socket
      |> assign(:experiments, [])
      |> load_experiments()

    {:ok, socket}
  end

  @impl true
  def handle_event("load_all_experiments", _, socket) do
    loaded_names = MapSet.new(socket.assigns.experiments, &to_string(&1.name))

    experiments =
      AnalyzerBridge.get_experiments_from_settings()
      |> Enum.reject(&MapSet.member?(loaded_names, &1.name))

    results =
      Enum.map(experiments, fn exp ->
        case AnalyzerBridge.load_context(exp.path, exp.name) do
          {:ok, _} -> {:ok, exp.name}
          {:error, {:already_loaded, _}} -> {:ok, exp.name}
          {:error, reason} -> {:error, exp.name, reason}
        end
      end)

    success_count = Enum.count(results, fn r -> match?({:ok, _}, r) end)
    total_count = length(experiments)

    socket =
      socket
      |> load_experiments()
      |> maybe_put_load_all_error(results)
      |> put_flash(:info, "Loaded #{success_count} of #{total_count} experiments")

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _, socket) do
    {:noreply, load_experiments(socket)}
  end

  @impl true
  def handle_event("unload_experiment", %{"name" => name}, socket) do
    socket =
      case AnalyzerBridge.unload_context(name) do
        :ok ->
          put_flash(socket, :info, "Experiment '#{name}' unloaded")

        {:error, reason} ->
          put_flash(socket, :error, "Could not unload experiment: #{inspect(reason)}")
      end

    {:noreply, load_experiments(socket)}
  end

  defp load_experiments(socket) do
    experiments =
      try do
        AnalyzerBridge.list_contexts()
      rescue
        _ -> []
      catch
        :exit, _ -> []
      end

    loaded_names = MapSet.new(experiments, &to_string(&1.name))

    loadable_count =
      AnalyzerBridge.get_experiments_from_settings()
      |> Enum.count(&(not MapSet.member?(loaded_names, &1.name)))

    socket
    |> assign(:experiments, experiments)
    |> assign(:loadable_count, loadable_count)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="page-container">
      <.page_header title="Dashboard" description="View and manage your loaded experiments.">
        <:actions>
          <button phx-click="refresh" phx-disable-with="Refreshing…" class="btn btn-secondary">
            Refresh
          </button>
          <.link navigate={~p"/settings"} class="btn btn-primary">Manage experiments</.link>
        </:actions>
      </.page_header>

      <section class="panel" aria-labelledby="loaded-experiments-title">
        <div class="panel-heading">
          <div class="flex items-center gap-3">
            <h2 id="loaded-experiments-title" class="section-title">Loaded experiments</h2>
            <span class="badge"><%= length(@experiments) %></span>
          </div>
          <button
            phx-click="load_all_experiments"
            phx-disable-with="Loading…"
            class="btn btn-secondary btn-sm"
            disabled={@loadable_count == 0}
          >
            Load saved experiments
          </button>
        </div>

        <%= if Enum.empty?(@experiments) do %>
          <div class="empty-state">
            <div class="mb-4 rounded-xl border border-slate-200 bg-slate-50 p-3 text-slate-400">
              <.icon name="flask" class="h-6 w-6" />
            </div>
            <h3 class="text-sm font-semibold text-slate-900">No experiments loaded</h3>
            <p class="mt-2 max-w-sm text-sm leading-6 text-slate-500">
              Add or load an experiment to explore its agents, logs, and analytics.
            </p>
            <.link
              navigate={~p"/settings"}
              class="mt-5 text-sm font-medium text-blue-700 hover:text-blue-800"
            >
              Browse experiments <span aria-hidden="true">→</span>
            </.link>
          </div>
        <% else %>
          <div class="grid gap-4 p-5 md:grid-cols-2 xl:grid-cols-3">
            <article :for={experiment <- @experiments} class="experiment-card">
              <h3 class="break-words text-sm font-semibold leading-6"><%= experiment.name %></h3>
              <dl class="my-5 grid grid-cols-2 gap-4">
                <div>
                  <dt class="text-xs text-slate-500">Agents</dt>
                  <dd class="mt-1 text-2xl font-semibold tabular-nums">
                    <%= experiment.agent_count %>
                  </dd>
                </div>
                <div>
                  <dt class="text-xs text-slate-500">Species</dt>
                  <dd class="mt-1 text-2xl font-semibold tabular-nums">
                    <%= experiment.specie_count %>
                  </dd>
                </div>
              </dl>
              <div class="mb-5 flex flex-wrap gap-1.5">
                <span class="badge">Mnesia</span>
                <span :if={experiment.logs_path} class="badge">Logs</span>
                <span :if={experiment.analytics_path} class="badge">Analytics</span>
              </div>
              <div class="page-actions mt-auto border-t border-slate-100 pt-4">
                <.link
                  navigate={~p"/agents?context=#{experiment.name}"}
                  class="btn btn-secondary btn-sm"
                >
                  View agents
                </.link>
                <.link
                  navigate={~p"/contexts/#{experiment.name}/artifacts"}
                  class="btn btn-secondary btn-sm"
                >
                  Artifacts
                </.link>
                <button
                  phx-click="unload_experiment"
                  phx-value-name={experiment.name}
                  data-confirm={"Unload #{experiment.name}? Files on disk will be kept."}
                  aria-label={"Unload #{experiment.name}"}
                  class="btn btn-danger btn-sm ml-auto"
                >
                  Unload
                </button>
              </div>
            </article>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  defp maybe_put_load_all_error(socket, results) do
    failures =
      results
      |> Enum.filter(fn
        {:error, _, _} -> true
        _ -> false
      end)
      |> Enum.take(3)

    case failures do
      [] ->
        socket

      failed ->
        sample =
          Enum.map_join(failed, "; ", fn {:error, exp_name, reason} ->
            "#{exp_name}: #{format_load_error(reason)}"
          end)

        put_flash(socket, :error, "Some experiments failed to load: #{sample}")
    end
  end

  defp format_load_error({:path_not_accessible, candidate_paths}) do
    "path not accessible from dashboard container (tried: #{Enum.join(candidate_paths, ", ")})"
  end

  defp format_load_error({:multiple_runs_found, run_paths}) do
    sample =
      run_paths
      |> Enum.take(3)
      |> Enum.join(", ")

    "multiple runs found. Select a specific run folder. Examples: #{sample}"
  end

  defp format_load_error(:no_mnesia_files) do
    "no Mnesia files found at the configured path"
  end

  defp format_load_error({:schema_node_mismatch, owner_nodes, current_node}) do
    "Mnesia schema belongs to #{inspect(owner_nodes)} but dashboard node is #{inspect(current_node)}"
  end

  defp format_load_error(reason), do: inspect(reason)
end
