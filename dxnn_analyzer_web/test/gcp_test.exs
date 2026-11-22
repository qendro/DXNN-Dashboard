defmodule DxnnAnalyzerWeb.GCPTest do
  use ExUnit.Case, async: false
  alias DxnnAnalyzerWeb.GCP.GCPBridge
  alias DxnnAnalyzerWeb.OCI.OCIServer

  defmodule MockBridge do
    def configs, do: ["gcp-local-dxnn.yml"]
    def fingerprint("gcp-local-dxnn.yml"), do: {:ok, "reviewed"}
    def fingerprint(_), do: {:error, "Missing configuration"}
    def records, do: :persistent_term.get({__MODULE__, :records}, [])

    def run(type, params) do
      send(Process.whereis(:gcp_test_owner), {:command, type, params, self()})

      receive do
        {:result, result} -> result
      end
    end
  end

  setup do
    Process.register(self(), :gcp_test_owner)
    start_supervised!({Phoenix.PubSub, name: DxnnAnalyzerWeb.PubSub})
    start_supervised!({Task.Supervisor, name: DxnnAnalyzerWeb.GCP.TaskSupervisor})

    opts =
      GCPBridge.server_opts()
      |> Keyword.merge(name: :gcp_test_server, bridge: MockBridge)

    start_supervised!(Supervisor.child_spec({OCIServer, opts}, id: :gcp_test_server))
    Phoenix.PubSub.subscribe(DxnnAnalyzerWeb.PubSub, "gcp_instances")
    :ok
  end

  defp instance(overrides \\ %{}) do
    Map.merge(
      %{
        "instance_id" => "4242424242",
        "name" => "dxnn-gcp",
        "state" => "RUNNING",
        "gce_status" => "RUNNING",
        "project" => "dxnn-test-project",
        "region" => "us-central1",
        "zone" => "us-central1-b",
        "machine_type" => "n2-standard-16",
        "provisioning" => "SPOT",
        "addresses" => [%{"public_ipv4" => "203.0.113.9"}],
        "ssh" => %{"username" => "ubuntu", "private_key" => "/host/AWS-Deployment/output/gcp/keys/k"}
      },
      overrides
    )
  end

  defp finished do
    receive do
      {:gcp_state, %{busy: false} = state} -> state
      {:gcp_state, _} -> finished()
    after
      2000 -> flunk("Worker did not complete")
    end
  end

  test "lifecycle arguments use project, zone, the hard reset verb and explicit disk choice" do
    for {choice, flag} <- [{"preserve", "--keep-boot-disk"}, {"delete", "--delete-boot-disk"}] do
      assert {:ok,
              ["terminate", "4242424242", "--project", "dxnn-test-project", "--zone", "us-central1-b",
               ^flag]} = GCPBridge.command_args(:terminate, %{instance: instance(), boot_volume: choice})
    end

    assert {:error, _} = GCPBridge.command_args(:terminate, %{instance: instance()})

    assert {:ok, ["reboot", "4242424242" | _]} =
             GCPBridge.command_args(:reboot, %{instance: instance()})

    assert {:error, _} =
             GCPBridge.command_args(:stop, %{instance: instance(%{"instance_id" => "ocid1.x"})})

    assert {:error, _} = GCPBridge.command_args(:stop, %{instance: instance(%{"zone" => nil})})
  end

  test "docker arguments mount ADC read-only and the GCP state directory writable" do
    settings = %{
      "GCP_DEPLOYMENT_PATH" => "/tmp/gcp-adapter-test",
      "HOST_AWS_DEPLOYMENT_PATH" => "/host/AWS-Deployment",
      "GCP_HOST_HOME" => "/host/home",
      "GCP_CREDENTIALS_FILE" => "/host/home/.config/gcloud/application_default_credentials.json",
      "HOST_GCP_ADAPTER_PATH" => "/host/DXNN-Dashboard/scripts/gcp_dashboard.py",
      "GCP_AUTH" => "adc"
    }

    previous = Map.new(settings, fn {key, _} -> {key, System.get_env(key)} end)
    System.put_env(settings)

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)

      File.rm_rf!("/tmp/gcp-adapter-test")
    end)

    assert {:ok, args, "/opt/dxnn/gcp_dashboard.py"} = GCPBridge.docker_args()
    creds = settings["GCP_CREDENTIALS_FILE"]
    assert "GOOGLE_APPLICATION_CREDENTIALS=#{creds}" in args
    assert "type=bind,source=#{creds},target=#{creds},readonly" in args

    assert "type=bind,source=/host/AWS-Deployment/output/gcp,target=/host/AWS-Deployment/output/gcp" in args

    assert List.last(args) == "aws-deployment:latest"

    System.put_env("GCP_AUTH", "metadata")
    assert {:ok, metadata_args, _} = GCPBridge.docker_args()
    refute Enum.any?(metadata_args, &String.contains?(&1, "application_default_credentials"))
  end

  test "a library notice before the adapter's JSON line still decodes" do
    noise = "/opt/x.py:212: FutureWarning: non-supported Python version\n  warnings.warn(m)\n"
    json = Jason.encode!(%{"ok" => true, "instances" => [instance()]})
    assert {:ok, %{"instances" => [_]}} = GCPBridge.decode_result(noise <> json <> "\n", 0)
    assert {:error, _} = GCPBridge.decode_result(noise, 1)
  end

  test "public metadata only, and SSH command for a running VM" do
    raw = Map.merge(instance(), %{"credential" => "secret", "machine" => %{"vcpus" => 16, "memory_gb" => 64.0}})
    public = GCPBridge.public_instance(raw)
    assert public["credential"] == nil
    assert {public["vcpus"], public["memory_gbs"]} == {16, 64.0}

    assert GCPBridge.ssh_command(instance()) ==
             "ssh -i '/host/AWS-Deployment/output/gcp/keys/k' -o IdentitiesOnly=yes ubuntu@203.0.113.9"

    assert GCPBridge.ssh_command(instance(%{"state" => "STOPPED"})) == nil
  end

  test "a launch seen while pending merges into its recorded instance instead of duplicating" do
    pending = %{"name" => "dxnn-free", "region" => "us-central1", "progress" => "launch-request-pending"}
    assert :ok = OCIServer.submit(:refresh, %{}, :gcp_test_server)
    assert_receive {:command, :refresh, _, worker}
    send(worker, {:result, {:error, %{"error" => "boom", "instances" => [pending]}}})
    finished()
    assert :ok = OCIServer.submit(:refresh, %{}, :gcp_test_server)
    assert_receive {:command, :refresh, _, worker}
    # The refresh fails again, but the saved record now has the instance ID.
    record = instance(%{"name" => "dxnn-free", "progress" => "ssh-verified"})
    :persistent_term.put({MockBridge, :records}, [record])
    send(worker, {:result, {:error, "still failing"}})
    state = finished()
    assert [%{"instance_id" => "4242424242", "progress" => "ssh-verified"}] = state.instances
  after
    :persistent_term.erase({MockBridge, :records})
  end

  test "the shared server broadcasts GCP events and gates actions on normalized state" do
    assert :ok = OCIServer.submit(:refresh, %{}, :gcp_test_server)
    assert_receive {:command, :refresh, _, worker}
    stopped = instance(%{"state" => "STOPPED", "gce_status" => "TERMINATED"})
    send(worker, {:result, {:ok, %{"instances" => [stopped]}}})
    state = finished()
    assert [%{"state" => "STOPPED"}] = state.instances

    assert {:error, _} =
             OCIServer.submit(:stop, %{id: "4242424242", region: "us-central1"}, :gcp_test_server)

    assert :ok =
             OCIServer.submit(:start, %{id: "4242424242", region: "us-central1"}, :gcp_test_server)

    assert_receive {:command, :start, %{instance: %{"zone" => "us-central1-b"}}, worker}

    assert {:error, "Another GCP operation is running. Wait for it to finish."} =
             OCIServer.submit(:refresh, %{}, :gcp_test_server)

    send(worker, {:result, {:error, %{"error" => "quota exceeded"}}})
    assert_receive {:command, :refresh, _, worker}
    send(worker, {:result, {:ok, %{"instances" => [instance()]}}})
    state = finished()
    assert [%{status: :failed, message: "quota exceeded"}] = state.operations
    assert [%{"state" => "RUNNING"}] = state.instances
  end
end
