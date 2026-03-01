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
              navigate={~p"/settings"}
              class="bg-gray-600 text-white px-4 py-2 rounded-md hover:bg-gray-700 transition"
            >
              ⚙️ Manage Experiments
            </.link>
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
                  </div>
                  <.link
                    navigate={~p"/agents?context=#{experiment.name}"}
                    class="block text-center bg-blue-600 text-white px-3 py-2 rounded-md text-sm hover:bg-blue-700 transition"
                  >
                    View Agents
                  </.link>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
