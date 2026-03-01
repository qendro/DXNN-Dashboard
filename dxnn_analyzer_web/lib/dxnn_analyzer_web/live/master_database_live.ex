defmodule DxnnAnalyzerWeb.MasterDatabaseLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.AnalyzerBridge

  @default_master_context "master"
  @default_master_path "./data/MasterDatabase"

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:master_context, @default_master_context)
      |> assign(:master_path, @default_master_path)
      |> assign(:agents, [])
      |> assign(:loading, false)
      |> assign(:selected_agents, MapSet.new())
      |> assign(:initialized, false)
      |> assign(:error, nil)
      |> check_and_load_master()

    {:ok, socket}
  end

  @impl true
  def handle_event("init_master", %{"path" => path}, socket) do
    # Create empty master context
    case AnalyzerBridge.create_empty_master(@default_master_context) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:master_path, path)
          |> assign(:initialized, true)
          |> assign(:error, nil)
          |> put_flash(:info, "Master database context created")
          |> load_agents()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Failed to initialize: #{reason}")}
    end
  end

  @impl true
  def handle_event("refresh", _, socket) do
    {:noreply, load_agents(socket)}
  end

  @impl true
  def handle_event("toggle_agent", %{"id" => id_str}, socket) do
    agent = Enum.find(socket.assigns.agents, fn a -> a.id_string == id_str end)
    
    if agent do
      selected = socket.assigns.selected_agents
      agent_id = agent.id

      selected =
        if MapSet.member?(selected, agent_id) do
          MapSet.delete(selected, agent_id)
        else
          MapSet.put(selected, agent_id)
        end

      {:noreply, assign(socket, :selected_agents, selected)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_to_disk", _, socket) do
    master_context = socket.assigns.master_context
    master_path = socket.assigns.master_path
    
    case AnalyzerBridge.save_master(master_context, master_path) do
      {:ok, _path} ->
        socket =
          socket
          |> put_flash(:info, "Master database saved to #{master_path}")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save: #{reason}")}
    end
  end

  @impl true
  def handle_event("load_as_context", %{"name" => context_name}, socket) do
    master_path = socket.assigns.master_path
    
    case AnalyzerBridge.load_master(master_path, context_name) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Master database loaded as context '#{context_name}'")
          |> push_navigate(to: ~p"/agents?context=#{context_name}")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to load as context: #{reason}")}
    end
  end

  defp check_and_load_master(socket) do
    master_path = socket.assigns.master_path
    master_context = socket.assigns.master_context

    # Try to load existing master database
    case AnalyzerBridge.load_master(master_path, master_context) do
      {:ok, _} ->
        socket
        |> assign(:initialized, true)
        |> load_agents()

      {:error, _reason} ->
        # Master doesn't exist yet, create empty context
        case AnalyzerBridge.create_empty_master(master_context) do
          {:ok, _} ->
            socket
            |> assign(:initialized, true)
            |> assign(:agents, [])
          
          {:error, _} ->
            assign(socket, :initialized, false)
        end
    end
  end

  defp load_agents(socket) do
    if socket.assigns.initialized do
      socket = assign(socket, :loading, true)
      master_context = socket.assigns.master_context

      # Use standard analyzer list_agents with master context
      case AnalyzerBridge.list_agents(context: master_context) do
        agents when is_list(agents) ->
          sorted_agents = Enum.sort_by(agents, & &1.fitness, :desc)

          socket
          |> assign(:agents, sorted_agents)
          |> assign(:loading, false)
          |> clear_flash()

        {:error, reason} ->
          socket
          |> assign(:agents, [])
          |> assign(:loading, false)
          |> put_flash(:error, "Failed to load agents: #{reason}")
      end
    else
      socket
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="mb-6">
          <.link navigate={~p"/"} class="text-blue-600 hover:text-blue-800 text-sm mb-2 inline-block">
            ← Back to Dashboard
          </.link>
          <h1 class="text-3xl font-bold text-gray-900">Master Database</h1>
          <p class="mt-2 text-gray-600">
            Your curated collection of elite agents from all experiments
          </p>
        </div>

        <%= if @error do %>
          <div class="mb-4 bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded">
            <%= @error %>
          </div>
        <% end %>

        <%= if !@initialized do %>
          <!-- Initialize Master Database -->
          <div class="bg-white shadow rounded-lg p-6 mb-6">
            <h2 class="text-xl font-semibold mb-4">Initialize Master Database</h2>
            <form phx-submit="init_master" class="space-y-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">
                  Master Database Path
                </label>
                <input
                  type="text"
                  name="path"
                  value={@master_path}
                  class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                  required
                />
                <p class="mt-1 text-sm text-gray-500">
                  This will create a new Mnesia database to store your selected agents
                </p>
              </div>
              <button
                type="submit"
                class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition"
              >
                Initialize Master Database
              </button>
            </form>
          </div>
        <% else %>
          <!-- Master Database Info -->
          <div class="bg-white shadow rounded-lg p-6 mb-6">
            <div class="flex justify-between items-center">
              <div>
                <h2 class="text-xl font-semibold">Database Location</h2>
                <p class="text-sm text-gray-600 mt-1"><%= @master_path %></p>
                <p class="text-sm text-gray-500 mt-2">
                  Total Agents: <span class="font-semibold"><%= length(@agents) %></span>
                </p>
              </div>
              <div class="flex gap-2">
                <button
                  phx-click="refresh"
                  class="text-blue-600 hover:text-blue-800 text-sm font-medium px-4 py-2 border border-blue-600 rounded-md"
                >
                  Refresh
                </button>
                <form phx-submit="load_as_context" class="inline">
                  <input
                    type="text"
                    name="name"
                    placeholder="Context name"
                    class="px-3 py-2 border border-gray-300 rounded-md text-sm mr-2"
                    required
                  />
                  <button
                    type="submit"
                    class="bg-green-600 text-white px-4 py-2 rounded-md hover:bg-green-700 transition text-sm"
                  >
                    Load as Context
                  </button>
                </form>
              </div>
            </div>
          </div>

          <!-- Selected Actions -->
          <%= if MapSet.size(@selected_agents) > 0 do %>
            <div class="bg-red-50 border border-red-200 rounded-lg p-4 mb-6">
              <div class="flex justify-between items-center">
                <span class="text-sm text-red-900">
                  <%= MapSet.size(@selected_agents) %> agent(s) selected
                </span>
                <button
                  phx-click="remove_selected"
                  class="bg-red-600 text-white px-4 py-2 rounded-md hover:bg-red-700 transition text-sm"
                >
                  Remove Selected
                </button>
              </div>
            </div>
          <% end %>

          <!-- Agent List -->
          <div class="bg-white shadow rounded-lg overflow-hidden">
            <%= if @loading do %>
              <div class="p-8 text-center text-gray-500">Loading agents...</div>
            <% else %>
              <%= if Enum.empty?(@agents) do %>
                <div class="p-8 text-center">
                  <p class="text-gray-500 mb-4">No agents in master database yet</p>
                  <.link
                    navigate={~p"/agents"}
                    class="text-blue-600 hover:text-blue-800 font-medium"
                  >
                    Go to Agent List to add agents →
                  </.link>
                </div>
              <% else %>
                <table class="min-w-full divide-y divide-gray-200">
                  <thead class="bg-gray-50">
                    <tr>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Select
                      </th>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Agent ID
                      </th>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Fitness
                      </th>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Generation
                      </th>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Type
                      </th>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Population
                      </th>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Actions
                      </th>
                    </tr>
                  </thead>
                  <tbody class="bg-white divide-y divide-gray-200">
                    <%= for agent <- @agents do %>
                      <tr class="hover:bg-gray-50">
                        <td class="px-6 py-4 whitespace-nowrap">
                          <input
                            type="checkbox"
                            phx-click="toggle_agent"
                            phx-value-id={agent.id_string}
                            checked={MapSet.member?(@selected_agents, agent.id)}
                            class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
                          />
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm font-mono text-gray-900">
                          <%= inspect(agent.id) %>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                          <span class="font-semibold text-green-600">
                            <%= Float.round(agent.fitness, 4) %>
                          </span>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                          <%= agent.generation %>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                          <%= agent.encoding_type %>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                          <%= inspect(agent.population_id) %>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm">
                          <span class="text-gray-400">View in context</span>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              <% end %>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
