defmodule DxnnAnalyzerWeb.SpotPricingLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.AWS.SpotPricingBridge

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:loading, false)
      |> assign(:pricing_data, [])
      |> assign(:last_updated, nil)
      |> assign(:error, nil)
      |> assign(:sort_by, :instance_type)
      |> assign(:sort_order, :asc)

    {:ok, socket}
  end

  @impl true
  def handle_event("refresh_pricing", _params, socket) do
    require Logger
    Logger.info("Refresh pricing clicked, fetching data...")
    
    socket = assign(socket, :loading, true)
    
    # Fetch pricing synchronously to avoid timeout issues
    case SpotPricingBridge.get_spot_pricing() do
      {:ok, pricing_data} ->
        Logger.info("Successfully fetched #{length(pricing_data)} instance prices")
        # Calculate price per GiB for each instance
        enriched_data = Enum.map(pricing_data, fn instance ->
          price_per_gib = calculate_price_per_gib(instance.lowest_price, instance.memory)
          Map.put(instance, :price_per_gib, price_per_gib)
        end)
        
        socket =
          socket
          |> assign(:pricing_data, sort_pricing_data(enriched_data, socket.assigns.sort_by, socket.assigns.sort_order))
          |> assign(:last_updated, DateTime.utc_now())
          |> assign(:loading, false)
          |> assign(:error, nil)
        {:noreply, socket}

      {:error, reason} ->
        Logger.error("Failed to fetch pricing: #{reason}")
        socket =
          socket
          |> assign(:loading, false)
          |> assign(:error, reason)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("sort", %{"column" => column}, socket) do
    column_atom = String.to_existing_atom(column)
    
    # Toggle sort order if clicking the same column, otherwise default to ascending
    sort_order = if socket.assigns.sort_by == column_atom do
      if socket.assigns.sort_order == :asc, do: :desc, else: :asc
    else
      :asc
    end
    
    sorted_data = sort_pricing_data(socket.assigns.pricing_data, column_atom, sort_order)
    
    socket =
      socket
      |> assign(:pricing_data, sorted_data)
      |> assign(:sort_by, column_atom)
      |> assign(:sort_order, sort_order)
    
    {:noreply, socket}
  end

  defp calculate_price_per_gib(nil, _memory), do: nil
  defp calculate_price_per_gib(_price, memory) when memory == 0, do: nil
  defp calculate_price_per_gib(price, memory) when is_binary(price) and is_number(memory) do
    price_float = String.to_float(price)
    (price_float / memory) |> Float.round(4) |> Float.to_string()
  end
  defp calculate_price_per_gib(_price, _memory), do: nil

  defp sort_pricing_data(data, sort_by, sort_order) do
    sorted = Enum.sort_by(data, fn item ->
      value = Map.get(item, sort_by)
      
      # Handle nil values and convert prices to floats for proper sorting
      case {sort_by, value} do
        {:us_east_1_price, nil} -> if sort_order == :asc, do: 999999, else: -1
        {:us_east_1_price, price} -> String.to_float(price)
        {:lowest_price, nil} -> if sort_order == :asc, do: 999999, else: -1
        {:lowest_price, price} -> String.to_float(price)
        {:price_per_gib, nil} -> if sort_order == :asc, do: 999999, else: -1
        {:price_per_gib, price} -> String.to_float(price)
        {:vcpus, v} -> v
        {:memory, v} -> v
        {_, v} -> v
      end
    end)
    
    if sort_order == :desc, do: Enum.reverse(sorted), else: sorted
  end

  defp build_launch_url(instance) do
    # Add $0.10 buffer to lowest price for max spot price
    max_price = (String.to_float(instance.lowest_price) + 0.10)
    |> Float.round(2)
    |> Float.to_string()
    
    # Build URL with query params
    "/aws-deployment?instance_type=#{URI.encode(instance.instance_type)}&region=#{URI.encode(instance.lowest_region)}&spot_max_price=#{max_price}&auto_open_modal=true"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="mb-8 flex justify-between items-center">
          <div>
            <h1 class="text-3xl font-bold text-gray-900">AWS Spot Instance Pricing</h1>
            <p class="mt-2 text-gray-600">Real-time spot prices for DXNN compute instances</p>
          </div>
          <div class="flex gap-2">
            <.link
              navigate={~p"/aws-deployment"}
              class="bg-gray-600 text-white px-4 py-2 rounded-md hover:bg-gray-700 transition"
            >
              ← AWS Deployment
            </.link>
            <.link
              navigate={~p"/"}
              class="bg-gray-600 text-white px-4 py-2 rounded-md hover:bg-gray-700 transition"
            >
              ← Dashboard
            </.link>
            <button
              phx-click="refresh_pricing"
              disabled={@loading}
              class={"bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition #{if @loading, do: "opacity-50 cursor-not-allowed"}"}
            >
              <%= if @loading do %>
                <span class="flex items-center space-x-2">
                  <div class="animate-spin h-4 w-4 border-2 border-white border-t-transparent rounded-full"></div>
                  <span>Loading...</span>
                </span>
              <% else %>
                🔄 Refresh Prices
              <% end %>
            </button>
          </div>
        </div>

        <%= if @last_updated do %>
          <div class="mb-4 text-sm text-gray-600">
            Last updated: <%= Calendar.strftime(@last_updated, "%Y-%m-%d %H:%M:%S UTC") %>
          </div>
        <% end %>

        <%= if @error do %>
          <div class="mb-6 bg-red-50 border border-red-200 rounded-lg p-4">
            <div class="flex items-center space-x-2">
              <span class="text-red-600 text-lg">⚠️</span>
              <span class="text-red-800 font-medium">Error loading pricing data</span>
            </div>
            <p class="text-sm text-red-700 mt-2"><%= @error %></p>
          </div>
        <% end %>

        <%= if Enum.empty?(@pricing_data) and not @loading do %>
          <div class="bg-white shadow rounded-lg p-12 text-center">
            <div class="text-gray-400 text-6xl mb-4">💰</div>
            <h3 class="text-xl font-semibold text-gray-700 mb-2">No Pricing Data</h3>
            <p class="text-gray-600 mb-6">Click "Refresh Prices" to load current spot instance pricing</p>
            <button
              phx-click="refresh_pricing"
              class="bg-blue-600 text-white px-6 py-3 rounded-md hover:bg-blue-700 transition"
            >
              🔄 Load Pricing Data
            </button>
          </div>
        <% else %>
          <div class="bg-white shadow rounded-lg overflow-hidden">
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-200">
                <thead class="bg-gray-50">
                  <tr>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      <button
                        phx-click="sort"
                        phx-value-column="instance_type"
                        class="flex items-center space-x-1 hover:text-gray-700"
                      >
                        <span>Instance Type</span>
                        <%= if @sort_by == :instance_type do %>
                          <span class="text-blue-600"><%= if @sort_order == :asc, do: "▲", else: "▼" %></span>
                        <% end %>
                      </button>
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      <button
                        phx-click="sort"
                        phx-value-column="vcpus"
                        class="flex items-center space-x-1 hover:text-gray-700"
                      >
                        <span>vCPUs</span>
                        <%= if @sort_by == :vcpus do %>
                          <span class="text-blue-600"><%= if @sort_order == :asc, do: "▲", else: "▼" %></span>
                        <% end %>
                      </button>
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      <button
                        phx-click="sort"
                        phx-value-column="memory"
                        class="flex items-center space-x-1 hover:text-gray-700"
                      >
                        <span>Memory (GiB)</span>
                        <%= if @sort_by == :memory do %>
                          <span class="text-blue-600"><%= if @sort_order == :asc, do: "▲", else: "▼" %></span>
                        <% end %>
                      </button>
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      <button
                        phx-click="sort"
                        phx-value-column="us_east_1_price"
                        class="flex items-center space-x-1 hover:text-gray-700"
                      >
                        <span>us-east-1 Price</span>
                        <%= if @sort_by == :us_east_1_price do %>
                          <span class="text-blue-600"><%= if @sort_order == :asc, do: "▲", else: "▼" %></span>
                        <% end %>
                      </button>
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      <button
                        phx-click="sort"
                        phx-value-column="lowest_price"
                        class="flex items-center space-x-1 hover:text-gray-700"
                      >
                        <span>Lowest Spot Price</span>
                        <%= if @sort_by == :lowest_price do %>
                          <span class="text-blue-600"><%= if @sort_order == :asc, do: "▲", else: "▼" %></span>
                        <% end %>
                      </button>
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      <button
                        phx-click="sort"
                        phx-value-column="price_per_gib"
                        class="flex items-center space-x-1 hover:text-gray-700"
                      >
                        <span>$/hr per GiB</span>
                        <%= if @sort_by == :price_per_gib do %>
                          <span class="text-blue-600"><%= if @sort_order == :asc, do: "▲", else: "▼" %></span>
                        <% end %>
                      </button>
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-gray-200">
                  <%= for instance <- @pricing_data do %>
                    <tr class="hover:bg-gray-50 transition">
                      <td class="px-6 py-4 whitespace-nowrap">
                        <span class="text-sm font-mono font-semibold text-gray-900">
                          <%= instance.instance_type %>
                        </span>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <span class="text-sm text-gray-700">
                          <%= instance.vcpus %>
                        </span>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <span class="text-sm text-gray-700">
                          <%= instance.memory %>
                        </span>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <%= if instance.us_east_1_price do %>
                          <span class="text-sm font-semibold text-green-700">
                            $<%= instance.us_east_1_price %>/hr
                          </span>
                        <% else %>
                          <span class="text-sm text-gray-400">N/A</span>
                        <% end %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <%= if instance.lowest_price do %>
                          <div class="flex flex-col">
                            <span class="text-sm font-semibold text-blue-700">
                              $<%= instance.lowest_price %>/hr
                            </span>
                            <span class="text-xs text-gray-500">
                              <%= instance.lowest_region %>
                            </span>
                          </div>
                        <% else %>
                          <span class="text-sm text-gray-400">N/A</span>
                        <% end %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <%= if instance.price_per_gib do %>
                          <span class="text-sm font-semibold text-purple-700">
                            $<%= instance.price_per_gib %>
                          </span>
                        <% else %>
                          <span class="text-sm text-gray-400">N/A</span>
                        <% end %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <%= if instance.lowest_price && instance.lowest_region do %>
                          <.link
                            navigate={build_launch_url(instance)}
                            class="inline-flex items-center px-3 py-1.5 bg-green-600 text-white text-sm font-medium rounded-md hover:bg-green-700 transition"
                          >
                            🚀 Launch
                          </.link>
                        <% else %>
                          <span class="text-sm text-gray-400">N/A</span>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>

          <div class="mt-6 bg-blue-50 border border-blue-200 rounded-lg p-4">
            <h3 class="text-sm font-semibold text-blue-900 mb-2">💡 About These Instances</h3>
            <ul class="text-sm text-blue-800 space-y-1">
              <li>• <strong>C-family:</strong> Compute-optimized for CPU-intensive DXNN training</li>
              <li>• <strong>M-family:</strong> General purpose with balanced compute and memory</li>
              <li>• <strong>T-family:</strong> Burstable performance for development/testing</li>
              <li>• <strong>$/hr per GiB:</strong> Cost efficiency metric (lowest price ÷ memory) - lower is better</li>
              <li>• Prices update in real-time and vary by availability</li>
              <li>• Spot instances can save up to 90% vs on-demand pricing</li>
            </ul>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
