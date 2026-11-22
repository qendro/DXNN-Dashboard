defmodule DxnnAnalyzerWeb.GCP.GCPBridge do
  @moduledoc """
  Small Docker adapter for Google Compute Engine; all resource decisions belong to
  AWS-Deployment/scripts/gcp_manager.py. Operations are serialized by a second
  `DxnnAnalyzerWeb.OCI.OCIServer` instance configured by `server_opts/0`.
  """
  alias DxnnAnalyzerWeb.OCI.OCIBridge

  @server DxnnAnalyzerWeb.GCP.Server

  def server, do: @server

  def server_opts do
    [
      name: @server,
      bridge: __MODULE__,
      topic: "gcp_instances",
      event: :gcp_state,
      label: "GCP",
      task_supervisor: DxnnAnalyzerWeb.GCP.TaskSupervisor,
      public_instance: &public_instance/1
    ]
  end

  def root, do: System.get_env("GCP_DEPLOYMENT_PATH", "/app/AWS-Deployment")

  def configs do
    Path.wildcard(Path.join(root(), "config/*.{yml,yaml}"))
    # Templates carry placeholder projects and can never launch.
    |> Enum.reject(&String.contains?(Path.basename(&1), ".example."))
    |> Enum.filter(fn path ->
      case YamlElixir.read_from_file(path) do
        {:ok, %{"project" => _, "machine_type" => _}} -> true
        _ -> false
      end
    end)
    |> Enum.map(&Path.basename/1)
  end

  def fingerprint(config) do
    with true <- config in configs(),
         {:ok, bytes} <- File.read(Path.join([root(), "config", config])) do
      {:ok, Base.encode16(:crypto.hash(:sha256, bytes))}
    else
      _ -> {:error, "Select an existing GCP YAML in AWS-Deployment/config."}
    end
  end

  def command_args(:refresh, _), do: {:ok, ["list"]}

  def command_args(type, %{config: config}) when type in [:summary, :launch] do
    with {:ok, _} <- fingerprint(config),
         {:ok, host} <- OCIBridge.host_root() do
      {:ok, [Atom.to_string(type), "-c", Path.join([host, "config", config])]}
    end
  end

  def command_args(type, %{instance: instance} = params)
      when type in [:start, :stop, :reboot, :terminate] do
    id = instance["instance_id"]
    project = instance["project"]
    zone = instance["zone"]

    cond do
      not is_binary(id) or not Regex.match?(~r/^\d+$/, id) ->
        {:error, "A recorded numeric instance ID is required."}

      not is_binary(project) or not is_binary(zone) or project == "" or zone == "" ->
        {:error, "Instance project or zone is missing; refresh first."}

      type == :terminate and params[:boot_volume] not in ["preserve", "delete"] ->
        {:error, "Explicitly choose keep or delete boot disk."}

      true ->
        # The adapter maps reboot to Compute Engine's hard reset.
        args = [Atom.to_string(type), id, "--project", project, "--zone", zone]

        args =
          case {type, params[:boot_volume]} do
            {:terminate, "preserve"} -> args ++ ["--keep-boot-disk"]
            {:terminate, "delete"} -> args ++ ["--delete-boot-disk"]
            _ -> args
          end

        {:ok, args}
    end
  end

  def command_args(_, _), do: {:error, "Unsupported GCP operation."}

  def run(type, params) do
    with :ok <- deployment_available(),
         {:ok, args} <- command_args(type, params),
         {:ok, base, script} <- docker_args(),
         # The CLI resolves SSH key paths without exposing contents.
         {plan, 0} <-
           System.cmd("docker", base ++ [script, "--mount-plan"] ++ args, stderr_to_stdout: true),
         {:ok, mounts} <- planned_mounts(plan, base) do
      {output, code} =
        System.cmd("docker", insert_mounts(base, mounts) ++ [script] ++ args,
          stderr_to_stdout: true
        )

      decode_result(output, code)
    else
      {:error, _} = error ->
        error

      {output, _code} ->
        case decode_json(output) do
          {:ok, %{"ok" => false} = result} ->
            {:error, result}

          _ ->
            {:error,
             "GCP path planning failed. Sign in first with AWS-Deployment/gcp-login.sh YOUR_PROJECT_ID, then check the YAML and the deployment image (./docker-gcp.sh list rebuilds it)."}
        end
    end
  rescue
    _ ->
      {:error,
       "Could not execute the GCP deployment container. Check Docker and the GCP mount settings."}
  end

  defp deployment_available do
    if File.regular?(Path.join(root(), "scripts/gcp_manager.py")) do
      :ok
    else
      {:error,
       "GCP deployment CLI is missing from the dashboard's deployment mount. Check HOST_AWS_DEPLOYMENT_PATH and the AWS-Deployment bind mount, then recreate the dashboard with ./compose.sh up -d --force-recreate."}
    end
  end

  def credentials_file(home) do
    System.get_env(
      "GCP_CREDENTIALS_FILE",
      home <> "/.config/gcloud/application_default_credentials.json"
    )
  end

  def docker_args do
    with {:ok, host} <- OCIBridge.host_root(),
         "/" <> _ = home <- System.get_env("GCP_HOST_HOME") || System.get_env("OCI_HOST_HOME"),
         metadata? = System.get_env("GCP_AUTH") == "metadata",
         credentials = credentials_file(home),
         true <- metadata? or String.starts_with?(credentials, "/") do
      image = System.get_env("GCP_DEPLOYMENT_IMAGE", "aws-deployment:latest")

      adapter =
        System.get_env(
          "HOST_GCP_ADAPTER_PATH",
          Path.join([Path.dirname(host), "DXNN-Dashboard", "scripts", "gcp_dashboard.py"])
        )

      credential_args =
        if metadata?,
          do: [],
          else: [
            "-e",
            "GOOGLE_APPLICATION_CREDENTIALS=#{credentials}",
            "--mount",
            "type=bind,source=#{credentials},target=#{credentials},readonly"
          ]

      quota =
        case System.get_env("GOOGLE_CLOUD_QUOTA_PROJECT") do
          value when is_binary(value) and value != "" ->
            ["-e", "GOOGLE_CLOUD_QUOTA_PROJECT=#{value}"]

          _ ->
            []
        end

      args =
        [
          "run",
          "--rm",
          "--label",
          "dxnn.operation=gcp",
          "-e",
          "GCP_HOST_HOME=#{home}",
          "-e",
          "GCP_HOST_ROOT=#{host}"
        ] ++
          credential_args ++
          quota ++
          [
            "--mount",
            "type=bind,source=#{host},target=#{host},readonly",
            "--mount",
            "type=bind,source=#{host}/output/gcp,target=#{host}/output/gcp",
            "--mount",
            "type=bind,source=#{adapter},target=/opt/dxnn/gcp_dashboard.py,readonly",
            "-w",
            host,
            "--entrypoint",
            "python3",
            image
          ]

      case File.mkdir_p(Path.join(root(), "output/gcp")) do
        :ok -> {:ok, args, "/opt/dxnn/gcp_dashboard.py"}
        _ -> {:error, "GCP state directory must be writable in the deployment mount."}
      end
    else
      {:error, _} = error -> error
      _ -> {:error, "Set GCP_HOST_HOME and GCP_CREDENTIALS_FILE to absolute Docker-host paths."}
    end
  end

  @doc false
  def planned_mounts(plan, base) do
    paths = String.split(plan, <<0>>, trim: true)

    if Enum.all?(paths, &(String.starts_with?(&1, "/") and not String.contains?(&1, ["\n", ","]))) do
      # The credentials file is already mounted; Docker rejects duplicate targets.
      {:ok,
       paths
       |> Enum.reject(&("type=bind,source=#{&1},target=#{&1},readonly" in base))
       |> Enum.flat_map(fn path ->
         ["--mount", "type=bind,source=#{path},target=#{path},readonly"]
       end)}
    else
      {:error, "GCP mount planner returned invalid host paths."}
    end
  end

  @doc false
  def insert_mounts(base, mounts) do
    {options, [image]} = Enum.split(base, -1)
    options ++ mounts ++ [image]
  end

  # The adapter prints one JSON line last; tolerate library notices before it.
  defp decode_json(output) do
    with {:error, _} <- Jason.decode(output) do
      output |> String.split("\n", trim: true) |> List.last("") |> Jason.decode()
    end
  end

  def decode_result(output, code) do
    case decode_json(output) do
      {:ok, %{"ok" => true} = result} when code == 0 ->
        {:ok, result}

      {:ok, %{"ok" => false} = result} ->
        {:error, result}

      _ ->
        {:error,
         "GCP adapter did not return a JSON result; outcome may be uncertain. Check the deployment image and adapter mount, then refresh before retrying."}
    end
  end

  # Only public metadata is broadcast. Never render raw CLI output or configs.
  def public_instance(instance) do
    instance =
      case instance["machine"] do
        %{} = machine ->
          instance
          |> Map.put_new("vcpus", machine["vcpus"])
          |> Map.put_new("memory_gbs", machine["memory_gb"])

        _ ->
          instance
      end

    Map.take(
      instance,
      ~w(instance_id name state gce_status region zone project machine_type vcpus memory_gbs provisioning time_created addresses progress ssh)
    )
    |> Map.update("ssh", nil, fn
      ssh when is_map(ssh) -> Map.take(ssh, ~w(username private_key))
      _ -> nil
    end)
  end

  def records do
    Path.wildcard(Path.join(root(), "output/gcp/*.json"))
    |> Enum.flat_map(fn path ->
      with {:ok, bytes} <- File.read(path), {:ok, record} <- Jason.decode(bytes) do
        [public_instance(record)]
      else
        _ -> []
      end
    end)
  end

  defdelegate ssh_command(instance), to: OCIBridge
end
