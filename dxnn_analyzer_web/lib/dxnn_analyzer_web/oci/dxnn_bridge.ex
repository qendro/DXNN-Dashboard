defmodule DxnnAnalyzerWeb.OCI.DxnnBridge do
  @moduledoc "Native OCI DXNN application and storage operations through the deployment container."
  alias DxnnAnalyzerWeb.OCI.OCIBridge

  @commands ~w(validate install status start stop checkpoint logs retry-upload reconcile)
  @storage ~w(ensure list snapshots download archive probe inventory)

  def configs do
    Path.wildcard(Path.join(OCIBridge.root(), "config/*.{yml,yaml}"))
    |> Enum.filter(fn path ->
      case YamlElixir.read_from_file(path) do
        {:ok, %{"schema_version" => 1, "storage" => %{"provider" => "oci_object_storage"}}} ->
          true

        _ ->
          false
      end
    end)
    |> Enum.map(&Path.basename/1)
  end

  def instances, do: OCIBridge.records()

  def command_args(command, params) do
    with true <- params["config"] in configs(),
         {:ok, host} <- OCIBridge.host_root(),
         {:ok, tail} <- operation_args(command, params) do
      args = ["-c", Path.join([host, "config", params["config"]])]

      args =
        if params["instance"] not in [nil, ""],
          do: args ++ ["--instance", params["instance"]],
          else: args

      {:ok, args ++ tail}
    else
      {:error, _} = error -> error
      _ -> {:error, "Select an existing Oracle runtime configuration."}
    end
  end

  defp operation_args(command, params) when command in @commands do
    cond do
      command != "validate" and
          not Enum.any?(instances(), &(&1["instance_id"] == params["instance"])) ->
        {:error, "Select a recorded Oracle instance."}

      command == "start" ->
        if valid_id?(params["run"]) and valid_id?(params["lineage"]) do
          args = ["start", "--run", params["run"], "--lineage", params["lineage"]]
          restore = params["restore"]

          if restore not in [nil, ""] do
            case Jason.decode(restore) do
              {:ok, %{"lineage_id" => l, "run_id" => r, "checkpoint_id" => c}} ->
                if Enum.all?([l, r, c], &valid_id?/1),
                  do: {:ok, args ++ ["--restore", restore]},
                  else: {:error, "Invalid restore identity."}

              _ ->
                {:error, "Restore must contain lineage_id, run_id, checkpoint_id."}
            end
          else
            {:ok, args}
          end
        else
          {:error, "Enter valid run and lineage IDs."}
        end

      true ->
        {:ok, [command]}
    end
  end

  defp operation_args("storage:" <> operation, params) when operation in @storage do
    if operation in ["download", "archive"] do
      if Enum.all?(~w(lineage run checkpoint), &valid_id?(params[&1])) and
           params["kind"] in ["checkpoints", "final"] do
        {:ok,
         [
           "storage",
           operation,
           "--lineage",
           params["lineage"],
           "--run",
           params["run"],
           "--checkpoint",
           params["checkpoint"],
           "--kind",
           params["kind"]
         ]}
      else
        {:error, "Invalid snapshot selection."}
      end
    else
      {:ok, ["storage", operation]}
    end
  end

  defp operation_args(_, _), do: {:error, "Unsupported Oracle DXNN operation."}

  defp valid_id?(value),
    do:
      is_binary(value) and Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\z/, value) and
        value not in [".", ".."]

  def run(command, params) do
    with {:ok, args} <- command_args(command, params),
         {:ok, base, _} <- OCIBridge.docker_args(),
         {:ok, host} <- OCIBridge.host_root() do
      script = Path.join([host, "scripts", "oci_dxnn.py"])

      case System.cmd("docker", base ++ [script, "--mount-plan"] ++ args, stderr_to_stdout: true) do
        {plan, 0} ->
          paths = String.split(plan, <<0>>, trim: true)

          if Enum.all?(
               paths,
               &(String.starts_with?(&1, "/") and not String.contains?(&1, ["\n", ","]))
             ) do
            mounts =
              Enum.flat_map(paths, &["--mount", "type=bind,source=#{&1},target=#{&1},readonly"])

            {options, [image]} = Enum.split(base, -1)

            {output, code} =
              System.cmd("docker", options ++ mounts ++ [image, script] ++ args,
                stderr_to_stdout: true
              )

            OCIBridge.decode_result(output, code)
          else
            {:error, "Invalid Oracle mount plan."}
          end

        _ ->
          {:error, "Oracle runtime path planning failed. Check configuration and host mounts."}
      end
    end
  rescue
    _ -> {:error, "Oracle DXNN command failed. Check Docker and deployment mounts."}
  end

  def local_download_path(relative) do
    if is_binary(relative) and String.starts_with?(relative, "output/oci/downloads/") and
         Enum.all?(Path.split(relative), &(&1 not in [".", ".."])) do
      {:ok, Path.join(OCIBridge.root(), relative)}
    else
      {:error, "Invalid artifact cache path."}
    end
  end
end
