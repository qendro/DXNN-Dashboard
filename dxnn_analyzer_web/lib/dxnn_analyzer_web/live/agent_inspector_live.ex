defmodule DxnnAnalyzerWeb.AgentInspectorLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.AnalyzerBridge

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, assign(socket, agent_id: URI.decode(id), loading: true)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    context = params["context"]

    socket =
      if context do
        agent_id_str = URI.decode(socket.assigns.agent_id)
        IO.puts("=== Agent Inspector Debug ===")
        IO.puts("Raw agent_id from URL: #{inspect(socket.assigns.agent_id)}")
        IO.puts("Decoded agent_id: #{inspect(agent_id_str)}")
        
        agent_id = parse_agent_id(agent_id_str)
        IO.puts("Parsed agent_id: #{inspect(agent_id)}")

        case AnalyzerBridge.inspect_agent(agent_id, context) do
          inspection when is_map(inspection) ->
            socket
            |> assign(:context, context)
            |> assign(:inspection, inspection)
            |> assign(:error, nil)
            |> assign(:loading, false)

          {:error, reason} ->
            IO.puts("Error from bridge: #{inspect(reason)}")
            socket
            |> assign(:context, context)
            |> assign(:inspection, nil)
            |> assign(:error, "Failed to load agent: #{inspect(reason)}")
            |> assign(:loading, false)

          _ ->
            socket
            |> assign(:context, context)
            |> assign(:inspection, nil)
            |> assign(:error, "Failed to load agent inspection")
            |> assign(:loading, false)
        end
      else
        assign(socket, error: "No context specified", loading: false)
      end

    {:noreply, socket}
  end

  defp parse_agent_id(id_str) do
    # Parse the Erlang term from its string representation
    try do
      {agent_id, _} = Code.eval_string(id_str)
      agent_id
    rescue
      e ->
        IO.puts("Error parsing agent ID: #{inspect(e)}")
        IO.puts("ID string was: #{id_str}")
        raise e
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="mb-6">
          <.link navigate={~p"/agents?context=#{@context}"} class="text-blue-600 hover:text-blue-800 text-sm mb-2 inline-block">
            ← Back to Experiment Details
          </.link>
          <h1 class="text-3xl font-bold text-gray-900">Agent Inspector</h1>
        </div>

        <%= if @loading do %>
          <div class="bg-white shadow rounded-lg p-6">
            <p class="text-gray-600">Loading agent data...</p>
          </div>
        <% end %>

        <%= if @error do %>
          <div class="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded mb-6">
            <%= @error %>
          </div>
        <% end %>

        <%= if @inspection do %>
          <div class="space-y-6">
            <!-- Basic Info -->
            <div class="bg-white shadow rounded-lg p-6">
              <h2 class="text-xl font-semibold mb-4 text-gray-900">Basic Information</h2>
              <dl class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                <div>
                  <dt class="text-sm font-medium text-gray-500">Agent ID</dt>
                  <dd class="mt-1 text-sm text-gray-900 font-mono break-all"><%= inspect(@inspection.id) %></dd>
                </div>
                <div>
                  <dt class="text-sm font-medium text-gray-500">Encoding Type</dt>
                  <dd class="mt-1 text-sm text-gray-900"><%= @inspection.encoding_type %></dd>
                </div>
                <div>
                  <dt class="text-sm font-medium text-gray-500">Generation</dt>
                  <dd class="mt-1 text-sm text-gray-900"><%= @inspection.generation %></dd>
                </div>
                <div>
                  <dt class="text-sm font-medium text-gray-500">Fitness</dt>
                  <dd class="mt-1 text-lg font-semibold text-green-600"><%= Float.round(@inspection.fitness, 6) %></dd>
                </div>
                <div>
                  <dt class="text-sm font-medium text-gray-500">Innovation Factor</dt>
                  <dd class="mt-1 text-sm text-gray-900"><%= @inspection.innovation_factor %></dd>
                </div>
                <div>
                  <dt class="text-sm font-medium text-gray-500">Heredity Type</dt>
                  <dd class="mt-1 text-sm text-gray-900"><%= @inspection.heredity_type || "N/A" %></dd>
                </div>
                <div>
                  <dt class="text-sm font-medium text-gray-500">Population ID</dt>
                  <dd class="mt-1 text-sm text-gray-900 font-mono">
                    <.link
                      navigate={~p"/populations?context=#{@context}"}
                      class="text-blue-600 hover:text-blue-800 hover:underline"
                    >
                      <%= inspect(@inspection.population_id) %>
                    </.link>
                  </dd>
                </div>
                <div>
                  <dt class="text-sm font-medium text-gray-500">Specie ID</dt>
                  <dd class="mt-1 text-sm text-gray-900 font-mono">
                    <.link
                      navigate={~p"/species?context=#{@context}"}
                      class="text-blue-600 hover:text-blue-800 hover:underline"
                    >
                      <%= inspect(@inspection.specie_id) %>
                    </.link>
                  </dd>
                </div>
                <div>
                  <dt class="text-sm font-medium text-gray-500">Cortex ID</dt>
                  <dd class="mt-1 text-sm text-gray-900 font-mono break-all"><%= inspect(@inspection.cx_id) %></dd>
                </div>
              </dl>
            </div>

            <!-- Topology Summary -->
            <%= if Map.has_key?(@inspection, :component_counts) do %>
              <div class="bg-white shadow rounded-lg p-6">
                <h2 class="text-xl font-semibold mb-4 text-gray-900">Network Topology</h2>
                <dl class="grid grid-cols-2 md:grid-cols-4 gap-6">
                  <div class="text-center">
                    <dt class="text-sm font-medium text-gray-500">Sensors</dt>
                    <dd class="mt-2 text-3xl font-bold text-blue-600">
                      <%= @inspection.component_counts.sensors %>
                    </dd>
                  </div>
                  <div class="text-center">
                    <dt class="text-sm font-medium text-gray-500">Neurons</dt>
                    <dd class="mt-2 text-3xl font-bold text-green-600">
                      <%= @inspection.component_counts.neurons %>
                    </dd>
                  </div>
                  <div class="text-center">
                    <dt class="text-sm font-medium text-gray-500">Actuators</dt>
                    <dd class="mt-2 text-3xl font-bold text-purple-600">
                      <%= @inspection.component_counts.actuators %>
                    </dd>
                  </div>
                  <div class="text-center">
                    <dt class="text-sm font-medium text-gray-500">Connections</dt>
                    <dd class="mt-2 text-3xl font-bold text-orange-600">
                      <%= @inspection.component_counts.total_connections %>
                    </dd>
                  </div>
                </dl>
              </div>
            <% end %>

            <!-- Tuning Parameters -->
            <div class="bg-white shadow rounded-lg p-6">
              <h2 class="text-xl font-semibold mb-4 text-gray-900">Tuning Parameters</h2>
              <dl class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                <div>
                  <dt class="text-sm font-medium text-gray-500">Tuning Selection Function</dt>
                  <dd class="mt-1 text-sm text-gray-900"><%= inspect(@inspection.tuning_selection_f) %></dd>
                </div>
                <div>
                  <dt class="text-sm font-medium text-gray-500">Annealing Parameter</dt>
                  <dd class="mt-1 text-sm text-gray-900"><%= inspect(@inspection.annealing_parameter) %></dd>
                </div>
                <div>
                  <dt class="text-sm font-medium text-gray-500">Tuning Duration Function</dt>
                  <dd class="mt-1 text-sm text-gray-900"><%= inspect(@inspection.tuning_duration_f) %></dd>
                </div>
                <div>
                  <dt class="text-sm font-medium text-gray-500">Perturbation Range</dt>
                  <dd class="mt-1 text-sm text-gray-900"><%= inspect(@inspection.perturbation_range) %></dd>
                </div>
                <div>
                  <dt class="text-sm font-medium text-gray-500">Pattern</dt>
                  <dd class="mt-1 text-sm text-gray-900"><%= inspect(@inspection.pattern) %></dd>
                </div>
                <div>
                  <dt class="text-sm font-medium text-gray-500">Fingerprint</dt>
                  <dd class="mt-1 text-sm text-gray-900 font-mono break-all"><%= inspect(@inspection.fingerprint) %></dd>
                </div>
              </dl>
            </div>

            <!-- Mutation Operators -->
            <%= if @inspection.mutation_operators && length(@inspection.mutation_operators) > 0 do %>
              <div class="bg-white shadow rounded-lg p-6">
                <h2 class="text-xl font-semibold mb-4 text-gray-900">Mutation Operators</h2>
                <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
                  <%= for {op, weight} <- @inspection.mutation_operators do %>
                    <div class="bg-gray-50 rounded p-3">
                      <div class="text-xs font-medium text-gray-500"><%= op %></div>
                      <div class="text-lg font-semibold text-gray-900"><%= weight %></div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <!-- Constraint Details -->
            <%= if @inspection.constraint do %>
              <div class="bg-white shadow rounded-lg p-6">
                <h2 class="text-xl font-semibold mb-4 text-gray-900">Constraint Configuration</h2>
                <div class="space-y-4">
                  <div>
                    <h3 class="text-sm font-medium text-gray-700 mb-2">Architecture</h3>
                    <dl class="grid grid-cols-1 md:grid-cols-2 gap-3 text-sm">
                      <div>
                        <dt class="text-gray-500">Morphology</dt>
                        <dd class="text-gray-900 font-mono"><%= @inspection.constraint.morphology %></dd>
                      </div>
                      <div>
                        <dt class="text-gray-500">Connection Architecture</dt>
                        <dd class="text-gray-900 font-mono"><%= @inspection.constraint.connection_architecture %></dd>
                      </div>
                    </dl>
                  </div>
                  
                  <div>
                    <h3 class="text-sm font-medium text-gray-700 mb-2">Neural Functions</h3>
                    <dl class="grid grid-cols-1 gap-2 text-sm">
                      <div>
                        <dt class="text-gray-500">Activation Functions</dt>
                        <dd class="text-gray-900 font-mono text-xs"><%= inspect(@inspection.constraint.neural_afs) %></dd>
                      </div>
                      <div>
                        <dt class="text-gray-500">Plasticity Functions</dt>
                        <dd class="text-gray-900 font-mono text-xs"><%= inspect(@inspection.constraint.neural_pfns) %></dd>
                      </div>
                      <div>
                        <dt class="text-gray-500">Aggregation Functions</dt>
                        <dd class="text-gray-900 font-mono text-xs"><%= inspect(@inspection.constraint.neural_aggr_fs) %></dd>
                      </div>
                    </dl>
                  </div>

                  <%= if @inspection.encoding_type == :substrate do %>
                    <div>
                      <h3 class="text-sm font-medium text-gray-700 mb-2">Substrate Configuration</h3>
                      <dl class="grid grid-cols-1 md:grid-cols-2 gap-3 text-sm">
                        <div>
                          <dt class="text-gray-500">Substrate Plasticities</dt>
                          <dd class="text-gray-900 font-mono text-xs"><%= inspect(@inspection.constraint.substrate_plasticities) %></dd>
                        </div>
                        <div>
                          <dt class="text-gray-500">Substrate Linkforms</dt>
                          <dd class="text-gray-900 font-mono text-xs"><%= inspect(@inspection.constraint.substrate_linkforms) %></dd>
                        </div>
                        <div>
                          <dt class="text-gray-500">Substrate ID</dt>
                          <dd class="text-gray-900 font-mono text-xs"><%= inspect(@inspection.substrate_id) %></dd>
                        </div>
                      </dl>
                    </div>
                  <% end %>

                  <div>
                    <h3 class="text-sm font-medium text-gray-700 mb-2">Evolution Parameters</h3>
                    <dl class="grid grid-cols-1 md:grid-cols-2 gap-3 text-sm">
                      <div>
                        <dt class="text-gray-500">Evolution Algorithm</dt>
                        <dd class="text-gray-900 font-mono"><%= @inspection.constraint.population_evo_alg_f %></dd>
                      </div>
                      <div>
                        <dt class="text-gray-500">Selection Function</dt>
                        <dd class="text-gray-900 font-mono"><%= @inspection.constraint.population_selection_f %></dd>
                      </div>
                      <div>
                        <dt class="text-gray-500">Fitness Postprocessor</dt>
                        <dd class="text-gray-900 font-mono"><%= @inspection.constraint.population_fitness_postprocessor_f %></dd>
                      </div>
                    </dl>
                  </div>
                </div>
              </div>
            <% end %>

            <!-- Evolution History -->
            <%= if @inspection.evo_hist && length(@inspection.evo_hist) > 0 do %>
              <div class="bg-white shadow rounded-lg p-6">
                <h2 class="text-xl font-semibold mb-4 text-gray-900">
                  Evolution History 
                  <span class="text-sm font-normal text-gray-500">(<%= length(@inspection.evo_hist) %> mutations)</span>
                </h2>
                <div class="max-h-96 overflow-y-auto">
                  <div class="space-y-2">
                    <%= for {mutation, idx} <- Enum.with_index(@inspection.evo_hist) do %>
                      <div class="bg-gray-50 rounded p-3 text-sm">
                        <span class="text-gray-500 font-mono">#<%= idx + 1 %></span>
                        <span class="ml-2 text-gray-900 font-mono"><%= inspect(mutation) %></span>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>

            <!-- Detailed Metrics -->
            <%= if @inspection.metrics do %>
              <div class="bg-white shadow rounded-lg p-6">
                <h2 class="text-xl font-semibold mb-4 text-gray-900">Network Metrics</h2>
                <dl class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                  <div>
                    <dt class="text-sm font-medium text-gray-500">Network Depth</dt>
                    <dd class="mt-1 text-lg font-semibold text-gray-900"><%= inspect(Map.get(@inspection.metrics, :depth, "N/A")) %></dd>
                  </div>
                  <div>
                    <dt class="text-sm font-medium text-gray-500">Network Width</dt>
                    <dd class="mt-1 text-lg font-semibold text-gray-900"><%= inspect(Map.get(@inspection.metrics, :width, "N/A")) %></dd>
                  </div>
                  <div>
                    <dt class="text-sm font-medium text-gray-500">Recurrent Connections</dt>
                    <dd class="mt-1 text-lg font-semibold text-gray-900"><%= inspect(Map.get(@inspection.metrics, :cycles, "N/A")) %></dd>
                  </div>
                </dl>
              </div>
            <% end %>

            <!-- Actions -->
            <div class="bg-white shadow rounded-lg p-6">
              <h2 class="text-xl font-semibold mb-4 text-gray-900">Actions</h2>
              <div class="flex flex-wrap gap-4">
                <.link
                  navigate={~p"/graph/#{URI.encode(@agent_id)}?context=#{@context}"}
                  class="bg-indigo-600 text-white px-4 py-2 rounded-md hover:bg-indigo-700 transition"
                >
                  View Interactive Graph
                </.link>
                <.link
                  navigate={~p"/topology/#{URI.encode(@agent_id)}?context=#{@context}"}
                  class="bg-green-600 text-white px-4 py-2 rounded-md hover:bg-green-700 transition"
                >
                  View Network Topology
                </.link>
                <button
                  phx-click="export_agent"
                  class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition"
                >
                  Export Agent Data
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("export_agent", _params, socket) do
    # Future: implement agent export functionality
    {:noreply, put_flash(socket, :info, "Export functionality coming soon")}
  end
end
