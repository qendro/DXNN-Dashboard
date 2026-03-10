defmodule DxnnAnalyzerWeb.ContextArtifactsLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.AnalyzerBridge

  @max_preview_bytes 200_000
  @max_files_per_group 500

  @impl true
  def mount(%{"context" => context_name}, _session, socket) do
    socket =
      socket
      |> assign(:context_name, context_name)
      |> assign(:bundle, %{})
      |> assign(:logs_files, [])
      |> assign(:analytics_files, [])
      |> assign(:selected_group, nil)
      |> assign(:selected_file_id, nil)
      |> assign(:selected_file_name, nil)
      |> assign(:preview, nil)
      |> assign(:error, nil)
      |> assign(:generating, false)
      |> assign(:generation_success, nil)
      |> load_artifacts(context_name)

    {:ok, socket}
  end

  @impl true
  def handle_event("open_file", %{"group" => group, "id" => id_str}, socket) do
    with {id, ""} <- Integer.parse(id_str),
         {:ok, file} <- find_file(group, id, socket.assigns),
         {:ok, preview} <- read_preview(file.path) do
      {:noreply,
       socket
       |> assign(:selected_group, group)
       |> assign(:selected_file_id, id)
       |> assign(:selected_file_name, file.rel_path)
       |> assign(:preview, preview)
       |> assign(:error, nil)}
    else
      :error ->
        {:noreply, put_flash(socket, :error, "Invalid file selection")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "File not found")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Unable to open file: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("generate_analytics", %{"format" => format}, socket) do
    format_atom = String.to_atom(format)
    
    socket = assign(socket, :generating, true)
    send(self(), {:do_generate_analytics, format_atom})
    
    {:noreply, socket}
  end

  @impl true
  def handle_info({:do_generate_analytics, format}, socket) do
    context_name = socket.assigns.context_name
    
    case AnalyzerBridge.generate_analytics(context_name, format) do
      {:ok, filepath} ->
        # Reload artifacts to show the new file
        socket =
          socket
          |> assign(:generating, false)
          |> assign(:generation_success, "Analytics generated: #{Path.basename(filepath)}")
          |> load_artifacts(context_name)
        
        {:noreply, socket}
      
      {:error, reason} ->
        socket =
          socket
          |> assign(:generating, false)
          |> assign(:error, "Failed to generate analytics: #{inspect(reason)}")
        
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="mb-6 flex items-center justify-between">
          <div>
            <.link navigate={~p"/"} class="text-blue-600 hover:text-blue-800 text-sm mb-2 inline-block">
              ← Back to Dashboard
            </.link>
            <h1 class="text-2xl font-bold text-gray-900">Artifacts: <%= @context_name %></h1>
            <p class="text-gray-600 text-sm mt-1">Logs and analytics files discovered for this loaded context</p>
          </div>
          <div class="flex gap-2">
            <.link
              navigate={~p"/agents?context=#{@context_name}"}
              class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition"
            >
              View Agents
            </.link>
            
            <!-- Analytics Generation Dropdown -->
            <div class="relative inline-block text-left">
              <button
                type="button"
                class="inline-flex items-center gap-2 bg-green-600 text-white px-4 py-2 rounded-md hover:bg-green-700 transition disabled:opacity-50 disabled:cursor-not-allowed"
                disabled={@generating}
                onclick="document.getElementById('analytics-menu').classList.toggle('hidden')"
              >
                <%= if @generating do %>
                  <svg class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  Generating...
                <% else %>
                  📊 Generate Analytics
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
                  </svg>
                <% end %>
              </button>
              
              <div id="analytics-menu" class="hidden absolute right-0 mt-2 w-48 rounded-md shadow-lg bg-white ring-1 ring-black ring-opacity-5 z-10">
                <div class="py-1" role="menu">
                  <button
                    phx-click="generate_analytics"
                    phx-value-format="csv"
                    class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
                    role="menuitem"
                  >
                    📄 CSV Format
                  </button>
                  <button
                    phx-click="generate_analytics"
                    phx-value-format="md"
                    class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
                    role="menuitem"
                  >
                    📝 Markdown Format
                  </button>
                  <button
                    phx-click="generate_analytics"
                    phx-value-format="log"
                    class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
                    role="menuitem"
                  >
                    📋 Log Format
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>

        <%= if @generation_success do %>
          <div class="bg-green-50 border border-green-200 rounded-md p-4 text-green-800 text-sm mb-4">
            ✅ <%= @generation_success %>
          </div>
        <% end %>

        <%= if @error do %>
          <div class="bg-red-50 border border-red-200 rounded-md p-4 text-red-800 text-sm">
            <%= @error %>
          </div>
        <% else %>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
            <div class="bg-white border border-gray-200 rounded-md p-4">
              <div class="text-sm text-gray-500">Bundle Root</div>
              <div class="font-mono text-xs text-gray-800 break-all mt-1"><%= @bundle.bundle_root || "-" %></div>
            </div>
            <div class="bg-white border border-gray-200 rounded-md p-4">
              <div class="text-sm text-gray-500">Mnesia Path</div>
              <div class="font-mono text-xs text-gray-800 break-all mt-1"><%= @bundle.mnesia_path || "-" %></div>
            </div>
            <div class="bg-white border border-gray-200 rounded-md p-4">
              <div class="text-sm text-gray-500">Logs Path</div>
              <div class="font-mono text-xs text-gray-800 break-all mt-1"><%= @bundle.logs_path || "-" %></div>
            </div>
            <div class="bg-white border border-gray-200 rounded-md p-4">
              <div class="text-sm text-gray-500">Analytics Path</div>
              <div class="font-mono text-xs text-gray-800 break-all mt-1"><%= @bundle.analytics_path || "-" %></div>
            </div>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <div class="bg-white shadow rounded-lg p-4">
              <h2 class="font-semibold text-gray-900 mb-3">Logs (<%= length(@logs_files) %>)</h2>
              <%= if Enum.empty?(@logs_files) do %>
                <p class="text-sm text-gray-500">No logs folder found.</p>
              <% else %>
                <div class="space-y-1 max-h-[32rem] overflow-y-auto">
                  <%= for file <- @logs_files do %>
                    <button
                      phx-click="open_file"
                      phx-value-group="logs"
                      phx-value-id={file.id}
                      class={"w-full text-left px-2 py-2 rounded text-xs border #{if @selected_group == "logs" and @selected_file_id == file.id, do: "bg-blue-50 border-blue-300", else: "hover:bg-gray-50 border-gray-200"}"}
                    >
                      <div class="font-mono break-all"><%= file.rel_path %></div>
                      <div class="text-gray-500 mt-0.5"><%= format_bytes(file.size) %></div>
                    </button>
                  <% end %>
                </div>
              <% end %>
            </div>

            <div class="bg-white shadow rounded-lg p-4">
              <h2 class="font-semibold text-gray-900 mb-3">Analytics (<%= length(@analytics_files) %>)</h2>
              <%= if Enum.empty?(@analytics_files) do %>
                <p class="text-sm text-gray-500">No analytics folder found.</p>
              <% else %>
                <div class="space-y-1 max-h-[32rem] overflow-y-auto">
                  <%= for file <- @analytics_files do %>
                    <button
                      phx-click="open_file"
                      phx-value-group="analytics"
                      phx-value-id={file.id}
                      class={"w-full text-left px-2 py-2 rounded text-xs border #{if @selected_group == "analytics" and @selected_file_id == file.id, do: "bg-indigo-50 border-indigo-300", else: "hover:bg-gray-50 border-gray-200"}"}
                    >
                      <div class="font-mono break-all"><%= file.rel_path %></div>
                      <div class="text-gray-500 mt-0.5"><%= format_bytes(file.size) %></div>
                    </button>
                  <% end %>
                </div>
              <% end %>
            </div>

            <div class="bg-white shadow rounded-lg p-4">
              <h2 class="font-semibold text-gray-900 mb-3">Preview</h2>
              <%= if @selected_file_name do %>
                <div class="text-xs text-gray-600 mb-2">
                  <span class="font-medium">File:</span> <span class="font-mono break-all"><%= @selected_file_name %></span>
                </div>
                <pre class="text-xs bg-gray-900 text-gray-100 p-3 rounded overflow-x-auto max-h-[32rem]"><%= @preview %></pre>
              <% else %>
                <p class="text-sm text-gray-500">Select a file from logs or analytics to preview.</p>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp load_artifacts(socket, context_name) do
    case AnalyzerBridge.get_context_artifacts(context_name) do
      {:ok, bundle} ->
        logs_files = list_artifact_files(bundle[:logs_path])
        analytics_files = list_artifact_files(bundle[:analytics_path])

        socket
        |> assign(:bundle, bundle)
        |> assign(:logs_files, logs_files)
        |> assign(:analytics_files, analytics_files)

      {:error, reason} ->
        assign(socket, :error, "Unable to load artifact metadata: #{inspect(reason)}")
    end
  end

  defp list_artifact_files(nil), do: []

  defp list_artifact_files(root_path) do
    root = Path.expand(root_path)

    if File.dir?(root) do
      root
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.sort()
      |> Enum.take(@max_files_per_group)
      |> Enum.with_index(1)
      |> Enum.map(fn {path, id} ->
        stat = File.stat!(path)

        %{
          id: id,
          path: path,
          rel_path: Path.relative_to(path, root),
          size: stat.size
        }
      end)
    else
      []
    end
  end

  defp find_file("logs", id, %{logs_files: files}), do: find_by_id(files, id)
  defp find_file("analytics", id, %{analytics_files: files}), do: find_by_id(files, id)
  defp find_file(_group, _id, _assigns), do: {:error, :not_found}

  defp find_by_id(files, id) do
    case Enum.find(files, &(&1.id == id)) do
      nil -> {:error, :not_found}
      file -> {:ok, file}
    end
  end

  defp read_preview(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, io} ->
        data = IO.binread(io, @max_preview_bytes)
        :ok = File.close(io)

        case data do
          :eof ->
            {:ok, ""}

          binary when is_binary(binary) ->
            preview = if String.valid?(binary), do: binary, else: inspect(binary)
            {:ok, preview}

          other ->
            {:error, other}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_bytes(size) when size < 1024, do: "#{size} B"
  defp format_bytes(size) when size < 1024 * 1024, do: "#{Float.round(size / 1024, 1)} KB"
  defp format_bytes(size), do: "#{Float.round(size / (1024 * 1024), 1)} MB"
end
