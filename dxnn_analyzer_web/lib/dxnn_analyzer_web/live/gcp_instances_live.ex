defmodule DxnnAnalyzerWeb.GCPInstancesLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.GCP.GCPBridge
  alias DxnnAnalyzerWeb.OCI.OCIServer

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(DxnnAnalyzerWeb.PubSub, "gcp_instances")
      OCIServer.submit(:refresh, %{}, server())
    end

    {:ok,
     assign(socket,
       gcp: OCIServer.state(server()),
       selected_config: "",
       termination: nil,
       expanded: MapSet.new()
     )}
  end

  defp server, do: Application.get_env(:dxnn_analyzer_web, :gcp_server, GCPBridge.server())

  @impl true
  def handle_info({:gcp_state, state}, socket), do: {:noreply, assign(socket, :gcp, state)}

  @impl true
  def handle_event("refresh", _, socket), do: submit(socket, :refresh, %{})

  def handle_event("toggle", %{"key" => key}, socket) do
    expanded = socket.assigns.expanded

    expanded =
      if MapSet.member?(expanded, key),
        do: MapSet.delete(expanded, key),
        else: MapSet.put(expanded, key)

    {:noreply, assign(socket, :expanded, expanded)}
  end

  def handle_event("select-config", %{"config" => config}, socket),
    do: {:noreply, assign(socket, :selected_config, config)}

  def handle_event("summary", %{"config" => config}, socket),
    do: submit(assign(socket, :selected_config, config), :summary, %{config: config})

  def handle_event("launch", _, socket) do
    submit(socket, :launch, %{
      config: socket.assigns.selected_config,
      fingerprint: socket.assigns.gcp.fingerprint
    })
  end

  def handle_event("action", %{"action" => action, "id" => id, "region" => region}, socket)
      when action in ["start", "stop", "reboot"] do
    submit(socket, String.to_existing_atom(action), %{id: id, region: region})
  end

  def handle_event("confirm-termination", %{"id" => id, "region" => region}, socket) do
    instance =
      Enum.find(
        socket.assigns.gcp.instances,
        &(&1["instance_id"] == id and &1["region"] == region)
      )

    {:noreply, assign(socket, :termination, instance)}
  end

  def handle_event("cancel-termination", _, socket),
    do: {:noreply, assign(socket, :termination, nil)}

  def handle_event(
        "terminate",
        %{"boot_volume" => choice},
        %{assigns: %{termination: i}} = socket
      )
      when not is_nil(i) do
    submit(assign(socket, :termination, nil), :terminate, %{
      id: i["instance_id"],
      region: i["region"],
      boot_volume: choice
    })
  end

  def handle_event("terminate", _, socket),
    do: {:noreply, put_flash(socket, :error, "Choose a boot-disk option first.")}

  defp submit(socket, type, params) do
    case OCIServer.submit(type, params, server()) do
      :ok -> {:noreply, assign(clear_flash(socket), :gcp, OCIServer.state(server()))}
      {:error, message} -> {:noreply, put_flash(socket, :error, message)}
    end
  end

  defp display(nil), do: "—"
  defp display(value), do: value
  defp public_ip(instance), do: Enum.find_value(instance["addresses"] || [], & &1["public_ipv4"])
  defp row_key(i), do: i["instance_id"] || "#{i["project"]}:#{i["region"]}:#{i["name"]}"

  defp state_label(i), do: if(i["instance_id"], do: display(i["state"]), else: "No VM recorded")

  defp progress_label(%{"progress" => "ssh-verified"}), do: "SSH verified"
  defp progress_label(%{"progress" => "ssh-verification-failed"}), do: "SSH verification failed"

  defp progress_label(%{"progress" => "capacity-exhausted"}),
    do: "Last launch: no capacity in any zone"

  defp progress_label(%{"progress" => "launch-outcome-unresolved"}),
    do: "Launch outcome uncertain"

  defp progress_label(%{"progress" => progress}) when is_binary(progress),
    do: progress |> String.replace("-", " ") |> String.capitalize()

  defp progress_label(_), do: "No saved progress"

  defp state_class(%{"state" => "RUNNING"}), do: "bg-green-50 text-green-800 ring-green-200"
  defp state_class(%{"state" => "STOPPED"}), do: "bg-amber-50 text-amber-800 ring-amber-200"
  defp state_class(_), do: "bg-gray-50 text-gray-700 ring-gray-200"

  defp spot?(i), do: i["provisioning"] == "SPOT"

  defp unavailable(gcp, i, :terminate),
    do:
      gcp.busy or gcp.refresh_error != nil or !is_binary(i["state"]) or
        i["state"] in ["UNKNOWN", "TERMINATING", "TERMINATED"]

  defp unavailable(gcp, i, states),
    do: gcp.busy or gcp.refresh_error != nil or i["state"] not in states

  @impl true
  def render(assigns) do
    ~H"""
    <div class="page-container space-y-6">
      <.page_header title="GCP Instances" description="Launch and manage Compute Engine VMs.">
        <:actions>
          <.link navigate={~p"/gcp-dxnn"} class="btn btn-secondary">DXNN controls</.link>
          <button id="gcp-refresh" phx-click="refresh" disabled={@gcp.busy} class="btn btn-secondary">
            Refresh
          </button>
        </:actions>
      </.page_header>
      <p :if={@gcp.busy} role="status" class="bg-blue-50 p-3 rounded">GCP operation in progress…</p>
      <p :if={@gcp.refresh_error} role="alert" class="bg-red-50 text-red-800 p-3 rounded">
        <%= @gcp.refresh_error %>
      </p>
      <p :if={@gcp.last_refresh} class="text-xs text-gray-500">
        Last successful refresh: <%= Calendar.strftime(@gcp.last_refresh, "%Y-%m-%d %H:%M:%S UTC") %>
      </p>

      <section class="panel p-4 space-y-3">
        <h2 class="text-lg font-semibold">Launch from existing YAML</h2>
        <p :if={@gcp.configs == []} class="text-sm text-gray-600">
          No GCP configurations found. Copy AWS-Deployment/config/gcp-dxnn.example.yml to
          config/gcp-local-dxnn.yml and set your project ID (example files are not listed).
        </p>
        <form
          id="gcp-config-form"
          phx-change="select-config"
          phx-submit="summary"
          class="flex flex-wrap gap-3"
        >
          <select name="config" required disabled={@gcp.busy} class="border rounded px-3 py-2">
            <option value="">Select GCP configuration</option>
            <option :for={config <- @gcp.configs} value={config} selected={config == @selected_config}>
              <%= config %>
            </option>
          </select>
          <button disabled={@gcp.busy} class="btn btn-secondary disabled:opacity-50">
            Review summary
          </button>
        </form>
        <p :if={@gcp.summary_error} role="alert" class="text-red-800"><%= @gcp.summary_error %></p>
        <div
          :if={@gcp.summary && @gcp.summary_config == @selected_config}
          id="gcp-launch-summary"
          class="bg-gray-50 p-4 rounded space-y-2"
        >
          <p class="font-semibold">
            <%= @gcp.summary["name"] %> · <%= @gcp.summary["mode"] %> · <%= @gcp.summary[
              "provisioning"
            ] %>
          </p>
          <p :if={@gcp.summary["mode"] == "paid"} class="text-red-800">
            Paid mode authorizes billable resources.
          </p>
          <p :if={@gcp.summary["provisioning"] == "spot"} class="text-amber-800">
            Spot VM: Google can preempt it at any time; on preemption it will <%= @gcp.summary[
              "spot_termination_action"
            ] %>.
          </p>
          <dl class="grid grid-cols-2 gap-2 text-sm">
            <dt>Project</dt>
            <dd class="break-all"><%= @gcp.summary["project"] %></dd>
            <dt>Region / preferred zone</dt>
            <dd>
              <%= @gcp.summary["region"] %> / <%= @gcp.summary["zone"] ||
                "Automatic with zone fallback" %>
            </dd>
            <dt>Machine type</dt>
            <dd><%= @gcp.summary["machine_type"] %></dd>
            <dt>Image</dt>
            <dd class="break-all">
              <%= get_in(@gcp.summary, ["image", "project"]) %>/<%= get_in(@gcp.summary, [
                "image",
                "family"
              ]) ||
                get_in(@gcp.summary, ["image", "name"]) %>
            </dd>
            <dt>Boot disk</dt>
            <dd>
              <%= get_in(@gcp.summary, ["boot_disk", "size_gb"]) %> GB <%= get_in(@gcp.summary, [
                "boot_disk",
                "type"
              ]) %>
            </dd>
            <dt>Network</dt>
            <dd class="break-all"><%= Jason.encode!(@gcp.summary["network"]) %></dd>
            <dt>SSH user / key</dt>
            <dd class="break-all">
              <%= get_in(@gcp.summary, ["ssh", "username"]) %> / <%= get_in(@gcp.summary, [
                "ssh",
                "private_key"
              ]) || "Generated in output/gcp/keys" %>
            </dd>
          </dl>
          <p class="text-sm text-gray-600">
            A saved launch is resumed using the same configuration. If SSH verification failed, its existing VM is retained.
          </p>
          <button
            id="gcp-launch"
            phx-click="launch"
            disabled={@gcp.busy}
            class="btn btn-primary disabled:opacity-50"
          >
            Launch / resume <%= @gcp.summary["name"] %>
          </button>
        </div>
      </section>

      <section class="panel overflow-x-auto">
        <table id="gcp-instances" class="min-w-full text-sm">
          <thead class="bg-gray-50 text-left">
            <tr>
              <th scope="col" class="px-4 py-3">Instance</th>
              <th scope="col" class="px-4 py-3">Current status</th>
              <th scope="col" class="px-4 py-3">External IPv4</th>
              <th scope="col" class="px-4 py-3">Actions</th>
            </tr>
          </thead>
          <tbody>
            <%= for {instance, index} <- Enum.with_index(@gcp.instances) do %>
              <tr class="border-t align-top">
                <td class="px-4 py-4">
                  <p class="font-semibold text-gray-900">
                    <%= instance["name"] %>
                    <span :if={spot?(instance)} class="ml-1 text-xs font-medium text-amber-700">
                      Spot
                    </span>
                  </p>
                  <p class="text-xs text-gray-500 mt-1">
                    <%= instance["project"] %> · <%= instance["zone"] || instance["region"] %>
                  </p>
                  <button
                    id={"gcp-toggle-#{index}"}
                    type="button"
                    phx-click="toggle"
                    phx-value-key={row_key(instance)}
                    aria-controls={"gcp-details-#{index}"}
                    aria-expanded={to_string(MapSet.member?(@expanded, row_key(instance)))}
                    class="mt-2 text-xs font-medium text-blue-700"
                  >
                    Details & SSH ▾
                  </button>
                </td>
                <td class="px-4 py-4">
                  <span class={[
                    "inline-flex px-2 py-1 rounded-full text-xs font-semibold ring-1 ring-inset",
                    state_class(instance)
                  ]}>
                    <%= state_label(instance) %>
                  </span>
                  <p class="text-xs text-gray-600 mt-2"><%= progress_label(instance) %></p>
                </td>
                <td class="px-4 py-4 font-mono text-xs"><%= display(public_ip(instance)) %></td>
                <td class="px-4 py-4">
                  <div class="flex flex-wrap gap-2">
                    <button
                      :for={
                        {action, label, states} <- [
                          {"start", "Start", ["STOPPED"]},
                          {"stop", "Stop", ["RUNNING"]},
                          {"reboot", "Reset", ["RUNNING"]}
                        ]
                      }
                      phx-click="action"
                      phx-value-action={action}
                      phx-value-id={instance["instance_id"]}
                      phx-value-region={instance["region"]}
                      disabled={unavailable(@gcp, instance, states)}
                      title={if action == "reboot", do: "Hard reset (power cycle)"}
                      class="btn btn-secondary btn-sm"
                    >
                      <%= label %>
                    </button>
                    <button
                      phx-click="confirm-termination"
                      phx-value-id={instance["instance_id"]}
                      phx-value-region={instance["region"]}
                      disabled={unavailable(@gcp, instance, :terminate)}
                      class="btn btn-danger btn-sm"
                    >
                      Delete
                    </button>
                  </div>
                </td>
              </tr>
              <tr id={"gcp-details-#{index}"} hidden={!MapSet.member?(@expanded, row_key(instance))}>
                <td colspan="4" class="px-4 pb-4">
                  <div class="bg-gray-50 border border-gray-100 rounded-lg p-4 space-y-4">
                    <dl
                      id={"gcp-time-#{index}"}
                      phx-hook="InstanceTime"
                      data-launched-at={instance["time_created"] || ""}
                      class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 text-sm"
                    >
                      <div>
                        <dt class="text-xs text-gray-500">Instance ID</dt>
                        <dd class="font-mono text-xs break-all mt-1">
                          <%= display(instance["instance_id"]) %>
                        </dd>
                      </div>
                      <div>
                        <dt class="text-xs text-gray-500">Launched (Central time)</dt>
                        <dd class="mt-1">
                          <time data-launch-time datetime={instance["time_created"]}>—</time>
                        </dd>
                      </div>
                      <div>
                        <dt class="text-xs text-gray-500">Time since launch</dt>
                        <dd data-elapsed-time class="mt-1">—</dd>
                      </div>
                      <div>
                        <dt class="text-xs text-gray-500">Machine type</dt>
                        <dd class="mt-1"><%= display(instance["machine_type"]) %></dd>
                      </div>
                      <div>
                        <dt class="text-xs text-gray-500">vCPUs / memory</dt>
                        <dd class="mt-1">
                          <%= display(instance["vcpus"]) %> vCPUs / <%= display(
                            instance["memory_gbs"]
                          ) %> GB
                        </dd>
                      </div>
                      <div>
                        <dt class="text-xs text-gray-500">Compute Engine status</dt>
                        <dd class="mt-1"><%= display(instance["gce_status"]) %></dd>
                      </div>
                    </dl>
                    <div
                      :if={
                        !@gcp.busy && is_nil(@gcp.refresh_error) && GCPBridge.ssh_command(instance)
                      }
                      id={"gcp-ssh-#{index}"}
                      phx-hook="CopySSH"
                      class="flex flex-wrap sm:flex-nowrap items-center gap-2"
                    >
                      <input
                        aria-label="SSH command"
                        value={GCPBridge.ssh_command(instance)}
                        readonly
                        class="border border-gray-200 rounded px-3 py-2 text-xs font-mono w-full min-w-0 bg-white"
                      />
                      <button type="button" class="text-blue-700 text-xs whitespace-nowrap px-2 py-2">
                        Copy SSH command
                      </button>
                    </div>
                  </div>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
        <p :if={@gcp.instances == []} class="p-4 text-gray-600">
          No recorded GCP instances. Refresh or launch an existing configuration.
        </p>
      </section>

      <section
        :if={@termination}
        id="gcp-termination"
        class="border border-red-300 rounded-lg bg-red-50 p-4 space-y-3"
      >
        <h2 class="font-semibold">Delete <%= @termination["name"] %></h2>
        <p class="break-all">
          <%= @termination["instance_id"] %> · <%= @termination["project"] %> · <%= @termination[
            "zone"
          ] %>
        </p>
        <form id="gcp-terminate-form" phx-submit="terminate" class="space-y-3">
          <label class="block">
            <input type="radio" name="boot_volume" value="preserve" required />
            Keep boot disk — its storage billing continues.
          </label>
          <label class="block">
            <input type="radio" name="boot_volume" value="delete" required />
            Delete boot disk — permanently delete its data.
          </label>
          <p class="text-sm">The VM will be deleted. Network resources are preserved.</p>
          <button disabled={@gcp.busy} class="btn btn-danger disabled:opacity-50">
            Delete this VM
          </button>
          <button type="button" phx-click="cancel-termination" class="btn btn-secondary">
            Cancel
          </button>
        </form>
      </section>

      <details
        :if={@gcp.operations != []}
        id="gcp-operation-history"
        open={Enum.any?(@gcp.operations, &(&1.status in [:running, :failed]))}
        class="panel p-4"
      >
        <summary class="cursor-pointer font-semibold">
          Operation history (<%= length(@gcp.operations) %>)
        </summary>
        <div class="mt-3 space-y-3">
          <div :for={operation <- @gcp.operations} class="border rounded p-3" role="status">
            <p class="font-semibold">
              <%= String.capitalize(to_string(operation.type)) %> · <%= operation.target %> · <%= operation.status %>
            </p>
            <p class={
              if operation.status == :failed, do: "text-red-800 mt-1", else: "text-gray-600 mt-1"
            }>
              <%= operation.message %>
            </p>
          </div>
        </div>
      </details>
    </div>
    """
  end
end
