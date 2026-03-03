defmodule DxnnAnalyzerWeb.AWS.AWSDeploymentServer do
  @moduledoc """
  GenServer for managing AWS deployment state and async operations.
  """
  use GenServer
  alias DxnnAnalyzerWeb.AWS.AWSBridge

  @refresh_interval 30_000  # 30 seconds
  @deployments_file "/app/AWS-Deployment/output/deployments.json"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_state) do
    schedule_refresh()
    deployments = load_deployments_from_file()
    
    {:ok, %{
      amis: [],
      instances: [],
      configs: [],
      last_refresh: nil,
      operations: %{},
      deployments: deployments
    }}
  end

  # Client API

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  def start_operation(operation_id, type) do
    GenServer.cast(__MODULE__, {:start_operation, operation_id, type})
  end

  def complete_operation(operation_id, result) do
    GenServer.cast(__MODULE__, {:complete_operation, operation_id, result})
  end

  def get_operation(operation_id) do
    GenServer.call(__MODULE__, {:get_operation, operation_id})
  end

  def append_output(operation_id, output) do
    GenServer.cast(__MODULE__, {:append_output, operation_id, output})
  end

  def record_deployment(instance_id, deployment_info) do
    GenServer.cast(__MODULE__, {:record_deployment, instance_id, deployment_info})
  end

  def get_deployment(instance_id) do
    GenServer.call(__MODULE__, {:get_deployment, instance_id})
  end

  # Server Callbacks

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:get_operation, operation_id}, _from, state) do
    operation = Map.get(state.operations, operation_id)
    {:reply, operation, state}
  end

  def handle_call({:get_deployment, instance_id}, _from, state) do
    deployment = Map.get(state.deployments, instance_id)
    {:reply, deployment, state}
  end

  def handle_cast(:refresh, state) do
    require Logger
    Logger.info("AWSDeploymentServer: Refresh called, current deployments: #{inspect(state.deployments)}")
    
    new_state = load_all_data(state)
    
    Logger.info("AWSDeploymentServer: After load_all_data, deployments: #{inspect(new_state.deployments)}")
    
    Phoenix.PubSub.broadcast(
      DxnnAnalyzerWeb.PubSub,
      "aws_deployment",
      {:state_updated, new_state}
    )
    {:noreply, new_state}
  end

  def handle_cast({:start_operation, operation_id, type}, state) do
    operation = %{
      id: operation_id,
      type: type,
      status: :running,
      started_at: DateTime.utc_now(),
      output: []
    }
    new_state = put_in(state, [:operations, operation_id], operation)
    
    # Broadcast to all connected clients
    Phoenix.PubSub.broadcast(
      DxnnAnalyzerWeb.PubSub,
      "aws_operations",
      {:operation_started, operation_id, type}
    )
    
    {:noreply, new_state}
  end

  def handle_cast({:complete_operation, operation_id, result}, state) do
    case get_in(state, [:operations, operation_id]) do
      nil -> {:noreply, state}
      operation ->
        updated_operation = Map.merge(operation, %{
          status: :completed,
          result: result,
          completed_at: DateTime.utc_now()
        })
        new_state = put_in(state, [:operations, operation_id], updated_operation)
        
        # Broadcast completion
        Phoenix.PubSub.broadcast(
          DxnnAnalyzerWeb.PubSub,
          "aws_operations",
          {:operation_completed, operation_id, result}
        )
        
        {:noreply, new_state}
    end
  end

  def handle_cast({:append_output, operation_id, output}, state) do
    case get_in(state, [:operations, operation_id]) do
      nil -> {:noreply, state}
      operation ->
        updated_output = operation.output ++ [output]
        updated_operation = Map.put(operation, :output, updated_output)
        new_state = put_in(state, [:operations, operation_id], updated_operation)
        {:noreply, new_state}
    end
  end

  def handle_cast({:record_deployment, instance_id, deployment_info}, state) do
    require Logger
    Logger.info("AWSDeploymentServer: Recording deployment for #{instance_id}")
    
    deployment = Map.merge(%{
      deployed_at: DateTime.utc_now(),
      instance_id: instance_id
    }, deployment_info)
    
    new_state = put_in(state, [:deployments, instance_id], deployment)
    
    # Persist to file
    save_deployments_to_file(new_state.deployments)
    
    Logger.info("AWSDeploymentServer: Deployments state: #{inspect(new_state.deployments)}")
    
    # Broadcast deployment update
    Phoenix.PubSub.broadcast(
      DxnnAnalyzerWeb.PubSub,
      "aws_deployment",
      {:deployment_recorded, instance_id, deployment}
    )
    
    {:noreply, new_state}
  end

  def handle_info(:refresh, state) do
    schedule_refresh()
    new_state = load_all_data(state)
    Phoenix.PubSub.broadcast(
      DxnnAnalyzerWeb.PubSub,
      "aws_deployment",
      {:state_updated, new_state}
    )
    {:noreply, new_state}
  end

  # Private Functions

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  defp load_all_data(state) do
    amis = case AWSBridge.list_amis() do
      {:ok, list} -> list
      _ -> state.amis
    end

    instances = case AWSBridge.list_instances() do
      {:ok, list} -> list
      _ -> state.instances
    end

    configs = case AWSBridge.list_configs() do
      {:ok, list} -> list
      _ -> state.configs
    end

    %{state |
      amis: amis,
      instances: instances,
      configs: configs,
      last_refresh: DateTime.utc_now()
      # deployments are preserved from existing state
    }
  end

  defp load_deployments_from_file do
    case File.read(@deployments_file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} ->
            # Convert string keys to atoms and parse DateTime
            data
            |> Enum.map(fn {instance_id, deployment} ->
              parsed_deployment = deployment
              |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
              |> Map.update(:deployed_at, nil, fn dt_string ->
                case DateTime.from_iso8601(dt_string) do
                  {:ok, dt, _} -> dt
                  _ -> nil
                end
              end)
              
              {instance_id, parsed_deployment}
            end)
            |> Map.new()
          {:error, reason} ->
            require Logger
            Logger.warning("Failed to parse deployments.json: #{inspect(reason)}")
            %{}
        end
      {:error, :enoent} ->
        # File doesn't exist yet, that's ok
        %{}
      {:error, reason} ->
        require Logger
        Logger.warning("Failed to read deployments.json: #{inspect(reason)}")
        %{}
    end
  end

  defp save_deployments_to_file(deployments) do
    # Convert DateTime to ISO8601 string for JSON serialization
    serializable = deployments
    |> Enum.map(fn {instance_id, deployment} ->
      serialized_deployment = deployment
      |> Map.update(:deployed_at, nil, fn dt ->
        if dt, do: DateTime.to_iso8601(dt), else: nil
      end)
      
      {instance_id, serialized_deployment}
    end)
    |> Map.new()
    
    case Jason.encode(serializable, pretty: true) do
      {:ok, json} ->
        File.write(@deployments_file, json)
      {:error, reason} ->
        require Logger
        Logger.error("Failed to encode deployments to JSON: #{inspect(reason)}")
    end
  end
end
