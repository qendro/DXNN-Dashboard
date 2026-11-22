defmodule DxnnAnalyzerWeb.GCP.DxnnBridge do
  @moduledoc """
  DXNN application and GCS storage operations on Compute Engine, through
  AWS-Deployment/scripts/gcp_dxnn.py in the deployment container.

  The CLI owns every decision (install bundles, run identity, --env rules,
  resume build checks, verified downloads). This module only validates the
  dashboard's inputs, builds argv, and decodes the CLI's JSON result.
  """
  alias DxnnAnalyzerWeb.GCP.GCPBridge
  alias DxnnAnalyzerWeb.OCI.OCIBridge

  @instance_commands ~w(install status logs checkpoint stop retry-upload)
  # `setup` changes bucket IAM and lifecycle rules; it stays a CLI-only step (gcp-dxnn-setup.sh).
  @storage ~w(verify list snapshots latest download)
  @worker_env_keys ~w(DXNN_STORAGE_PROVIDER DXNN_FINAL_DIR DXNN_STOP_DIR DXNN_RESTORE_DIR
                      DXNN_CHECKPOINT_PAUSE_MS DXNN_RUN_CONFIGS_FILE)

  def configs do
    Path.wildcard(Path.join(GCPBridge.root(), "config/*.{yml,yaml}"))
    |> Enum.reject(&String.contains?(Path.basename(&1), ".example."))
    |> Enum.filter(fn path ->
      case YamlElixir.read_from_file(path) do
        {:ok, %{"schema_version" => 1, "storage" => %{"provider" => "gcs"}}} -> true
        _ -> false
      end
    end)
    |> Enum.map(&Path.basename/1)
  end

  def instances, do: GCPBridge.records()

  def command_args(command, params) do
    with true <- params["config"] in configs(),
         {:ok, host} <- OCIBridge.host_root(),
         {:ok, tail} <- operation_args(command, params) do
      {:ok, ["-c", Path.join([host, "config", params["config"]])] ++ tail}
    else
      {:error, _} = error -> error
      _ -> {:error, "Select an existing GCP runtime configuration."}
    end
  end

  defp operation_args("validate", _), do: {:ok, ["validate"]}

  defp operation_args("storage:" <> operation, params) when operation in @storage do
    case operation do
      "latest" ->
        if valid_id?(params["lineage"]) and valid_id?(params["run"]),
          do:
            {:ok, ["storage", "latest", "--lineage", params["lineage"], "--run", params["run"]]},
          else: {:error, "Enter valid run and lineage IDs."}

      "download" ->
        if Enum.all?(~w(lineage run checkpoint), &valid_id?(params[&1])) and
             params["kind"] in ["checkpoints", "final"] do
          {:ok,
           ["storage", "download", "--lineage", params["lineage"], "--run", params["run"]] ++
             ["--checkpoint", params["checkpoint"], "--kind", params["kind"]]}
        else
          {:error, "Invalid snapshot selection."}
        end

      _ ->
        {:ok, ["storage", operation]}
    end
  end

  defp operation_args(command, params) do
    with {:ok, instance} <- recorded_instance(params["instance"]) do
      instance_args(command, instance, params)
    end
  end

  defp instance_args(command, instance, _) when command in @instance_commands,
    do: {:ok, [command, instance]}

  defp instance_args("start", instance, params) do
    with true <- valid_id?(params["run"]) and valid_id?(params["lineage"]),
         {:ok, restore} <- restore_args(params["restore"]),
         {:ok, env} <- env_args(params["env"]) do
      {:ok,
       ["start", instance, "--run", params["run"], "--lineage", params["lineage"]] ++
         restore ++ env}
    else
      false -> {:error, "Enter valid run and lineage IDs."}
      {:error, _} = error -> error
    end
  end

  defp instance_args("resume", instance, params) do
    optional = fn flag, key ->
      case params[key] do
        blank when blank in [nil, ""] -> {:ok, []}
        value -> if valid_id?(value), do: {:ok, [flag, value]}, else: :invalid
      end
    end

    with true <- valid_id?(params["run"]),
         {:ok, from} <- optional.("--from-run", "from_run"),
         {:ok, lineage} <- optional.("--lineage", "lineage"),
         {:ok, env} <- env_args(params["env"]) do
      force = if params["force_build"] == "true", do: ["--force-build"], else: []
      {:ok, ["resume", instance, "--run", params["run"]] ++ from ++ lineage ++ env ++ force}
    else
      {:error, _} = error -> error
      _ -> {:error, "Enter a valid new run ID (and valid optional from-run and lineage IDs)."}
    end
  end

  defp instance_args(_, _, _), do: {:error, "Unsupported GCP DXNN operation."}

  # The CLI accepts a recorded name or numeric ID; pass the ID so a reused name cannot be mistaken.
  defp recorded_instance(id) do
    if is_binary(id) and Regex.match?(~r/\A\d+\z/, id) and
         Enum.any?(instances(), &(&1["instance_id"] == id)),
       do: {:ok, id},
       else: {:error, "Select a recorded GCP instance."}
  end

  defp restore_args(blank) when blank in [nil, ""], do: {:ok, []}

  defp restore_args(restore) do
    case Jason.decode(restore) do
      {:ok, %{"lineage_id" => l, "run_id" => r, "checkpoint_id" => c} = ref} ->
        if Enum.all?([l, r, c], &valid_id?/1),
          do:
            {:ok,
             ["--restore", Jason.encode!(Map.take(ref, ~w(lineage_id run_id checkpoint_id)))]},
          else: {:error, "Invalid restore identity."}

      _ ->
        {:error, "Restore must contain lineage_id, run_id, checkpoint_id."}
    end
  end

  @doc "Parses KEY=VALUE lines (blank lines ignored) with the same rules as cloud_common.run_env."
  def env_args(text) when text in [nil, ""], do: {:ok, []}

  def env_args(text) when is_binary(text) do
    pairs =
      text
      |> String.split(["\n", "\r"], trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    invalid =
      Enum.find(pairs, fn pair ->
        case String.split(pair, "=", parts: 2) do
          [key, value] ->
            not Regex.match?(~r/\ADXNN_[A-Z0-9_]{1,60}\z/, key) or key in @worker_env_keys or
              not Regex.match?(~r/\A[A-Za-z0-9_.,:+\/@=-]{0,200}\z/, value)

          _ ->
            true
        end
      end)

    keys = Enum.map(pairs, &hd(String.split(&1, "=", parts: 2)))

    cond do
      invalid ->
        {:error,
         "Invalid environment line #{inspect(invalid)}: use DXNN_KEY=value, value of A-Z a-z 0-9 _ . , : + / @ = -, and no worker-owned keys."}

      length(pairs) > 32 ->
        {:error, "A run takes at most 32 environment pairs."}

      length(Enum.uniq(keys)) != length(keys) ->
        {:error, "Each environment key may appear only once."}

      true ->
        {:ok, Enum.flat_map(pairs, &["--env", &1])}
    end
  end

  def env_args(_), do: {:error, "Invalid environment pairs."}

  defp valid_id?(value),
    do:
      is_binary(value) and Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\z/, value) and
        value not in [".", ".."]

  def run("storage:archive", params) do
    with {:ok, %{"result" => result}} <- run("storage:download", params),
         {:ok, path} <- local_download_path(result["path"]) do
      archive(path, params)
    end
  end

  def run(command, params) do
    with {:ok, args} <- command_args(command, params),
         {:ok, base, _adapter} <- GCPBridge.docker_args(),
         {:ok, host} <- OCIBridge.host_root() do
      script = Path.join([host, "scripts", "gcp_dxnn.py"])

      case System.cmd("docker", base ++ [script, "--mount-plan"] ++ args, stderr_to_stdout: true) do
        {plan, 0} ->
          with {:ok, mounts} <- GCPBridge.planned_mounts(plan, base) do
            {output, code} =
              System.cmd("docker", GCPBridge.insert_mounts(base, mounts) ++ [script] ++ args,
                stderr_to_stdout: true
              )

            decode_result(output, code)
          end

        {output, _} ->
          case decode_result(output, 1) do
            {:error, %{"error" => _}} = error ->
              error

            _ ->
              {:error,
               "GCP runtime path planning failed. Check the runtime YAML, source_dir and GCP sign-in (AWS-Deployment/gcp-login.sh)."}
          end
      end
    end
  rescue
    _ -> {:error, "GCP DXNN command failed. Check Docker and deployment mounts."}
  end

  @doc """
  gcp_dxnn.py prints one indented JSON document last; progress notes (install) may precede it
  on the merged stream. Decode from the last line that opens a top-level object.
  """
  def decode_result(output, code) do
    lines = String.split(output, "\n")

    decoded =
      lines
      |> Enum.with_index()
      |> Enum.filter(fn {line, _} -> String.starts_with?(line, "{") end)
      |> Enum.reverse()
      |> Enum.find_value(fn {_, index} ->
        case Jason.decode(lines |> Enum.drop(index) |> Enum.join("\n")) do
          {:ok, %{} = result} -> result
          _ -> nil
        end
      end)

    case decoded do
      %{"ok" => true} = result when code == 0 ->
        {:ok, result}

      %{"ok" => false} = result ->
        {:error, result}

      _ ->
        {:error,
         "GCP DXNN tool did not return a JSON result; outcome may be uncertain. Refresh status before retrying."}
    end
  end

  def error_message(%{"error" => error}) when is_binary(error), do: error
  def error_message(error) when is_binary(error), do: error
  def error_message(_), do: "GCP operation failed."

  def local_download_path(relative) do
    if is_binary(relative) and String.starts_with?(relative, "output/gcp/downloads/") and
         Enum.all?(Path.split(relative), &(&1 not in [".", ".."])) do
      {:ok, Path.join(GCPBridge.root(), relative)}
    else
      {:error, "Invalid artifact cache path."}
    end
  end

  def exports_dir, do: Path.join(GCPBridge.root(), "output/gcp/exports")

  # Zip a verified download (the CLI checked every file's SHA-256 against the committed manifest).
  defp archive(path, params) do
    files =
      Path.wildcard(Path.join(path, "**"), match_dot: true)
      |> Enum.filter(&File.regular?/1)
      |> Enum.reject(&(File.lstat!(&1).type == :symlink))
      |> Enum.map(&String.to_charlist(Path.relative_to(&1, path)))

    token = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    target = Path.join(exports_dir(), token <> ".zip")
    filename = "dxnn-#{params["lineage"]}-#{params["run"]}-#{params["checkpoint"]}.zip"

    with :ok <- File.mkdir_p(exports_dir()),
         {:ok, _} <- :zip.create(String.to_charlist(target), files, cwd: String.to_charlist(path)) do
      {:ok, %{"result" => %{"token" => token, "filename" => filename}}}
    else
      _ -> {:error, "Could not prepare the archive in output/gcp/exports."}
    end
  end
end
