defmodule DxnnAnalyzerWeb.ComparatorLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.AnalyzerBridge

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :comparison, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    context = params["context"]
    ids_param = params["ids"]

    socket =
      if context && ids_param do
        agent_ids = parse_agent_ids(ids_param)

        case AnalyzerBridge.compare_agents(agent_ids, context) do
          comparison when is_map(comparison) ->
            socket
            |> assign(:context, context)
            |> assign(:agent_ids, agent_ids)
            |> assign(:comparison, comparison)
            |> assign(:error, nil)

          _ ->
            socket
            |> assign(:context, context)
            |> assign(:error, "Failed to compare agents")
        end
      else
        assign(socket, :error, "Missing context or agent IDs")
      end

    {:noreply, socket}
  end

  defp parse_agent_ids(ids_str) do
    ids_str
    |> URI.decode()
    |> String.split(",")
    |> Enum.map(fn id_str ->
      {agent_id, _} = Code.eval_string(id_str)
      agent_id
    end)
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
          <h1 class="text-3xl font-bold text-gray-900">Agent Comparison</h1>
        </div>

        <%= if @error do %>
          <div class="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded mb-6">
            <%= @error %>
          </div>
        <% end %>

        <%= if @comparison do %>
          <div class="space-y-6">
            <!-- Comparison Summary -->
            <div class="bg-white shadow rounded-lg p-6">
              <h2 class="text-xl font-semibold mb-4">Comparison Summary</h2>
              <p class="text-gray-600">
                Comparing <%= length(@agent_ids) %> agents from context: <%= @context %>
              </p>
            </div>

            <!-- Comparison Data -->
            <div class="bg-white shadow rounded-lg p-6">
              <h2 class="text-xl font-semibold mb-4">Comparison Results</h2>
              <div class="overflow-x-auto">
                <pre class="bg-gray-50 p-4 rounded text-sm"><%= inspect(@comparison, pretty: true, limit: :infinity) %></pre>
              </div>
            </div>

            <!-- Agent IDs -->
            <div class="bg-white shadow rounded-lg p-6">
              <h2 class="text-xl font-semibold mb-4">Compared Agents</h2>
              <div class="space-y-2">
                <%= for agent_id <- @agent_ids do %>
                  <div class="flex items-center justify-between border border-gray-200 rounded p-3">
                    <span class="font-mono text-sm"><%= inspect(agent_id) %></span>
                    <.link
                      navigate={~p"/agents/#{URI.encode(inspect(agent_id))}?context=#{@context}"}
                      class="text-blue-600 hover:text-blue-800 text-sm"
                    >
                      View Details
                    </.link>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
