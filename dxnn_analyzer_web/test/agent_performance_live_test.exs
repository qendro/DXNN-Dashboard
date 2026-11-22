defmodule DxnnAnalyzerWeb.AgentPerformanceLiveTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias DxnnAnalyzerWeb.AgentPerformanceLive

  setup do
    root = Path.join(System.tmp_dir!(), "agent-performance-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "Benchmarker"))
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  defp load(root, contents) do
    File.write!(Path.join([root, "Benchmarker", "agent_trades.log"]), contents)

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        experiments: [%{name: "test", logs_path: root, agent_count: 240}],
        selected_experiment: "test",
        selected_metric: "raw_total_profit"
      }
    }

    {:noreply, socket} = AgentPerformanceLive.handle_info({:load_experiment_data, "test"}, socket)
    socket.assigns
  end

  test "episode evaluations populate agents, charts, and native metric columns", %{root: root} do
    assigns = load(root, """
    generation_start | generation: 0 | total_agents: 240
    [AGENT:<0.425.0>] FITNESS_EVAL | mode=score | fitness_function=alpha_t | fitness=-992.0000 | episodes=8 | mean_z=0.0000 | mean_alpha=0.0000 | std_alpha=0.0000 | entries=8 | mean_abs_exposure=1.000 | active=0.000 | holder_episodes=8 | pnl=16.15
    [AGENT:<0.425.0>] FITNESS_EVAL | mode=validation | fitness_function=alpha_t | fitness=0.4305 | episodes=8 | mean_z=0.1522 | mean_alpha=0.1515 | std_alpha=0.7777 | entries=4424 | mean_abs_exposure=1.000 | active=1.002 | holder_episodes=0 | pnl=27.25
    """)

    assert [agent] = assigns.agents
    assert agent.fitness == 0.4305
    assert agent.pnl == 27.25
    assert agent.entries == 4424
    assert length(assigns.chart_data) == 2
    assert assigns.selected_metric == "fitness"
    html = render_component(&AgentPerformanceLive.render/1, assigns)
    assert html =~ "Mean Alpha"
    assert html =~ "27.25"
    refute html =~ "Raw Total Profit"
    refute html =~ "No agent data"
  end

  test "legacy evaluations still populate their original metrics", %{root: root} do
    assigns = load(root, """
    [AGENT:<0.475.0>] FITNESS_EVAL | fitness_function=phase0_close_trades | fitness=5.067343531029578e1 | raw_total_profit=280.4058 | balance=300 | realized_pl=0 | unrealized_pl=-19.5942 | realized_trades=0 | trades=[none]
    [AGENT:<0.475.0>] FITNESS_EVAL | fitness=invalid
    """)

    assert [agent] = assigns.agents
    assert_in_delta agent.fitness, 50.67343531029578, 0.000001
    assert agent.realized_trades == 0
    assert length(assigns.chart_data) == 1
    assert assigns.selected_metric == "raw_total_profit"
    html = render_component(&AgentPerformanceLive.render/1, assigns)
    assert html =~ "Raw Total Profit"
    refute html =~ "Mean Alpha"
  end
end
