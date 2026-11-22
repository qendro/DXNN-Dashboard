defmodule DxnnAnalyzerWeb.OCI.OCIServer do
  @moduledoc """
  Serializes VM lifecycle operations for one provider and broadcasts public state.

  Defaults serve Oracle (OCI). The GCP page runs a second instance with its own
  bridge, topic and event (see `DxnnAnalyzerWeb.GCP.GCPBridge.server_opts/0`).
  """
  use GenServer
  alias DxnnAnalyzerWeb.OCI.OCIBridge

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def state(server \\ __MODULE__), do: GenServer.call(server, :state)

  def submit(type, params \\ %{}, server \\ __MODULE__),
    do: GenServer.call(server, {:submit, type, params})

  @impl true
  def init(opts) do
    {:ok,
     %{
       bridge: Keyword.get(opts, :bridge, OCIBridge),
       topic: Keyword.get(opts, :topic, "oci_instances"),
       event: Keyword.get(opts, :event, :oci_state),
       label: Keyword.get(opts, :label, "OCI"),
       task_supervisor: Keyword.get(opts, :task_supervisor, DxnnAnalyzerWeb.OCI.TaskSupervisor),
       public_instance: Keyword.get(opts, :public_instance, &OCIBridge.public_instance/1),
       active: nil,
       public: %{
         instances: [],
         configs: [],
         summary: nil,
         summary_config: nil,
         fingerprint: nil,
         busy: false,
         operations: [],
         summary_error: nil,
         refresh_error: nil,
         last_refresh: nil
       }
     }}
  end

  @impl true
  def handle_call(:state, _from, state), do: {:reply, state.public, state}

  def handle_call({:submit, _, _}, _from, %{active: active} = state) when not is_nil(active),
    do:
      {:reply, {:error, "Another #{state.label} operation is running. Wait for it to finish."},
       state}

  def handle_call({:submit, type, params}, _from, state) do
    case validate(type, params, state) do
      {:ok, params} ->
        bridge = state.bridge

        task =
          Task.Supervisor.async_nolink(state.task_supervisor, fn ->
            result = bridge.run(type, params)

            refreshed =
              if type in [:launch, :start, :stop, :reboot, :terminate],
                do: bridge.run(:refresh, %{}),
                else: nil

            {result, refreshed}
          end)

        operation = %{
          id: System.unique_integer([:positive]),
          type: type,
          target: target(params),
          status: :running,
          message: "Running #{type}; saved CLI progress is retained.",
          started_at: DateTime.utc_now()
        }

        public = %{state.public | busy: true, configs: bridge.configs()}

        public =
          if type in [:refresh, :summary],
            do: public,
            else: %{public | operations: Enum.take([operation | public.operations], 8)}

        public =
          if type == :summary,
            do: %{
              public
              | summary: nil,
                summary_config: nil,
                fingerprint: nil,
                summary_error: nil
            },
            else: public

        new = %{
          state
          | public: public,
            active: %{ref: task.ref, operation: operation, params: params}
        }

        Process.send_after(self(), :progress, 2_000)
        broadcast(new)
        {:reply, :ok, new}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  defp validate(:summary, %{config: config} = params, state) do
    with {:ok, fingerprint} <- state.bridge.fingerprint(config),
         do: {:ok, Map.put(params, :fingerprint, fingerprint)}
  end

  defp validate(:launch, %{config: config, fingerprint: expected} = params, state) do
    with true <- state.public.summary_config == config and state.public.fingerprint == expected,
         {:ok, ^expected} <- state.bridge.fingerprint(config) do
      {:ok, params}
    else
      _ ->
        {:error,
         "Configuration changed or summary is missing. Review its summary again before launching."}
    end
  end

  defp validate(:refresh, _, _), do: {:ok, %{}}

  defp validate(type, %{id: id, region: region} = params, state)
       when type in [:start, :stop, :reboot, :terminate] do
    instance =
      Enum.find(state.public.instances, &(&1["instance_id"] == id and &1["region"] == region))

    allowed =
      case type do
        :start ->
          ["STOPPED"]

        :stop ->
          ["RUNNING"]

        :reboot ->
          ["RUNNING"]

        :terminate ->
          if instance && is_binary(instance["state"]) &&
               instance["state"] not in ["UNKNOWN", "TERMINATING", "TERMINATED"],
             do: [instance["state"]],
             else: []
      end

    cond do
      state.public.refresh_error != nil ->
        {:error, "Instance state is uncertain. Refresh successfully before taking an action."}

      instance == nil or instance["state"] not in allowed ->
        {:error, "Instance is unavailable or transitioning. Refresh its state first."}

      type == :terminate and params[:boot_volume] not in ["preserve", "delete"] ->
        {:error, "Choose preserve or delete boot volume explicitly."}

      true ->
        {:ok, Map.put(params, :instance, instance)}
    end
  end

  defp validate(_, _, state), do: {:error, "Unsupported #{state.label} request."}

  @impl true
  def handle_info({ref, {result, refreshed}}, %{active: %{ref: ref} = active} = state) do
    Process.demonitor(ref, [:flush])
    state = apply_result(state, active, result, refreshed)
    broadcast(state)
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{active: %{ref: ref} = active} = state) do
    message =
      "Worker stopped; operation outcome is uncertain. Refresh and inspect the retained CLI record before retrying."

    state = apply_result(state, active, {:error, message}, nil)
    broadcast(state)
    {:noreply, state}
  end

  def handle_info(:progress, %{active: nil} = state), do: {:noreply, state}

  def handle_info(:progress, state) do
    public = merge_records(state.public, state.bridge.records())
    state = %{state | public: public}
    broadcast(state)
    Process.send_after(self(), :progress, 2_000)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp apply_result(state, active, result, refreshed) do
    public = %{state.public | busy: false}

    public =
      if active.operation.type == :summary do
        case result do
          {:ok, %{"summary" => summary}} ->
            %{
              public
              | summary: summary,
                summary_config: active.params.config,
                fingerprint: active.params.fingerprint,
                summary_error: nil
            }

          _ ->
            %{public | summary_error: error_message(result, state.label)}
        end
      else
        apply_instances(public, refreshed || result, state)
      end

    public =
      if active.operation.type in [:refresh, :summary],
        do: public,
        else: %{
          public
          | operations:
              Enum.map(public.operations, fn op ->
                if op.id == active.operation.id do
                  %{
                    op
                    | status: if(match?({:ok, _}, result), do: :completed, else: :failed),
                      message:
                        cond do
                          not match?({:ok, _}, result) ->
                            error_message(result, state.label)

                          public.refresh_error ->
                            "Action completed; refresh failed and current state is uncertain."

                          true ->
                            "Completed; actual #{state.label} state refreshed."
                        end
                  }
                else
                  op
                end
              end)
        }

    public = merge_records(public, state.bridge.records())
    %{state | public: public, active: nil}
  end

  defp apply_instances(public, {:ok, %{"instances" => instances}}, state) do
    %{
      public
      | instances: Enum.map(instances, state.public_instance),
        refresh_error: nil,
        last_refresh: DateTime.utc_now()
    }
  end

  defp apply_instances(public, result, state) do
    public =
      case result do
        {:error, %{"instances" => instances}} when instances != [] ->
          %{public | instances: Enum.map(instances, state.public_instance)}

        _ ->
          public
      end

    %{public | refresh_error: error_message(result, state.label)}
  end

  defp merge_records(public, records) do
    instances =
      Enum.reduce(records, public.instances, fn record, instances ->
        same_launch? = fn item -> item["name"] == record["name"] and item["region"] == record["region"] end

        index =
          Enum.find_index(instances, fn item ->
            if record["instance_id"],
              # A row seen while the launch was still pending has no ID yet.
              do:
                item["instance_id"] == record["instance_id"] or
                  (is_nil(item["instance_id"]) and same_launch?.(item)),
              else: same_launch?.(item)
          end)

        if index do
          List.update_at(instances, index, fn
            %{"instance_id" => id} = item when is_binary(id) ->
              Map.merge(record, item) |> Map.put("progress", record["progress"])

            item ->
              # The record now knows more (ID, zone) than the pending row.
              Map.merge(item, record)
          end)
        else
          instances ++ [Map.put(record, "state", "UNKNOWN")]
        end
      end)

    %{public | instances: instances}
  end

  defp error_message({:error, %{"error" => error}}, _label) when is_binary(error), do: error
  defp error_message({:error, error}, _label) when is_binary(error), do: error

  defp error_message(_, label),
    do: "#{label} result was incomplete; outcome is uncertain. Refresh before retrying."

  defp target(%{instance: instance}), do: "#{instance["name"]} (#{instance["instance_id"]})"
  defp target(%{config: config}), do: config
  defp target(_), do: "Recorded instances"

  defp broadcast(state),
    do:
      Phoenix.PubSub.broadcast(
        DxnnAnalyzerWeb.PubSub,
        state.topic,
        {state.event, state.public}
      )
end
