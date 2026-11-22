defmodule DxnnAnalyzerWeb.GCPDxnnTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
  import Phoenix.ConnTest
  @endpoint DxnnAnalyzerWeb.Endpoint
  alias DxnnAnalyzerWeb.GCP.DxnnBridge

  defmodule MockBridge do
    def configs, do: ["gcp-local-runtime.yml"]

    def instances,
      do: [%{"instance_id" => "4242424242", "name" => "dxnn-gcp", "zone" => "us-central1-b"}]

    def run(command, params) do
      send(Process.whereis(:gcp_dxnn_owner), {:operation, command, params})

      case command do
        "storage:snapshots" ->
          {:ok,
           %{
             "result" => [
               %{
                 "lineage_id" => "pilot",
                 "run_id" => "run-1",
                 "kind" => "final",
                 "checkpoint_id" => "result",
                 "restorable" => false,
                 "bytes" => 2_500_000,
                 "created_at" => 1_763_000_000
               }
             ]
           }}

        "storage:archive" ->
          {:ok,
           %{"result" => %{"token" => String.duplicate("b", 32), "filename" => "dxnn-run-1.zip"}}}

        "stop" ->
          {:error, %{"ok" => false, "error" => "Run run-1 is not running."}}

        _ ->
          {:ok,
           %{
             "result" => %{
               "vm" => "RUNNING",
               "worker" => %{
                 "state" => "running",
                 "run_id" => "run-1",
                 "env" => %{"DXNN_TEST_ARM" => "ff_vol"},
                 "progress" => %{"generation" => 17, "gen_seconds" => 42.5}
               }
             }
           }}
      end
    end
  end

  setup do
    Process.register(self(), :gcp_dxnn_owner)
    Application.put_env(:dxnn_analyzer_web, :gcp_dxnn_bridge, MockBridge)
    on_exit(fn -> Application.delete_env(:dxnn_analyzer_web, :gcp_dxnn_bridge) end)
    start_supervised!({Phoenix.PubSub, name: DxnnAnalyzerWeb.PubSub})
    start_supervised!(DxnnAnalyzerWeb.Endpoint)
    :ok
  end

  test "start sends run identity and environment asynchronously and shows progress" do
    {:ok, view, html} = live(Phoenix.ConnTest.build_conn(), "/gcp-dxnn")
    assert html =~ "GCP DXNN"

    view
    |> form("form", %{
      "config" => "gcp-local-runtime.yml",
      "instance" => "4242424242",
      "run" => "run-1",
      "lineage" => "pilot",
      "env" => "DXNN_TEST_ARM=ff_vol"
    })
    |> render_change()

    view |> element("button[phx-value-command=start]") |> render_click()

    assert_receive {:operation, "start",
                    %{"run" => "run-1", "lineage" => "pilot", "env" => "DXNN_TEST_ARM=ff_vol"}}

    html = render_async(view)
    assert html =~ "gcp-dxnn-progress"
    assert html =~ "42.5"
    assert html =~ "ff_vol"
  end

  test "CLI errors are shown, not hidden behind a generic message" do
    {:ok, view, _} = live(Phoenix.ConnTest.build_conn(), "/gcp-dxnn")
    view |> element("button[phx-value-command=stop]") |> render_click()
    assert render_async(view) =~ "Run run-1 is not running."
  end

  test "storage lists committed snapshots and prepares a verified archive" do
    {:ok, view, _} = live(Phoenix.ConnTest.build_conn(), "/gcp-storage")
    view |> form("form", %{"config" => "gcp-local-runtime.yml"}) |> render_change()
    view |> element("button[phx-click=list]") |> render_click()
    html = render_async(view)
    assert html =~ "pilot / run-1"
    assert html =~ "2.5 MB"
    view |> element("button[phx-click=archive]") |> render_click()
    assert render_async(view) =~ "/gcp-storage/download/"

    assert_receive {:operation, "storage:archive",
                    %{
                      "checkpoint" => "result",
                      "kind" => "final",
                      "config" => "gcp-local-runtime.yml"
                    }}
  end

  test "download controller rejects malformed tokens" do
    conn =
      Phoenix.ConnTest.get(
        Phoenix.ConnTest.build_conn(),
        "/gcp-storage/download/invalid/dxnn-a.zip"
      )

    assert conn.status == 404
  end

  test "artifact cache paths cannot escape the GCP download directory" do
    assert {:error, _} = DxnnBridge.local_download_path("output/gcp/downloads/../../secret")
    assert {:error, _} = DxnnBridge.local_download_path("output/oci/downloads/x")
    assert {:ok, _} = DxnnBridge.local_download_path("output/gcp/downloads/bucket/pilot/run-1")
  end

  test "environment pairs follow the worker's rules" do
    assert {:ok, ["--env", "DXNN_TEST_ARM=ff_vol+fold_2015", "--env", "DXNN_EPISODE_SEED=1"]} =
             DxnnBridge.env_args("DXNN_TEST_ARM=ff_vol+fold_2015\n\nDXNN_EPISODE_SEED=1\n")

    assert {:ok, []} = DxnnBridge.env_args("")
    assert {:error, _} = DxnnBridge.env_args("PATH=/tmp")
    assert {:error, _} = DxnnBridge.env_args("DXNN_FINAL_DIR=/tmp")
    assert {:error, _} = DxnnBridge.env_args("DXNN_TEST_ARM=$(rm -rf /)")
    assert {:error, _} = DxnnBridge.env_args("DXNN_A=1\nDXNN_A=2")
  end

  test "decodes indented results printed after progress notes" do
    output =
      "Uploading 12 MB bundle and installing (several minutes)...\n" <>
        Jason.encode!(%{"ok" => true, "result" => %{"state" => "ready"}}, pretty: true) <> "\n"

    assert {:ok, %{"result" => %{"state" => "ready"}}} = DxnnBridge.decode_result(output, 0)

    assert {:error, %{"error" => "nope"}} =
             DxnnBridge.decode_result(~s({"ok": false, "error": "nope"}\n), 1)

    assert {:error, message} = DxnnBridge.decode_result("Traceback ...", 1)
    assert is_binary(message)
  end
end
