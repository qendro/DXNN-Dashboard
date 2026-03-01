defmodule DxnnAnalyzerWeb.AgentListLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.AnalyzerBridge

  @impl true
  def mount(_params, _session, socket) do
    contexts = AnalyzerBridge.list_contexts()

    socket =
      socket
      |> assign(:contexts, contexts)
      |> assign(:selected_context, nil)
      |> assign(:agents, [])
      |> assign(:loading, false)
      |> assign(:selected_agents, MapSet.new())
      |> assign(:show_best_only, false)
      |> assign(:best_count, 10)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    context = params["context"]

    socket =
      if context do
        socket
        |> assign(:selected_context, context)
        |> load_agents(context)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_context", %{"context" => context}, socket) do
    {:noreply, push_patch(socket, to: ~p"/agents?context=#{context}")}
  end

  @impl true
  def handle_event("toggle_agent", %{"id" => id_str}, socket) do
    # Find the actual agent by id_string
    agent = Enum.find(socket.assigns.agents, fn a -> a.id_string == id_str end)
    
    if agent do
      selected = socket.assigns.selected_agents
      agent_id = agent.id  # Use the actual Erlang tuple ID

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
  def handle_event("toggle_best", %{"value" => value}, socket) do
    show_best = value == "true"
    socket = assign(socket, :show_best_only, show_best)

    socket =
      if socket.assigns.selected_context do
        load_agents(socket, socket.assigns.selected_context)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_best_count", %{"count" => count}, socket) do
    {count_int, _} = Integer.parse(count)
    socket = assign(socket, :best_count, count_int)

    socket =
      if socket.assigns.show_best_only && socket.assigns.selected_context do
        load_agents(socket, socket.assigns.selected_context)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("compare_selected", _, socket) do
    if MapSet.size(socket.assigns.selected_agents) < 2 do
      {:noreply, put_flash(socket, :error, "Select at least 2 agents to compare")}
    else
      agent_ids = MapSet.to_list(socket.assigns.selected_agents)
      context = socket.assigns.selected_context
      {:noreply, push_navigate(socket, to: ~p"/compare?context=#{context}&ids=#{encode_ids(agent_ids)}")}
    end
  end

  @impl true
  def handle_event("save_to_master", _, socket) do
    if MapSet.size(socket.assigns.selected_agents) == 0 do
      {:noreply, put_flash(socket, :error, "No agents selected")}
    else
      agent_ids = MapSet.to_list(socket.assigns.selected_agents)
      context = socket.assigns.selected_context

      IO.puts("=== Save to Master Debug ===")
      IO.puts("Selected agents count: #{length(agent_ids)}")
      IO.puts("Context: #{inspect(context)}")
      IO.puts("Agent IDs: #{inspect(agent_ids)}")

      # Create or use existing master context
      master_context = "master"
      
      # Try to create empty master context (will return existing if already exists)
      case AnalyzerBridge.create_empty_master(master_context) do
        {:ok, _} ->
          IO.puts("Master context ready")
        {:error, reason} ->
          IO.puts("Error with master context: #{inspect(reason)}")
      end
      
      # Add agents to master context
      case AnalyzerBridge.add_to_master(agent_ids, context, master_context) do
        {:ok, count} ->
          IO.puts("Successfully added #{count} agents")
          
          # Save master context to disk
          case AnalyzerBridge.save_master(master_context, "./data/MasterDatabase") do
            {:ok, _path} ->
              socket =
                socket
                |> assign(:selected_agents, MapSet.new())
                |> put_flash(:info, "Successfully added #{count} agent(s) to master database and saved to disk")

              {:noreply, socket}
            
            {:error, save_reason} ->
              IO.puts("Error saving master: #{inspect(save_reason)}")
              # Still consider it a success since agents were added to context
              socket =
                socket
                |> assign(:selected_agents, MapSet.new())
                |> put_flash(:info, "Added #{count} agent(s) to master context (save to disk failed: #{inspect(save_reason)})")
              
              {:noreply, socket}
          end

        {:error, reason} ->
          IO.puts("Error adding to master: #{inspect(reason)}")
          {:noreply, put_flash(socket, :error, "Failed to add agents: #{inspect(reason)}")}
      end
    end
  end

  defp load_agents(socket, context) do
    socket = assign(socket, :loading, true)

    result = if socket.assigns.show_best_only do
      AnalyzerBridge.find_best(socket.assigns.best_count, context: context)
    else
      AnalyzerBridge.list_agents(context: context)
    end

    case result do
      {:error, reason} ->
        socket
        |> assign(:agents, [])
        |> assign(:loading, false)
        |> put_flash(:error, "Failed to load agents: #{reason}")
      
      agents when is_list(agents) ->
        socket
        |> assign(:agents, agents)
        |> assign(:loading, false)
        |> clear_flash()
    end
  end

  defp encode_ids(ids) do
    ids
    |> Enum.map(&inspect/1)
    |> Enum.join(",")
    |> URI.encode()
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
          <h1 class="text-3xl font-bold text-gray-900">Agent List</h1>
        </div>

        <!-- Context Selector -->
        <div class="bg-white shadow rounded-lg p-6 mb-6">
          <label class="block text-sm font-medium text-gray-700 mb-2">Select Context</label>
          <select
            phx-change="select_context"
            name="context"
            class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          >
            <option value="">-- Select a context --</option>
            <%= for context <- @contexts do %>
              <option value={context.name} selected={context.name == @selected_context}>
                <%= context.name %> (<%= context.agent_count %> agents)
              </option>
            <% end %>
          </select>
        </div>

        <%= if @selected_context do %>
          <!-- Filters -->
          <div class="bg-white shadow rounded-lg p-6 mb-6">
            <div class="flex items-center gap-6">
              <div class="flex items-center">
                <input
                  type="checkbox"
                  id="show-best"
                  phx-click="toggle_best"
                  phx-value-value={!@show_best_only}
                  checked={@show_best_only}
                  class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
                />
                <label for="show-best" class="ml-2 text-sm text-gray-700">
                  Show best agents only
                </label>
              </div>

              <%= if @show_best_only do %>
                <div class="flex items-center gap-2">
                  <label class="text-sm text-gray-700">Count:</label>
                  <input
                    type="number"
                    value={@best_count}
                    phx-change="update_best_count"
                    name="count"
                    min="1"
                    max="100"
                    class="w-20 px-2 py-1 border border-gray-300 rounded-md text-sm"
                  />
                </div>
              <% end %>
            </div>
          </div>

          <!-- Selected Actions -->
          <%= if MapSet.size(@selected_agents) > 0 do %>
            <div class="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-6">
              <div class="flex justify-between items-center">
                <span class="text-sm text-blue-900">
                  <%= MapSet.size(@selected_agents) %> agent(s) selected
                </span>
                <div class="flex gap-2">
                  <button
                    phx-click="save_to_master"
                    class="bg-green-600 text-white px-4 py-2 rounded-md hover:bg-green-700 transition text-sm"
                  >
                    Save to Master Database
                  </button>
                  <button
                    phx-click="compare_selected"
                    class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition text-sm"
                  >
                    Compare Selected
                  </button>
                </div>
              </div>
            </div>
          <% end %>

          <!-- Agent List -->
          <div class="bg-white shadow rounded-lg overflow-hidden">
            <%= if @loading do %>
              <div class="p-8 text-center text-gray-500">Loading agents...</div>
            <% else %>
              <%= if Enum.empty?(@agents) do %>
                <div class="p-8 text-center text-gray-500">No agents found</div>
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
                        Neurons
                      </th>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Sensors
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
                          <%= Float.round(agent.fitness, 4) %>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                          <%= agent.generation %>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                          <%= agent.encoding_type %>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                          <%= agent.neuron_count %>
                        </td>
                        <td class="px-6 py-4 text-sm text-gray-900">
                          <div class="max-w-xs truncate" title={Enum.join(agent.sensors, ", ")}>
                            <%= Enum.join(agent.sensors, ", ") %>
                          </div>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm">
                          <.link
                            navigate={~p"/agents/#{URI.encode(agent.id_string)}?context=#{@selected_context}"}
                            class="text-blue-600 hover:text-blue-800 mr-3"
                          >
                            Inspect
                          </.link>
                          <.link
                            navigate={~p"/graph/#{URI.encode(agent.id_string)}?context=#{@selected_context}"}
                            class="text-indigo-600 hover:text-indigo-800 mr-3"
                          >
                            Graph
                          </.link>
                          <.link
                            navigate={~p"/topology/#{URI.encode(agent.id_string)}?context=#{@selected_context}"}
                            class="text-green-600 hover:text-green-800"
                          >
                            Topology
                          </.link>
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
