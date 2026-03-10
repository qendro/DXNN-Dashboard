defmodule DxnnAnalyzerWeb.AWS.AWSBridge do
  @moduledoc """
  Bridge module for AWS operations. Wraps AWS CLI and bash scripts.
  """

  @aws_deployment_path "/app/AWS-Deployment"

  # AMI Operations

  def list_amis do
    case run_script("ami-manager.sh", ["--list"]) do
      {:ok, output} -> parse_ami_list(output)
      {:error, _} = error -> error
    end
  end

  def create_ami(name \\ nil) do
    args = if name, do: ["--create", "--name", name], else: ["--create"]
    run_script_async("ami-manager.sh", args)
  end

  def delete_ami(ami_id) do
    run_script("ami-manager.sh", ["--delete", ami_id])
  end

  def delete_all_amis do
    run_script("ami-manager.sh", ["--delete-all"])
  end

  # Instance Operations

  def list_instances do
    # List ALL instances in running/pending/stopped states
    case System.cmd("aws", [
      "ec2", "describe-instances",
      "--filters",
      "Name=instance-state-name,Values=pending,running,stopping,stopped",
      "--query", "Reservations[*].Instances[*].[InstanceId,PublicIpAddress,InstanceType,State.Name,LaunchTime,Tags[?Key=='Name'].Value|[0]]",
      "--output", "json"
    ], stderr_to_stdout: true) do
      {output, 0} -> parse_instance_list(output)
      {error, _} -> {:error, error}
    end
  end

  def launch_instance(config_file) do
    run_script_async("docker-deploy.sh", ["-c", config_file])
  end

  def terminate_instance(instance_id) do
    case System.cmd("aws", ["ec2", "terminate-instances", "--instance-ids", instance_id], stderr_to_stdout: true) do
      {_output, 0} -> 
        # Remove from deployments tracking
        remove_deployment_tracking(instance_id)
        {:ok, "Instance #{instance_id} terminating"}
      {error, _} -> {:error, error}
    end
  end

  def terminate_all_instances do
    # Get all instances before terminating
    {:ok, instances} = list_instances()
    instance_ids = Enum.map(instances, & &1.id)
    
    result = run_script("docker-deploy.sh", ["-x"])
    
    # Remove all from deployments tracking
    Enum.each(instance_ids, &remove_deployment_tracking/1)
    
    result
  end

  def get_instance_logs(instance_id) do
    case System.cmd("aws", [
      "ec2", "get-console-output",
      "--instance-id", instance_id,
      "--output", "text"
    ], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end

  # Config Operations

  def list_configs do
    config_path = Path.join(@aws_deployment_path, "config")
    case File.ls(config_path) do
      {:ok, files} ->
        configs = files
        |> Enum.filter(&String.ends_with?(&1, ".yml"))
        |> Enum.map(&parse_config_file(Path.join(config_path, &1)))
        |> Enum.reject(&is_nil/1)
        {:ok, configs}
      {:error, _} = error -> error
    end
  end

  def read_config(config_file) do
    config_path = Path.join([@aws_deployment_path, "config", config_file])
    case File.read(config_path) do
      {:ok, content} ->
        case YamlElixir.read_from_string(content) do
          {:ok, parsed} -> {:ok, %{raw: content, parsed: parsed}}
          {:error, _} = error -> error
        end
      {:error, _} = error -> error
    end
  end

  def deploy_config(key_file, host, config_files, branch \\ nil, start \\ false, auto_terminate \\ false) do
    # config_files is now a list (can be empty)
    args = ["-i", key_file, "-h", host]
    
    # Add config files if provided
    args = if length(config_files) > 0 do
      args ++ ["-c" | config_files]
    else
      args
    end
    
    args = if branch, do: args ++ ["-b", branch], else: args
    args = if start, do: args ++ ["--start"], else: args
    args = if auto_terminate, do: args ++ ["--auto-terminate"], else: args
    run_script_async("deploy-config.sh", args)
  end

  # SSH Operations

  def ssh_command(key_file, host, command) do
    System.cmd("ssh", [
      "-i", key_file,
      "-o", "StrictHostKeyChecking=no",
      "-o", "UserKnownHostsFile=/dev/null",
      "ubuntu@#{host}",
      command
    ], stderr_to_stdout: true)
  end

  def get_tmux_status(key_file, host) do
    case ssh_command(key_file, host, "tmux list-sessions 2>/dev/null | grep trader") do
      {output, 0} -> {:ok, :running, output}
      {_, _} -> {:ok, :stopped, ""}
    end
  end

  def capture_tmux_pane(key_file, host, session \\ "trader", lines \\ 100) do
    case ssh_command(key_file, host, "tmux capture-pane -t #{session} -p -S -#{lines} 2>/dev/null") do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end

  def get_ssh_output(key_file, host, command) do
    case ssh_command(key_file, host, command) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end

  def start_training(key_file, host) do
    ssh_command(key_file, host, "sudo /usr/local/bin/dxnn-wrapper.sh")
  end

  def stop_training(key_file, host) do
    ssh_command(key_file, host, "tmux kill-session -t trader 2>/dev/null || true")
  end

  def tail_log(key_file, host, log_file, lines \\ 50) do
    ssh_command(key_file, host, "sudo tail -n #{lines} #{log_file}")
  end

  # Checkpoint Operations

  def force_checkpoint(key_file, host) do
    # Checkpoint is no longer needed - just a status check
    ssh_command(key_file, host, "echo 'Ready for S3 upload'")
  end

  def trigger_s3_upload(key_file, host) do
    # Trigger S3 upload directly from filesystem (no checkpoint needed)
    ssh_command(key_file, host, """
    export COMPLETION_STATUS=manual
    export EXIT_CODE=0
    export POPULATION_ID=manual_$(date +%s)
    export LINEAGE_ID=manual
    export S3_BUCKET=${S3_BUCKET:-dxnn-checkpoints}
    export S3_PREFIX=${S3_PREFIX:-dxnn-prod}
    export AUTO_TERMINATE=false
    sudo -E /usr/local/bin/finalize_run.sh
    """)
  end

  # Log File Operations

  def list_log_files(key_file, host) do
    case ssh_command(key_file, host, """
    (sudo find /var/log -maxdepth 1 -type f \\( -name 'dxnn*.log' -o -name 'spot*.log' -o -name 'cloud-init*.log' \\) 2>/dev/null | \
    while read f; do
      size=$(sudo du -h "$f" 2>/dev/null | cut -f1)
      echo "$f|$size"
    done) && \
    (find ~/dxnn-trader/logs -type f 2>/dev/null | \
    while read f; do
      size=$(du -h "$f" 2>/dev/null | cut -f1)
      echo "$f|$size"
    done) || true
    """) do
      {output, 0} -> parse_log_files(output)
      {error, _} -> {:error, error}
    end
  end

  def read_log_file(key_file, host, log_path, lines \\ 100) do
    ssh_command(key_file, host, "sudo tail -n #{lines} '#{log_path}' 2>/dev/null || tail -n #{lines} '#{log_path}'")
  end

  def get_checkpoint_status(key_file, host) do
    case ssh_command(key_file, host, """
    if [ -d /var/lib/dxnn/checkpoints ]; then
      last=$(sudo ls -t /var/lib/dxnn/checkpoints/ 2>/dev/null | head -1)
      size=$(sudo du -sh /var/lib/dxnn/checkpoints 2>/dev/null | cut -f1)
      count=$(sudo ls /var/lib/dxnn/checkpoints/ 2>/dev/null | wc -l)
      echo "$last|$size|$count"
    else
      echo "none|0|0"
    fi
    """) do
      {output, 0} -> parse_checkpoint_status(output)
      {error, _} -> {:error, error}
    end
  end

  # S3 Operations

  def list_s3_jobs(bucket \\ "dxnn-checkpoints", prefix \\ "dxnn-prod") do
    case System.cmd("aws", [
      "s3", "ls",
      "s3://#{bucket}/#{prefix}/",
      "--output", "text"
    ], stderr_to_stdout: true) do
      {output, 0} -> parse_s3_jobs(output)
      {error, _} -> {:error, error}
    end
  end

  def list_s3_runs(bucket, prefix, lineage_id) do
    case System.cmd("aws", [
      "s3", "ls",
      "s3://#{bucket}/#{prefix}/#{lineage_id}/",
      "--output", "text"
    ], stderr_to_stdout: true) do
      {output, 0} -> parse_s3_runs(output, bucket, prefix, lineage_id)
      {error, _} -> {:error, error}
    end
  end

  def get_s3_checkpoint_metadata(bucket, prefix, lineage_id, population_id) do
    temp_file = "/tmp/s3_success_#{:erlang.phash2({bucket, lineage_id, population_id})}"
    s3_path = "s3://#{bucket}/#{prefix}/#{lineage_id}/#{population_id}/_SUCCESS"
    
    case System.cmd("aws", ["s3", "cp", s3_path, temp_file], stderr_to_stdout: true) do
      {_, 0} ->
        case File.read(temp_file) do
          {:ok, content} ->
            File.rm(temp_file)
            case Jason.decode(content) do
              {:ok, metadata} -> {:ok, metadata}
              {:error, _} -> {:error, "Invalid metadata format"}
            end
          {:error, reason} -> {:error, reason}
        end
      {error, _} ->
        File.rm(temp_file)
        {:error, error}
    end
  end

  def download_s3_checkpoint(bucket, prefix, lineage_id, population_id, local_path) do
    s3_path = "s3://#{bucket}/#{prefix}/#{lineage_id}/#{population_id}/"
    
    File.mkdir_p!(local_path)
    
    case System.cmd("aws", [
      "s3", "sync",
      s3_path,
      local_path,
      "--no-progress"
    ], stderr_to_stdout: true) do
      {_, 0} -> {:ok, local_path}
      {error, _} -> {:error, error}
    end
  end

  def list_instance_s3_checkpoints(instance_id) do
    # Try to find checkpoints associated with this instance
    # Uses instance_id as lineage_id pattern
    list_s3_jobs()
    |> case do
      {:ok, jobs} ->
        matching = Enum.filter(jobs, fn job -> 
          String.contains?(job.id, instance_id) || String.contains?(instance_id, job.id)
        end)
        {:ok, matching}
      error -> error
    end
  end

  # Helper Functions

  defp remove_deployment_tracking(instance_id) do
    deployments_file = "/app/AWS-Deployment/output/deployments.json"
    
    case File.read(deployments_file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, deployments} ->
            updated = Map.delete(deployments, instance_id)
            case Jason.encode(updated, pretty: true) do
              {:ok, json} -> File.write(deployments_file, json)
              _ -> :ok
            end
          _ -> :ok
        end
      _ -> :ok
    end
  end

  defp run_script(script_name, args) do
    script_path = Path.join(@aws_deployment_path, script_name)
    case System.cmd("bash", [script_path | args], cd: @aws_deployment_path, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end

  defp run_script_async(script_name, args) do
    script_path = Path.join(@aws_deployment_path, script_name)
    parent = self()
    
    spawn(fn ->
      # Use spawn_executable with proper environment to avoid TTY issues
      port = Port.open({:spawn_executable, "/bin/bash"}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        :use_stdio,
        args: [script_path | args],
        cd: @aws_deployment_path,
        env: [
          {'PATH', String.to_charlist(System.get_env("PATH", "/usr/local/bin:/usr/bin:/bin"))},
          {'HOME', String.to_charlist(System.get_env("HOME", "/root"))}
        ]
      ])
      
      stream_output(port, parent)
    end)
    
    {:ok, :started}
  end

  defp stream_output(port, parent) do
    receive do
      {^port, {:data, data}} ->
        send(parent, {:script_output, data})
        stream_output(port, parent)
      {^port, {:exit_status, status}} ->
        send(parent, {:script_complete, status})
      after
        900_000 -> send(parent, {:script_timeout, "Script timed out after 15 minutes with no output"})
    end
  end

  defp parse_ami_list(output) do
    lines = String.split(output, "\n", trim: true)
    amis = Enum.reduce(lines, [], fn line, acc ->
      case Regex.run(~r/(ami-[a-z0-9]+)\s+(.+?)\s+(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})/, line) do
        [_, ami_id, name, created_at] ->
          [%{id: ami_id, name: String.trim(name), created_at: created_at, state: "available"} | acc]
        _ -> acc
      end
    end)
    {:ok, Enum.reverse(amis)}
  end

  defp parse_instance_list(json) do
    case Jason.decode(json) do
      {:ok, data} when is_list(data) ->
        instances = data
        |> List.flatten()
        |> Enum.chunk_every(6)
        |> Enum.map(fn
          [id, ip, type, state, launch_time, name] when is_binary(id) ->
            %{
              id: id,
              ip: ip || "N/A",
              type: type,
              state: state,
              launch_time: launch_time,
              name: name || "unnamed"
            }
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)
        {:ok, instances}
      {:error, _} = error -> error
    end
  end

  defp parse_config_file(path) do
    case File.read(path) do
      {:ok, content} ->
        case YamlElixir.read_from_string(content) do
          {:ok, parsed} ->
            %{
              name: Path.basename(path),
              path: path,
              instance_type: get_in(parsed, ["aws", "instance_type"]) || "unknown",
              ami_id: get_in(parsed, ["aws", "ami_id"]) || "N/A"
            }
          _ -> nil
        end
      _ -> nil
    end
  end

  defp parse_log_files(output) do
    logs = output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      case String.split(line, "|", parts: 2) do
        [path, size] -> %{path: String.trim(path), size: String.trim(size)}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    {:ok, logs}
  end

  defp parse_checkpoint_status(output) do
    case String.split(String.trim(output), "|") do
      [last, size, count] ->
        {:ok, %{
          last_checkpoint: if(last == "none", do: nil, else: last),
          total_size: size,
          count: String.to_integer(count)
        }}
      _ -> {:error, "Invalid checkpoint status"}
    end
  end

  defp parse_s3_jobs(output) do
    jobs = output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      case Regex.run(~r/PRE\s+(.+)\/$/, line) do
        [_, lineage_id] -> %{id: String.trim(lineage_id), type: "lineage"}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    {:ok, jobs}
  end

  defp parse_s3_runs(output, bucket, prefix, lineage_id) do
    runs = output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      case Regex.run(~r/PRE\s+(.+)\/$/, line) do
        [_, population_id] -> 
          %{
            id: String.trim(population_id),
            lineage_id: lineage_id,
            bucket: bucket,
            prefix: prefix,
            s3_path: "s3://#{bucket}/#{prefix}/#{lineage_id}/#{String.trim(population_id)}/"
          }
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    {:ok, runs}
  end
end
