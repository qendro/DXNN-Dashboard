defmodule DxnnAnalyzerWeb.DashboardLiveTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
  alias DxnnAnalyzerWeb.{AnalyzerBridge, DashboardLive}

  defmodule BridgeStub do
    use GenServer

    def start_link(state), do: GenServer.start_link(__MODULE__, state, name: AnalyzerBridge)
    def init(state), do: {:ok, state}
    def handle_call(:list_contexts, _, state), do: {:reply, state.loaded, state}
    def handle_call(:get_experiments_from_settings, _, state), do: {:reply, state.saved, state}
    def handle_call({:unload_context, _}, _, state), do: {:reply, {:error, :busy}, state}

    def handle_call({:load_context, _, name}, _, state) do
      send(state.owner, {:loaded, name})
      {:reply, {:ok, name}, %{state | loaded: [%{name: name} | state.loaded]}}
    end
  end

  defp socket do
    %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, flash: %{}}, private: %{live_temp: %{}}}
  end

  test "analysis pages without an experiment provide a working route back to the dashboard" do
    start_supervised!({Phoenix.PubSub, name: DxnnAnalyzerWeb.PubSub})
    start_supervised!(DxnnAnalyzerWeb.Endpoint)

    for path <- ["/populations", "/species", "/compare"] do
      conn = Phoenix.ConnTest.build_conn()
      conn = Phoenix.ConnTest.dispatch(conn, DxnnAnalyzerWeb.Endpoint, :get, path, nil)
      assert conn.status == 200
      assert conn.resp_body =~ "Back to dashboard"
    end
  end

  test "bulk load skips experiments already in memory and disables itself when finished" do
    start_supervised!(
      {BridgeStub,
       %{
         owner: self(),
         loaded: [%{name: "loaded"}],
         saved: [%{name: "loaded", path: "/loaded"}, %{name: "saved", path: "/saved"}]
       }}
    )

    {:ok, socket} = DashboardLive.mount(%{}, %{}, socket())
    assert socket.assigns.loadable_count == 1
    {:noreply, socket} = DashboardLive.handle_event("load_all_experiments", %{}, socket)
    assert_received {:loaded, "saved"}
    refute_received {:loaded, "loaded"}
    assert socket.assigns.loadable_count == 0
  end

  test "an unload error is reported without claiming success" do
    start_supervised!({BridgeStub, %{owner: self(), loaded: [], saved: []}})

    {:noreply, socket} =
      DashboardLive.handle_event("unload_experiment", %{"name" => "busy"}, socket())

    assert socket.assigns.flash["error"] =~ "Could not unload"
    refute socket.assigns.flash["info"]
  end

  test "experiment actions retain context and explain what unloading does" do
    start_supervised!({Phoenix.PubSub, name: DxnnAnalyzerWeb.PubSub})
    start_supervised!(DxnnAnalyzerWeb.Endpoint)

    html =
      render_component(&DashboardLive.render/1,
        experiments: [
          %{
            name: "run with spaces",
            agent_count: 12,
            specie_count: 2,
            logs_path: nil,
            analytics_path: nil
          }
        ],
        loadable_count: 0
      )

    document = Floki.parse_document!(html)

    assert Floki.attribute(Floki.find(document, "a[href^='/agents?']"), "href") ==
             ["/agents?context=run+with+spaces"]

    unload = Floki.find(document, "button[phx-click=unload_experiment]")
    assert Floki.attribute(unload, "phx-value-name") == ["run with spaces"]
    assert Floki.attribute(unload, "data-confirm") |> hd() =~ "Files on disk will be kept"
    assert Floki.find(document, "button[phx-click=load_all_experiments][disabled]") != []
  end
end
