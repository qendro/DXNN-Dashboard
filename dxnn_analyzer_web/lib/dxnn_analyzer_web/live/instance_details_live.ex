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
      |> assign(:ssh_output, "")
      |> assign(:ssh_loading, false)
      |> assign(:ssh_command, "")
      |> assign(:tmux_output, "")
      |> assign(:tmux_loading, false)
      |> assign(:tmux_auto_refresh, false)
      |> assign(:tmux_timer, nil)
      |> assign(:tmux_lines, 100)
      |> assign(:checkpoint_status, nil)
      |> assign(:checkpoint_loading, false)
      |> assign(:available_logs, [])
      |> assign(:selected_log, nil)
      |> assign(:log_lines, 100)
      |> assign(:log_viewer_content, "")
      |> assign(:log_viewer_loading, false)
      |> assign(:s3_checkpoints, [])
      |> assign(:s3_loading, false)
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

  def handle_event("execute_ssh_command", %{"command" => command}, socket) do
    socket = assign(socket, :ssh_loading, true)
    key_file = get_key_path(socket.assigns.instance_id)
    host = socket.assigns.instance.ip

    case AWSBridge.get_ssh_output(key_file, host, command) do
      {:ok, output} ->
        {:noreply, assign(socket, ssh_output: output, ssh_loading: false, ssh_command: command)}
      {:error, error} ->
        {:noreply, socket |> assign(:ssh_loading, false) |> put_flash(:error, "SSH command failed: #{error}")}
    end
  end

  def handle_event("load_tmux", _, socket) do
    socket = assign(socket, :tmux_loading, true)
    key_file = get_key_path(socket.assigns.instance_id)
    host = socket.assigns.instance.ip
    lines = Map.get(socket.assigns, :tmux_lines, 100)

    case AWSBridge.capture_tmux_pane(key_file, host, "trader", lines) do
      {:ok, output} ->
        {:noreply, assign(socket, tmux_output: output, tmux_loading: false)}
      {:error, error} ->
        {:noreply, socket |> assign(:tmux_loading, false) |> put_flash(:error, "Failed to capture tmux: #{error}")}
    end
  end

  def handle_event("update_tmux_lines", %{"lines" => lines_str}, socket) do
    lines = String.to_integer(lines_str)
    {:noreply, assign(socket, :tmux_lines, lines)}
  end

  def handle_event("toggle_tmux_auto_refresh", _, socket) do
    new_state = !socket.assigns.tmux_auto_refresh
    
    socket = if new_state do
      timer = Process.send_after(self(), :refresh_tmux, 3000)
      assign(socket, tmux_auto_refresh: true, tmux_timer: timer)
    else
      if socket.assigns.tmux_timer, do: Process.cancel_timer(socket.assigns.tmux_timer)
      assign(socket, tmux_auto_refresh: false, tmux_timer: nil)
    end

    {:noreply, socket}
  end

  def handle_info(:refresh_tmux, socket) do
    if socket.assigns.tmux_auto_refresh do
      key_file = get_key_path(socket.assigns.instance_id)
      host = socket.assigns.instance.ip
      lines = Map.get(socket.assigns, :tmux_lines, 100)

      socket = case AWSBridge.capture_tmux_pane(key_file, host, "trader", lines) do
        {:ok, output} -> assign(socket, :tmux_output, output)
        {:error, _} -> socket
      end

      timer = Process.send_after(self(), :refresh_tmux, 3000)
      {:noreply, assign(socket, :tmux_timer, timer)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("force_checkpoint", _, socket) do
    key_file = get_key_path(socket.assigns.instance_id)
    host = socket.assigns.instance.ip
    
    case AWSBridge.force_checkpoint(key_file, host) do
      {_, 0} ->
        {:noreply, put_flash(socket, :info, "Checkpoint created successfully")}
      {error, _} ->
        {:noreply, put_flash(socket, :error, "Checkpoint failed: #{error}")}
    end
  end

  def handle_event("upload_to_s3", _, socket) do
    key_file = get_key_path(socket.assigns.instance_id)
    host = socket.assigns.instance.ip
    
    socket = assign(socket, :checkpoint_loading, true)
    
    case AWSBridge.trigger_s3_upload(key_file, host) do
      {_, 0} ->
        {:noreply, socket |> assign(:checkpoint_loading, false) |> put_flash(:info, "S3 upload initiated")}
      {error, _} ->
        {:noreply, socket |> assign(:checkpoint_loading, false) |> put_flash(:error, "S3 upload failed: #{error}")}
    end
  end

  def handle_event("load_checkpoint_status", _, socket) do
    key_file = get_key_path(socket.assigns.instance_id)
    host = socket.assigns.instance.ip
    
    case AWSBridge.get_checkpoint_status(key_file, host) do
      {:ok, status} ->
        {:noreply, assign(socket, :checkpoint_status, status)}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to load checkpoint status")}
    end
  end

  def handle_event("load_available_logs", _, socket) do
    if socket.assigns.instance do
      key_file = get_key_path(socket.assigns.instance_id)
      host = socket.assigns.instance.ip
      
      case AWSBridge.list_log_files(key_file, host) do
        {:ok, logs} ->
          {:noreply, assign(socket, :available_logs, logs)}
        {:error, error} ->
          {:noreply, put_flash(socket, :error, "Failed to list logs: #{error}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Instance data not loaded")}
    end
  end

  def handle_event("select_log", %{"log" => log_path}, socket) do
    IO.puts("DEBUG: select_log called with: #{inspect(log_path)}")
    {:noreply, assign(socket, :selected_log, log_path)}
  end

  def handle_event("update_log_lines", %{"lines" => lines}, socket) do
    {:noreply, assign(socket, :log_lines, String.to_integer(lines))}
  end

  def handle_event("view_log", _, socket) do
    cond do
      is_nil(socket.assigns.instance) ->
        {:noreply, put_flash(socket, :error, "Instance data not loaded")}
      
      is_nil(socket.assigns.selected_log) || socket.assigns.selected_log == "" ->
        {:noreply, put_flash(socket, :error, "Please select a log file")}
      
      true ->
        socket = assign(socket, :log_viewer_loading, true)
        key_file = get_key_path(socket.assigns.instance_id)
        host = socket.assigns.instance.ip
        
        # read_log_file returns {output, exit_code} tuple from System.cmd
        case AWSBridge.read_log_file(key_file, host, socket.assigns.selected_log, socket.assigns.log_lines) do
          {output, 0} ->
            {:noreply, assign(socket, log_viewer_content: output, log_viewer_loading: false)}
          {error, exit_code} ->
            error_msg = if is_binary(error), do: error, else: inspect(error)
            {:noreply, socket |> assign(:log_viewer_loading, false) |> put_flash(:error, "Failed to read log (exit #{exit_code}): #{error_msg}")}
        end
    end
  end

  def handle_event("load_s3_checkpoints", _, socket) do
    socket = assign(socket, :s3_loading, true)
    
    case AWSBridge.list_instance_s3_checkpoints(socket.assigns.instance_id) do
      {:ok, checkpoints} ->
        {:noreply, assign(socket, s3_checkpoints: checkpoints, s3_loading: false)}
      {:error, _} ->
        {:noreply, socket |> assign(:s3_loading, false) |> put_flash(:error, "Failed to load S3 checkpoints")}
    end
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
                <.overview_tab 
                  instance={@instance} 
                  deployment={@deployment} 
                  checkpoint_status={@checkpoint_status}
                  checkpoint_loading={@checkpoint_loading}
                />
              <% "logs" -> %>
                <.logs_tab 
                  log_content={@log_content} 
                  log_loading={@log_loading}
                  available_logs={@available_logs}
                  selected_log={@selected_log}
                  log_lines={@log_lines}
                  log_viewer_content={@log_viewer_content}
                  log_viewer_loading={@log_viewer_loading}
                />
              <% "ssh" -> %>
                <.ssh_tab 
                  instance={@instance} 
                  deployment={@deployment}
                  ssh_output={@ssh_output}
                  ssh_loading={@ssh_loading}
                  ssh_command={@ssh_command}
                />
              <% "monitoring" -> %>
                <.monitoring_tab 
                  instance={@instance}
                  tmux_output={@tmux_output}
                  tmux_loading={@tmux_loading}
                  tmux_auto_refresh={@tmux_auto_refresh}
                />
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

      <!-- Checkpoint Controls -->
      <%= if @deployment && @deployment.started do %>
        <div class="mt-6 pt-6 border-t border-gray-200">
          <h3 class="font-medium text-gray-700 mb-3">Checkpoint Management</h3>
          
          <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
            <%= if @checkpoint_status do %>
              <div class="mb-4 space-y-2 text-sm">
                <div>
                  <span class="text-gray-600">Last Checkpoint:</span>
                  <span class="ml-2 font-mono text-gray-900"><%= @checkpoint_status.last_checkpoint || "None" %></span>
                </div>
                <div>
                  <span class="text-gray-600">Total Size:</span>
                  <span class="ml-2 text-gray-900"><%= @checkpoint_status.total_size %></span>
                </div>
                <div>
                  <span class="text-gray-600">Checkpoint Count:</span>
                  <span class="ml-2 text-gray-900"><%= @checkpoint_status.count %></span>
                </div>
              </div>
            <% end %>
            
            <div class="flex items-center space-x-3">
              <button
                phx-click="load_checkpoint_status"
                class="bg-gray-600 text-white px-4 py-2 rounded hover:bg-gray-700 transition text-sm"
              >
                🔍 Check Status
              </button>
              <button
                phx-click="force_checkpoint"
                class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 transition text-sm"
              >
                📸 Create Checkpoint
              </button>
              <button
                phx-click="upload_to_s3"
                class="bg-green-600 text-white px-4 py-2 rounded hover:bg-green-700 transition text-sm"
                disabled={@checkpoint_loading}
              >
                <%= if @checkpoint_loading do %>
                  ⏳ Uploading...
                <% else %>
                  ☁️ Upload to S3
                <% end %>
              </button>
            </div>
            
            <p class="text-xs text-gray-600 mt-3">
              Create Checkpoint: Local backup (~2-5s) • Upload to S3: Full backup with logs
            </p>
          </div>
        </div>
      <% end %>
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
            🔄 Load Console Logs
          <% end %>
        </button>
      </div>
      
      <%= if @log_content != "" do %>
        <div class="bg-gray-900 text-green-400 p-4 rounded font-mono text-xs overflow-auto max-h-[600px] mb-6">
          <pre><%= @log_content %></pre>
        </div>
      <% else %>
        <div class="bg-gray-50 border border-gray-200 rounded-lg p-8 text-center mb-6">
          <p class="text-gray-600">Click "Load Console Logs" to view EC2 console output.</p>
          <p class="text-gray-500 text-sm mt-2">Note: Requires ec2:GetConsoleOutput IAM permission</p>
        </div>
      <% end %>

      <!-- Log File Browser -->
      <div class="mt-6 pt-6 border-t border-gray-200">
        <h3 class="text-lg font-semibold mb-4">Log File Browser</h3>
        
        <div class="bg-white border border-gray-200 rounded-lg p-4">
          <div class="flex items-center space-x-3 mb-4">
            <button
              phx-click="load_available_logs"
              class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 transition text-sm"
            >
              📂 List Log Files
            </button>
          </div>

          <%= if length(@available_logs) > 0 do %>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">Select Log File</label>
                <select
                  phx-change="select_log"
                  name="log"
                  class="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
                >
                  <option value="">-- Select a log file --</option>
                  <%= for log <- @available_logs do %>
                    <option value={log.path} selected={@selected_log == log.path}>
                      <%= Path.basename(log.path) %> (<%= log.size %>)
                    </option>
                  <% end %>
                </select>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">Lines to Show</label>
                <select
                  phx-change="update_log_lines"
                  name="lines"
                  class="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
                >
                  <option value="50">Last 50 lines</option>
                  <option value="100" selected={@log_lines == 100}>Last 100 lines</option>
                  <option value="200">Last 200 lines</option>
                  <option value="500">Last 500 lines</option>
                  <option value="1000">Last 1000 lines</option>
                </select>
              </div>
            </div>

            <button
              phx-click="view_log"
              class="bg-green-600 hover:bg-green-700 text-white px-4 py-2 rounded transition text-sm"
            >
              <%= if @log_viewer_loading do %>
                ⏳ Loading...
              <% else %>
                👁️ View Log
              <% end %>
            </button>

            <%= if !@selected_log do %>
              <p class="text-xs text-gray-500 mt-2">Please select a log file from the dropdown above</p>
            <% end %>

            <%= if @log_viewer_content != "" do %>
              <div class="mt-4">
                <div class="flex justify-between items-center mb-2">
                  <h4 class="font-medium text-gray-700">
                    <%= Path.basename(@selected_log) %> (Last <%= @log_lines %> lines)
                  </h4>
                  <button
                    onclick={"navigator.clipboard.writeText(`#{String.replace(@log_viewer_content, "`", "\\`")}`)"}
                    class="text-xs text-blue-600 hover:text-blue-800"
                  >
                    📋 Copy
                  </button>
                </div>
                <div class="bg-gray-900 text-green-400 p-4 rounded font-mono text-xs overflow-auto max-h-[500px]">
                  <pre><%= @log_viewer_content %></pre>
                </div>
              </div>
            <% end %>
          <% else %>
            <div class="bg-gray-50 border border-gray-200 rounded-lg p-6 text-center">
              <p class="text-gray-600">Click "List Log Files" to see available logs</p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp ssh_tab(assigns) do
    ~H"""
    <div>
      <h2 class="text-xl font-semibold mb-4">SSH Terminal Viewer</h2>
      
      <div class="space-y-6">
        <!-- Quick Commands -->
        <div class="bg-gray-50 border border-gray-200 rounded-lg p-4">
          <h3 class="font-medium text-gray-700 mb-3">Quick Commands</h3>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
            <button
              phx-click="execute_ssh_command"
              phx-value-command="uptime"
              class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 transition text-sm"
              disabled={@ssh_loading}
            >
              📊 System Uptime
            </button>
            <button
              phx-click="execute_ssh_command"
              phx-value-command="free -h"
              class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 transition text-sm"
              disabled={@ssh_loading}
            >
              💾 Memory Usage
            </button>
            <button
              phx-click="execute_ssh_command"
              phx-value-command="df -h"
              class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 transition text-sm"
              disabled={@ssh_loading}
            >
              💿 Disk Usage
            </button>
            <button
              phx-click="execute_ssh_command"
              phx-value-command="ps aux --sort=-%mem | head -10"
              class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 transition text-sm"
              disabled={@ssh_loading}
            >
              🔝 Top Processes
            </button>
            <%= if @deployment do %>
              <button
                phx-click="execute_ssh_command"
                phx-value-command="tail -50 /var/log/dxnn-run.log"
                class="bg-green-600 text-white px-4 py-2 rounded hover:bg-green-700 transition text-sm"
                disabled={@ssh_loading}
              >
                📜 DXNN Logs
              </button>
              <button
                phx-click="execute_ssh_command"
                phx-value-command="tmux list-sessions"
                class="bg-green-600 text-white px-4 py-2 rounded hover:bg-green-700 transition text-sm"
                disabled={@ssh_loading}
              >
                🖥️ TMUX Sessions
              </button>
            <% end %>
          </div>
        </div>

        <!-- Output Terminal -->
        <%= if @ssh_output != "" do %>
          <div>
            <div class="flex justify-between items-center mb-2">
              <h3 class="font-medium text-gray-700">Output: <%= @ssh_command %></h3>
              <button
                onclick={"navigator.clipboard.writeText(`#{String.replace(@ssh_output, "`", "\\`")}`)"}
                class="text-xs text-blue-600 hover:text-blue-800"
              >
                📋 Copy Output
              </button>
            </div>
            <div class="bg-gray-900 text-green-400 p-4 rounded font-mono text-xs overflow-auto max-h-[500px]">
              <pre id="ssh-output" phx-hook="ScrollToBottom"><%= @ssh_output %></pre>
            </div>
          </div>
        <% else %>
          <div class="bg-gray-50 border border-gray-200 rounded-lg p-8 text-center">
            <p class="text-gray-600">Click a command above to execute it via SSH</p>
            <p class="text-gray-500 text-sm mt-2">Output will appear here</p>
          </div>
        <% end %>

        <!-- SSH Connection Info -->
        <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
          <h3 class="font-medium text-blue-900 mb-2">Manual SSH Connection</h3>
          <code class="block bg-blue-100 text-blue-900 p-2 rounded text-xs font-mono break-all">
            ssh -i AWS-Deployment/output/<%= get_key_filename(@instance.id) %> ubuntu@<%= @instance.ip %>
          </code>
        </div>
      </div>
    </div>
    """
  end

  defp monitoring_tab(assigns) do
    # Ensure tmux_lines has a default value
    assigns = assign_new(assigns, :tmux_lines, fn -> 100 end)
    
    ~H"""
    <div>
      <h2 class="text-xl font-semibold mb-4">TMUX Session Viewer</h2>
      
      <div class="space-y-4">
        <!-- Controls -->
        <div class="flex items-center justify-between bg-gray-50 border border-gray-200 rounded-lg p-4">
          <div class="flex items-center space-x-4">
            <button
              phx-click="load_tmux"
              class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 transition text-sm"
              disabled={@tmux_loading}
            >
              <%= if @tmux_loading do %>
                ⏳ Loading...
              <% else %>
                🔄 Refresh TMUX
              <% end %>
            </button>
            
            <button
              phx-click="toggle_tmux_auto_refresh"
              class={"#{if @tmux_auto_refresh, do: "bg-green-600 hover:bg-green-700", else: "bg-gray-600 hover:bg-gray-700"} text-white px-4 py-2 rounded transition text-sm"}
            >
              <%= if @tmux_auto_refresh do %>
                ⏸️ Stop Auto-Refresh
              <% else %>
                ▶️ Auto-Refresh (3s)
              <% end %>
            </button>

            <div class="flex items-center space-x-2">
              <label for="tmux-lines" class="text-sm text-gray-700 font-medium">Lines:</label>
              <select
                id="tmux-lines"
                phx-change="update_tmux_lines"
                name="lines"
                class="border border-gray-300 rounded px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                <option value="50" selected={@tmux_lines == 50}>50</option>
                <option value="100" selected={@tmux_lines == 100}>100</option>
                <option value="200" selected={@tmux_lines == 200}>200</option>
                <option value="500" selected={@tmux_lines == 500}>500</option>
                <option value="1000" selected={@tmux_lines == 1000}>1000</option>
                <option value="2000" selected={@tmux_lines == 2000}>2000</option>
                <option value="5000" selected={@tmux_lines == 5000}>5000</option>
                <option value="10000" selected={@tmux_lines == 10000}>10000</option>
              </select>
            </div>
          </div>
          
          <%= if @tmux_auto_refresh do %>
            <div class="flex items-center space-x-2">
              <div class="animate-pulse w-2 h-2 rounded-full bg-green-500"></div>
              <span class="text-green-600 text-sm font-medium">Live</span>
            </div>
          <% end %>
        </div>

        <!-- TMUX Output -->
        <%= if @tmux_output != "" do %>
          <div class="bg-gray-900 text-green-400 p-4 rounded font-mono text-xs overflow-auto max-h-[600px] border-2 border-gray-700">
            <pre id="tmux-output" phx-hook="ScrollToBottom"><%= @tmux_output %></pre>
          </div>
        <% else %>
          <div class="bg-gray-50 border border-gray-200 rounded-lg p-8 text-center">
            <p class="text-gray-600">Click "Refresh TMUX" to view the trader session</p>
            <p class="text-gray-500 text-sm mt-2">Shows last <%= @tmux_lines %> lines of the tmux pane</p>
          </div>
        <% end %>

        <!-- Info -->
        <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
          <h3 class="font-medium text-blue-900 mb-2">About TMUX Viewer</h3>
          <ul class="text-blue-800 text-sm space-y-1">
            <li>• View-only mode (read-only access to tmux session)</li>
            <li>• Shows last <%= @tmux_lines %> lines of the "trader" session</li>
            <li>• Auto-refresh updates every 3 seconds when enabled</li>
            <li>• For interactive control, use SSH directly</li>
            <li>• 10k lines is feasible but may take a few seconds to load</li>
          </ul>
        </div>
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

  defp get_key_path(instance_id) do
    "/app/AWS-Deployment/output/#{get_key_filename(instance_id)}"
  end

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
