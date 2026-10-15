defmodule DxnnAnalyzerWeb.OCITest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
  alias DxnnAnalyzerWeb.OCI.{OCIBridge, OCIServer}

  defmodule MockBridge do
    def configs, do: ["oci-local.yml"]
    def fingerprint("oci-local.yml"), do: {:ok, "reviewed"}
    def fingerprint(_), do: {:error, "Missing configuration"}
    def records, do: []

    def run(type, params) do
      send(Process.whereis(:oci_test_owner), {:command, type, params, self()})

      receive do
        {:result, result} -> result
      end
    end
  end

  setup do
    Process.register(self(), :oci_test_owner)
    start_supervised!({Phoenix.PubSub, name: DxnnAnalyzerWeb.PubSub})
    start_supervised!({Task.Supervisor, name: DxnnAnalyzerWeb.OCI.TaskSupervisor})
    start_supervised!({OCIServer, name: :oci_test_server, bridge: MockBridge})
    Phoenix.PubSub.subscribe(DxnnAnalyzerWeb.PubSub, "oci_instances")
    :ok
  end

  defp instance do
    %{
      "instance_id" => "ocid1.instance.oc1.example",
      "name" => "qbot",
      "state" => "RUNNING",
      "region" => "us-chicago-1",
      "ad" => "CHICAGO-AD-1",
      "shape" => "VM.Standard.A1.Flex",
      "ocpus" => 2,
      "memory_gbs" => 8,
      "time_created" => "2026-10-11T22:00:00+00:00",
      "progress" => "ssh-verification-failed",
      "addresses" => [%{"public_ipv4" => "203.0.113.7"}],
      "ssh" => %{"username" => "ubuntu", "private_key" => "/Users/example/.ssh/oci key"}
    }
  end

  defp finished do
    receive do
      {:oci_state, %{busy: false} = state} -> state
      {:oci_state, _} -> finished()
    after
      2000 -> flunk("Worker did not complete")
    end
  end

  defp find(html, selector), do: html |> Floki.parse_document!() |> Floki.find(selector)

  test "a missing deployment mount reports stale dashboard paths before invoking Docker" do
    previous = System.get_env("OCI_DEPLOYMENT_PATH")
    missing = Path.join(System.tmp_dir!(), "missing-oci-#{System.unique_integer([:positive])}")
    System.put_env("OCI_DEPLOYMENT_PATH", missing)

    on_exit(fn ->
      if previous,
        do: System.put_env("OCI_DEPLOYMENT_PATH", previous),
        else: System.delete_env("OCI_DEPLOYMENT_PATH")
    end)

    assert {:error, message} = OCIBridge.run(:refresh, %{})
    assert message =~ "deployment CLI is missing"
    assert message =~ "HOST_AWS_DEPLOYMENT_PATH"
    assert message =~ "--force-recreate"
  end

  test "explicit lifecycle arguments, both storage choices, JSON failure and host SSH path" do
    settings = %{
      "OCI_DEPLOYMENT_PATH" => "/tmp/oci-adapter-test",
      "HOST_AWS_DEPLOYMENT_PATH" => "/host/AWS-Deployment",
      "OCI_HOST_HOME" => "/host/home",
      "OCI_CREDENTIALS_DIR" => "/host/credentials",
      "OCI_CONFIG_FILE" => "/host/credentials/config",
      "HOST_OCI_ADAPTER_PATH" => "/host/DXNN-Dashboard/scripts/oci_dashboard.py"
    }

    previous = Map.new(settings, fn {key, _} -> {key, System.get_env(key)} end)
    System.put_env(settings)

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)

      File.rm_rf!("/tmp/oci-adapter-test")
    end)

    assert {:ok, docker_args, "/opt/dxnn/oci_dashboard.py"} = OCIBridge.docker_args()

    assert "type=bind,source=/host/AWS-Deployment,target=/host/AWS-Deployment,readonly" in docker_args

    assert "type=bind,source=/host/AWS-Deployment/output/oci,target=/host/AWS-Deployment/output/oci" in docker_args

    assert "type=bind,source=/host/credentials,target=/host/credentials,readonly" in docker_args

    for {choice, flag} <- [
          {"preserve", "--preserve-boot-volume"},
          {"delete", "--delete-boot-volume"}
        ] do
      assert {:ok, ["terminate", "ocid1.instance.oc1.example", "--region", "us-chicago-1", ^flag]} =
               OCIBridge.command_args(:terminate, %{instance: instance(), boot_volume: choice})
    end

    assert {:error, _} = OCIBridge.command_args(:terminate, %{instance: instance()})

    for action <- [:start, :stop, :reboot] do
      assert {:ok, [command, "ocid1.instance.oc1.example", "--region", "us-chicago-1"]} =
               OCIBridge.command_args(action, %{instance: instance()})

      assert command == Atom.to_string(action)
    end

    assert {:error, %{"instances" => [_]}} =
             OCIBridge.decode_result(
               Jason.encode!(%{
                 "ok" => false,
                 "error" => "SSH failed",
                 "instances" => [instance()]
               }),
               1
             )

    assert OCIBridge.ssh_command(instance()) ==
             "ssh -i '/Users/example/.ssh/oci key' -o IdentitiesOnly=yes ubuntu@203.0.113.7"

    assert OCIBridge.ssh_command(Map.put(instance(), "state", "UNKNOWN")) == nil

    assert OCIBridge.public_instance(Map.put(instance(), "credential", "secret"))["credential"] ==
             nil
  end

  test "duplicate launches are rejected and SSH failure keeps the created instance after refresh" do
    assert :ok = OCIServer.submit(:summary, %{config: "oci-local.yml"}, :oci_test_server)
    assert_receive {:command, :summary, _, worker}
    send(worker, {:result, {:ok, %{"summary" => %{"name" => "qbot", "mode" => "free-only"}}}})
    finished()
    params = %{config: "oci-local.yml", fingerprint: "reviewed"}
    assert :ok = OCIServer.submit(:launch, params, :oci_test_server)
    assert_receive {:command, :launch, ^params, worker}
    assert {:error, _} = OCIServer.submit(:launch, params, :oci_test_server)

    assert {:error, _} =
             OCIServer.submit(
               :stop,
               %{id: instance()["instance_id"], region: "us-chicago-1"},
               :oci_test_server
             )

    # A reconnected browser reads the same running operation, without launching.
    assert OCIServer.state(:oci_test_server).busy

    send(
      worker,
      {:result,
       {:error,
        %{"error" => "Instance created, SSH verification failed", "instances" => [instance()]}}}
    )

    assert_receive {:command, :refresh, %{}, worker}
    send(worker, {:result, {:ok, %{"instances" => [instance()]}}})
    state = finished()
    assert [created] = state.instances
    assert created["instance_id"] == instance()["instance_id"]
    assert [operation] = state.operations
    assert operation.status == :failed
    assert operation.message =~ "SSH verification failed"
    refute_receive {:command, :launch, _, _}, 20

    assert {:error, _} =
             OCIServer.submit(:launch, %{params | fingerprint: "changed"}, :oci_test_server)
  end

  test "mocked page renders instance metadata, summary, SSH and explicit termination choices" do
    oci = %{
      OCIServer.state(:oci_test_server)
      | instances: [instance()],
        configs: ["oci-local.yml"],
        summary_config: "oci-local.yml",
        summary: %{
          "name" => "qbot",
          "mode" => "paid",
          "region" => "us-chicago-1",
          "shape" => "VM.Standard.A1.Flex",
          "ocpus" => 2,
          "memory_gbs" => 8,
          "image" => %{"id" => "image"},
          "network" => %{},
          "ssh" => %{"username" => "ubuntu"}
        }
    }

    html =
      render_component(&DxnnAnalyzerWeb.OracleInstancesLive.render/1,
        oci: oci,
        selected_config: "oci-local.yml",
        termination: instance(),
        expanded_stats: MapSet.new()
      )

    assert html =~ "Oracle Instances"
    assert html =~ "ocid1.instance.oc1.example"
    assert html =~ "203.0.113.7"
    assert html =~ "VM.Standard.A1.Flex"
    assert html =~ "Paid mode authorizes billable resources"
    assert html =~ "Copy SSH command"
    assert html =~ "Launched (Central time)"
    assert html =~ "Time since launch"
    assert html =~ "Includes stopped time; not continuous uptime."

    assert Floki.attribute(find(html, "#oci-time-0"), "data-launched-at") == [
             instance()["time_created"]
           ]

    assert OCIBridge.public_instance(instance())["time_created"] == instance()["time_created"]
    assert length(find(html, "#oci-instances thead th")) == 4
    assert [_] = find(html, "#oci-stats-0[hidden]")
    assert Floki.attribute(find(html, "#oci-toggle-stats-0"), "aria-expanded") == ["false"]
    assert html =~ ~s(value="preserve")
    assert html =~ ~s(value="delete")
    refute html =~ ~s(value="preserve" checked)
    routes = Phoenix.Router.routes(DxnnAnalyzerWeb.Router)
    assert Enum.any?(routes, &(&1.path == "/oracle-instances"))
    assert Enum.any?(routes, &(&1.path == "/aws-deployment"))
    assert Enum.any?(routes, &(&1.path == "/aws-deployment/instance/:instance_id"))
    aws_bridge = File.read!("lib/dxnn_analyzer_web/aws/aws_bridge.ex")
    assert aws_bridge =~ ~s|run_script_async("docker-deploy.sh", args)|
    assert aws_bridge =~ ~s|args = ["-c", config_file]|

    assert File.read!("lib/dxnn_analyzer_web/live/dashboard_live.ex") =~
             ~s|navigate={~p"/aws-deployment"}|
  end

  test "stats stay expanded across updates and a historical verification error shows recovery only for the same verified VM" do
    id = instance()["instance_id"]
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, expanded_stats: MapSet.new()}}

    {:noreply, socket} =
      DxnnAnalyzerWeb.OracleInstancesLive.handle_event("toggle-stats", %{"key" => id}, socket)

    {:noreply, socket} =
      DxnnAnalyzerWeb.OracleInstancesLive.handle_info(
        {:oci_state, OCIServer.state(:oci_test_server)},
        socket
      )

    assert MapSet.member?(socket.assigns.expanded_stats, id)

    operation = %{
      id: 1,
      type: :launch,
      target: "oci-local.yml",
      status: :failed,
      message: "Instance created: #{id}, but SSH verification failed"
    }

    oci = %{OCIServer.state(:oci_test_server) | instances: [instance()], operations: [operation]}

    assigns = [
      oci: oci,
      selected_config: "",
      termination: nil,
      expanded_stats: socket.assigns.expanded_stats
    ]

    html = render_component(&DxnnAnalyzerWeb.OracleInstancesLive.render/1, assigns)
    assert find(html, "#oci-stats-0[hidden]") == []
    assert [_] = find(html, "#oci-operation-history[open]")
    refute html =~ "Recovered:"

    verified = Map.put(instance(), "progress", "ssh-verified")
    recovered = %{oci | instances: [verified]}

    html =
      render_component(
        &DxnnAnalyzerWeb.OracleInstancesLive.render/1,
        Keyword.put(assigns, :oci, recovered)
      )

    assert html =~ "Recovered: the same instance is now running and SSH verified."
    assert html =~ operation.message
    assert find(html, "#oci-operation-history[open]") == []

    other_instance = Map.put(verified, "instance_id", "ocid1.instance.oc1.other")

    html =
      render_component(
        &DxnnAnalyzerWeb.OracleInstancesLive.render/1,
        Keyword.put(assigns, :oci, %{recovered | instances: [other_instance]})
      )

    refute html =~ "Recovered:"
    assert [_] = find(html, "#oci-operation-history[open]")
  end
end
