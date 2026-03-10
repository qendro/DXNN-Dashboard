defmodule DxnnAnalyzerWeb.S3ExperimentsLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.AWS.AWSBridge
  alias DxnnAnalyzerWeb.AnalyzerBridge

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:bucket, "dxnn-checkpoints")
      |> assign(:prefix, "dxnn-prod")
      |> assign(:jobs, [])
      |> assign(:selected_job, nil)
      |> assign(:runs, [])
      |> assign(:selected_run, nil)
      |> assign(:run_metadata, nil)
      |> assign(:loading, false)
      |> assign(:downloading, false)
      |> assign(:download_progress, "")

    {:ok, socket}
  end

  @impl true
  def handle_event("load_jobs", _, socket) do
    socket = assign(socket, :loading, true)
    
    case AWSBridge.list_s3_jobs(socket.assigns.bucket, socket.assigns.prefix) do
      {:ok, jobs} ->
        {:noreply, assign(socket, jobs: jobs, loading: false)}
      {:error, error} ->
        {:noreply, socket |> assign(:loading, false) |> put_flash(:error, "Failed to load jobs: #{error}")}
    end
  end

  def handle_event("select_job", %{"job_id" => lineage_id}, socket) do
    socket = assign(socket, loading: true, selected_job: lineage_id, runs: [], selected_run: nil, run_metadata: nil)
    
    case AWSBridge.list_s3_runs(socket.assigns.bucket, socket.assigns.prefix, lineage_id) do
      {:ok, runs} ->
        {:noreply, assign(socket, runs: runs, loading: false)}
      {:error, error} ->
        {:noreply, socket |> assign(:loading, false) |> put_flash(:error, "Failed to load runs: #{error}")}
    end
  end

  def handle_event("select_run", %{"run_id" => run_id}, socket) do
    socket = assign(socket, :selected_run, run_id)
    
    # Load metadata for selected run
    case AWSBridge.get_s3_checkpoint_metadata(
      socket.assigns.bucket,
      socket.assigns.prefix,
      socket.assigns.selected_job,
      run_id
    ) do
      {:ok, metadata} ->
        {:noreply, assign(socket, :run_metadata, metadata)}
      {:error, _} ->
        {:noreply, assign(socket, :run_metadata, nil)}
    end
  end

  def handle_event("load_as_context", _, socket) do
    if socket.assigns.selected_job && socket.assigns.selected_run do
      socket = assign(socket, downloading: true, download_progress: "Downloading from S3...")
      
      # Create local path for download
      local_path = "/app/data/s3_cache/#{socket.assigns.selected_job}/#{socket.assigns.selected_run}"
      
      case AWSBridge.download_s3_checkpoint(
        socket.assigns.bucket,
        socket.assigns.prefix,
        socket.assigns.selected_job,
        socket.assigns.selected_run,
        local_path
      ) do
        {:ok, path} ->
          context_name = build_s3_context_name(socket.assigns.selected_job, socket.assigns.selected_run)

          case AnalyzerBridge.load_context(path, context_name) do
            {:ok, _} ->
              {:noreply, socket 
                |> assign(downloading: false, download_progress: "")
                |> put_flash(:info, "Context loaded successfully as '#{context_name}'")
                |> push_navigate(to: "/")}
            {:error, {:already_loaded, _}} ->
              {:noreply, socket 
                |> assign(downloading: false, download_progress: "")
                |> put_flash(:info, "Context '#{context_name}' is already loaded")
                |> push_navigate(to: "/")}
            {:error, reason} ->
              {:noreply, socket
                |> assign(downloading: false, download_progress: "")
                |> put_flash(:error, "Failed to load context: #{format_load_error(reason)}")}
          end
        {:error, error} ->
          {:noreply, socket 
            |> assign(downloading: false, download_progress: "")
            |> put_flash(:error, "Download failed: #{error}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please select a job and run")}
    end
  end

  def handle_event("clear_cache", _, socket) do
    cache_path = "/app/data/s3_cache"
    
    case File.rm_rf(cache_path) do
      {:ok, _} ->
        File.mkdir_p!(cache_path)
        {:noreply, put_flash(socket, :info, "Cache cleared successfully")}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to clear cache: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="mb-8 flex justify-between items-center">
          <div>
            <h1 class="text-3xl font-bold text-gray-900">S3 Experiments</h1>
            <p class="mt-2 text-gray-600">Browse and load experiments from S3 checkpoints</p>
          </div>
          <div class="flex space-x-3">
            <.link
              navigate={~p"/s3-explorer"}
              class="bg-teal-600 text-white px-4 py-2 rounded-md hover:bg-teal-700 transition"
            >
              🗂️ S3 Explorer
            </.link>
            <button
              phx-click="clear_cache"
              class="bg-red-600 text-white px-4 py-2 rounded-md hover:bg-red-700 transition"
            >
              🗑️ Clear Cache
            </button>
            <.link
              navigate="/"
              class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition"
            >
              ← Back to Dashboard
            </.link>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <!-- Jobs List -->
          <div class="bg-white shadow rounded-lg p-6">
            <div class="flex justify-between items-center mb-4">
              <h2 class="text-lg font-semibold">Lineage IDs</h2>
              <button
                phx-click="load_jobs"
                class="bg-blue-600 text-white px-3 py-1 rounded text-sm hover:bg-blue-700 transition"
                disabled={@loading}
              >
                <%= if @loading && !@selected_job do %>
                  ⏳
                <% else %>
                  🔄
                <% end %>
              </button>
            </div>

            <%= if length(@jobs) > 0 do %>
              <div class="space-y-2 max-h-[600px] overflow-y-auto">
                <%= for job <- @jobs do %>
                  <button
                    phx-click="select_job"
                    phx-value-job_id={job.id}
                    class={"w-full text-left px-3 py-2 rounded text-sm transition #{if @selected_job == job.id, do: "bg-blue-100 border-2 border-blue-500", else: "bg-gray-50 hover:bg-gray-100 border-2 border-transparent"}"}
                  >
                    <div class="font-mono text-xs break-all"><%= job.id %></div>
                  </button>
                <% end %>
              </div>
            <% else %>
              <div class="text-center py-8 text-gray-500 text-sm">
                Click refresh to load lineage IDs
              </div>
            <% end %>
          </div>

          <!-- Runs List -->
          <div class="bg-white shadow rounded-lg p-6">
            <h2 class="text-lg font-semibold mb-4">Population IDs</h2>

            <%= if @selected_job do %>
              <%= if length(@runs) > 0 do %>
                <div class="space-y-2 max-h-[600px] overflow-y-auto">
                  <%= for run <- @runs do %>
                    <button
                      phx-click="select_run"
                      phx-value-run_id={run.id}
                      class={"w-full text-left px-3 py-2 rounded text-sm transition #{if @selected_run == run.id, do: "bg-green-100 border-2 border-green-500", else: "bg-gray-50 hover:bg-gray-100 border-2 border-transparent"}"}
                    >
                      <div class="font-mono text-xs"><%= run.id %></div>
                    </button>
                  <% end %>
                </div>
              <% else %>
                <div class="text-center py-8 text-gray-500 text-sm">
                  <%= if @loading do %>
                    Loading runs...
                  <% else %>
                    No runs found for this lineage
                  <% end %>
                </div>
              <% end %>
            <% else %>
              <div class="text-center py-8 text-gray-500 text-sm">
                Select a lineage to view runs
              </div>
            <% end %>
          </div>

          <!-- Run Details -->
          <div class="bg-white shadow rounded-lg p-6">
            <h2 class="text-lg font-semibold mb-4">Run Details</h2>

            <%= if @selected_run && @run_metadata do %>
              <div class="space-y-4">
                <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
                  <h3 class="font-medium text-blue-900 mb-3">Checkpoint Info</h3>
                  <dl class="space-y-2 text-sm">
                    <div>
                      <dt class="text-gray-600">Run ID</dt>
                      <dd class="font-mono text-gray-900 text-xs break-all"><%= @run_metadata["run_id"] %></dd>
                    </div>
                    <div>
                      <dt class="text-gray-600">Status</dt>
                      <dd class="text-gray-900"><%= @run_metadata["status"] || @run_metadata["completion_status"] %></dd>
                    </div>
                    <div>
                      <dt class="text-gray-600">Finalized At</dt>
                      <dd class="text-gray-900"><%= @run_metadata["finalized_at"] %></dd>
                    </div>
                    <%= if @run_metadata["exit_code"] do %>
                      <div>
                        <dt class="text-gray-600">Exit Code</dt>
                        <dd class="text-gray-900"><%= @run_metadata["exit_code"] %></dd>
                      </div>
                    <% end %>
                    <%= if @run_metadata["reason"] do %>
                      <div>
                        <dt class="text-gray-600">Reason</dt>
                        <dd class="text-gray-900"><%= @run_metadata["reason"] %></dd>
                      </div>
                    <% end %>
                  </dl>
                </div>

                <div class="bg-gray-50 border border-gray-200 rounded-lg p-4">
                  <h3 class="font-medium text-gray-700 mb-2">S3 Location</h3>
                  <code class="block text-xs font-mono text-gray-900 break-all">
                    s3://<%= @bucket %>/<%= @prefix %>/<%= @selected_job %>/<%= @selected_run %>/
                  </code>
                </div>

                <button
                  phx-click="load_as_context"
                  class="w-full bg-green-600 text-white px-4 py-3 rounded-md hover:bg-green-700 transition font-medium"
                  disabled={@downloading}
                >
                  <%= if @downloading do %>
                    ⏳ <%= @download_progress %>
                  <% else %>
                    📥 Load as Context
                  <% end %>
                </button>

                <p class="text-xs text-gray-600 text-center">
                  Downloads run bundle and loads Mnesia context (logs/analytics kept on disk)
                </p>
              </div>
            <% else %>
              <div class="text-center py-8 text-gray-500 text-sm">
                <%= if @selected_run do %>
                  Loading metadata...
                <% else %>
                  Select a run to view details
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Info Box -->
        <div class="mt-6 bg-blue-50 border border-blue-200 rounded-lg p-4">
          <h3 class="font-medium text-blue-900 mb-2">About S3 Experiments</h3>
          <ul class="text-blue-800 text-sm space-y-1">
            <li>• Browse checkpoints uploaded from EC2 instances</li>
            <li>• Lineage ID format: 4-char code (e.g., 7g6n, p08s)</li>
            <li>• Population ID format: timestamp_code_runN (e.g., 2026-03-04T04:09:10Z_7g6n_run1)</li>
            <li>• Download and load experiments directly into the analyzer</li>
            <li>• Cached downloads stored in /app/data/s3_cache/</li>
            <li>• Use "Clear Cache" to free disk space</li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp build_s3_context_name(lineage_id, population_id) do
    safe_lineage = sanitize_context_fragment(lineage_id)
    run_fragment =
      population_id
      |> String.split("_")
      |> List.last()
      |> sanitize_context_fragment()

    "s3_#{safe_lineage}_#{run_fragment}"
  end

  defp sanitize_context_fragment(value) when is_binary(value) do
    value
    |> String.replace(~r/[^a-zA-Z0-9_-]/u, "_")
    |> String.trim("_")
    |> case do
      "" -> "run"
      cleaned -> cleaned
    end
  end

  defp format_load_error({:path_not_accessible, candidate_paths}) do
    "path not accessible from dashboard container (tried: #{Enum.join(candidate_paths, ", ")})"
  end

  defp format_load_error({:multiple_runs_found, run_paths}) do
    sample =
      run_paths
      |> Enum.take(3)
      |> Enum.join(", ")

    "multiple runs found. Select a specific run folder. Examples: #{sample}"
  end

  defp format_load_error(:no_mnesia_files) do
    "no Mnesia files found in downloaded run bundle"
  end

  defp format_load_error({:schema_node_mismatch, owner_nodes, current_node}) do
    "Mnesia schema belongs to #{inspect(owner_nodes)} but dashboard node is #{inspect(current_node)}"
  end

  defp format_load_error({:empty_checkpoint, message}), do: "empty checkpoint: #{message}"
  defp format_load_error({:aborted, {:no_exists, _}}), do: "checkpoint has no agent data yet"
  defp format_load_error(reason), do: inspect(reason)
end
