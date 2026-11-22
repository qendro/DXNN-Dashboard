defmodule DxnnAnalyzerWeb.OCIDxnnTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
  import Phoenix.ConnTest
  @endpoint DxnnAnalyzerWeb.Endpoint
  alias DxnnAnalyzerWeb.OCI.{DxnnBridge, OCIBridge}

  defmodule MockBridge do
    def configs, do: ["oci-local-runtime.yml"]

    def instances,
      do: [
        %{"instance_id" => "ocid1.instance.pilot", "name" => "pilot", "region" => "us-chicago-1"}
      ]

    def run(command, params) do
      send(Process.whereis(:oci_dxnn_owner), {:operation, command, params})

      case command do
        "storage:snapshots" ->
          {:ok,
           %{
             "result" => [
               %{
                 "lineage_id" => "pilot",
                 "run_id" => "run-1",
                 "kind" => "checkpoints",
                 "checkpoint_id" => "cp-1"
               }
             ]
           }}

        "storage:archive" ->
          {:ok,
           %{"result" => %{"token" => String.duplicate("a", 32), "filename" => "dxnn-run-1.zip"}}}

        _ ->
          {:ok, %{"result" => %{"state" => "running", "run_id" => "run-1"}}}
      end
    end
  end

  setup do
    Process.register(self(), :oci_dxnn_owner)
    Application.put_env(:dxnn_analyzer_web, :oci_dxnn_bridge, MockBridge)
    on_exit(fn -> Application.delete_env(:dxnn_analyzer_web, :oci_dxnn_bridge) end)
    start_supervised!({Phoenix.PubSub, name: DxnnAnalyzerWeb.PubSub})
    start_supervised!(DxnnAnalyzerWeb.Endpoint)
    :ok
  end

  test "DXNN controls send explicit run identity asynchronously" do
    {:ok, view, html} = live(Phoenix.ConnTest.build_conn(), "/oracle-dxnn")
    assert html =~ "Oracle DXNN"

    view
    |> form("form", %{
      "config" => "oci-local-runtime.yml",
      "instance" => "ocid1.instance.pilot",
      "run" => "run-1",
      "lineage" => "pilot"
    })
    |> render_change()

    view |> element("button[phx-value-command=start]") |> render_click()
    assert_receive {:operation, "start", %{"run" => "run-1", "lineage" => "pilot"}}
    assert render_async(view) =~ "running"
  end

  test "committed snapshots expose restore reference and verified archive download" do
    {:ok, view, _} = live(Phoenix.ConnTest.build_conn(), "/oracle-artifacts")
    view |> form("form", %{"config" => "oci-local-runtime.yml"}) |> render_change()
    view |> element("button[phx-click=list]") |> render_click()
    assert render_async(view) =~ "cp-1"
    view |> element("button[phx-click=archive]") |> render_click()
    assert render_async(view) =~ "/oracle-artifacts/download/"

    assert_receive {:operation, "storage:archive",
                    %{"checkpoint" => "cp-1", "kind" => "checkpoints"}}
  end

  test "artifact cache paths cannot escape deployment root" do
    assert {:error, _} = DxnnBridge.local_download_path("output/oci/downloads/../../secret")
    assert {:error, _} = DxnnBridge.local_download_path("/etc/passwd")
    assert {:ok, _} = DxnnBridge.local_download_path("output/oci/downloads/storage/pilot/run-1")
  end

  test "download controller rejects traversal tokens" do
    conn =
      Phoenix.ConnTest.get(
        Phoenix.ConnTest.build_conn(),
        "/oracle-artifacts/download/invalid/dxnn-run.zip"
      )

    assert conn.status == 404
  end

  test "instance principal containers do not mount user API credentials" do
    previous =
      Map.new(
        ~w(OCI_AUTH OCI_HOST_HOME OCI_CREDENTIALS_DIR HOST_AWS_DEPLOYMENT_PATH OCI_DEPLOYMENT_PATH),
        &{&1, System.get_env(&1)}
      )

    root = Path.join(System.tmp_dir!(), "dxnn-bridge-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)

    System.put_env(%{
      "OCI_AUTH" => "instance_principal",
      "OCI_HOST_HOME" => "/home/ubuntu",
      "OCI_CREDENTIALS_DIR" => "/absent/credentials",
      "HOST_AWS_DEPLOYMENT_PATH" => root,
      "OCI_DEPLOYMENT_PATH" => root
    })

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)

      File.rm_rf!(root)
    end)

    assert {:ok, args, _} = OCIBridge.docker_args()
    refute Enum.any?(args, &String.starts_with?(&1, "type=bind,source=/absent/credentials"))
    assert "OCI_AUTH=instance_principal" in args
    assert "host" in args
  end
end
