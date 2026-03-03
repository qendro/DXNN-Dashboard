defmodule DxnnAnalyzerWeb.SpecieListLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.AnalyzerBridge

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:context, nil)
      |> assign(:species, [])
      |> assign(:loading, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    context = params["context"]

    socket =
      if context do
        socket
        |> assign(:context, context)
        |> load_species(context)
      else
        socket
      end

    {:noreply, socket}
  end

  defp load_species(socket, context) do
    socket = assign(socket, :loading, true)

    species = case AnalyzerBridge.get_species(context) do
      {:ok, specs} when is_list(specs) -> specs
      {:ok, _} -> []
      {:error, _} -> []
      _ -> []
    end

    socket
    |> assign(:species, species)
    |> assign(:loading, false)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="mb-6">
          <.link navigate={~p"/agents?context=#{@context}"} class="text-blue-600 hover:text-blue-800 text-sm mb-2 inline-block">
            ← Back to Experiment
          </.link>
          <h1 class="text-3xl font-bold text-gray-900">Species</h1>
          <%= if @context do %>
            <p class="text-gray-600 mt-2">Experiment: <span class="font-semibold"><%= @context %></span></p>
          <% end %>
        </div>

        <%= if @loading do %>
          <div class="bg-white shadow rounded-lg p-8 text-center text-gray-500">
            Loading species...
          </div>
        <% else %>
          <%= if Enum.empty?(@species) do %>
            <div class="bg-white shadow rounded-lg p-8 text-center">
              <p class="text-gray-500 mb-4">No species found in this experiment</p>
              <.link
                navigate={~p"/agents?context=#{@context}"}
                class="inline-block bg-blue-600 text-white px-6 py-3 rounded-md hover:bg-blue-700 transition"
              >
                Back to Experiment
              </.link>
            </div>
          <% else %>
            <div class="space-y-6">
              <%= for specie <- @species do %>
                <div class="bg-white shadow rounded-lg p-6">
                  <div class="flex justify-between items-start mb-4">
                    <h2 class="text-xl font-semibold text-gray-900">
                      Specie: <span class="font-mono text-blue-600"><%= inspect(specie.id) %></span>
                    </h2>
                    <div class="flex gap-2">
                      <span class="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-green-100 text-green-800">
                        <%= specie.agent_count %> agents
                      </span>
                      <%= if specie.champion_count > 0 do %>
                        <span class="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-yellow-100 text-yellow-800">
                          <%= specie.champion_count %> champions
                        </span>
                      <% end %>
                    </div>
                  </div>
                  
                  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                    <div>
                      <dt class="text-sm font-medium text-gray-500">Population ID</dt>
                      <dd class="mt-1 text-sm text-gray-900 font-mono"><%= inspect(specie.population_id) %></dd>
                    </div>
                    
                    <div>
                      <dt class="text-sm font-medium text-gray-500">Fitness</dt>
                      <dd class="mt-1 text-sm text-gray-900"><%= inspect(specie.fitness) %></dd>
                    </div>
                    
                    <div>
                      <dt class="text-sm font-medium text-gray-500">Innovation Factor</dt>
                      <dd class="mt-1 text-sm text-gray-900"><%= inspect(specie.innovation_factor) %></dd>
                    </div>
                    
                    <div>
                      <dt class="text-sm font-medium text-gray-500">Active Agents</dt>
                      <dd class="mt-1 text-sm text-gray-900"><%= specie.agent_count %></dd>
                    </div>
                    
                    <div>
                      <dt class="text-sm font-medium text-gray-500">Dead Pool</dt>
                      <dd class="mt-1 text-sm text-gray-900"><%= specie.dead_pool_count %></dd>
                    </div>
                    
                    <div>
                      <dt class="text-sm font-medium text-gray-500">Champions</dt>
                      <dd class="mt-1 text-sm text-gray-900"><%= specie.champion_count %></dd>
                    </div>
                    
                    <%= if specie.constraint && specie.constraint.morphology do %>
                      <div>
                        <dt class="text-sm font-medium text-gray-500">Morphology</dt>
                        <dd class="mt-1 text-sm text-gray-900"><%= inspect(specie.constraint.morphology) %></dd>
                      </div>
                    <% end %>
                    
                    <%= if specie.constraint && specie.constraint.connection_architecture do %>
                      <div>
                        <dt class="text-sm font-medium text-gray-500">Connection Architecture</dt>
                        <dd class="mt-1 text-sm text-gray-900"><%= inspect(specie.constraint.connection_architecture) %></dd>
                      </div>
                    <% end %>
                  </div>
                  
                  <%= if !Enum.empty?(specie.agent_ids) do %>
                    <div class="mt-4 pt-4 border-t border-gray-200">
                      <h3 class="text-sm font-medium text-gray-500 mb-2">Agents in this Specie</h3>
                      <div class="flex flex-wrap gap-2">
                        <%= for agent_id <- Enum.take(specie.agent_ids, 10) do %>
                          <.link
                            navigate={~p"/agents/#{URI.encode(inspect(agent_id))}?context=#{@context}"}
                            class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800 hover:bg-blue-200"
                          >
                            <%= inspect(agent_id) %>
                          </.link>
                        <% end %>
                        <%= if length(specie.agent_ids) > 10 do %>
                          <span class="text-xs text-gray-500">+ <%= length(specie.agent_ids) - 10 %> more</span>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                  
                  <%= if !Enum.empty?(specie.champion_ids) do %>
                    <div class="mt-4 pt-4 border-t border-gray-200">
                      <h3 class="text-sm font-medium text-gray-500 mb-2">Champion Agents</h3>
                      <div class="flex flex-wrap gap-2">
                        <%= for champion_id <- specie.champion_ids do %>
                          <.link
                            navigate={~p"/agents/#{URI.encode(inspect(champion_id))}?context=#{@context}"}
                            class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800 hover:bg-yellow-200"
                          >
                            <%= inspect(champion_id) %>
                          </.link>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
