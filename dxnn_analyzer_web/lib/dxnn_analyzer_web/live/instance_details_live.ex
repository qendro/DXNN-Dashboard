defmodule DxnnAnalyzerWeb.InstanceDetailsLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.AWS.{AWSBridge, AWSDeploymentServer}

  @impl true
  def mount(%{"instance_id" => instance_id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(DxnnAnalyzerWeb.PubSub, "aws_deployment")
    end

    socket =
      socket
      |> assign(:instance_id, instance_id)
      |> assign(:instance, nil)
      |> assign(:deployment, nil)
      |> assign(:active_tab, "overview")
      |> assign(:log_content, "")
      |> assign(:log_loading, false)
      |> load_instance_data()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:state_updated, state}, socket) do
    instance = Enum.find(state.instances, fn inst -> 
      inst.id == socket.assigns.instance_id 
    end)
    
    deployment = Map.get(state.deployments || %{}, socket.assigns.instance_id)
    
    socket =
      socket
      |> assign(:instance, instance)
      |> assign(:deployment, deployment)
    
    {:noreply, socket}
  end

  def handle_info({:deployment_recorded, instance_id, deployment}, socket) do
    if instance_id == socket.assigns.instance_id do
      {:noreply, assign(socket, :deployment, deployment)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  def handle_event("load_logs", _, socket) do
    socket = assign(socket, :log_loading, true)
    
    case AWSBridge.get_instance_logs(socket.assigns.instance_id) do
      {:ok, logs} ->
        {:noreply, assign(socket, log_content: logs, log_loading: false)}
      {:error, error} ->
        {:noreply, socket |> assign(:log_loading, false) |> put_flash(:error, "Failed to load logs: #{error}")}
    end
  end

  def handle_event("refresh_instance", _, socket) do
    AWSDeploymentServer.refresh()
    {:noreply, put_flash(socket, :info, "Refreshing instance data...")}
  end

  defp load_instance_data(socket) do
    state = AWSDeploymentServer.get_state()
    
    instance = Enum.find(state.instances, fn inst -> 
      inst.id == socket.assigns.instance_id 
    end)
    
    deployment = Map.get(state.deployments || %{}, socket.assigns.instance_id)
    
    socket
    |> assign(:instance, instance)
    |> assign(:deployment, deployment)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Header -->
        <div class="mb-6">
          <div class="flex items-center space-x-4 mb-4">
            <.link navigate="/aws-deployment" class="text-blue-600 hover:text-blue-800">
              ← Back to Instances
            </.link>
          </div>
          
          <%= if @instance do %>
            <div class="flex justify-between items-start">
              <div>
                <h1 class="text-3xl font-bold text-gray-900"><%= @instance.id %></h1>
                <p class="text-gray-600 mt-1"><%= @instance.name %></p>
              </div>
              <button
                phx-click="refresh_instance"
                class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition"
              >
                🔄 Refresh
              </button>
            </div>
          <% else %>
            <h1 class="text-3xl font-bold text-gray-900">Instance Not Found</h1>
          <% end %>
        </div>

        <%= if @instance do %>
          <!-- Tabs -->
          <div class="border-b border-gray-200 mb-6">
            <nav class="-mb-px flex space-x-8">
              <button
                phx-click="switch_tab"
                phx-value-tab="overview"
                class={"#{if @active_tab == "overview", do: "border-blue-500 text-blue-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"} whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm"}
              >
                Overview
              </button>
              <button
                phx-click="switch_tab"
                phx-value-tab="logs"
                class={"#{if @active_tab == "logs", do: "border-blue-500 text-blue-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"} whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm"}
              >
                Console Logs
              </button>
              <button
                phx-click="switch_tab"
                phx-value-tab="ssh"
                class={"#{if @active_tab == "ssh", do: "border-blue-500 text-blue-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"} whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm"}
              >
                SSH Commands
              </button>
              <button
                phx-click="switch_tab"
                phx-value-tab="monitoring"
                class={"#{if @active_tab == "monitoring", do: "border-blue-500 text-blue-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"} whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm"}
              >
                Monitoring
              </button>
            </nav>
          </div>

          <!-- Tab Content -->
          <div class="bg-white shadow rounded-lg p-6">
            <%= case @active_tab do %>
              <% "overview" -> %>
                <.overview_tab instance={@instance} deployment={@deployment} />
              <% "logs" -> %>
                <.logs_tab log_content={@log_content} log_loading={@log_loading} />
              <% "ssh" -> %>
                <.ssh_tab instance={@instance} deployment={@deployment} />
              <% "monitoring" -> %>
                <.monitoring_tab instance={@instance} />
            <% end %>
          </div>
        <% else %>
          <div class="bg-white shadow rounded-lg p-6">
            <p class="text-gray-600">Instance not found or has been terminated.</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Tab Components

  defp overview_tab(assigns) do
    ~H"""
    <div>
      <h2 class="text-xl font-semibold mb-4">Instance Information</h2>
      
      <div class="grid grid-cols-2 gap-6">
        <div>
          <h3 class="font-medium text-gray-700 mb-3">Basic Details</h3>
          <dl class="space-y-2">
            <div>
              <dt class="text-sm text-gray-600">Instance ID</dt>
              <dd class="text-sm font-mono text-gray-900"><%= @instance.id %></dd>
            </div>
            <div>
              <dt class="text-sm text-gray-600">Instance Type</dt>
              <dd class="text-sm text-gray-900"><%= @instance.type %></dd>
            </div>
            <div>
              <dt class="text-sm text-gray-600">Public IP</dt>
              <dd class="text-sm font-mono text-gray-900"><%= @instance.ip %></dd>
            </div>
            <div>
              <dt class="text-sm text-gray-600">State</dt>
              <dd class="text-sm">
                <span class={"px-2 py-1 text-xs rounded-full #{state_color(@instance.state)}"}>
                  <%= @instance.state %>
                </span>
              </dd>
            </div>
            <div>
              <dt class="text-sm text-gray-600">Launch Time</dt>
              <dd class="text-sm text-gray-900"><%= @instance.launch_time %></dd>
            </div>
            <div>
              <dt class="text-sm text-gray-600">Name</dt>
              <dd class="text-sm text-gray-900"><%= @instance.name %></dd>
            </div>
          </dl>
        </div>

        <div>
          <h3 class="font-medium text-gray-700 mb-3">Deployment Status</h3>
          <%= if @deployment do %>
            <div class="bg-green-50 border border-green-200 rounded-lg p-4">
              <div class="flex items-center space-x-2 mb-3">
                <span class="text-green-600 text-xl">✅</span>
                <span class="font-semibold text-green-800">Config Deployed</span>
              </div>
              <dl class="space-y-2">
                <div>
                  <dt class="text-sm text-gray-600">Branch</dt>
                  <dd class="text-sm font-mono text-gray-900"><%= @deployment.branch %></dd>
                </div>
                <div>
                  <dt class="text-sm text-gray-600">Deployed At</dt>
                  <dd class="text-sm text-gray-900"><%= format_datetime(@deployment.deployed_at) %></dd>
                </div>
                <div>
                  <dt class="text-sm text-gray-600">Training Status</dt>
                  <dd class="text-sm">
                    <%= if @deployment.started do %>
                      <span class="text-green-600">🟢 Started</span>
                    <% else %>
                      <span class="text-gray-600">⚪ Not Started</span>
                    <% end %>
                  </dd>
                </div>
              </dl>
            </div>
          <% else %>
            <div class="bg-gray-50 border border-gray-200 rounded-lg p-4">
              <p class="text-gray-600 text-sm">No configuration deployed yet.</p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp logs_tab(assigns) do
    ~H"""
    <div>
      <div class="flex justify-between items-center mb-4">
        <h2 class="text-xl font-semibold">Console Logs</h2>
        <button
          phx-click="load_logs"
          class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition text-sm"
          disabled={@log_loading}
        >
          <%= if @log_loading do %>
            ⏳ Loading...
          <% else %>
            🔄 Load Logs
          <% end %>
        </button>
      </div>
      
      <%= if @log_content != "" do %>
        <div class="bg-gray-900 text-green-400 p-4 rounded font-mono text-xs overflow-auto max-h-[600px]">
          <pre><%= @log_content %></pre>
        </div>
      <% else %>
        <div class="bg-gray-50 border border-gray-200 rounded-lg p-8 text-center">
          <p class="text-gray-600">Click "Load Logs" to view console output.</p>
          <p class="text-gray-500 text-sm mt-2">Note: Requires ec2:GetConsoleOutput IAM permission</p>
        </div>
      <% end %>
    </div>
    """
  end

  defp ssh_tab(assigns) do
    ~H"""
    <div>
      <h2 class="text-xl font-semibold mb-4">SSH Commands</h2>
      
      <div class="space-y-4">
        <div>
          <div class="flex items-center justify-between mb-2">
            <label class="text-sm font-medium text-gray-700">Connect to Instance</label>
            <button
              onclick={"navigator.clipboard.writeText('ssh -i AWS-Deployment/output/#{get_key_filename(@instance.id)} ubuntu@#{@instance.ip}')"}
              class="text-xs text-blue-600 hover:text-blue-800"
            >
              📋 Copy
            </button>
          </div>
          <code class="block bg-gray-900 text-green-400 p-3 rounded text-sm font-mono break-all select-all">
            ssh -i AWS-Deployment/output/<%= get_key_filename(@instance.id) %> ubuntu@<%= @instance.ip %>
          </code>
        </div>

        <%= if @deployment do %>
          <div>
            <div class="flex items-center justify-between mb-2">
              <label class="text-sm font-medium text-gray-700">Attach to Training Session</label>
              <button
                onclick="navigator.clipboard.writeText('tmux attach -t trader')"
                class="text-xs text-blue-600 hover:text-blue-800"
              >
                📋 Copy
              </button>
            </div>
            <code class="block bg-gray-900 text-green-400 p-3 rounded text-sm font-mono select-all">
              tmux attach -t trader
            </code>
            <p class="text-xs text-gray-500 mt-1">Run this after SSH'ing into the instance</p>
          </div>

          <div>
            <div class="flex items-center justify-between mb-2">
              <label class="text-sm font-medium text-gray-700">View Training Logs</label>
              <button
                onclick="navigator.clipboard.writeText('tail -f /var/log/dxnn-run.log')"
                class="text-xs text-blue-600 hover:text-blue-800"
              >
                📋 Copy
              </button>
            </div>
            <code class="block bg-gray-900 text-green-400 p-3 rounded text-sm font-mono select-all">
              tail -f /var/log/dxnn-run.log
            </code>
            <p class="text-xs text-gray-500 mt-1">Run this after SSH'ing into the instance</p>
          </div>
        <% end %>

        <div class="bg-blue-50 border border-blue-200 rounded-lg p-4 mt-6">
          <h3 class="font-medium text-blue-900 mb-2">SSH Key Location</h3>
          <p class="text-sm text-blue-800">
            Key file: <code class="font-mono bg-blue-100 px-2 py-1 rounded"><%= get_key_filename(@instance.id) %></code>
          </p>
          <p class="text-xs text-blue-700 mt-2">
            Located in: <code class="font-mono">AWS-Deployment/output/</code>
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp monitoring_tab(assigns) do
    ~H"""
    <div>
      <h2 class="text-xl font-semibold mb-4">Monitoring</h2>
      
      <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-6 text-center">
        <p class="text-yellow-800 font-medium">🚧 Coming Soon</p>
        <p class="text-yellow-700 text-sm mt-2">
          Real-time monitoring features will be added here, including:
        </p>
        <ul class="text-yellow-700 text-sm mt-3 space-y-1">
          <li>• Live tmux session viewer</li>
          <li>• Real-time log streaming</li>
          <li>• Resource usage metrics</li>
          <li>• Training progress visualization</li>
        </ul>
      </div>
    </div>
    """
  end

  # Helper Functions

  defp state_color("running"), do: "bg-green-100 text-green-800"
  defp state_color("pending"), do: "bg-yellow-100 text-yellow-800"
  defp state_color("stopping"), do: "bg-orange-100 text-orange-800"
  defp state_color("stopped"), do: "bg-red-100 text-red-800"
  defp state_color(_), do: "bg-gray-100 text-gray-800"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end
  defp format_datetime(_), do: "Unknown"

  defp get_key_filename(instance_id) do
    case File.ls("/app/AWS-Deployment/output") do
      {:ok, files} ->
        json_files = Enum.filter(files, &String.ends_with?(&1, ".json"))
        
        matching_data = Enum.find_value(json_files, fn file ->
          path = Path.join("/app/AWS-Deployment/output", file)
          case File.read(path) do
            {:ok, content} ->
              case Jason.decode(content) do
                {:ok, data} -> 
                  if data["instance_id"] == instance_id do
                    data
                  else
                    nil
                  end
                _ -> nil
              end
            _ -> nil
          end
        end)
        
        if matching_data do
          ssh_key_file = matching_data["ssh_key_file"]
          if ssh_key_file do
            Path.basename(ssh_key_file)
          else
            key_name = matching_data["key_name"]
            if key_name do
              "#{key_name}-key.pem"
            else
              "aws-deployment-key-*.pem"
            end
          end
        else
          deployment_keys = files
          |> Enum.filter(&(String.starts_with?(&1, "aws-deployment-key-") and String.ends_with?(&1, ".pem")))
          |> Enum.sort()
          |> Enum.reverse()
          
          if length(deployment_keys) > 0 do
            List.first(deployment_keys)
          else
            "aws-deployment-key-*.pem"
          end
        end
      _ -> "aws-deployment-key-*.pem"
    end
  end
end
