defmodule DxnnAnalyzerWeb.OCI.OCIBridge do
  @moduledoc "Small Docker adapter; all OCI resource decisions belong to AWS-Deployment."

  def root, do: System.get_env("OCI_DEPLOYMENT_PATH", "/app/AWS-Deployment")

  def configs do
    Path.wildcard(Path.join(root(), "config/*.{yml,yaml}"))
    |> Enum.filter(fn path ->
      case YamlElixir.read_from_file(path) do
        {:ok, %{"compartment_id" => _, "shape" => _}} -> true
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
      _ -> {:error, "Select an existing OCI YAML in AWS-Deployment/config."}
    end
  end

  def command_args(:refresh, _), do: {:ok, ["list"]}

  def command_args(type, %{config: config}) when type in [:summary, :launch] do
    with {:ok, _} <- fingerprint(config),
         {:ok, host} <- host_root() do
      {:ok, [Atom.to_string(type), "-c", Path.join([host, "config", config])]}
    end
  end

  def command_args(type, %{instance: instance} = params)
      when type in [:start, :stop, :reboot, :terminate] do
    id = instance["instance_id"]
    region = instance["region"]

    cond do
      not is_binary(id) or not String.starts_with?(id, "ocid1.instance.") ->
        {:error, "An explicit instance OCID is required."}

      not is_binary(region) or region == "" ->
        {:error, "Instance region is missing; refresh first."}

      type == :terminate and params[:boot_volume] not in ["preserve", "delete"] ->
        {:error, "Explicitly choose preserve or delete boot volume."}

      true ->
        args = [Atom.to_string(type), id, "--region", region]

        args =
          if type == :terminate, do: args ++ ["--#{params.boot_volume}-boot-volume"], else: args

        {:ok, args}
    end
  end

  def command_args(_, _), do: {:error, "Unsupported OCI operation."}

  def run(type, params) do
    with :ok <- deployment_available(),
         {:ok, args} <- command_args(type, params),
         {:ok, base, script} <- docker_args(),
         # The CLI resolves signing and SSH key paths without exposing contents.
         {plan, 0} <-
           System.cmd("docker", base ++ [script, "--mount-plan"] ++ args, stderr_to_stdout: true),
         {:ok, mounts} <- planned_mounts(plan) do
      {output, code} =
        System.cmd(
          "docker",
          insert_mounts(base, mounts) ++
            [script] ++ args,
          stderr_to_stdout: true
        )

      decode_result(output, code)
    else
      {:error, _} = error ->
        error

      {output, _code} ->
        case Jason.decode(output) do
          {:ok, %{"ok" => false} = result} ->
            {:error, result}

          _ ->
            {:error,
             "OCI path planning failed. Check the deployment CLI, YAML, credential profile and host mounts."}
        end
    end
  rescue
    _ ->
      {:error,
       "Could not execute the OCI deployment container. Check Docker and the OCI mount settings."}
  end

  defp deployment_available do
    if File.regular?(Path.join(root(), "scripts/oci_manager.py")) do
      :ok
    else
      {:error,
       "OCI deployment CLI is missing from the dashboard's deployment mount. Check HOST_AWS_DEPLOYMENT_PATH and the AWS-Deployment bind mount; after moving the checkout, recreate the dashboard with ./compose.sh up -d --force-recreate."}
    end
  end

  def host_root do
    case System.get_env("HOST_AWS_DEPLOYMENT_PATH") do
      "/" <> _ = path ->
        {:ok, String.trim_trailing(path, "/")}

      _ ->
        {:error,
         "Set HOST_AWS_DEPLOYMENT_PATH to the absolute Docker-host AWS-Deployment directory."}
    end
  end

  def docker_args do
    with {:ok, host} <- host_root(),
         "/" <> _ = home <- System.get_env("OCI_HOST_HOME"),
         "/" <> _ = credentials <- System.get_env("OCI_CREDENTIALS_DIR", home <> "/.oci") do
      config = System.get_env("OCI_CONFIG_FILE", credentials <> "/config")
      image = System.get_env("OCI_DEPLOYMENT_IMAGE", "aws-deployment:latest")

      adapter =
        System.get_env(
          "HOST_OCI_ADAPTER_PATH",
          Path.join([Path.dirname(host), "DXNN-Dashboard", "scripts", "oci_dashboard.py"])
        )

      args = [
        "run",
        "--rm",
        "--label",
        "dxnn.operation=oci",
        "-e",
        "OCI_HOST_HOME=#{home}",
        "-e",
        "OCI_HOST_ROOT=#{host}",
        "-e",
        "OCI_CONFIG_FILE=#{config}",
        "-e",
        "OCI_PROFILE=#{System.get_env("OCI_PROFILE", "DEFAULT")}",
        "-e",
        "OCI_SIGNING_KEY_FILE=#{System.get_env("OCI_SIGNING_KEY_FILE", "")}",
        "--mount",
        "type=bind,source=#{host},target=#{host},readonly",
        "--mount",
        "type=bind,source=#{host}/output/oci,target=#{host}/output/oci",
        "--mount",
        "type=bind,source=#{credentials},target=#{credentials},readonly",
        "--mount",
        "type=bind,source=#{config},target=#{config},readonly",
        "--mount",
        "type=bind,source=#{adapter},target=/opt/dxnn/oci_dashboard.py,readonly",
        "-w",
        host,
        "--entrypoint",
        "python3",
        image
      ]

      # Create only the existing ignored state directory, through the dashboard bind.
      case File.mkdir_p(Path.join(root(), "output/oci")) do
        :ok -> {:ok, args, "/opt/dxnn/oci_dashboard.py"}
        _ -> {:error, "OCI state directory must be writable in the deployment mount."}
      end
    else
      {:error, _} = error -> error
      _ -> {:error, "Set OCI_HOST_HOME and OCI_CREDENTIALS_DIR to absolute Docker-host paths."}
    end
  end

  defp planned_mounts(plan) do
    paths = String.split(plan, <<0>>, trim: true)

    if Enum.all?(paths, &(String.starts_with?(&1, "/") and not String.contains?(&1, ["\n", ","]))) do
      {:ok,
       Enum.flat_map(paths, fn path ->
         ["--mount", "type=bind,source=#{path},target=#{path},readonly"]
       end)}
    else
      {:error, "OCI mount planner returned invalid host paths."}
    end
  end

  defp insert_mounts(base, mounts) do
    {options, [image]} = Enum.split(base, -1)
    options ++ mounts ++ [image]
  end

  def decode_result(output, code) do
    case Jason.decode(output) do
      {:ok, %{"ok" => true} = result} when code == 0 ->
        {:ok, result}

      {:ok, %{"ok" => false} = result} ->
        {:error, result}

      _ ->
        {:error,
         "OCI adapter did not return a JSON result; outcome may be uncertain. Check the deployment image and adapter mount, then refresh before retrying."}
    end
  end

  # Only public metadata is broadcast. Never render raw CLI output or configs.
  def public_instance(instance) do
    Map.take(
      instance,
      ~w(instance_id name state region ad shape ocpus memory_gbs time_created addresses progress ssh)
    )
    |> Map.update("ssh", nil, fn
      ssh when is_map(ssh) -> Map.take(ssh, ~w(username private_key))
      _ -> nil
    end)
  end

  def records do
    Path.wildcard(Path.join(root(), "output/oci/*.json"))
    |> Enum.flat_map(fn path ->
      with {:ok, bytes} <- File.read(path), {:ok, record} <- Jason.decode(bytes) do
        [public_instance(record)]
      else
        _ -> []
      end
    end)
  end

  def ssh_command(instance) do
    ssh = instance["ssh"] || %{}
    ip = Enum.find_value(instance["addresses"] || [], & &1["public_ipv4"])
    key = ssh["private_key"]
    user = ssh["username"]

    with true <- instance["state"] == "RUNNING",
         true <- is_binary(key) and String.starts_with?(key, "/"),
         true <- is_binary(user) and Regex.match?(~r/^[a-z_][a-z0-9_-]*$/, user),
         {:ok, address} <- :inet.parse_ipv4_address(to_charlist(ip || "")) do
      host = address |> :inet.ntoa() |> to_string()
      "ssh -i '#{String.replace(key, "'", "'\\''")}' -o IdentitiesOnly=yes #{user}@#{host}"
    else
      _ -> nil
    end
  end
end
