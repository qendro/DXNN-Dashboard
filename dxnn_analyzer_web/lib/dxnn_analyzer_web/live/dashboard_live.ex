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
    experiments = AnalyzerBridge.get_experiments_from_settings()
    
    results = Enum.map(experiments, fn exp ->
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
    AnalyzerBridge.unload_context(name)

    socket =
      socket
      |> put_flash(:info, "Experiment '#{name}' unloaded")
      |> load_experiments()

    {:noreply, socket}
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
    
    assign(socket, :experiments, experiments)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="mb-8 flex justify-between items-center">
          <div>
            <h1 class="text-3xl font-bold text-gray-900">DXNN Analyzer Dashboard</h1>
            <p class="mt-2 text-gray-600">View and manage loaded experiments</p>
          </div>
          <div class="flex gap-2">
            <.link
              navigate={~p"/analytics"}
              class="bg-indigo-600 text-white px-4 py-2 rounded-md hover:bg-indigo-700 transition"
            >
              📊 Analytics
            </.link>
            <.link
              navigate={~p"/s3-experiments"}
              class="bg-green-600 text-white px-4 py-2 rounded-md hover:bg-green-700 transition"
            >
              📦 S3 Experiments
            </.link>
            <.link
              navigate={~p"/s3-explorer"}
              class="bg-teal-600 text-white px-4 py-2 rounded-md hover:bg-teal-700 transition"
            >
              🗂️ S3 Explorer
            </.link>
            <.link
              navigate={~p"/aws-deployment"}
              class="bg-purple-600 text-white px-4 py-2 rounded-md hover:bg-purple-700 transition"
            >
              ☁️ AWS Deployment
            </.link>
            <.link
              navigate={~p"/settings"}
              class="bg-gray-600 text-white px-4 py-2 rounded-md hover:bg-gray-700 transition"
            >
              ⚙️ Manage Experiments
            </.link>
            <button
              phx-click="load_all_experiments"
              class="bg-green-600 text-white px-4 py-2 rounded-md hover:bg-green-700 transition"
            >
              📂 Load All
            </button>
            <button
              phx-click="refresh"
              class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition"
            >
              🔄 Refresh
            </button>
          </div>
        </div>

        <!-- Loaded Experiments -->
        <div class="bg-white shadow rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-6">Loaded Experiments</h2>
          
          <%= if Enum.empty?(@experiments) do %>
            <div class="text-center py-12">
              <p class="text-gray-500 mb-4">No experiments loaded</p>
              <.link
                navigate={~p"/settings"}
                class="inline-block bg-blue-600 text-white px-6 py-3 rounded-md hover:bg-blue-700 transition"
              >
                Go to Settings to Load Experiments
              </.link>
            </div>
          <% else %>
            <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
              <%= for experiment <- @experiments do %>
                <div class="border-2 border-gray-200 rounded-lg p-4 hover:shadow-lg transition">
                  <div class="flex justify-between items-start mb-2">
                    <h3 class="font-semibold text-lg"><%= experiment.name %></h3>
                    <button
                      phx-click="unload_experiment"
                      phx-value-name={experiment.name}
                      class="text-red-600 hover:text-red-800 text-sm font-bold"
                    >
                      ✕
                    </button>
                  </div>
                  <div class="text-sm text-gray-600 mb-3">
                    <div>Agents: <span class="font-medium"><%= experiment.agent_count %></span></div>
                    <div>Species: <span class="font-medium"><%= experiment.specie_count %></span></div>
                    <div class="mt-2 flex flex-wrap gap-1">
                      <span class="inline-flex bg-gray-100 text-gray-700 px-2 py-0.5 rounded text-xs">
                        Mnesia
                      </span>
                      <%= if experiment.logs_path do %>
                        <span class="inline-flex bg-blue-100 text-blue-700 px-2 py-0.5 rounded text-xs">
                          logs
                        </span>
                      <% end %>
                      <%= if experiment.analytics_path do %>
                        <span class="inline-flex bg-indigo-100 text-indigo-700 px-2 py-0.5 rounded text-xs">
                          analytics
                        </span>
                      <% end %>
                    </div>
                  </div>
                  <div class="grid grid-cols-2 gap-2">
                    <.link
                      navigate={~p"/agents?context=#{experiment.name}"}
                      class="block text-center bg-blue-600 text-white px-3 py-2 rounded-md text-sm hover:bg-blue-700 transition"
                    >
                      Agents
                    </.link>
                    <.link
                      navigate={~p"/contexts/#{experiment.name}/artifacts"}
                      class="block text-center bg-slate-700 text-white px-3 py-2 rounded-md text-sm hover:bg-slate-800 transition"
                    >
                      Artifacts
                    </.link>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
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
