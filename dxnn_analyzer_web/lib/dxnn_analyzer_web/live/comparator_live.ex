defmodule DxnnAnalyzerWeb.ComparatorLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.{AgentId, AnalyzerBridge}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, comparison: nil, context: nil, error: nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    context = params["context"]
    socket = assign(socket, context: context, comparison: nil, agent_ids: [], error: nil)

    result =
      with true <- is_binary(context) and context != "",
           {:ok, ids} <- AgentId.parse_many(params["ids"]) do
        {ids, AnalyzerBridge.compare_agents(ids, context)}
      else
        false -> {:error, "Choose an experiment from the dashboard first"}
        error -> error
      end

    socket =
      case result do
        {ids, comparison} when is_list(ids) and is_map(comparison) ->
          assign(socket, agent_ids: ids, comparison: comparison)

        {:error, message} ->
          assign(socket, :error, message)

        {_, {:error, reason}} ->
          assign(socket, :error, "Could not compare agents: #{inspect(reason)}")

        _ ->
          assign(socket, :error, "Could not compare agents")
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-w-0">
      <div class="page-container">
        <div class="mb-6">
          <.link
            navigate={if @context, do: ~p"/agents?context=#{@context}", else: ~p"/"}
            class="text-blue-600 hover:text-blue-800 text-sm mb-2 inline-block"
          >
            ← <%= if @context, do: "Back to experiment", else: "Back to dashboard" %>
          </.link>
          <h1 class="page-title">Agent Comparison</h1>
        </div>

        <%= if @error do %>
          <div class="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded mb-6">
            <%= @error %>
          </div>
        <% end %>

        <%= if @comparison do %>
          <div class="space-y-6">
            <!-- Comparison Summary -->
            <div class="panel p-6">
              <h2 class="section-title mb-4">Comparison Summary</h2>
              <p class="text-gray-600">
                Comparing <%= length(@agent_ids) %> agents from context: <%= @context %>
              </p>
            </div>
            <!-- Comparison Data -->
            <div class="panel p-6">
              <h2 class="section-title mb-4">Comparison Results</h2>
              <div class="overflow-x-auto">
                <pre class="bg-gray-50 p-4 rounded text-sm"><%= inspect(@comparison, pretty: true, limit: :infinity) %></pre>
              </div>
            </div>
            <!-- Agent IDs -->
            <div class="panel p-6">
              <h2 class="section-title mb-4">Compared Agents</h2>
              <div class="space-y-2">
                <%= for agent_id <- @agent_ids do %>
                  <div class="flex items-center justify-between border border-gray-200 rounded p-3">
                    <span class="font-mono text-sm"><%= inspect(agent_id) %></span>
                    <.link
                      navigate={~p"/agents/#{inspect(agent_id)}?context=#{@context}"}
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
