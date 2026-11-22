defmodule DxnnAnalyzerWeb.OracleArtifactsLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.{AnalyzerBridge, OCI.DxnnBridge}

  def mount(_, _, socket),
    do:
      {:ok,
       assign(socket,
         configs: bridge().configs(),
         config: "",
         snapshots: [],
         busy: false,
         download: nil,
         pending: nil
       )}

  def handle_event("config", %{"config" => config}, socket),
    do: {:noreply, assign(socket, config: config, snapshots: [], download: nil)}

  def handle_event("list", _, socket),
    do: execute(socket, "storage:snapshots", %{"config" => socket.assigns.config}, :list)

  def handle_event(action, params, socket) when action in ["load", "archive"] do
    # Only identities returned by the committed-snapshot listing can be selected.
    selected =
      Enum.find(socket.assigns.snapshots, fn item ->
        item["lineage_id"] == params["lineage"] and item["run_id"] == params["run"] and
          item["checkpoint_id"] == params["checkpoint"] and item["kind"] == params["kind"]
      end)

    if selected do
      args = Map.put(params, "config", socket.assigns.config)

      execute(
        socket,
        if(action == "load", do: "storage:download", else: "storage:archive"),
        args,
        {action, selected}
      )
    else
      {:noreply, put_flash(socket, :error, "Refresh and select a committed snapshot.")}
    end
  end

  defp execute(%{assigns: %{busy: true}} = socket, _, _, _), do: {:noreply, socket}

  defp execute(socket, command, params, pending) do
    module = bridge()

    {:noreply,
     socket
     |> assign(busy: true, pending: pending)
     |> start_async(:storage, fn -> module.run(command, params) end)}
  end

  def handle_async(:storage, {:ok, {:ok, %{"result" => result}}}, socket) do
    socket = assign(socket, :busy, false)

    case socket.assigns.pending do
      :list ->
        {:noreply, assign(socket, :snapshots, result)}

      {"archive", _} ->
        {:noreply, assign(socket, :download, result)}

      {"load", selected} ->
        with {:ok, path} <- DxnnBridge.local_download_path(result["relative_path"]),
             identity =
               :crypto.hash(:sha256, result["relative_path"] <> Jason.encode!(selected))
               |> Base.encode16(case: :lower),
             {:ok, _} <-
               AnalyzerBridge.load_context(path, "oci_" <> String.slice(identity, 0, 20)) do
          {:noreply,
           socket
           |> put_flash(:info, "Oracle run loaded into analysis.")
           |> push_navigate(to: ~p"/")}
        else
          {:error, {:already_loaded, _}} ->
            {:noreply, push_navigate(socket, to: ~p"/")}

          _ ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Artifact downloaded, but analysis could not load its database. Check backup compatibility."
             )}
        end
    end
  end

  def handle_async(:storage, _, socket),
    do:
      {:noreply,
       socket
       |> assign(:busy, false)
       |> put_flash(
         :error,
         "Oracle storage operation failed; check bucket permissions and configuration."
       )}

  defp bridge, do: Application.get_env(:dxnn_analyzer_web, :oci_dxnn_bridge, DxnnBridge)

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_header
        title="Oracle Object Storage"
        description="Browse committed checkpoints and results, download verified bundles, and load experiments into analysis."
      >
        <:actions>
          <.link navigate={~p"/oracle-dxnn"} class="btn btn-secondary">DXNN controls</.link>
        </:actions>
      </.page_header>
      <form phx-change="config" class="flex gap-3">
        <select name="config" class="rounded border-gray-300">
          <option value="">Select runtime YAML</option>
          <option :for={config <- @configs} value={config} selected={config == @config}>
            <%= config %>
          </option>
        </select>
        <button type="button" phx-click="list" disabled={@busy} class="btn btn-primary">Refresh snapshots</button>
      </form>
      <p :if={@busy} role="status">Loading Oracle artifacts…</p>
      <a
        :if={@download}
        href={~p"/oracle-artifacts/download/#{@download["token"]}/#{@download["filename"]}"}
        class="btn btn-primary"
      >
        Download verified archive
      </a>
      <div :for={item <- @snapshots} class="border rounded-lg bg-white p-4 space-y-2">
        <p class="font-semibold"><%= item["lineage_id"] %> / <%= item["run_id"] %></p>
        <p class="text-sm"><%= item["kind"] %> · <%= item["checkpoint_id"] %></p>
        <div class="flex gap-2">
          <button
            :for={
              {action, label} <- [{"load", "Load into analysis"}, {"archive", "Prepare download"}]
            }
            phx-click={action}
            phx-value-lineage={item["lineage_id"]}
            phx-value-run={item["run_id"]}
            phx-value-checkpoint={item["checkpoint_id"]}
            phx-value-kind={item["kind"]}
            disabled={@busy}
            class="btn btn-secondary"
          >
            <%= label %>
          </button>
        </div>
        <details :if={item["restorable"]}>
          <summary class="text-sm cursor-pointer">Restore reference</summary>
          <code class="text-xs break-all">
            <%= Jason.encode!(Map.take(item, ["lineage_id", "run_id", "checkpoint_id"])) %>
          </code>
        </details>
      </div>
      <p :if={@snapshots == [] && !@busy} class="text-gray-500">
        Select a configuration and refresh to see committed snapshots.
      </p>
    </div>
    """
  end
end
