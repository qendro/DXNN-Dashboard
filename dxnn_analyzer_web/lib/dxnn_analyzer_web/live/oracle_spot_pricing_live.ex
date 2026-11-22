defmodule DxnnAnalyzerWeb.OracleSpotPricingLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.OCI.SpotPricingBridge

  @columns [
    {:shape, "Shape"},
    {:gpus, "GPUs"},
    {:ocpus, "OCPUs"},
    {:vcpus, "vCPUs"},
    {:memory, "RAM (GB)"},
    {:on_demand, "On-demand / hr"},
    {:on_demand_monthly, "On-demand / month"},
    {:preemptible, "Preemptible / hr"},
    {:monthly, "Preemptible / month"},
    {:per_vcpu, "Per vCPU / hr"},
    {:per_gpu, "Per GPU / hr"},
    {:per_gb, "Per GB / hr"}
  ]
  @sort_columns Map.new(@columns, fn {key, _} -> {Atom.to_string(key), key} end)

  def mount(_, _, socket) do
    socket =
      assign(socket,
        catalog: nil,
        pricing_data: [],
        loading: false,
        error: nil,
        form: %{"ocpus" => "8", "memory" => "32", "hours" => "730"},
        quoted: %{ocpus: 8, memory: 32, hours: 730},
        sort_by: :preemptible,
        sort_order: :asc,
        instance_kind: "all"
      )

    {:ok, if(connected?(socket), do: fetch(socket), else: socket)}
  end

  def handle_event("refresh_pricing", _, %{assigns: %{loading: true}} = socket),
    do: {:noreply, socket}

  def handle_event("refresh_pricing", _, socket), do: {:noreply, fetch(socket)}

  def handle_event("configure", params, socket) do
    form = Map.take(params, ~w(ocpus memory hours))
    socket = assign(socket, :form, Map.merge(socket.assigns.form, form))
    {:noreply, recalculate(socket)}
  end

  def handle_event("filter", %{"kind" => kind}, socket) when kind in ["all", "cpu", "gpu"],
    do: {:noreply, assign(socket, :instance_kind, kind)}

  def handle_event("filter", _, socket), do: {:noreply, socket}

  def handle_event("sort", %{"column" => column}, socket) do
    case Map.fetch(@sort_columns, column) do
      {:ok, key} ->
        direction =
          if socket.assigns.sort_by == key and socket.assigns.sort_order == :asc,
            do: :desc,
            else: :asc

        {:noreply, socket |> assign(sort_by: key, sort_order: direction) |> sort_rows()}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_async(:pricing, {:ok, {:ok, catalog}}, socket) do
    {:noreply, socket |> assign(catalog: catalog, loading: false, error: nil) |> recalculate()}
  end

  def handle_async(:pricing, {:ok, {:error, error}}, socket),
    do: {:noreply, assign(socket, loading: false, error: error)}

  def handle_async(:pricing, {:exit, _}, socket),
    do:
      {:noreply,
       assign(socket, loading: false, error: "Oracle pricing refresh stopped. Try again.")}

  defp fetch(socket) do
    bridge = Application.get_env(:dxnn_analyzer_web, :oracle_pricing_bridge, SpotPricingBridge)

    socket
    |> assign(loading: true, error: nil)
    |> start_async(:pricing, fn -> bridge.fetch_catalog() end)
  end

  defp recalculate(socket) do
    form = socket.assigns.form
    ocpus = integer(form["ocpus"])
    memory = integer(form["memory"])
    hours = integer(form["hours"])
    # Validate input even while the first catalog fetch is in flight.
    catalog = socket.assigns.catalog || %{rates: []}

    case SpotPricingBridge.quote(catalog, ocpus, memory, hours) do
      {:ok, rows} ->
        socket
        |> assign(
          pricing_data: rows,
          error: nil,
          quoted: %{ocpus: ocpus, memory: memory, hours: hours}
        )
        |> sort_rows()

      {:error, error} ->
        assign(socket, error: error, pricing_data: [])
    end
  end

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp integer(_), do: nil

  defp sort_rows(socket) do
    key = socket.assigns.sort_by

    {available, missing} =
      Enum.split_with(socket.assigns.pricing_data, &(Map.get(&1, key) != nil))

    sorted = Enum.sort_by(available, &{Map.get(&1, key), &1.shape}, socket.assigns.sort_order)
    assign(socket, :pricing_data, sorted ++ Enum.sort_by(missing, & &1.shape))
  end

  defp money(nil, _), do: "—"
  defp money(value, decimals), do: "$" <> :erlang.float_to_binary(value * 1.0, decimals: decimals)
  defp timestamp(nil), do: "Unavailable"
  defp timestamp(date), do: Calendar.strftime(date, "%Y-%m-%d %H:%M UTC")
  defp columns, do: @columns
  defp visible_rows(rows, "cpu"), do: Enum.filter(rows, &(&1.kind == :cpu))
  defp visible_rows(rows, "gpu"), do: Enum.filter(rows, &(&1.kind == :gpu))
  defp visible_rows(rows, _), do: rows

  def render(assigns) do
    ~H"""
    <div class="min-w-0">
      <div class="page-container space-y-5">
        <.page_header
          title="Oracle Spot Pricing"
          description="Compare Oracle CPU and GPU instance prices for DXNN workloads."
        >
          <:actions>
            <.link navigate={~p"/spot-pricing"} class="btn btn-secondary">AWS Spot Pricing</.link>
            <button phx-click="refresh_pricing" disabled={@loading} class="btn btn-primary">
              Refresh prices
            </button>
          </:actions>
        </.page_header>
        <form
          id="oracle-pricing-config"
          phx-change="configure"
          phx-submit="configure"
          class="panel p-5 grid grid-cols-1 sm:grid-cols-3 gap-4"
        >
          <label class="text-sm font-medium text-gray-700">
            Flex CPU OCPUs per instance<input
              type="number"
              name="ocpus"
              min="1"
              max="126"
              step="1"
              value={@form["ocpus"]}
              phx-debounce="300"
              class="block mt-1 w-full rounded border-gray-300"
            />
          </label>
          <label class="text-sm font-medium text-gray-700">
            Flex CPU memory per instance (GB)<input
              type="number"
              name="memory"
              min="1"
              max="1454"
              step="1"
              value={@form["memory"]}
              phx-debounce="300"
              class="block mt-1 w-full rounded border-gray-300"
            />
          </label>
          <label class="text-sm font-medium text-gray-700">
            Hours per month<input
              type="number"
              name="hours"
              min="1"
              max="744"
              step="1"
              value={@form["hours"]}
              phx-debounce="300"
              class="block mt-1 w-full rounded border-gray-300"
            />
          </label>
        </form>
        <div class="panel p-5 text-sm text-gray-600 space-y-2">
          <p>
            Oracle calls spot capacity <strong>preemptible</strong>. Eligible shapes use its published 50% discount. GPU2 and GPU3 are listed as eligible; A10 is not listed, and bare-metal L40S does not support preemptible capacity. All requested shapes include on-demand pricing. Capacity varies by region.
          </p>
          <p>
            CPU Flex rows use the OCPUs and memory selected above. GPU rows use their fixed GPU count, OCPUs, and system RAM; their instance price is the per-GPU rate multiplied by GPU count, with host CPU and RAM included. One OCPU is 2 vCPUs on x86 and Arm A4, and 1 vCPU on Arm A1. Hardware performance still varies.
          </p>
          <p>
            USD compute only. Boot volumes, Object Storage, network, paid OS images, taxes, account discounts, and free-tier allowances are excluded. A1 uses its paid rate after any allowance. These estimates do not check regional availability.
          </p>
          <div class="flex flex-wrap gap-4">
            <a
              href="https://www.oracle.com/cloud/price-list/"
              target="_blank"
              rel="noopener noreferrer"
              class="text-blue-700 underline"
            >
              Oracle price list
            </a>
            <a
              href="https://docs.oracle.com/en-us/iaas/Content/Compute/Concepts/preemptible.htm"
              target="_blank"
              rel="noopener noreferrer"
              class="text-blue-700 underline"
            >
              Preemptible shapes and terms
            </a>
            <a
              href={SpotPricingBridge.catalog_url()}
              target="_blank"
              rel="noopener noreferrer"
              class="text-blue-700 underline"
            >
              Public USD catalog
            </a>
          </div>
        </div>
        <div
          :if={@error}
          role="alert"
          class="bg-red-50 border border-red-200 rounded-lg p-4 text-red-800"
        >
          <%= @error %>
        </div>
        <p :if={@loading} role="status" class="text-sm text-gray-600">
          Fetching current Oracle list prices…
        </p>
        <div :if={@catalog} class="flex flex-wrap justify-between gap-2 text-sm text-gray-600">
          <span>
            Fetched: <%= timestamp(@catalog.fetched_at) %> · Catalog updated: <%= timestamp(
              @catalog.catalog_updated_at
            ) %>
          </span>
          <span>
            CPU Flex: <%= @quoted.ocpus %> OCPUs · <%= @quoted.memory %> GB · All shapes: <%= @quoted.hours %> hours/month
          </span>
        </div>
        <div class="flex gap-2" aria-label="Instance type">
          <button
            :for={
              {kind, label} <- [
                {"all", "All instances"},
                {"cpu", "CPU instances"},
                {"gpu", "GPU instances"}
              ]
            }
            phx-click="filter"
            phx-value-kind={kind}
            aria-pressed={@instance_kind == kind}
            class={if @instance_kind == kind, do: "btn btn-primary", else: "btn btn-secondary"}
          >
            <%= label %>
          </button>
        </div>
        <div :if={@pricing_data != []} class="panel overflow-hidden">
          <div class="overflow-x-auto">
            <table id="oracle-pricing-table" class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th
                    :for={{key, label} <- columns()}
                    scope="col"
                    aria-sort={
                      if @sort_by == key,
                        do: if(@sort_order == :asc, do: "ascending", else: "descending"),
                        else: "none"
                    }
                    class="px-5 py-3 text-left text-xs font-medium text-gray-600 whitespace-nowrap"
                  >
                    <button phx-click="sort" phx-value-column={key}>
                      <%= label %><span :if={@sort_by == key}><%= if @sort_order == :asc, do: " ▲", else: " ▼" %></span>
                    </button>
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-100">
                <tr
                  :for={row <- visible_rows(@pricing_data, @instance_kind)}
                  id={"oracle-price-#{row.shape}"}
                >
                  <td class="px-5 py-4 text-sm">
                    <div class="font-mono font-medium text-gray-900"><%= row.shape %></div>
                    <div class="text-xs text-gray-500">
                      <%= row.processor %> · <%= row.architecture %>
                    </div>
                    <div class="text-xs text-gray-500">
                      <%= if row.kind == :gpu,
                        do: "Fixed GPU shape · #{row.gpus} × #{row.gpu_memory} GB VRAM",
                        else: "CPU Flex" %>
                    </div>
                    <p :if={row.eligibility_note} class="text-xs text-amber-700 mt-1">
                      <%= row.eligibility_note %>
                    </p>
                    <p :if={row.reason} class="text-xs text-amber-700 mt-1"><%= row.reason %></p>
                  </td>
                  <td class="px-5 py-4 text-sm text-gray-700"><%= row.gpus %></td>
                  <td class="px-5 py-4 text-sm text-gray-700"><%= row.ocpus %></td>
                  <td class="px-5 py-4 text-sm text-gray-700"><%= row.vcpus %></td>
                  <td class="px-5 py-4 text-sm text-gray-700"><%= row.memory %></td>
                  <td class="px-5 py-4 text-sm tabular-nums text-gray-600">
                    <%= money(row.on_demand, 4) %>
                  </td>
                  <td class="px-5 py-4 text-sm tabular-nums text-gray-600">
                    <%= money(row.on_demand_monthly, 2) %>
                  </td>
                  <td class="px-5 py-4 text-sm tabular-nums font-semibold text-green-700">
                    <%= money(row.preemptible, 4) %>
                    <span
                      :if={!row.preemptible_supported}
                      class="block text-xs font-normal text-gray-500"
                    >
                      Not available
                    </span>
                  </td>
                  <td class="px-5 py-4 text-sm tabular-nums text-gray-700">
                    <%= money(row.monthly, 2) %>
                  </td>
                  <td class="px-5 py-4 text-sm tabular-nums text-gray-700">
                    <%= money(row.per_vcpu, 6) %>
                  </td>
                  <td class="px-5 py-4 text-sm tabular-nums text-gray-700">
                    <%= money(row.per_gpu, 6) %>
                  </td>
                  <td class="px-5 py-4 text-sm tabular-nums text-gray-700">
                    <%= money(row.per_gb, 6) %>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        <p :if={!@loading && @catalog == nil} class="text-sm text-gray-600">
          Refresh prices to load Oracle's public catalog. No OCI credentials are needed.
        </p>
        <details :if={@catalog} class="text-sm text-gray-600 panel p-4">
          <summary class="cursor-pointer font-medium">Unit prices and calculation</summary>
          <p class="mt-3">
            CPU Flex hourly estimate = (OCPUs × CPU rate + GB × memory rate) × 0.5. Eligible GPU hourly estimate = GPU count × GPU rate × 0.5. Unsupported shapes show on-demand costs only. Monthly estimates use the hours selected above.
          </p>
          <ul class="mt-2 space-y-1">
            <li :for={rate <- @catalog.rates}>
              <%= rate.shape %>:
              <%= if rate.kind == :gpu do %>
                <%= money(rate.gpu_rate, 6) %>/GPU/hr × <%= rate.gpus %> GPUs
              <% else %>
                <%= money(rate.cpu_rate, 6) %>/OCPU/hr + <%= money(rate.memory_rate, 6) %>/GB/hr
              <% end %>
            </li>
          </ul>
        </details>
      </div>
    </div>
    """
  end
end
