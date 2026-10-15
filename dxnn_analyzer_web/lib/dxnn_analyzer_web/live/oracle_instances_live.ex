defmodule DxnnAnalyzerWeb.OracleInstancesLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.OCI.{OCIBridge, OCIServer}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(DxnnAnalyzerWeb.PubSub, "oci_instances")
      OCIServer.submit(:refresh)
    end

    {:ok,
     assign(socket,
       oci: OCIServer.state(),
       selected_config: "",
       termination: nil,
       expanded_stats: MapSet.new()
     )}
  end

  @impl true
  def handle_info({:oci_state, state}, socket), do: {:noreply, assign(socket, :oci, state)}

  @impl true
  def handle_event("refresh", _, socket), do: submit(socket, :refresh, %{})

  def handle_event("toggle-stats", %{"key" => key}, socket) do
    expanded = socket.assigns.expanded_stats

    expanded =
      if MapSet.member?(expanded, key),
        do: MapSet.delete(expanded, key),
        else: MapSet.put(expanded, key)

    {:noreply, assign(socket, :expanded_stats, expanded)}
  end

  def handle_event("select-config", %{"config" => config}, socket),
    do: {:noreply, assign(socket, :selected_config, config)}

  def handle_event("summary", %{"config" => config}, socket) do
    submit(assign(socket, :selected_config, config), :summary, %{config: config})
  end

  def handle_event("launch", _, socket) do
    submit(socket, :launch, %{
      config: socket.assigns.selected_config,
      fingerprint: socket.assigns.oci.fingerprint
    })
  end

  def handle_event("action", %{"action" => action, "id" => id, "region" => region}, socket)
      when action in ["start", "stop", "reboot"] do
    type = %{"start" => :start, "stop" => :stop, "reboot" => :reboot}[action]
    submit(socket, type, %{id: id, region: region})
  end

  def handle_event("confirm-termination", %{"id" => id, "region" => region}, socket) do
    instance =
      Enum.find(
        socket.assigns.oci.instances,
        &(&1["instance_id"] == id and &1["region"] == region)
      )

    {:noreply, assign(socket, :termination, instance)}
  end

  def handle_event("cancel-termination", _, socket),
    do: {:noreply, assign(socket, :termination, nil)}

  def handle_event(
        "terminate",
        %{"boot_volume" => choice},
        %{assigns: %{termination: instance}} = socket
      )
      when not is_nil(instance) do
    submit(assign(socket, :termination, nil), :terminate, %{
      id: instance["instance_id"],
      region: instance["region"],
      boot_volume: choice
    })
  end

  def handle_event("terminate", _, socket),
    do: {:noreply, put_flash(socket, :error, "Choose a boot-volume option first.")}

  defp submit(socket, type, params) do
    case OCIServer.submit(type, params) do
      :ok -> {:noreply, assign(clear_flash(socket), :oci, OCIServer.state())}
      {:error, message} -> {:noreply, put_flash(socket, :error, message)}
    end
  end

  defp display(nil), do: "—"

  defp display(value) when is_float(value),
    do: if(value == trunc(value), do: trunc(value), else: value)

  defp display(value), do: value
  defp public_ip(instance), do: Enum.find_value(instance["addresses"] || [], & &1["public_ipv4"])

  defp row_key(instance),
    do: instance["instance_id"] || "#{instance["region"]}:#{instance["name"]}"

  defp state_label(instance),
    do: if(instance["instance_id"], do: display(instance["state"]), else: "No VM recorded")

  defp progress_label(%{"progress" => "ssh-verified"}), do: "SSH verified"
  defp progress_label(%{"progress" => "ssh-verification-failed"}), do: "SSH verification failed"

  defp progress_label(%{"progress" => "capacity-exhausted"}),
    do: "Last launch: no available capacity"

  defp progress_label(%{"progress" => "launch-outcome-unresolved"}),
    do: "Launch outcome uncertain"

  defp progress_label(%{"progress" => progress}) when is_binary(progress),
    do: progress |> String.replace("-", " ") |> String.capitalize()

  defp progress_label(_), do: "No saved progress"

  defp state_class(instance) do
    case instance["state"] do
      "RUNNING" -> "bg-green-50 text-green-800 ring-green-200"
      "STOPPED" -> "bg-amber-50 text-amber-800 ring-amber-200"
      _ -> "bg-gray-50 text-gray-700 ring-gray-200"
    end
  end

  # Preserve the failed attempt, and distinguish its error from current health.
  # Only the same explicit OCID and a later saved verification count as recovery.
  defp recovered?(operation, instances) do
    operation.type == :launch and operation.status == :failed and
      String.contains?(operation.message, "verification failed") and
      Enum.any?(instances, fn instance ->
        id = instance["instance_id"]

        is_binary(id) and id != "" and String.contains?(operation.message, id) and
          instance["state"] == "RUNNING" and instance["progress"] == "ssh-verified"
      end)
  end

  defp needs_attention?(operation, instances),
    do:
      operation.status == :running or
        (operation.status == :failed and not recovered?(operation, instances))

  defp unavailable(oci, instance, :terminate),
    do:
      oci.busy or oci.refresh_error != nil or !is_binary(instance["state"]) or
        instance["state"] in ["UNKNOWN", "TERMINATING", "TERMINATED"]

  defp unavailable(oci, instance, states),
    do: oci.busy or oci.refresh_error != nil or instance["state"] not in states

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8 space-y-6">
      <div class="flex justify-between items-center">
        <h1 class="text-3xl font-bold text-gray-900">Oracle Instances</h1>
        <button
          id="oci-refresh"
          phx-click="refresh"
          disabled={@oci.busy}
          class="bg-blue-600 text-white px-4 py-2 rounded disabled:opacity-50"
        >
          Refresh
        </button>
      </div>
      <p class="text-sm text-gray-600">
        OCI instances recorded by AWS-Deployment. Operations continue while you reload or leave this page.
      </p>
      <p :if={@oci.busy} role="status" class="bg-blue-50 p-3 rounded">OCI operation in progress…</p>
      <p :if={@oci.refresh_error} role="alert" class="bg-red-50 text-red-800 p-3 rounded">
        <%= @oci.refresh_error %>
      </p>
      <p :if={@oci.last_refresh} class="text-xs text-gray-500">
        Last successful refresh: <%= Calendar.strftime(@oci.last_refresh, "%Y-%m-%d %H:%M:%S UTC") %>
      </p>

      <section class="bg-white border rounded-lg p-4 space-y-3">
        <h2 class="text-lg font-semibold">Launch from existing YAML</h2>
        <form id="oci-config-form" phx-change="select-config" phx-submit="summary" class="flex gap-3">
          <select name="config" required disabled={@oci.busy} class="border rounded px-3 py-2">
            <option value="">Select OCI configuration</option>
            <option :for={config <- @oci.configs} value={config} selected={config == @selected_config}>
              <%= config %>
            </option>
          </select>
          <button
            disabled={@oci.busy}
            class="bg-gray-800 text-white px-4 py-2 rounded disabled:opacity-50"
          >
            Review summary
          </button>
        </form>
        <p :if={@oci.summary_error} role="alert" class="text-red-800"><%= @oci.summary_error %></p>
        <div
          :if={@oci.summary && @oci.summary_config == @selected_config}
          id="oci-launch-summary"
          class="bg-gray-50 p-4 rounded space-y-2"
        >
          <p class="font-semibold"><%= @oci.summary["name"] %> · <%= @oci.summary["mode"] %></p>
          <p :if={@oci.summary["mode"] == "paid"} class="text-red-800">
            Paid mode authorizes billable resources.
          </p>
          <p :if={@oci.summary["mode"] == "free-only"}>
            Free-only eligibility is checked by the deployment CLI at launch.
          </p>
          <dl class="grid grid-cols-2 gap-2 text-sm">
            <dt>Region / preferred AD</dt>
            <dd>
              <%= @oci.summary["region"] %> / <%= @oci.summary["availability_domain"] ||
                "Automatic with capacity fallback" %>
            </dd>
            <dt>Shape / OCPUs / RAM</dt>
            <dd>
              <%= @oci.summary["shape"] %> / <%= @oci.summary["ocpus"] %> / <%= @oci.summary[
                "memory_gbs"
              ] %> GB
            </dd>
            <dt>Image</dt>
            <dd class="break-all">
              <%= get_in(@oci.summary, ["image", "id"]) ||
                get_in(@oci.summary, ["image", "display_name"]) %>
            </dd>
            <dt>Compartment</dt>
            <dd class="break-all"><%= @oci.summary["compartment_id"] %></dd>
            <dt>Network</dt>
            <dd class="break-all"><%= Jason.encode!(@oci.summary["network"]) %></dd>
            <dt>SSH user / host key path</dt>
            <dd class="break-all">
              <%= get_in(@oci.summary, ["ssh", "username"]) %> / <%= get_in(@oci.summary, [
                "ssh",
                "private_key"
              ]) || "Generated in output/oci/keys" %>
            </dd>
          </dl>
          <p class="text-sm text-gray-600">
            A saved launch is resumed using the same configuration. If SSH verification failed, its existing instance is retained.
          </p>
          <button
            id="oci-launch"
            phx-click="launch"
            disabled={@oci.busy}
            class="bg-purple-600 text-white px-4 py-2 rounded disabled:opacity-50"
          >
            Launch / resume <%= @oci.summary["name"] %>
          </button>
        </div>
      </section>

      <section class="bg-white border rounded-lg overflow-x-auto">
        <table id="oci-instances" class="min-w-full text-sm">
          <thead class="bg-gray-50 text-left">
            <tr>
              <th scope="col" class="px-4 py-3">Instance</th>
              <th scope="col" class="px-4 py-3">Current status</th>
              <th scope="col" class="px-4 py-3">Public IPv4</th>
              <th scope="col" class="px-4 py-3">Actions</th>
            </tr>
          </thead>
          <tbody>
            <%= for {instance, index} <- Enum.with_index(@oci.instances) do %>
              <tr class="border-t align-top">
                <td class="px-4 py-4">
                  <p class="font-semibold text-gray-900"><%= instance["name"] %></p>
                  <p class="text-xs text-gray-500 mt-1"><%= instance["region"] %></p>
                  <button
                    id={"oci-toggle-stats-#{index}"}
                    type="button"
                    phx-click="toggle-stats"
                    phx-value-key={row_key(instance)}
                    aria-controls={"oci-stats-#{index}"}
                    aria-expanded={
                      if MapSet.member?(@expanded_stats, row_key(instance)), do: "true", else: "false"
                    }
                    class="mt-2 text-xs font-medium text-blue-700 flex items-center gap-1"
                  >
                    Stats & SSH
                    <span
                      aria-hidden="true"
                      class={
                        if MapSet.member?(@expanded_stats, row_key(instance)),
                          do: "w-3 h-3 rotate-180",
                          else: "w-3 h-3"
                      }
                    >
                      ▾
                    </span>
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
                        {action, states} <- [
                          {"start", ["STOPPED"]},
                          {"stop", ["RUNNING"]},
                          {"reboot", ["RUNNING"]}
                        ]
                      }
                      phx-click="action"
                      phx-value-action={action}
                      phx-value-id={instance["instance_id"]}
                      phx-value-region={instance["region"]}
                      disabled={unavailable(@oci, instance, states)}
                      class="border border-gray-200 rounded px-2 py-1 text-blue-700 hover:bg-blue-50 disabled:opacity-40 disabled:cursor-not-allowed"
                    >
                      <%= String.capitalize(action) %>
                    </button>
                    <button
                      phx-click="confirm-termination"
                      phx-value-id={instance["instance_id"]}
                      phx-value-region={instance["region"]}
                      disabled={unavailable(@oci, instance, :terminate)}
                      class="border border-red-200 rounded px-2 py-1 text-red-700 hover:bg-red-50 disabled:opacity-40 disabled:cursor-not-allowed"
                    >
                      Terminate
                    </button>
                  </div>
                </td>
              </tr>
              <tr
                id={"oci-stats-#{index}"}
                hidden={!MapSet.member?(@expanded_stats, row_key(instance))}
              >
                <td colspan="4" class="px-4 pb-4">
                  <div class="bg-gray-50 border border-gray-100 rounded-lg p-4 space-y-4">
                    <dl
                      id={"oci-time-#{index}"}
                      phx-hook="InstanceTime"
                      data-launched-at={instance["time_created"] || ""}
                      class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 text-sm"
                    >
                      <div class="sm:col-span-2 lg:col-span-3">
                        <dt class="text-xs text-gray-500">Instance OCID</dt>
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
                        <p class="text-xs text-gray-500 mt-1">
                          Includes stopped time; not continuous uptime.
                        </p>
                      </div>
                      <div>
                        <dt class="text-xs text-gray-500">Availability domain</dt>
                        <dd class="mt-1"><%= display(instance["ad"]) %></dd>
                      </div>
                      <div>
                        <dt class="text-xs text-gray-500">Shape</dt>
                        <dd class="mt-1"><%= display(instance["shape"]) %></dd>
                      </div>
                      <div>
                        <dt class="text-xs text-gray-500">Compute / memory</dt>
                        <dd class="mt-1">
                          <%= display(instance["ocpus"]) %> OCPUs / <%= display(
                            instance["memory_gbs"]
                          ) %> GB
                        </dd>
                      </div>
                    </dl>
                    <div
                      :if={
                        !@oci.busy && is_nil(@oci.refresh_error) && OCIBridge.ssh_command(instance)
                      }
                      id={"oci-ssh-#{index}"}
                      phx-hook="CopySSH"
                      class="flex flex-wrap sm:flex-nowrap items-center gap-2"
                    >
                      <input
                        aria-label="SSH command"
                        value={OCIBridge.ssh_command(instance)}
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
        <p :if={@oci.instances == []} class="p-4 text-gray-600">
          No recorded OCI instances. Refresh or launch an existing configuration.
        </p>
      </section>

      <section
        :if={@termination}
        id="oci-termination"
        class="border border-red-300 rounded-lg bg-red-50 p-4 space-y-3"
      >
        <h2 class="font-semibold">Terminate <%= @termination["name"] %></h2>
        <p class="break-all"><%= @termination["instance_id"] %> · <%= @termination["region"] %></p>
        <form id="oci-terminate-form" phx-submit="terminate" class="space-y-3">
          <label class="block">
            <input type="radio" name="boot_volume" value="preserve" required />
            Preserve boot volume — storage allocation and billing can continue.
          </label>
          <label class="block">
            <input type="radio" name="boot_volume" value="delete" required />
            Delete boot volume — permanently delete its data.
          </label>
          <p class="text-sm">The instance will be terminated. Network resources are preserved.</p>
          <button
            disabled={@oci.busy}
            class="bg-red-700 text-white px-4 py-2 rounded disabled:opacity-50"
          >
            Terminate this instance
          </button>
          <button type="button" phx-click="cancel-termination" class="px-4 py-2">Cancel</button>
        </form>
      </section>

      <details
        :if={@oci.operations != []}
        id="oci-operation-history"
        open={Enum.any?(@oci.operations, &needs_attention?(&1, @oci.instances))}
        class="bg-white border rounded-lg p-4"
      >
        <summary class="cursor-pointer font-semibold">
          Operation history (<%= length(@oci.operations) %>)
        </summary>
        <div class="mt-3 space-y-3">
          <div :for={operation <- @oci.operations} class="border rounded p-3" role="status">
            <p class="font-semibold">
              <%= String.capitalize(to_string(operation.type)) %> · <%= operation.target %> · <%= if recovered?(
                                                                                                       operation,
                                                                                                       @oci.instances
                                                                                                     ),
                                                                                                     do:
                                                                                                       "Earlier verification failure",
                                                                                                     else:
                                                                                                       operation.status %>
            </p>
            <p :if={recovered?(operation, @oci.instances)} class="text-green-800 mt-1">
              Recovered: the same instance is now running and SSH verified.
            </p>
            <details :if={recovered?(operation, @oci.instances)} class="mt-2 text-sm text-gray-600">
              <summary class="cursor-pointer">Original error</summary>
              <p class="mt-2"><%= operation.message %></p>
            </details>
            <p
              :if={!recovered?(operation, @oci.instances)}
              class={
                if needs_attention?(operation, @oci.instances) && operation.status == :failed,
                  do: "text-red-800 mt-1",
                  else: "text-gray-600 mt-1"
              }
            >
              <%= operation.message %>
            </p>
          </div>
        </div>
      </details>
    </div>
    """
  end
end
