defmodule DxnnAnalyzerWeb.GraphViewerLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.{AgentId, AnalyzerBridge}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     assign(socket,
       agent_id: URI.decode(id),
       context: nil,
       graph: nil,
       error: nil,
       selected_edge: nil,
       selected_node_id: nil,
       graph_layout: "hierarchical"
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    context = params["context"]
    socket = assign(socket, context: context, graph: nil, error: nil)

    result =
      with true <- is_binary(context) and context != "",
           {:ok, agent_id} <- AgentId.parse(socket.assigns.agent_id) do
        AnalyzerBridge.get_topology_graph(agent_id, context)
      else
        false -> {:error, "Choose an experiment from the dashboard first"}
        error -> error
      end

    socket =
      case result do
        data when is_map(data) -> assign(socket, :graph, data)
        {:error, reason} -> assign(socket, :error, "Could not load graph: #{inspect(reason)}")
        _ -> assign(socket, :error, "Could not load graph")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_node", %{"node_id" => node_id}, socket) do
    {:noreply, assign(socket, selected_node_id: node_id, selected_edge: nil)}
  end

  @impl true
  def handle_event(
        "select_edge",
        %{"source" => source, "target" => target, "weight" => weight, "recurrent" => recurrent},
        socket
      ) do
    edge_info = %{
      source: source,
      target: target,
      weight: weight,
      recurrent: recurrent,
      source_node: get_node_by_id(socket.assigns.graph, source),
      target_node: get_node_by_id(socket.assigns.graph, target)
    }

    {:noreply, assign(socket, selected_edge: edge_info, selected_node_id: nil)}
  end

  @impl true
  def handle_event("change_layout", %{"layout" => layout}, socket) do
    {:noreply, assign(socket, :graph_layout, layout)}
  end

  @impl true
  def handle_event("close_details", _params, socket) do
    {:noreply, assign(socket, selected_node_id: nil, selected_edge: nil)}
  end

  defp get_node_by_id(graph, node_id) do
    if graph && graph.nodes do
      Enum.find(graph.nodes, fn n -> n.id == node_id end)
    else
      nil
    end
  end

  defp get_selected_node(assigns) do
    if assigns[:selected_node_id] && assigns[:graph] do
      Enum.find(assigns.graph.nodes, fn n -> n.id == assigns.selected_node_id end)
    else
      nil
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:selected_node, fn -> get_selected_node(assigns) end)
      |> assign_new(:selected_edge, fn -> nil end)
      |> assign_new(:graph, fn -> nil end)
      |> assign_new(:context, fn -> nil end)

    ~H"""
    <div class="min-w-0">
      <div class="page-container">
        <!-- Header -->
        <div class="mb-6">
          <.link
            navigate={if @context, do: ~p"/agents/#{@agent_id}?context=#{@context}", else: ~p"/"}
            class="text-blue-600 hover:text-blue-800 text-sm mb-2 inline-block"
          >
            ← <%= if @context, do: "Back to agent", else: "Back to dashboard" %>
          </.link>
          <div class="flex justify-between items-start">
            <div>
              <h1 class="page-title">Neural Network Graph</h1>
              <p class="text-gray-600 mt-1">Agent: <%= @agent_id %></p>
            </div>
            <%= if @graph do %>
              <div class="page-actions">
                <select
                  phx-change="change_layout"
                  name="layout"
                  class="px-4 py-2 border border-gray-300 rounded-md bg-white"
                >
                  <option value="hierarchical" selected={@graph_layout == "hierarchical"}>
                    Hierarchical
                  </option>
                  <option value="force" selected={@graph_layout == "force"}>Force-Directed</option>
                  <option value="circular" selected={@graph_layout == "circular"}>Circular</option>
                </select>
              </div>
            <% end %>
          </div>
        </div>

        <%= if @error do %>
          <div class="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded mb-6">
            <%= @error %>
          </div>
        <% end %>

        <%= if @graph do %>
          <!-- Stats Bar -->
          <div class="panel p-4 mb-6">
            <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div class="text-center">
                <div class="text-2xl font-bold text-blue-600">
                  <%= @graph.stats.sensor_count %>
                </div>
                <div class="text-sm text-gray-600">Sensors</div>
              </div>
              <div class="text-center">
                <div class="text-2xl font-bold text-green-600">
                  <%= @graph.stats.neuron_count %>
                </div>
                <div class="text-sm text-gray-600">Neurons</div>
              </div>
              <div class="text-center">
                <div class="text-2xl font-bold text-purple-600">
                  <%= @graph.stats.actuator_count %>
                </div>
                <div class="text-sm text-gray-600">Actuators</div>
              </div>
              <div class="text-center">
                <div class="text-2xl font-bold text-orange-600">
                  <%= @graph.stats.connection_count %>
                </div>
                <div class="text-sm text-gray-600">Connections</div>
              </div>
            </div>
          </div>
          <!-- Main Graph Container -->
          <div class="panel overflow-hidden">
            <div class="relative">
              <!-- Graph Canvas -->
              <div
                id="graph-container"
                phx-hook="NetworkGraph"
                phx-update="ignore"
                data-graph={Jason.encode!(@graph)}
                data-layout={@graph_layout}
                class="w-full bg-gray-50"
                style="height: 600px;"
              >
                <svg id="network-svg" class="w-full h-full"></svg>
              </div>
              <!-- Legend -->
              <div class="absolute top-4 left-4 bg-white bg-opacity-90 rounded-lg shadow p-4">
                <h3 class="text-sm font-semibold mb-2">Legend</h3>
                <div class="space-y-2 text-xs">
                  <div class="flex items-center gap-2">
                    <div class="w-4 h-4 rounded-full bg-blue-500"></div>
                    <span>Sensor</span>
                  </div>
                  <div class="flex items-center gap-2">
                    <div class="w-4 h-4 rounded-full bg-green-500"></div>
                    <span>Neuron</span>
                  </div>
                  <div class="flex items-center gap-2">
                    <div class="w-4 h-4 rounded-full bg-purple-500"></div>
                    <span>Actuator</span>
                  </div>
                  <div class="border-t border-gray-300 my-2"></div>
                  <div class="flex items-center gap-2">
                    <svg width="20" height="4">
                      <line x1="0" y1="2" x2="20" y2="2" stroke="#94a3b8" stroke-width="2" />
                    </svg>
                    <span>Connection</span>
                  </div>
                  <div class="flex items-center gap-2">
                    <svg width="20" height="4">
                      <line
                        x1="0"
                        y1="2"
                        x2="20"
                        y2="2"
                        stroke="#94a3b8"
                        stroke-width="2"
                        stroke-dasharray="3,3"
                      />
                    </svg>
                    <span>Self-loop</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
          <!-- Layer Information -->
          <%= if length(@graph.layers) > 0 do %>
            <div class="panel p-6 mt-6">
              <h2 class="section-title mb-4">Layer Structure</h2>
              <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                <%= for layer <- @graph.layers do %>
                  <div class="border border-gray-200 rounded-lg p-4">
                    <div class="text-lg font-semibold text-gray-900">
                      Layer <%= layer.layer %>
                    </div>
                    <div class="text-sm text-gray-600 mt-1">
                      <%= layer.neuron_count %> neurons
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
          <!-- Node Details Sidebar -->
          <%= if @selected_node do %>
            <div class="fixed inset-y-0 right-0 w-96 bg-white shadow-2xl transform transition-transform duration-300 ease-in-out z-50 overflow-y-auto">
              <div class="p-6">
                <div class="flex justify-between items-start mb-4">
                  <h2 class="text-xl font-bold text-gray-900">Node Details</h2>
                  <button phx-click="close_details" class="text-gray-400 hover:text-gray-600">
                    <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M6 18L18 6M6 6l12 12"
                      />
                    </svg>
                  </button>
                </div>

                <div class="space-y-4">
                  <div>
                    <div class="text-sm font-medium text-gray-500">Type</div>
                    <div class="mt-1 text-lg font-semibold capitalize text-gray-900">
                      <%= @selected_node.type %>
                    </div>
                  </div>

                  <div>
                    <div class="text-sm font-medium text-gray-500">ID</div>
                    <div class="mt-1 text-xs font-mono text-gray-900 break-all">
                      <%= @selected_node.id %>
                    </div>
                  </div>

                  <%= if @selected_node.type == "neuron" do %>
                    <div>
                      <div class="text-sm font-medium text-gray-500">Layer</div>
                      <div class="mt-1 text-lg text-gray-900"><%= @selected_node.layer %></div>
                    </div>

                    <div>
                      <div class="text-sm font-medium text-gray-500">Activation Function</div>
                      <div class="mt-1 text-gray-900"><%= inspect(@selected_node.af) %></div>
                    </div>

                    <%= if @selected_node.pf do %>
                      <div>
                        <div class="text-sm font-medium text-gray-500">Plasticity Function</div>
                        <div class="mt-1 text-gray-900"><%= inspect(@selected_node.pf) %></div>
                      </div>
                    <% end %>

                    <div>
                      <div class="text-sm font-medium text-gray-500">Aggregation Function</div>
                      <div class="mt-1 text-gray-900"><%= inspect(@selected_node.aggr_f) %></div>
                    </div>

                    <div class="grid grid-cols-2 gap-4">
                      <div>
                        <div class="text-sm font-medium text-gray-500">Inputs</div>
                        <div class="mt-1 text-2xl font-bold text-blue-600">
                          <%= @selected_node.input_count %>
                        </div>
                      </div>
                      <div>
                        <div class="text-sm font-medium text-gray-500">Outputs</div>
                        <div class="mt-1 text-2xl font-bold text-green-600">
                          <%= @selected_node.output_count %>
                        </div>
                      </div>
                    </div>
                    <!-- Expandable Connection Lists -->
                    <div class="border-t border-gray-200 pt-4 space-y-3">
                      <!-- Input Connections -->
                      <details class="group">
                        <summary class="cursor-pointer list-none">
                          <div class="flex items-center justify-between p-3 bg-blue-50 rounded-lg hover:bg-blue-100 transition-colors">
                            <div class="flex items-center gap-2">
                              <svg
                                class="w-4 h-4 text-blue-600 transition-transform group-open:rotate-90"
                                fill="none"
                                stroke="currentColor"
                                viewBox="0 0 24 24"
                              >
                                <path
                                  stroke-linecap="round"
                                  stroke-linejoin="round"
                                  stroke-width="2"
                                  d="M9 5l7 7-7 7"
                                />
                              </svg>
                              <span class="text-sm font-semibold text-blue-900">
                                Input Connections
                              </span>
                            </div>
                            <span class="text-xs bg-blue-200 text-blue-800 px-2 py-1 rounded-full">
                              <%= length(@selected_node.input_ids || []) %>
                            </span>
                          </div>
                        </summary>
                        <div class="mt-2 ml-4 space-y-1 max-h-48 overflow-y-auto">
                          <%= for input_id <- @selected_node.input_ids || [] do %>
                            <div class="text-xs font-mono bg-gray-50 p-2 rounded border border-gray-200 break-all">
                              <%= input_id %>
                            </div>
                          <% end %>
                        </div>
                      </details>
                      <!-- Input Modulation Connections -->
                      <%= if length(@selected_node.input_modulation_ids || []) > 0 do %>
                        <details class="group">
                          <summary class="cursor-pointer list-none">
                            <div class="flex items-center justify-between p-3 bg-indigo-50 rounded-lg hover:bg-indigo-100 transition-colors">
                              <div class="flex items-center gap-2">
                                <svg
                                  class="w-4 h-4 text-indigo-600 transition-transform group-open:rotate-90"
                                  fill="none"
                                  stroke="currentColor"
                                  viewBox="0 0 24 24"
                                >
                                  <path
                                    stroke-linecap="round"
                                    stroke-linejoin="round"
                                    stroke-width="2"
                                    d="M9 5l7 7-7 7"
                                  />
                                </svg>
                                <span class="text-sm font-semibold text-indigo-900">
                                  Modulation Inputs
                                </span>
                              </div>
                              <span class="text-xs bg-indigo-200 text-indigo-800 px-2 py-1 rounded-full">
                                <%= length(@selected_node.input_modulation_ids) %>
                              </span>
                            </div>
                          </summary>
                          <div class="mt-2 ml-4 space-y-1 max-h-48 overflow-y-auto">
                            <%= for mod_id <- @selected_node.input_modulation_ids do %>
                              <div class="text-xs font-mono bg-gray-50 p-2 rounded border border-gray-200 break-all">
                                <%= mod_id %>
                              </div>
                            <% end %>
                          </div>
                        </details>
                      <% end %>
                      <!-- Output Connections -->
                      <details class="group">
                        <summary class="cursor-pointer list-none">
                          <div class="flex items-center justify-between p-3 bg-green-50 rounded-lg hover:bg-green-100 transition-colors">
                            <div class="flex items-center gap-2">
                              <svg
                                class="w-4 h-4 text-green-600 transition-transform group-open:rotate-90"
                                fill="none"
                                stroke="currentColor"
                                viewBox="0 0 24 24"
                              >
                                <path
                                  stroke-linecap="round"
                                  stroke-linejoin="round"
                                  stroke-width="2"
                                  d="M9 5l7 7-7 7"
                                />
                              </svg>
                              <span class="text-sm font-semibold text-green-900">
                                Output Connections
                              </span>
                            </div>
                            <span class="text-xs bg-green-200 text-green-800 px-2 py-1 rounded-full">
                              <%= length(@selected_node.output_ids || []) %>
                            </span>
                          </div>
                        </summary>
                        <div class="mt-2 ml-4 space-y-1 max-h-48 overflow-y-auto">
                          <%= for output_id <- @selected_node.output_ids || [] do %>
                            <div class="text-xs font-mono bg-gray-50 p-2 rounded border border-gray-200 break-all">
                              <%= output_id %>
                            </div>
                          <% end %>
                        </div>
                      </details>
                      <!-- Recurrent Output Connections -->
                      <%= if length(@selected_node.ro_ids || []) > 0 do %>
                        <details class="group">
                          <summary class="cursor-pointer list-none">
                            <div class="flex items-center justify-between p-3 bg-red-50 rounded-lg hover:bg-red-100 transition-colors">
                              <div class="flex items-center gap-2">
                                <svg
                                  class="w-4 h-4 text-red-600 transition-transform group-open:rotate-90"
                                  fill="none"
                                  stroke="currentColor"
                                  viewBox="0 0 24 24"
                                >
                                  <path
                                    stroke-linecap="round"
                                    stroke-linejoin="round"
                                    stroke-width="2"
                                    d="M9 5l7 7-7 7"
                                  />
                                </svg>
                                <span class="text-sm font-semibold text-red-900">
                                  Recurrent Outputs
                                </span>
                              </div>
                              <span class="text-xs bg-red-200 text-red-800 px-2 py-1 rounded-full">
                                <%= length(@selected_node.ro_ids) %>
                              </span>
                            </div>
                          </summary>
                          <div class="mt-2 ml-4 space-y-1 max-h-48 overflow-y-auto">
                            <%= for ro_id <- @selected_node.ro_ids do %>
                              <div class="text-xs font-mono bg-gray-50 p-2 rounded border border-gray-200 break-all">
                                <%= ro_id %>
                              </div>
                            <% end %>
                          </div>
                        </details>
                      <% end %>
                    </div>
                  <% end %>

                  <%= if @selected_node.type in ["sensor", "actuator"] do %>
                    <div>
                      <div class="text-sm font-medium text-gray-500">Name</div>
                      <div class="mt-1 text-gray-900"><%= @selected_node.name %></div>
                    </div>

                    <div>
                      <div class="text-sm font-medium text-gray-500">Vector Length</div>
                      <div class="mt-1 text-gray-900"><%= @selected_node.vl %></div>
                    </div>
                    <!-- Connection Lists -->
                    <div class="border-t border-gray-200 pt-4 space-y-3">
                      <%= if @selected_node.type == "sensor" && @selected_node.fanout_ids do %>
                        <details class="group">
                          <summary class="cursor-pointer list-none">
                            <div class="flex items-center justify-between p-3 bg-blue-50 rounded-lg hover:bg-blue-100 transition-colors">
                              <div class="flex items-center gap-2">
                                <svg
                                  class="w-4 h-4 text-blue-600 transition-transform group-open:rotate-90"
                                  fill="none"
                                  stroke="currentColor"
                                  viewBox="0 0 24 24"
                                >
                                  <path
                                    stroke-linecap="round"
                                    stroke-linejoin="round"
                                    stroke-width="2"
                                    d="M9 5l7 7-7 7"
                                  />
                                </svg>
                                <span class="text-sm font-semibold text-blue-900">
                                  Fanout Connections
                                </span>
                              </div>
                              <span class="text-xs bg-blue-200 text-blue-800 px-2 py-1 rounded-full">
                                <%= length(@selected_node.fanout_ids) %>
                              </span>
                            </div>
                          </summary>
                          <div class="mt-2 ml-4 space-y-1 max-h-48 overflow-y-auto">
                            <%= for fanout_id <- @selected_node.fanout_ids do %>
                              <div class="text-xs font-mono bg-gray-50 p-2 rounded border border-gray-200 break-all">
                                <%= fanout_id %>
                              </div>
                            <% end %>
                          </div>
                        </details>
                      <% end %>

                      <%= if @selected_node.type == "actuator" && @selected_node.fanin_ids do %>
                        <details class="group">
                          <summary class="cursor-pointer list-none">
                            <div class="flex items-center justify-between p-3 bg-purple-50 rounded-lg hover:bg-purple-100 transition-colors">
                              <div class="flex items-center gap-2">
                                <svg
                                  class="w-4 h-4 text-purple-600 transition-transform group-open:rotate-90"
                                  fill="none"
                                  stroke="currentColor"
                                  viewBox="0 0 24 24"
                                >
                                  <path
                                    stroke-linecap="round"
                                    stroke-linejoin="round"
                                    stroke-width="2"
                                    d="M9 5l7 7-7 7"
                                  />
                                </svg>
                                <span class="text-sm font-semibold text-purple-900">
                                  Fanin Connections
                                </span>
                              </div>
                              <span class="text-xs bg-purple-200 text-purple-800 px-2 py-1 rounded-full">
                                <%= length(@selected_node.fanin_ids) %>
                              </span>
                            </div>
                          </summary>
                          <div class="mt-2 ml-4 space-y-1 max-h-48 overflow-y-auto">
                            <%= for fanin_id <- @selected_node.fanin_ids do %>
                              <div class="text-xs font-mono bg-gray-50 p-2 rounded border border-gray-200 break-all">
                                <%= fanin_id %>
                              </div>
                            <% end %>
                          </div>
                        </details>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
          <!-- Edge Details Sidebar -->
          <%= if @selected_edge do %>
            <div class="fixed inset-y-0 right-0 w-96 bg-white shadow-2xl transform transition-transform duration-300 ease-in-out z-50 overflow-y-auto">
              <div class="p-6">
                <div class="flex justify-between items-start mb-4">
                  <h2 class="text-xl font-bold text-gray-900">Connection Details</h2>
                  <button phx-click="close_details" class="text-gray-400 hover:text-gray-600">
                    <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M6 18L18 6M6 6l12 12"
                      />
                    </svg>
                  </button>
                </div>

                <div class="space-y-4">
                  <div>
                    <div class="text-sm font-medium text-gray-500">Weight</div>
                    <div class="mt-1 text-2xl font-bold text-gray-900">
                      <%= if is_float(@selected_edge.weight),
                        do: Float.round(@selected_edge.weight, 4),
                        else: @selected_edge.weight %>
                    </div>
                  </div>

                  <%= if @selected_edge.recurrent do %>
                    <div class="bg-red-50 border border-red-200 rounded-lg p-3">
                      <div class="flex items-center gap-2">
                        <svg
                          class="w-5 h-5 text-red-600"
                          fill="none"
                          stroke="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                          />
                        </svg>
                        <div>
                          <div class="text-sm font-semibold text-red-900">Recurrent Connection</div>
                          <div class="text-xs text-red-700">
                            This connection loops back to an earlier layer or itself
                          </div>
                        </div>
                      </div>
                    </div>
                  <% end %>

                  <div class="border-t border-gray-200 pt-4">
                    <div class="text-sm font-semibold text-gray-700 mb-2">Source Node</div>
                    <%= if @selected_edge.source_node do %>
                      <div class="bg-blue-50 rounded-lg p-3 space-y-2">
                        <div>
                          <div class="text-xs text-gray-500">Type</div>
                          <div class="text-sm font-medium capitalize">
                            <%= @selected_edge.source_node.type %>
                          </div>
                        </div>
                        <%= if @selected_edge.source_node.label do %>
                          <div>
                            <div class="text-xs text-gray-500">Label</div>
                            <div class="text-sm font-medium">
                              <%= @selected_edge.source_node.label %>
                            </div>
                          </div>
                        <% end %>
                        <div>
                          <div class="text-xs text-gray-500">ID</div>
                          <div class="text-xs font-mono break-all">
                            <%= @selected_edge.source %>
                          </div>
                        </div>
                      </div>
                    <% else %>
                      <div class="text-sm text-gray-500">
                        <%= @selected_edge.source %>
                      </div>
                    <% end %>
                  </div>

                  <div class="border-t border-gray-200 pt-4">
                    <div class="text-sm font-semibold text-gray-700 mb-2">Target Node</div>
                    <%= if @selected_edge.target_node do %>
                      <div class="bg-purple-50 rounded-lg p-3 space-y-2">
                        <div>
                          <div class="text-xs text-gray-500">Type</div>
                          <div class="text-sm font-medium capitalize">
                            <%= @selected_edge.target_node.type %>
                          </div>
                        </div>
                        <%= if @selected_edge.target_node.label do %>
                          <div>
                            <div class="text-xs text-gray-500">Label</div>
                            <div class="text-sm font-medium">
                              <%= @selected_edge.target_node.label %>
                            </div>
                          </div>
                        <% end %>
                        <div>
                          <div class="text-xs text-gray-500">ID</div>
                          <div class="text-xs font-mono break-all">
                            <%= @selected_edge.target %>
                          </div>
                        </div>
                      </div>
                    <% else %>
                      <div class="text-sm text-gray-500">
                        <%= @selected_edge.target %>
                      </div>
                    <% end %>
                  </div>

                  <div class="border-t border-gray-200 pt-4">
                    <div class="text-sm text-gray-600">
                      <svg
                        class="w-4 h-4 inline mr-1"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                        />
                      </svg>
                      This connection transmits signals from the source node to the target node with the specified weight.
                    </div>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
