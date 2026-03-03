defmodule DxnnAnalyzerWeb.PopulationListLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.AnalyzerBridge

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:context, nil)
      |> assign(:populations, [])
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
        |> load_populations(context)
      else
        socket
      end

    {:noreply, socket}
  end

  defp load_populations(socket, context) do
    socket = assign(socket, :loading, true)

    populations = case AnalyzerBridge.get_populations(context) do
      {:ok, pops} when is_list(pops) -> pops
      {:ok, _} -> []
      {:error, _} -> []
      _ -> []
    end

    socket
    |> assign(:populations, populations)
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
          <h1 class="text-3xl font-bold text-gray-900">Populations</h1>
          <%= if @context do %>
            <p class="text-gray-600 mt-2">Experiment: <span class="font-semibold"><%= @context %></span></p>
          <% end %>
        </div>

        <%= if @loading do %>
          <div class="bg-white shadow rounded-lg p-8 text-center text-gray-500">
            Loading populations...
          </div>
        <% else %>
          <%= if Enum.empty?(@populations) do %>
            <div class="bg-white shadow rounded-lg p-8 text-center">
              <p class="text-gray-500 mb-4">No populations found in this experiment</p>
              <.link
                navigate={~p"/agents?context=#{@context}"}
                class="inline-block bg-blue-600 text-white px-6 py-3 rounded-md hover:bg-blue-700 transition"
              >
                Back to Experiment
              </.link>
            </div>
          <% else %>
            <div class="space-y-6">
              <%= for pop <- @populations do %>
                <div class="bg-white shadow rounded-lg p-6">
                  <h2 class="text-xl font-semibold mb-4 text-gray-900">
                    Population: <span class="font-mono text-blue-600"><%= inspect(pop.id) %></span>
                  </h2>
                  
                  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                    <div>
                      <dt class="text-sm font-medium text-gray-500">Polis ID</dt>
                      <dd class="mt-1 text-sm text-gray-900"><%= inspect(pop.polis_id) %></dd>
                    </div>
                    
                    <div>
                      <dt class="text-sm font-medium text-gray-500">Evolution Algorithm</dt>
                      <dd class="mt-1 text-sm text-gray-900"><%= inspect(pop.evo_alg_f) %></dd>
                    </div>
                    
                    <div>
                      <dt class="text-sm font-medium text-gray-500">Selection Function</dt>
                      <dd class="mt-1 text-sm text-gray-900"><%= inspect(pop.selection_f) %></dd>
                    </div>
                    
                    <div>
                      <dt class="text-sm font-medium text-gray-500">Fitness Postprocessor</dt>
                      <dd class="mt-1 text-sm text-gray-900"><%= inspect(pop.fitness_postprocessor_f) %></dd>
                    </div>
                    
                    <div>
                      <dt class="text-sm font-medium text-gray-500">Innovation Factor</dt>
                      <dd class="mt-1 text-sm text-gray-900"><%= inspect(pop.innovation_factor) %></dd>
                    </div>
                    
                    <div>
                      <dt class="text-sm font-medium text-gray-500">Species Count</dt>
                      <dd class="mt-1 text-sm text-gray-900"><%= length(pop.specie_ids) %></dd>
                    </div>
                    
                    <div class="md:col-span-2">
                      <dt class="text-sm font-medium text-gray-500">Morphologies</dt>
                      <dd class="mt-1 text-sm text-gray-900"><%= inspect(pop.morphologies) %></dd>
                    </div>
                    
                    <%= if pop.trace && pop.trace.tot_evaluations do %>
                      <div>
                        <dt class="text-sm font-medium text-gray-500">Total Evaluations</dt>
                        <dd class="mt-1 text-sm text-gray-900"><%= pop.trace.tot_evaluations %></dd>
                      </div>
                      
                      <div>
                        <dt class="text-sm font-medium text-gray-500">Step Size</dt>
                        <dd class="mt-1 text-sm text-gray-900"><%= pop.trace.step_size %></dd>
                      </div>
                    <% end %>
                  </div>
                  
                  <%= if !Enum.empty?(pop.specie_ids) do %>
                    <div class="mt-4 pt-4 border-t border-gray-200">
                      <h3 class="text-sm font-medium text-gray-500 mb-2">Species in this Population</h3>
                      <div class="flex flex-wrap gap-2">
                        <%= for specie_id <- Enum.take(pop.specie_ids, 10) do %>
                          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                            <%= inspect(specie_id) %>
                          </span>
                        <% end %>
                        <%= if length(pop.specie_ids) > 10 do %>
                          <span class="text-xs text-gray-500">+ <%= length(pop.specie_ids) - 10 %> more</span>
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
