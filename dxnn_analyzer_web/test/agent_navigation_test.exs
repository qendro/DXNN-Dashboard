defmodule DxnnAnalyzerWeb.AgentNavigationTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
  import Phoenix.ConnTest
  @endpoint DxnnAnalyzerWeb.Endpoint
  alias DxnnAnalyzerWeb.{AgentId, AnalyzerBridge}

  defmodule BridgeStub do
    use GenServer
    def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: AnalyzerBridge)
    def init(_), do: {:ok, nil}
    def handle_call({:compare_agents, ids, _}, _, state), do: {:reply, %{agents: ids}, state}

    def handle_call({action, _, _}, _, state)
        when action in [:inspect_agent, :get_topology, :get_topology_graph],
        do: {:reply, {:error, "Agent not found"}, state}
  end

  setup do
    start_supervised!({Phoenix.PubSub, name: DxnnAnalyzerWeb.PubSub})
    start_supervised!(DxnnAnalyzerWeb.Endpoint)
    start_supervised!(BridgeStub)
    :ok
  end

  test "IDs round trip nested tuple data and reject expressions" do
    for id <- [{1.0, :agent}, {{-1, 1.234e-8}, :agent}, {:agent, {1, 2, 3}}] do
      assert AgentId.parse(inspect(id)) == {:ok, id}
    end

    assert AgentId.parse_many("{1.0, :agent},{2.0, :agent}") ==
             {:ok, [{1.0, :agent}, {2.0, :agent}]}

    for input <- ["System.system_time()", "{send(self(), :executed), :agent}", "bad ID", "1"] do
      assert {:error, _} = AgentId.parse(input)
    end

    assert {:error, _} = AgentId.parse_many("{1.0, :agent}")
    refute_received :executed
  end

  test "comparison results retain the Erlang analyzer's metrics" do
    record = {:agent_comparison, [{1.0, :agent}, {2.0, :agent}], [:add_neuron], [], [], 0.75}
    result = DxnnAnalyzerWeb.AnalyzerBridge.Formatters.format_comparison({:ok, record})
    assert result.structural_similarity == 0.75
    assert result.common_mutations == [:add_neuron]
    assert length(result.agents) == 2
  end

  test "detail pages remain usable with missing context, malformed IDs, and absent agents" do
    for route <- ["agents", "topology", "graph"],
        suffix <- ["invalid", "invalid?context=run", "%7B1.0%2C%20%3Aagent%7D?context=run"] do
      {:ok, view, html} = live(Phoenix.ConnTest.build_conn(), "/#{route}/#{suffix}")
      assert html =~ "Could not load"
      assert has_element?(view, "a[href='/']")
    end
  end

  test "comparison parses tuples as whole IDs and clears stale results after invalid input" do
    conn = Phoenix.ConnTest.build_conn()
    params = URI.encode_query(%{context: "run", ids: "{1.0, :agent},{2.0, :agent}"})
    {:ok, view, html} = live(conn, "/compare?#{params}")
    assert html =~ "Comparing 2 agents"
    assert has_element?(view, "a[href='/agents/%7B1.0%2C%20%3Aagent%7D?context=run']")
    html = render_patch(view, "/compare?context=run&ids=invalid")
    refute html =~ "Comparing 2 agents"
    assert html =~ "valid agents"
  end
end
