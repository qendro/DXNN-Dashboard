defmodule DxnnAnalyzerWeb.S3ExplorerLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.AWS.S3Explorer

  @download_ttl_ms :timer.minutes(30)
  @download_staging_dir "/app/data/s3_downloads"

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:bucket, "dxnn-checkpoints")
      |> assign(:current_path, "")
      |> assign(:items, [])
      |> assign(:breadcrumbs, [])
      |> assign(:loading, false)
      |> assign(:selected_items, MapSet.new())
      |> assign(:show_delete_modal, false)
      |> assign(:deleting, false)
      |> assign(:downloading, false)
      |> assign(:download_progress, "")

    {:ok, socket}
  end

  @impl true
  def handle_event("load_bucket", _, socket) do
    load_path(socket, "")
  end

  def handle_event("navigate", %{"path" => path}, socket) do
    load_path(socket, path)
  end

  def handle_event("toggle_select", %{"key" => key}, socket) do
    selected = socket.assigns.selected_items

    new_selected =
      if MapSet.member?(selected, key) do
        MapSet.delete(selected, key)
      else
        MapSet.put(selected, key)
      end

    {:noreply, assign(socket, :selected_items, new_selected)}
  end

  def handle_event("select_all", _, socket) do
    all_keys = Enum.map(socket.assigns.items, & &1.key) |> MapSet.new()
    {:noreply, assign(socket, :selected_items, all_keys)}
  end

  def handle_event("deselect_all", _, socket) do
    {:noreply, assign(socket, :selected_items, MapSet.new())}
  end

  def handle_event("show_delete_modal", _, socket) do
    if MapSet.size(socket.assigns.selected_items) > 0 do
      {:noreply, assign(socket, :show_delete_modal, true)}
    else
      {:noreply, put_flash(socket, :error, "No items selected")}
    end
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :show_delete_modal, false)}
  end

  def handle_event("confirm_delete", _, socket) do
    socket = assign(socket, deleting: true, show_delete_modal: false)

    selected_list = MapSet.to_list(socket.assigns.selected_items)

    case S3Explorer.delete_objects(socket.assigns.bucket, selected_list) do
      {:ok, _} ->
        socket =
          socket
          |> assign(deleting: false, selected_items: MapSet.new())
          |> put_flash(:info, "Successfully deleted #{length(selected_list)} item(s)")

        # Reload current path
        load_path(socket, socket.assigns.current_path)

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:deleting, false)
         |> put_flash(:error, "Delete failed: #{error}")}
    end
  end

  def handle_event("download_selected", _, socket) do
    if MapSet.size(socket.assigns.selected_items) == 0 do
      {:noreply, put_flash(socket, :error, "No items selected")}
    else
      selected_list = MapSet.to_list(socket.assigns.selected_items)

      # Keep direct download for a single file; use ZIP archives for folders or multi-select.
      if length(selected_list) == 1 and not String.ends_with?(hd(selected_list), "/") do
        [key] = selected_list

        case S3Explorer.generate_download_url(socket.assigns.bucket, key) do
          {:ok, url} ->
            {:noreply,
             push_event(socket, "download_file", %{url: url, filename: Path.basename(key)})}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, "Failed to generate download URL: #{error}")}
        end
      else
        parent = self()
        bucket = socket.assigns.bucket
        current_path = socket.assigns.current_path
        selected_count = length(selected_list)

        Task.start(fn ->
          result = S3Explorer.build_download_archive(bucket, selected_list, current_path)
          send(parent, {:download_archive_ready, result, selected_count})
        end)

        {:noreply,
         socket
         |> assign(:downloading, true)
         |> assign(:download_progress, "Preparing ZIP archive...")}
      end
    end
  end

  def handle_event("change_bucket", %{"bucket" => bucket}, socket) do
    socket =
      socket
      |> assign(:bucket, bucket)
      |> assign(:current_path, "")
      |> assign(:items, [])
      |> assign(:breadcrumbs, [])
      |> assign(:selected_items, MapSet.new())

    {:noreply, socket}
  end

  defp load_path(socket, path) do
    socket = assign(socket, loading: true)

    case S3Explorer.list_objects(socket.assigns.bucket, path) do
      {:ok, items} ->
        breadcrumbs = build_breadcrumbs(path)

        {:noreply,
         socket
         |> assign(items: items, current_path: path, breadcrumbs: breadcrumbs, loading: false)
         |> assign(:selected_items, MapSet.new())}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> put_flash(:error, "Failed to load: #{error}")}
    end
  end

  defp build_breadcrumbs(""), do: []

  defp build_breadcrumbs(path) do
    parts = String.split(path, "/", trim: true)

    Enum.with_index(parts)
    |> Enum.map(fn {part, idx} ->
      path = Enum.take(parts, idx + 1) |> Enum.join("/") |> Kernel.<>("/")
      %{name: part, path: path}
    end)
  end

  defp format_size(size) when size < 1024, do: "#{size} B"
  defp format_size(size) when size < 1024 * 1024, do: "#{Float.round(size / 1024, 2)} KB"

  defp format_size(size) when size < 1024 * 1024 * 1024,
    do: "#{Float.round(size / (1024 * 1024), 2)} MB"

  defp format_size(size), do: "#{Float.round(size / (1024 * 1024 * 1024), 2)} GB"

  @impl true
  def handle_info({:download_archive_ready, {:ok, archive}, selected_count}, socket) do
    case stage_archive_for_http_download(archive) do
      {:ok, staged} ->
        Process.send_after(self(), {:cleanup_download_file, staged.path}, @download_ttl_ms)

        download_url = ~p"/s3-explorer/download/#{staged.token}/#{staged.filename}"

        {:noreply,
         socket
         |> assign(:downloading, false)
         |> assign(:download_progress, "")
         |> put_flash(:info, "Prepared #{selected_count} item(s) for download")
         |> push_event("download_file", %{url: download_url, filename: staged.filename})}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:downloading, false)
         |> assign(:download_progress, "")
         |> put_flash(:error, "Download failed: #{error}")}
    end
  end

  def handle_info({:download_archive_ready, {:error, error}, _selected_count}, socket) do
    {:noreply,
     socket
     |> assign(:downloading, false)
     |> assign(:download_progress, "")
     |> put_flash(:error, "Download failed: #{error}")}
  end

  def handle_info({:cleanup_download_file, path}, socket) do
    File.rm_rf(path)
    {:noreply, socket}
  end

  defp stage_archive_for_http_download(%{
         archive_path: archive_path,
         archive_name: archive_name,
         cleanup_path: cleanup_path
       }) do
    with :ok <- File.mkdir_p(@download_staging_dir),
         token <- generate_download_token(),
         filename <- sanitize_filename(archive_name),
         staged_path <- Path.join(@download_staging_dir, "#{token}_#{filename}"),
         :ok <- move_or_copy_file(archive_path, staged_path) do
      File.rm_rf(cleanup_path)
      {:ok, %{token: token, filename: filename, path: staged_path}}
    else
      {:error, reason} ->
        File.rm_rf(cleanup_path)
        {:error, "Failed to stage archive: #{inspect(reason)}"}
    end
  end

  defp move_or_copy_file(from, to) do
    case File.rename(from, to) do
      :ok ->
        :ok

      {:error, _} ->
        File.cp(from, to)
    end
  end

  defp generate_download_token do
    :crypto.strong_rand_bytes(12)
    |> Base.url_encode64(padding: false)
  end

  defp sanitize_filename(filename) do
    filename
    |> Path.basename()
    |> String.replace(~r/[^A-Za-z0-9._-]/, "_")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50" phx-hook="FileDownloader" id="s3-explorer">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Header -->
        <div class="mb-8 flex justify-between items-center">
          <div>
            <h1 class="text-3xl font-bold text-gray-900">S3 Explorer</h1>
            <p class="mt-2 text-gray-600">Browse, download, and manage S3 objects</p>
          </div>
          <.link
            navigate="/"
            class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition"
          >
            ← Back to Dashboard
          </.link>
        </div>
        <!-- Bucket Selector & Actions -->
        <div class="bg-white shadow rounded-lg p-6 mb-6">
          <div class="flex flex-wrap gap-4 items-center justify-between">
            <div class="flex items-center gap-4">
              <label class="text-sm font-medium text-gray-700">Bucket:</label>
              <select
                phx-change="change_bucket"
                name="bucket"
                class="border border-gray-300 rounded-md px-3 py-2 text-sm"
              >
                <option value="dxnn-checkpoints" selected={@bucket == "dxnn-checkpoints"}>
                  dxnn-checkpoints
                </option>
                <option value="dxnn-backups" selected={@bucket == "dxnn-backups"}>
                  dxnn-backups
                </option>
              </select>

              <button
                phx-click="load_bucket"
                class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition text-sm"
                disabled={@loading}
              >
                <%= if @loading do %>
                  ⏳
                <% else %>
                  🔄 Refresh
                <% end %>
              </button>
            </div>

            <div class="flex gap-2">
              <%= if MapSet.size(@selected_items) > 0 do %>
                <span class="text-sm text-gray-600 self-center">
                  <%= MapSet.size(@selected_items) %> selected
                </span>
                <button
                  phx-click="deselect_all"
                  class="bg-gray-500 text-white px-3 py-2 rounded-md hover:bg-gray-600 transition text-sm"
                >
                  Clear
                </button>
                <button
                  phx-click="download_selected"
                  class="bg-green-600 text-white px-3 py-2 rounded-md hover:bg-green-700 transition text-sm"
                  disabled={@downloading}
                >
                  <%= if @downloading do %>
                    ⏳ Downloading...
                  <% else %>
                    📥 Download
                  <% end %>
                </button>
                <button
                  phx-click="show_delete_modal"
                  class="bg-red-600 text-white px-3 py-2 rounded-md hover:bg-red-700 transition text-sm"
                  disabled={@deleting}
                >
                  🗑️ Delete
                </button>
              <% else %>
                <button
                  phx-click="select_all"
                  class="bg-gray-500 text-white px-3 py-2 rounded-md hover:bg-gray-600 transition text-sm"
                  disabled={length(@items) == 0}
                >
                  Select All
                </button>
              <% end %>
            </div>
          </div>

          <%= if @downloading and @download_progress != "" do %>
            <p class="mt-3 text-sm text-blue-700"><%= @download_progress %></p>
          <% end %>
        </div>
        <!-- Breadcrumbs -->
        <%= if length(@breadcrumbs) > 0 do %>
          <div class="bg-white shadow rounded-lg p-4 mb-6">
            <div class="flex items-center gap-2 text-sm">
              <button
                phx-click="navigate"
                phx-value-path=""
                class="text-blue-600 hover:text-blue-800 font-medium"
              >
                🏠 Root
              </button>
              <%= for crumb <- @breadcrumbs do %>
                <span class="text-gray-400">/</span>
                <button
                  phx-click="navigate"
                  phx-value-path={crumb.path}
                  class="text-blue-600 hover:text-blue-800"
                >
                  <%= crumb.name %>
                </button>
              <% end %>
            </div>
          </div>
        <% end %>
        <!-- Items List -->
        <div class="bg-white shadow rounded-lg overflow-hidden">
          <%= if length(@items) > 0 do %>
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-12">
                    Select
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Name
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Type
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Size
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Last Modified
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for item <- @items do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-6 py-4 whitespace-nowrap">
                      <input
                        type="checkbox"
                        phx-click="toggle_select"
                        phx-value-key={item.key}
                        checked={MapSet.member?(@selected_items, item.key)}
                        class="h-4 w-4 text-blue-600 rounded"
                      />
                    </td>
                    <td class="px-6 py-4">
                      <%= if item.type == :folder do %>
                        <button
                          phx-click="navigate"
                          phx-value-path={item.key}
                          class="text-blue-600 hover:text-blue-800 font-medium flex items-center gap-2"
                        >
                          📁 <%= item.name %>
                        </button>
                      <% else %>
                        <span class="flex items-center gap-2">
                          📄 <%= item.name %>
                        </span>
                      <% end %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= if item.type == :folder, do: "Folder", else: "File" %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= if item.size, do: format_size(item.size), else: "-" %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= if item.last_modified do %>
                        <%= Calendar.strftime(item.last_modified, "%Y-%m-%d %H:%M:%S") %>
                      <% else %>
                        -
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% else %>
            <div class="text-center py-12 text-gray-500">
              <%= if @loading do %>
                <div class="text-lg">⏳ Loading...</div>
              <% else %>
                <div class="text-lg">📂 Empty folder</div>
                <p class="text-sm mt-2">No objects found in this location</p>
              <% end %>
            </div>
          <% end %>
        </div>
        <!-- Info Box -->
        <div class="mt-6 bg-blue-50 border border-blue-200 rounded-lg p-4">
          <h3 class="font-medium text-blue-900 mb-2">S3 Explorer Features</h3>
          <ul class="text-blue-800 text-sm space-y-1">
            <li>• Browse S3 buckets and folders</li>
            <li>• Select multiple files/folders for batch operations</li>
            <li>• Download single files directly to your browser</li>
            <li>• Download folders and multi-selects as ZIP archives</li>
            <li>• Delete files and folders (with confirmation)</li>
            <li>• Navigate using breadcrumbs</li>
          </ul>
          <div class="mt-3 p-3 bg-yellow-50 border border-yellow-200 rounded">
            <p class="text-yellow-800 text-sm">
              <strong>Note:</strong>
              Folder and multi-item downloads are packaged into a ZIP before download.
              Large selections can take time while files are fetched from S3.
            </p>
          </div>
        </div>
      </div>
      <!-- Delete Confirmation Modal -->
      <%= if @show_delete_modal do %>
        <div class="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50">
          <div class="relative top-20 mx-auto p-5 border w-96 shadow-lg rounded-md bg-white">
            <div class="mt-3 text-center">
              <div class="mx-auto flex items-center justify-center h-12 w-12 rounded-full bg-red-100">
                <span class="text-2xl">⚠️</span>
              </div>
              <h3 class="text-lg leading-6 font-medium text-gray-900 mt-4">Delete Confirmation</h3>
              <div class="mt-2 px-7 py-3">
                <p class="text-sm text-gray-500">
                  Are you sure you want to delete <%= MapSet.size(@selected_items) %> item(s)?
                  This action cannot be undone.
                </p>
              </div>
              <div class="flex gap-3 px-4 py-3">
                <button
                  phx-click="cancel_delete"
                  class="flex-1 bg-gray-300 text-gray-700 px-4 py-2 rounded-md hover:bg-gray-400 transition"
                >
                  Cancel
                </button>
                <button
                  phx-click="confirm_delete"
                  class="flex-1 bg-red-600 text-white px-4 py-2 rounded-md hover:bg-red-700 transition"
                >
                  Delete
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
