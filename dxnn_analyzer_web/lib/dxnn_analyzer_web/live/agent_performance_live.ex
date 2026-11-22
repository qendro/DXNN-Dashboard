defmodule DxnnAnalyzerWeb.AgentPerformanceLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.AnalyzerBridge

  @legacy_metrics [
    {:fitness, "Fitness"},
    {:raw_total_profit, "Raw Total Profit"},
    {:realized_pl, "Realized P/L"},
    {:unrealized_pl, "Unrealized P/L"},
    {:realized_trades, "Trades"}
  ]
  @episode_metrics [
    {:fitness, "Fitness"},
    {:pnl, "P/L"},
    {:entries, "Entries"},
    {:episodes, "Episodes"},
    {:mean_z, "Mean Z"},
    {:mean_alpha, "Mean Alpha"},
    {:std_alpha, "Alpha Std. Dev."},
    {:mean_abs_exposure, "Mean Absolute Exposure"},
    {:active, "Active"},
    {:holder_episodes, "Holder Episodes"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      case AnalyzerBridge.start_analyzer() do
        :ok -> :ok
        {:error, {:already_started, _}} -> :ok
        _ -> :ok
      end
    end

    experiments = load_available_experiments()

    socket =
      socket
      |> assign(:experiments, experiments)
      |> assign(:selected_experiment, nil)
      |> assign(:agents, [])
      |> assign(:chart_data, [])
      |> assign(:selected_metric, "fitness")
      |> assign(:metrics, @legacy_metrics)
      |> assign(:loading, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_experiment", %{"experiment" => exp_name}, socket) do
    schedule_experiment_load(exp_name, socket)
  end

  @impl true
  def handle_event("select_experiment", %{"value" => exp_name}, socket) do
    schedule_experiment_load(exp_name, socket)
  end

  @impl true
  def handle_event("select_experiment", params, socket) do
    exp_name =
      params
      |> Map.values()
      |> Enum.find_value(fn
        %{"experiment" => value} when is_binary(value) -> value
        _ -> nil
      end) || ""

    schedule_experiment_load(exp_name, socket)
  end

  @impl true
  def handle_event("change_metric", %{"metric" => metric}, socket) do
    sorted_agents = sort_agents_by_metric(socket.assigns.agents, metric)

    socket =
      socket
      |> assign(:selected_metric, metric)
      |> assign(:agents, sorted_agents)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_metric", %{"value" => metric}, socket) do
    sorted_agents = sort_agents_by_metric(socket.assigns.agents, metric)

    socket =
      socket
      |> assign(:selected_metric, metric)
      |> assign(:agents, sorted_agents)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_metric", params, socket) do
    metric =
      params
      |> Map.values()
      |> Enum.find_value(fn
        %{"metric" => value} when is_binary(value) -> value
        _ -> nil
      end) || socket.assigns.selected_metric

    sorted_agents = sort_agents_by_metric(socket.assigns.agents, metric)

    socket =
      socket
      |> assign(:selected_metric, metric)
      |> assign(:agents, sorted_agents)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:load_experiment_data, exp_name}, socket) do
    experiment = Enum.find(socket.assigns.experiments, &(&1.name == exp_name))

    logs_path = resolve_logs_path(experiment)

    {agents, chart_data} =
      if experiment && logs_path do
        parse_agent_trades(logs_path)
      else
        {[], []}
      end

    metrics =
      if Enum.any?(agents, &Map.has_key?(&1, :episodes)),
        do: @episode_metrics,
        else: @legacy_metrics

    selected_metric =
      if Enum.any?(metrics, fn {key, _} -> to_string(key) == socket.assigns.selected_metric end),
        do: socket.assigns.selected_metric,
        else: "fitness"

    sorted_agents = sort_agents_by_metric(agents, selected_metric)

    socket =
      socket
      |> assign(:agents, sorted_agents)
      |> assign(:chart_data, chart_data)
      |> assign(:metrics, metrics)
      |> assign(:selected_metric, selected_metric)
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-w-0">
      <div class="page-container">
        <!-- Header -->
        <.page_header title="Analytics" description="Monitor agent fitness and trading performance." />
        <!-- Experiment Selector -->
        <div class="panel p-6 mb-6">
          <label class="block text-sm font-medium text-gray-700 mb-2">
            Select Experiment
          </label>
          <form phx-change="select_experiment">
            <select
              name="experiment"
              class="w-full px-4 py-2 border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
            >
              <option value="">-- Choose an experiment --</option>
              <%= for exp <- @experiments do %>
                <option value={exp.name} selected={@selected_experiment == exp.name}>
                  <%= exp.name %> (<%= exp.agent_count %> agents)
                </option>
              <% end %>
            </select>
          </form>
        </div>

        <%= if @loading do %>
          <div class="panel p-12 text-center">
            <div class="inline-block animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600">
            </div>
            <p class="mt-4 text-gray-600">Loading agent data...</p>
          </div>
        <% else %>
          <%= if @selected_experiment && length(@agents) > 0 do %>
            <!-- Controls -->
            <div class="panel p-4 mb-6 flex items-center justify-between">
              <form phx-change="change_metric" class="flex items-center gap-4">
                <label class="text-sm font-medium text-gray-700">Metric:</label>
                <select name="metric" class="px-3 py-1 border border-gray-300 rounded-md text-sm">
                  <%= for {key, label} <- @metrics do %>
                    <option value={key} selected={@selected_metric == to_string(key)}>
                      <%= label %>
                    </option>
                  <% end %>
                </select>
              </form>
              <span class="text-sm text-gray-600">
                Total Agents: <span class="font-semibold"><%= length(@agents) %></span>
              </span>
            </div>
            <!-- Chart -->
            <div class="panel p-6 mb-6">
              <h2 class="section-title mb-4">Performance Over Time</h2>
              <div class="bg-blue-50 border border-blue-200 rounded p-3 mb-4 text-sm text-blue-800">
                💡 <strong>Chart:</strong>
                Shows <%= metric_label(@selected_metric) %> progression across all agent evaluations with 200-point Simple Moving Average (red line)
              </div>
              <div
                id="performanceChartContainer"
                class="relative h-96"
                phx-hook="PerformanceChart"
                data-chart={
                  Jason.encode!(%{
                    data: prepare_chart_data(@chart_data, @selected_metric),
                    metric: @selected_metric,
                    label: metric_label(@selected_metric)
                  })
                }
              >
                <canvas id="performanceChart" phx-update="ignore" class="w-full h-full"></canvas>
              </div>
            </div>
            <!-- Top Agents Table -->
            <div class="panel p-6">
              <h2 class="section-title mb-4">Top 50 Agents</h2>
              <div class="overflow-x-auto">
                <table class="min-w-full divide-y divide-gray-200">
                  <thead class="bg-gray-50">
                    <tr>
                      <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Rank
                      </th>
                      <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        PID
                      </th>
                      <%= for {_key, label} <- @metrics do %>
                        <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                          <%= label %>
                        </th>
                      <% end %>
                    </tr>
                  </thead>
                  <tbody class="bg-white divide-y divide-gray-200">
                    <%= for {agent, idx} <- Enum.with_index(Enum.take(@agents, 50), 1) do %>
                      <tr class="hover:bg-gray-50">
                        <td class="px-4 py-3 text-sm text-gray-900"><%= idx %></td>
                        <td class="px-4 py-3 text-sm font-mono text-blue-600"><%= agent.pid %></td>
                        <%= for {key, _label} <- @metrics do %>
                          <td class="px-4 py-3 text-sm text-right text-gray-900">
                            <%= format_number(Map.get(agent, key)) %>
                          </td>
                        <% end %>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          <% else %>
            <%= if @selected_experiment do %>
              <div class="panel p-12 text-center">
                <p class="text-gray-500">No agent data found for this experiment</p>
                <p class="text-sm text-gray-400 mt-2">
                  Make sure the experiment has logs/Benchmarker/agent_trades.log
                </p>
              </div>
            <% end %>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper functions

  defp load_available_experiments do
    try do
      AnalyzerBridge.list_contexts()
    rescue
      _ -> []
    catch
      :exit, _ -> []
    end
  end

  defp parse_agent_trades(logs_path) do
    agent_trades_path = Path.join([logs_path, "Benchmarker", "agent_trades.log"])

    if File.exists?(agent_trades_path) do
      case File.read(agent_trades_path) do
        {:ok, contents} ->
          lines = String.split(contents, "\n", trim: true)

          {agents_map, all_trades} =
            Enum.reduce(lines, {%{}, []}, fn line, {agents_acc, trades_acc} ->
              case parse_fitness_eval_line(line) do
                {:ok, data} ->
                  pid = data.pid

                  # Keep latest metrics per PID and all samples for charting.
                  updated_agents = Map.put(agents_acc, pid, data)
                  {updated_agents, [data | trades_acc]}

                :error ->
                  {agents_acc, trades_acc}
              end
            end)

          agents = Map.values(agents_map)
          chart_data = Enum.reverse(all_trades)
          {agents, chart_data}

        {:error, _reason} ->
          {[], []}
      end
    else
      {[], []}
    end
  end

  defp sort_agents_by_metric(agents, metric) do
    metric_atom = String.to_atom(metric)

    agents
    |> Enum.sort_by(fn agent -> Map.get(agent, metric_atom, 0) end, :desc)
  end

  defp parse_fitness_eval_line(line) do
    with true <- String.contains?(line, "FITNESS_EVAL"),
         {:ok, pid} <- extract_pid(line),
         {:ok, metrics} <- extract_metrics(line) do
      {:ok, Map.put(metrics, :pid, pid)}
    else
      _ -> :error
    end
  end

  defp extract_pid(line) do
    case Regex.run(~r/\[AGENT:(<[0-9.]+>)\]/, line) do
      [_, pid] -> {:ok, pid}
      _ -> :error
    end
  end

  defp extract_metrics(line) do
    fields =
      Regex.scan(~r/(\w+)=([^\s|]+)/, line)
      |> Map.new(fn [_, key, value] -> {key, value} end)

    metrics = if Map.has_key?(fields, "episodes"), do: @episode_metrics, else: @legacy_metrics

    Enum.reduce_while(metrics, {:ok, %{}}, fn {key, _label}, {:ok, acc} ->
      value = Map.get(fields, to_string(key), "")

      parser =
        if key in [:realized_trades, :entries, :episodes, :holder_episodes],
          do: &parse_integer/1,
          else: &parse_float/1

      case parser.(value) do
        {:ok, number} -> {:cont, {:ok, Map.put(acc, key, number)}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp parse_float(value) do
    case Float.parse(value) do
      {number, ""} ->
        {:ok, number}

      _ ->
        case Integer.parse(value) do
          {number, ""} -> {:ok, number * 1.0}
          _ -> :error
        end
    end
  end

  defp parse_integer(value) do
    case Integer.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp schedule_experiment_load(exp_name, socket) do
    socket =
      socket
      |> assign(:loading, true)
      |> assign(:selected_experiment, exp_name)

    send(self(), {:load_experiment_data, exp_name})

    {:noreply, socket}
  end

  defp resolve_logs_path(nil), do: nil

  defp resolve_logs_path(experiment) do
    candidates =
      [
        Map.get(experiment, :logs_path),
        Path.join([Map.get(experiment, :bundle_root) || "", "logs"]),
        Path.join([Map.get(experiment, :path) || "", "logs"]),
        derive_logs_from_mnesia_path(Map.get(experiment, :mnesia_path)),
        derive_logs_from_mnesia_path(Map.get(experiment, :path))
      ]
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&Path.expand/1)
      |> Enum.uniq()

    Enum.find(candidates, &File.dir?/1)
  end

  defp derive_logs_from_mnesia_path(nil), do: nil

  defp derive_logs_from_mnesia_path(path) when is_binary(path) do
    expanded = Path.expand(path)

    cond do
      Path.basename(expanded) == "Mnesia.nonode@nohost" ->
        Path.join(Path.dirname(expanded), "logs")

      true ->
        Path.join(expanded, "logs")
    end
  end

  defp prepare_chart_data(chart_data, metric) do
    raw_data =
      chart_data
      |> Enum.with_index(1)
      |> Enum.map(fn {data, idx} ->
        %{x: idx, y: Map.get(data, String.to_atom(metric), 0)}
      end)

    sma_data = calculate_sma(raw_data, 200)

    %{
      raw: raw_data,
      sma: sma_data
    }
  end

  defp calculate_sma(data, window_size) do
    values = Enum.map(data, & &1.y)

    data
    |> Enum.with_index()
    |> Enum.map(fn {point, idx} ->
      if idx >= window_size - 1 do
        window_values = Enum.slice(values, (idx - window_size + 1)..idx)
        avg = Enum.sum(window_values) / window_size
        %{x: point.x, y: avg}
      else
        # For points before we have enough data, return nil
        %{x: point.x, y: nil}
      end
    end)
  end

  defp metric_label(metric) do
    Enum.find_value(@legacy_metrics ++ @episode_metrics, "Value", fn {key, label} ->
      if to_string(key) == metric, do: label
    end)
  end

  defp format_number(nil), do: "—"

  defp format_number(num) when is_float(num) do
    :erlang.float_to_binary(num, decimals: 2)
  end

  defp format_number(num), do: to_string(num)
end
