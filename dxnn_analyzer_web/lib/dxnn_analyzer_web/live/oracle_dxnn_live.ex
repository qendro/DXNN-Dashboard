defmodule DxnnAnalyzerWeb.OracleDxnnLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.OCI.DxnnBridge

  def mount(_, _, socket) do
    {:ok,
     assign(socket,
       configs: bridge().configs(),
       instances: bridge().instances(),
       form: %{"config" => "", "instance" => "", "run" => "", "lineage" => "", "restore" => ""},
       busy: false,
       result: nil,
       operation: nil
     )}
  end

  def handle_event("change", values, socket),
    do: {:noreply, assign(socket, :form, Map.merge(socket.assigns.form, values))}

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

  def handle_async(:operation, {:ok, {:error, error}}, socket), do: failure(socket, error)

  def handle_async(:operation, {:exit, _}, socket),
    do: failure(socket, "Operation stopped. Inspect worker state before retrying.")

  defp failure(socket, error),
    do:
      {:noreply,
       socket
       |> assign(:busy, false)
       |> put_flash(:error, if(is_binary(error), do: error, else: "Oracle operation failed."))}

  defp bridge, do: Application.get_env(:dxnn_analyzer_web, :oci_dxnn_bridge, DxnnBridge)

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_header
        title="Oracle DXNN"
        description="Install, run, checkpoint, and recover DXNN on Oracle Compute."
      >
        <:actions>
          <.link navigate={~p"/oracle-instances"} class="btn btn-secondary">Instances</.link><.link
            navigate={~p"/oracle-artifacts"}
            class="btn btn-secondary"
          >Object Storage</.link>
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
          Oracle instance<select name="instance" class="block w-full rounded border-gray-300"><option value="">Select recorded instance</option><option
              :for={instance <- @instances}
              selected={@form["instance"] == instance["instance_id"]}
              value={instance["instance_id"]}
            ><%= instance["name"] %> — <%= instance["region"] %></option></select>
        </label>
        <label>
          Run ID<input
            name="run"
            value={@form["run"]}
            class="block w-full rounded border-gray-300"
            placeholder="pilot-001"
          />
        </label>
        <label>
          Lineage ID<input
            name="lineage"
            value={@form["lineage"]}
            class="block w-full rounded border-gray-300"
            placeholder="pilot"
          />
        </label>
        <label class="md:col-span-2">
          Restore checkpoint (optional JSON)<input
            name="restore"
            value={@form["restore"]}
            class="block w-full rounded border-gray-300 font-mono text-sm"
            placeholder="Copy a restore reference from Object Storage"
          />
        </label>
      </form>
      <p class="text-sm text-gray-600">
        Install applies the selected source/configuration bundle. Stop DXNN requests a transactional checkpoint before exit. VM lifecycle controls are on Instances.
      </p>
      <div class="flex flex-wrap gap-2">
        <button
          :for={
            {command, label} <- [
              {"validate", "Validate config"},
              {"install", "Install / update"},
              {"start", "Start DXNN"},
              {"status", "Refresh status"},
              {"checkpoint", "Checkpoint"},
              {"stop", "Stop DXNN"},
              {"retry-upload", "Retry final upload"},
              {"logs", "Read logs"},
              {"reconcile", "Apply completion action"}
            ]
          }
          phx-click="operate"
          phx-value-command={command}
          disabled={@busy}
          data-confirm={
            if command == "install",
              do: "Install the selected source and configuration on this instance?",
              else: nil
          }
          class="btn btn-secondary"
        >
          <%= label %>
        </button>
      </div>
      <p :if={@busy} role="status">Running <%= @operation %>…</p>
      <pre
        :if={@result}
        id="oracle-dxnn-result"
        class="bg-gray-900 text-gray-100 p-4 rounded overflow-auto max-h-[36rem] text-xs"
      ><%= Jason.encode!(@result, pretty: true) %></pre>
    </div>
    """
  end
end
