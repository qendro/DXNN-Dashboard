defmodule DxnnAnalyzerWeb.DashboardLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.AnalyzerBridge

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Start the analyzer when the first client connects
      case AnalyzerBridge.start_analyzer() do
        :ok -> :ok
        {:error, {:already_started, _}} -> :ok
        _ -> :ok
      end
    end

    socket =
      socket
      |> assign(:contexts, [])
      |> assign(:loading_path, "")
      |> assign(:loading_name, "")
      |> assign(:error, nil)
      |> load_contexts()

    {:ok, socket}
  end

  @impl true
  def handle_event("load_context", %{"path" => path, "name" => name}, socket) do
    case AnalyzerBridge.load_context(path, name) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Context '#{name}' loaded successfully")
          |> assign(:error, nil)
          |> load_contexts()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Failed to load: #{reason}")}
    end
  end

  @impl true
  def handle_event("unload_context", %{"name" => name}, socket) do
    AnalyzerBridge.unload_context(name)

    socket =
      socket
      |> put_flash(:info, "Context '#{name}' unloaded")
      |> load_contexts()

    {:noreply, socket}
  end

  @impl true
  def handle_event("load_master", _, socket) do
    master_path = "./data/MasterDatabase"
    context_name = "master"
    
    case AnalyzerBridge.load_master(master_path, context_name) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Master database loaded as context 'master'")
          |> load_contexts()
        
        {:noreply, socket}
      
      {:error, reason} ->
        socket =
          socket
          |> put_flash(:error, "Failed to load master database: #{inspect(reason)}")
        
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("refresh", _, socket) do
    {:noreply, load_contexts(socket)}
  end

  defp load_contexts(socket) do
    contexts = 
      try do
        AnalyzerBridge.list_contexts()
      rescue
        _ -> []
      catch
        :exit, _ -> []
      end
    
    assign(socket, :contexts, contexts)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-gray-900">DXNN Analyzer Dashboard</h1>
          <p class="mt-2 text-gray-600">Load and analyze DXNN trading agent populations</p>
          <div class="mt-4">
            <.link
              navigate={~p"/master"}
              class="inline-flex items-center px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700 transition"
            >
              <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 19a2 2 0 01-2-2V7a2 2 0 012-2h4l2 2h4a2 2 0 012 2v1M5 19h14a2 2 0 002-2v-5a2 2 0 00-2-2H9a2 2 0 00-2 2v5a2 2 0 01-2 2z" />
              </svg>
              View Master Database
            </.link>
          </div>
        </div>

        <%= if @error do %>
          <div class="mb-4 bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded">
            <%= @error %>
          </div>
        <% end %>

        <!-- Load Context Form -->
        <div class="bg-white shadow rounded-lg p-6 mb-8">
          <h2 class="text-xl font-semibold mb-4">Load Mnesia Context</h2>
          <form phx-submit="load_context" class="space-y-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">
                Mnesia Folder Path
              </label>
              <input
                type="text"
                name="path"
                placeholder="../DXNN-Trader-V2/DXNN-Trader-v2/Mnesia.nonode@nohost"
                class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                required
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">
                Context Name
              </label>
              <input
                type="text"
                name="name"
                placeholder="exp1"
                class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                required
              />
            </div>
            <button
              type="submit"
              class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition"
            >
              Load Context
            </button>
          </form>
        </div>

        <!-- Load Master Database -->
        <div class="bg-white shadow rounded-lg p-6 mb-8">
          <h2 class="text-xl font-semibold mb-4">Load Master Database</h2>
          <p class="text-gray-600 mb-4">Load your elite agents from the master database as a context</p>
          <button
            phx-click="load_master"
            class="bg-green-600 text-white px-4 py-2 rounded-md hover:bg-green-700 transition"
          >
            Load Master Database as Context
          </button>
        </div>

        <!-- Loaded Contexts -->
        <div class="bg-white shadow rounded-lg p-6">
          <div class="flex justify-between items-center mb-4">
            <h2 class="text-xl font-semibold">Loaded Contexts</h2>
            <button
              phx-click="refresh"
              class="text-blue-600 hover:text-blue-800 text-sm font-medium"
            >
              Refresh
            </button>
          </div>

          <%= if Enum.empty?(@contexts) do %>
            <p class="text-gray-500 text-center py-8">
              No contexts loaded. Load a Mnesia folder to get started.
            </p>
          <% else %>
            <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
              <%= for context <- @contexts do %>
                <div class="border border-gray-200 rounded-lg p-4 hover:shadow-md transition">
                  <div class="flex justify-between items-start mb-2">
                    <h3 class="font-semibold text-lg"><%= context.name %></h3>
                    <button
                      phx-click="unload_context"
                      phx-value-name={context.name}
                      class="text-red-600 hover:text-red-800 text-sm"
                    >
                      Unload
                    </button>
                  </div>
                  <p class="text-sm text-gray-600 mb-3 truncate" title={context.path}>
                    <%= context.path %>
                  </p>
                  <div class="grid grid-cols-2 gap-2 text-sm">
                    <div>
                      <span class="text-gray-500">Agents:</span>
                      <span class="font-medium ml-1"><%= context.agent_count %></span>
                    </div>
                    <div>
                      <span class="text-gray-500">Species:</span>
                      <span class="font-medium ml-1"><%= context.specie_count %></span>
                    </div>
                  </div>
                  <div class="mt-4 flex gap-2">
                    <.link
                      navigate={~p"/agents?context=#{context.name}"}
                      class="flex-1 text-center bg-blue-600 text-white px-3 py-1.5 rounded text-sm hover:bg-blue-700 transition"
                    >
                      View Agents
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
end
