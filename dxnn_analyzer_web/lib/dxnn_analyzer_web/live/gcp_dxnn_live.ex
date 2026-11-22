defmodule DxnnAnalyzerWeb.GCPDxnnLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.GCP.DxnnBridge

  @fields ~w(config instance run lineage restore env from_run force_build)

  def mount(_, _, socket) do
    {:ok,
     assign(socket,
       configs: bridge().configs(),
       instances: bridge().instances(),
       form: Map.new(@fields, &{&1, ""}),
       busy: false,
       result: nil,
       operation: nil
     )}
  end

  def handle_event("change", values, socket) do
    # An unchecked checkbox sends nothing; keep the form explicit.
    values = Map.put_new(Map.take(values, @fields), "force_build", "false")
    {:noreply, assign(socket, :form, Map.merge(socket.assigns.form, values))}
  end

  def handle_event("operate", %{"command" => command}, socket) do
    if socket.assigns.busy do
      {:noreply, socket}
    else
      params = socket.assigns.form
      module = bridge()

      {:noreply,
       socket
       |> assign(busy: true, operation: command)
       |> start_async(:operation, fn -> module.run(command, params) end)}
    end
  end

  def handle_async(:operation, {:ok, {:ok, result}}, socket),
    do: {:noreply, assign(socket, busy: false, result: result["result"])}

  def handle_async(:operation, {:ok, {:error, error}}, socket),
    do: failure(socket, DxnnBridge.error_message(error))

  def handle_async(:operation, {:exit, _}, socket),
    do: failure(socket, "Operation stopped. Refresh status before retrying.")

  defp failure(socket, message),
    do: {:noreply, socket |> assign(:busy, false) |> put_flash(:error, message)}

  defp bridge, do: Application.get_env(:dxnn_analyzer_web, :gcp_dxnn_bridge, DxnnBridge)

  # status returns {vm, worker, app}; show the run's progress fields when the worker reported them.
  defp progress(%{"worker" => %{} = worker}) do
    fields =
      ~w(state run_id lineage_id run_index generation summary_time gen_seconds vm_mb best_score)
      |> Enum.flat_map(fn key ->
        case worker[key] || get_in(worker, ["progress", key]) do
          nil -> []
          value -> [{key, value}]
        end
      end)

    env = worker["env"]
    if env not in [nil, %{}], do: fields ++ [{"env", Jason.encode!(env)}], else: fields
  end

  defp progress(_), do: []

  def render(assigns) do
    assigns = assign(assigns, :progress, progress(assigns.result))

    ~H"""
    <div class="space-y-6">
      <.page_header
        title="GCP DXNN"
        description="Install, run, checkpoint, resume, and recover DXNN on Compute Engine with GCS checkpoints."
      >
        <:actions>
          <.link navigate={~p"/gcp-instances"} class="btn btn-secondary">Instances</.link><.link
            navigate={~p"/gcp-storage"}
            class="btn btn-secondary"
          >GCS Storage</.link>
        </:actions>
      </.page_header>
      <form
        phx-change="change"
        class="grid grid-cols-1 md:grid-cols-2 gap-4 bg-white rounded-lg border p-5"
      >
        <label>
          Runtime configuration<select name="config" class="block w-full rounded border-gray-300"><option value="">Select runtime YAML</option><option
              :for={config <- @configs}
              selected={@form["config"] == config}
              value={config}
            ><%= config %></option></select>
        </label>
        <label>
          GCP instance<select name="instance" class="block w-full rounded border-gray-300"><option value="">Select recorded instance</option><option
              :for={instance <- @instances}
              selected={@form["instance"] == instance["instance_id"]}
              value={instance["instance_id"]}
            ><%= instance["name"] %> — <%= instance["zone"] || instance["region"] %></option></select>
        </label>
        <label>
          Run ID<input
            name="run"
            value={@form["run"]}
            class="block w-full rounded border-gray-300"
            placeholder="pilot-001 (new run ID for resume)"
          />
        </label>
        <label>
          Lineage ID<input
            name="lineage"
            value={@form["lineage"]}
            class="block w-full rounded border-gray-300"
            placeholder="pilot (resume: defaults to last run's)"
          />
        </label>
        <label>
          Resume from run (optional)<input
            name="from_run"
            value={@form["from_run"]}
            class="block w-full rounded border-gray-300"
            placeholder="Default: the VM's last run"
          />
        </label>
        <label class="flex items-center gap-2 self-end">
          <input type="hidden" name="force_build" value="false" /><input
            type="checkbox"
            name="force_build"
            value="true"
            checked={@form["force_build"] == "true"}
          /> Resume on a different build (--force-build)
        </label>
        <label class="md:col-span-2">
          Environment for DXNN (one DXNN_KEY=value per line; start only, resume keeps the run's own)<textarea
            name="env"
            rows="3"
            class="block w-full rounded border-gray-300 font-mono text-sm"
            placeholder="DXNN_TEST_ARM=ff_vol&#10;DXNN_EPISODE_SEED=1&#10;DXNN_EVOLUTION_SEED=1"
          ><%= @form["env"] %></textarea>
        </label>
        <label class="md:col-span-2">
          Restore checkpoint (optional JSON, start only)<input
            name="restore"
            value={@form["restore"]}
            class="block w-full rounded border-gray-300 font-mono text-sm"
            placeholder="Copy a restore reference from GCS Storage"
          />
        </label>
      </form>
      <p class="text-sm text-gray-600">
        Install uploads the configured source and data files and builds OTP on the VM (several minutes). Stop DXNN checkpoints at the next generation boundary, then exits. Resume continues the newest restorable checkpoint with the run's recorded environment. VM lifecycle controls are on Instances.
      </p>
      <div class="flex flex-wrap gap-2">
        <button
          :for={
            {command, label} <- [
              {"validate", "Validate config"},
              {"install", "Install / update"},
              {"start", "Start DXNN"},
              {"resume", "Resume"},
              {"status", "Refresh status"},
              {"checkpoint", "Checkpoint"},
              {"stop", "Stop DXNN"},
              {"retry-upload", "Retry final upload"},
              {"logs", "Read logs"}
            ]
          }
          phx-click="operate"
          phx-value-command={command}
          disabled={@busy}
          data-confirm={
            case command do
              "install" -> "Install the selected source and configuration on this instance?"
              "resume" -> "Start a new run from the newest checkpoint of the previous run?"
              _ -> nil
            end
          }
          class="btn btn-secondary"
        >
          <%= label %>
        </button>
      </div>
      <p :if={@busy} role="status">Running <%= @operation %>…</p>
      <dl
        :if={@progress != []}
        id="gcp-dxnn-progress"
        class="grid grid-cols-2 md:grid-cols-4 gap-3 bg-white rounded-lg border p-4 text-sm"
      >
        <div :for={{key, value} <- @progress}>
          <dt class="text-gray-500"><%= key %></dt>
          <dd class="font-mono break-all"><%= value %></dd>
        </div>
      </dl>
      <div :if={is_map(@result) and is_binary(@result["generations"])} class="space-y-2">
        <h3 class="font-semibold">Generation summary</h3>
        <pre class="bg-gray-900 text-gray-100 p-4 rounded overflow-auto text-xs"><%= @result["generations"] %></pre>
        <h3 class="font-semibold">Run log</h3>
        <pre class="bg-gray-900 text-gray-100 p-4 rounded overflow-auto max-h-[36rem] text-xs"><%= @result["run_log"] %></pre>
      </div>
      <pre
        :if={@result && !(is_map(@result) and is_binary(@result["generations"]))}
        id="gcp-dxnn-result"
        class="bg-gray-900 text-gray-100 p-4 rounded overflow-auto max-h-[36rem] text-xs"
      ><%= Jason.encode!(@result, pretty: true) %></pre>
    </div>
    """
  end
end
