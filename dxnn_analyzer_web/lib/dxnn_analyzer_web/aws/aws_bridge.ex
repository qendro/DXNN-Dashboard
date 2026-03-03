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
      {_output, 0} -> {:ok, "Instance #{instance_id} terminating"}
      {error, _} -> {:error, error}
    end
  end

  def terminate_all_instances do
    run_script("docker-deploy.sh", ["-x"])
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

  def deploy_config(key_file, host, config_file, branch \\ nil, start \\ false) do
    args = ["-i", key_file, "-h", host, "-c", config_file]
    args = if branch, do: args ++ ["-b", branch], else: args
    args = if start, do: args ++ ["--start"], else: args
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

  def start_training(key_file, host) do
    ssh_command(key_file, host, "sudo /usr/local/bin/dxnn-wrapper.sh")
  end

  def stop_training(key_file, host) do
    ssh_command(key_file, host, "tmux kill-session -t trader 2>/dev/null || true")
  end

  def tail_log(key_file, host, log_file, lines \\ 50) do
    ssh_command(key_file, host, "sudo tail -n #{lines} #{log_file}")
  end

  # Helper Functions

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
        60_000 -> send(parent, {:script_timeout, "Script timed out"})
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
end
