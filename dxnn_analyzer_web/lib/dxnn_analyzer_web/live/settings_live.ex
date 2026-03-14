defmodule DxnnAnalyzerWeb.SettingsLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.{AnalyzerBridge, RunBundleResolver}

  @impl true
  def mount(_params, _session, socket) do
    auto_download_path = AnalyzerBridge.get_s3_auto_download_path()
    saved_copy_destination = load_saved_copy_destination()
    
    socket =
      socket
      |> assign(:experiments, [])
      |> assign(:show_add_modal, false)
      |> assign(:show_create_modal, false)
      |> assign(:show_browser, false)
      |> assign(:current_path, "/app/Documents")
      |> assign(:directories, [])
      |> assign(:browser_mode, :add)
      |> assign(:s3_auto_download_path, auto_download_path)
      |> assign(:s3_path_edit_mode, false)
      |> assign(:copy_source_path, "")
      |> assign(:copy_destination_path, saved_copy_destination || "/app/Documents/DXNN_Main/DXNN-Dashboard/Databases/Local_v1")
      |> assign(:copying, false)
      |> assign(:copy_result, nil)
      |> assign(:copy_validation_error, nil)
      |> assign(:show_copy_browser, false)
      |> assign(:copy_browser_mode, :source)
      |> assign(:copy_browse_path, "/app/Documents/DXNN_Main")
      |> assign(:copy_browse_folders, [])
      |> load_experiments()

    {:ok, socket}
  end

  @impl true
  def handle_event("load_all_experiments", _, socket) do
    experiments = socket.assigns.experiments
    unloaded_experiments = Enum.filter(experiments, fn exp -> !exp.loaded end)
    
    if Enum.empty?(unloaded_experiments) do
      {:noreply, put_flash(socket, :info, "All experiments are already loaded")}
    else
      results =
        Enum.map(unloaded_experiments, fn exp ->
          case load_experiment_context(exp) do
            {:ok, _} -> {:ok, exp.name}
            {:error, reason} -> {:error, exp.name, reason}
          end
        end)
      
      success_count = Enum.count(results, fn r -> match?({:ok, _}, r) end)
      total_count = length(unloaded_experiments)
      
      socket =
        socket
        |> load_experiments()
        |> maybe_put_load_all_error(results)
        |> put_flash(:info, "Loaded #{success_count} of #{total_count} experiments")
      
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("show_add_modal", _, socket) do
    {:noreply, assign(socket, :show_add_modal, true)}
  end

  @impl true
  def handle_event("show_browser", %{"mode" => mode}, socket) do
    browser_mode =
      case mode do
        "create" -> :create
        _ -> :add
      end

    current_path = socket.assigns.current_path
    
    socket =
      socket
      |> assign(:show_browser, true)
      |> assign(:browser_mode, browser_mode)
      |> load_directories(current_path)
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("close_browser", _, socket) do
    {:noreply, assign(socket, :show_browser, false)}
  end

  @impl true
  def handle_event("navigate_to", %{"path" => path}, socket) do
    socket = load_directories(socket, path)
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_folder", %{"path" => path, "name" => name}, socket) do
    mode = socket.assigns.browser_mode
    
    case mode do
      :add ->
        case AnalyzerBridge.add_experiment_to_settings(name, path) do
          :ok ->
            socket =
              socket
              |> load_experiments()
              |> assign(:show_browser, false)
              |> put_flash(:info, "Experiment '#{name}' added")
            {:noreply, socket}
          
          {:error, :already_exists} ->
            {:noreply, put_flash(socket, :error, "Experiment already exists")}
          
          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
        end
      
      :create ->
        case AnalyzerBridge.create_experiment_in_settings(name, path) do
          :ok ->
            socket =
              socket
              |> load_experiments()
              |> assign(:show_browser, false)
              |> put_flash(:info, "Experiment '#{name}' created")
            {:noreply, socket}
          
          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("close_add_modal", _, socket) do
    {:noreply, assign(socket, :show_add_modal, false)}
  end

  @impl true
  def handle_event("show_create_modal", _, socket) do
    {:noreply, assign(socket, :show_create_modal, true)}
  end

  @impl true
  def handle_event("close_create_modal", _, socket) do
    {:noreply, assign(socket, :show_create_modal, false)}
  end

  @impl true
  def handle_event("add_experiment", %{"name" => name, "path" => path}, socket) do
    case AnalyzerBridge.add_experiment_to_settings(name, path) do
      :ok ->
        socket =
          socket
          |> load_experiments()
          |> assign(:show_add_modal, false)
          |> put_flash(:info, "Experiment '#{name}' added")
        {:noreply, socket}
      
      {:error, :already_exists} ->
        {:noreply, put_flash(socket, :error, "Experiment already exists")}
      
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("create_experiment", %{"name" => name, "path" => path}, socket) do
    case AnalyzerBridge.create_experiment_in_settings(name, path) do
      :ok ->
        socket =
          socket
          |> load_experiments()
          |> assign(:show_create_modal, false)
          |> put_flash(:info, "Experiment '#{name}' created")
        {:noreply, socket}
      
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("load_experiment", %{"name" => name}, socket) do
    experiments = socket.assigns.experiments
    experiment = Enum.find(experiments, fn e -> e.name == name end)
    
    if experiment do
      case load_experiment_context(experiment) do
        {:ok, :loaded} ->
          socket =
            socket
            |> load_experiments()
            |> put_flash(:info, "Experiment '#{name}' loaded successfully")

          {:noreply, socket}

        {:ok, :empty} ->
          socket =
            socket
            |> load_experiments()
            |> put_flash(:info, "Experiment '#{name}' loaded (empty)")

          {:noreply, socket}

        {:error, reason} ->
          socket =
            socket
            |> load_experiments()
            |> put_flash(:error, "Failed to load '#{name}': #{format_load_error(reason)}")

          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "Experiment not found")}
    end
  end

  @impl true
  def handle_event("remove_experiment", %{"name" => name}, socket) do
    case AnalyzerBridge.remove_experiment_from_settings(name) do
      :ok ->
        socket =
          socket
          |> load_experiments()
          |> put_flash(:info, "Experiment '#{name}' removed")
        {:noreply, socket}
      
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("save_experiment", %{"name" => name}, socket) do
    experiments = socket.assigns.experiments
    experiment = Enum.find(experiments, fn e -> e.name == name end)
    
    if experiment do
      IO.puts("=== Saving experiment ===")
      IO.puts("Name: #{name}")
      IO.puts("Path: #{experiment.path}")
      
      case AnalyzerBridge.save_experiment(name, experiment.path) do
        {:ok, saved_path} ->
          IO.puts("Save successful to: #{inspect(saved_path)}")
          socket =
            socket
            |> put_flash(:info, "Experiment '#{name}' saved to disk successfully")
          {:noreply, socket}
        
        {:error, reason} ->
          IO.puts("Save failed: #{inspect(reason)}")
          {:noreply, put_flash(socket, :error, "Failed to save '#{name}': #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Experiment not found")}
    end
  end

  @impl true
  def handle_event("toggle_s3_path_edit", _, socket) do
    {:noreply, assign(socket, :s3_path_edit_mode, !socket.assigns.s3_path_edit_mode)}
  end

  @impl true
  def handle_event("save_s3_path", %{"path" => path}, socket) do
    case AnalyzerBridge.set_s3_auto_download_path(path) do
      :ok ->
        socket =
          socket
          |> assign(:s3_auto_download_path, path)
          |> assign(:s3_path_edit_mode, false)
          |> put_flash(:info, "S3 auto-download path updated successfully")
        {:noreply, socket}
      
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update path: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("cancel_s3_path_edit", _, socket) do
    {:noreply, assign(socket, :s3_path_edit_mode, false)}
  end

  # Copy Experiment handlers
  @impl true
  def handle_event("validate_copy_source", %{"source_path" => path}, socket) do
    validation_error = validate_copy_source_path(path)
    {:noreply, assign(socket, copy_source_path: path, copy_validation_error: validation_error)}
  end

  @impl true
  def handle_event("update_copy_destination", %{"destination_path" => path}, socket) do
    {:noreply, assign(socket, copy_destination_path: path)}
  end

  @impl true
  def handle_event("browse_copy_source", _, socket) do
    folders = list_copy_folders(socket.assigns.copy_browse_path)
    
    socket =
      socket
      |> assign(:show_copy_browser, true)
      |> assign(:copy_browser_mode, :source)
      |> assign(:copy_browse_folders, folders)

    {:noreply, socket}
  end

  @impl true
  def handle_event("browse_copy_destination", _, socket) do
    folders = list_copy_folders(socket.assigns.copy_browse_path)
    
    socket =
      socket
      |> assign(:show_copy_browser, true)
      |> assign(:copy_browser_mode, :destination)
      |> assign(:copy_browse_folders, folders)

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_copy_browser", _, socket) do
    {:noreply, assign(socket, show_copy_browser: false)}
  end

  @impl true
  def handle_event("navigate_copy_to", %{"path" => path}, socket) do
    folders = list_copy_folders(path)
    {:noreply, assign(socket, copy_browse_path: path, copy_browse_folders: folders)}
  end

  @impl true
  def handle_event("select_copy_folder", %{"path" => path}, socket) do
    if socket.assigns.copy_browser_mode == :source do
      validation_error = validate_copy_source_path(path)
      
      socket =
        socket
        |> assign(:copy_source_path, path)
        |> assign(:copy_validation_error, validation_error)
        |> assign(:show_copy_browser, false)
      
      {:noreply, socket}
    else
      socket =
        socket
        |> assign(:copy_destination_path, path)
        |> assign(:show_copy_browser, false)
      
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("copy_experiment", _, socket) do
    source = String.trim(socket.assigns.copy_source_path)
    destination = String.trim(socket.assigns.copy_destination_path)

    with :ok <- validate_copy_inputs(source, destination, socket.assigns.copy_validation_error) do
      socket = assign(socket, copying: true, copy_result: nil)
      
      parent = self()
      Task.start(fn ->
        result = DxnnAnalyzerWeb.ExperimentCopier.copy_experiment(source, destination)
        send(parent, {:copy_complete, result})
      end)
      
      {:noreply, socket}
    else
      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def handle_event("stop_propagation", _, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:copy_complete, {:ok, new_path}}, socket) do
    save_copy_destination(socket.assigns.copy_destination_path)
    
    socket =
      socket
      |> assign(copying: false, copy_result: {:ok, new_path})
      |> put_flash(:info, "Experiment copied successfully to: #{new_path}")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:copy_complete, {:error, reason}}, socket) do
    socket =
      socket
      |> assign(copying: false, copy_result: {:error, reason})
      |> put_flash(:error, "Copy failed: #{reason}")

    {:noreply, socket}
  end

  defp load_experiments(socket) do
    experiments = AnalyzerBridge.get_experiments_from_settings()
    
    # Check which experiments are currently loaded
    loaded_contexts = try do
      AnalyzerBridge.list_contexts()
    rescue
      _ -> []
    catch
      :exit, _ -> []
    end
    
    loaded_names = Enum.map(loaded_contexts, & &1.name) |> MapSet.new()
    
    # Enhance experiments with load status
    experiments_with_status = Enum.map(experiments, fn exp ->
      is_loaded = MapSet.member?(loaded_names, exp.name)
      
      # Check if it's an empty experiment (no agents)
      is_empty = if is_loaded do
        context = Enum.find(loaded_contexts, fn c -> c.name == exp.name end)
        context &&
          context.agent_count == 0 &&
          context.population_count == 0 &&
          context.specie_count == 0
      else
        false
      end
      
      Map.merge(exp, %{
        loaded: is_loaded,
        empty: is_empty
      })
    end)
    
    assign(socket, :experiments, experiments_with_status)
  end

  defp load_directories(socket, path) do
    case File.ls(path) do
      {:ok, entries} ->
        directories = entries
        |> Enum.filter(fn entry ->
          full_path = Path.join(path, entry)
          File.dir?(full_path) && !String.starts_with?(entry, ".")
        end)
        |> Enum.sort()
        |> Enum.map(fn dir ->
          full_path = Path.join(path, dir)
          loadable_run = loadable_run_path?(full_path)
          %{name: dir, path: full_path, loadable_run: loadable_run}
        end)
        
        parent_path = Path.dirname(path)
        
        socket
        |> assign(:current_path, path)
        |> assign(:parent_path, parent_path)
        |> assign(:directories, directories)
      
      {:error, _reason} ->
        socket
        |> assign(:directories, [])
        |> put_flash(:error, "Cannot read directory: #{path}")
    end
  end

  defp loadable_run_path?(path) do
    case RunBundleResolver.resolve(path, allow_single_nested: true) do
      {:ok, _bundle} -> true
      {:error, _reason} -> false
    end
  end

  defp load_experiment_context(%{name: name, path: path}) do
    case AnalyzerBridge.load_context(path, name) do
      {:ok, _} -> {:ok, :loaded}
      {:error, {:already_loaded, _}} -> {:ok, :loaded}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_put_load_all_error(socket, results) do
    failures =
      results
      |> Enum.filter(fn
        {:error, _, _} -> true
        _ -> false
      end)
      |> Enum.take(3)

    case failures do
      [] ->
        socket

      failed ->
        sample =
          Enum.map_join(failed, "; ", fn {:error, exp_name, reason} ->
            "#{exp_name}: #{format_load_error(reason)}"
          end)

        put_flash(socket, :error, "Some experiments failed to load: #{sample}")
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
    "no Mnesia files found at the configured path"
  end

  defp format_load_error({:schema_node_mismatch, owner_nodes, current_node}) do
    "Mnesia schema belongs to #{inspect(owner_nodes)} but dashboard node is #{inspect(current_node)}"
  end

  defp format_load_error(reason), do: inspect(reason)

  # Copy Experiment helper functions
  defp validate_copy_source_path(path) do
    trimmed = String.trim(path)
    
    cond do
      trimmed == "" -> nil
      not File.exists?(trimmed) -> "Source path does not exist"
      not File.dir?(trimmed) -> "Source path must be a directory"
      not has_copy_required_files?(trimmed) -> "Missing required files (Mnesia.nonode@nohost/, logs/, config.erl, exp_runner.erl)"
      true -> nil
    end
  end

  defp validate_copy_inputs(source, destination, validation_error) do
    cond do
      source == "" -> {:error, "Please enter a source path"}
      destination == "" -> {:error, "Please enter a destination path"}
      validation_error != nil -> {:error, validation_error}
      true -> :ok
    end
  end

  defp has_copy_required_files?(path) do
    required = [
      {"Mnesia.nonode@nohost", &File.dir?/1},
      {"logs", &File.dir?/1},
      {"config.erl", &File.exists?/1},
      {"exp_runner.erl", &File.exists?/1}
    ]

    Enum.all?(required, fn {name, check_fn} ->
      path |> Path.join(name) |> check_fn.()
    end)
  end

  defp list_copy_folders(path) do
    case File.ls(path) do
      {:ok, items} ->
        items
        |> Enum.map(&Path.join(path, &1))
        |> Enum.filter(&File.dir?/1)
        |> Enum.map(fn full_path ->
          %{
            name: Path.basename(full_path),
            path: full_path,
            has_required: has_copy_required_files?(full_path)
          }
        end)
        |> Enum.sort_by(& &1.name)
      
      {:error, _} ->
        []
    end
  end

  defp load_saved_copy_destination do
    settings_file = copy_settings_file_path()
    
    with {:ok, content} <- File.read(settings_file),
         {:ok, %{"destination_path" => path}} <- Jason.decode(content) do
      path
    else
      _ -> nil
    end
  end

  defp save_copy_destination(path) do
    settings_file = copy_settings_file_path()
    
    settings_file
    |> Path.dirname()
    |> File.mkdir_p()
    
    content = Jason.encode!(%{destination_path: path}, pretty: true)
    File.write(settings_file, content)
  end

  defp copy_settings_file_path do
    Path.join([File.cwd!(), "data", "copy_experiment_settings.json"])
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="mb-6">
          <.link navigate={~p"/"} class="text-blue-600 hover:text-blue-800 text-sm mb-2 inline-block">
            ← Back to Dashboard
          </.link>
          <h1 class="text-3xl font-bold text-gray-900">Manage Experiments</h1>
          <p class="mt-2 text-gray-600">Add existing experiments or create new ones</p>
        </div>

        <div class="bg-white shadow rounded-lg p-6">
          <div class="flex justify-between items-center mb-6">
            <h2 class="text-xl font-semibold">Experiments</h2>
            <div class="flex gap-2">
              <button
                phx-click="load_all_experiments"
                class="bg-purple-600 text-white px-4 py-2 rounded-md hover:bg-purple-700 transition border border-purple-700 shadow-sm"
              >
                📂 Load All
              </button>
              <button
                phx-click="show_add_modal"
                class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition"
              >
                + Add Existing
              </button>
              <button
                phx-click="show_create_modal"
                class="bg-green-600 text-white px-4 py-2 rounded-md hover:bg-green-700 transition"
              >
                + Create New
              </button>
            </div>
          </div>
          
          <%= if Enum.empty?(@experiments) do %>
            <p class="text-gray-500 text-center py-8">No experiments configured. Add an existing experiment or create a new one.</p>
          <% else %>
            <div class="space-y-3">
              <%= for exp <- @experiments do %>
                <div class="flex items-center justify-between p-4 border border-gray-200 rounded-lg hover:bg-gray-50">
                  <div class="flex-1 min-w-0">
                    <div class="flex items-center gap-3">
                      <div class="font-semibold text-lg"><%= exp.name %></div>
                      <%= if exp.loaded do %>
                        <%= if exp.empty do %>
                          <span class="inline-flex items-center bg-yellow-100 text-yellow-800 px-2 py-1 rounded text-xs font-medium">
                            ✓ Loaded (Empty)
                          </span>
                        <% else %>
                          <span class="inline-flex items-center bg-green-100 text-green-800 px-2 py-1 rounded text-xs font-medium">
                            ✓ Loaded
                          </span>
                        <% end %>
                      <% end %>
                    </div>
                    <div class="font-mono text-sm text-gray-600 mt-1 truncate" title={exp.path}>
                      <%= exp.path %>
                    </div>
                  </div>
                  <div class="flex gap-2 ml-4">
                    <%= if !exp.loaded do %>
                      <button
                        phx-click="load_experiment"
                        phx-value-name={exp.name}
                        class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition text-sm"
                      >
                        Load
                      </button>
                    <% else %>
                      <button
                        phx-click="save_experiment"
                        phx-value-name={exp.name}
                        class="bg-green-600 text-white px-4 py-2 rounded-md hover:bg-green-700 transition text-sm"
                        title="Save changes to disk"
                      >
                        💾 Save
                      </button>
                    <% end %>
                    <button
                      phx-click="remove_experiment"
                      phx-value-name={exp.name}
                      class="text-red-600 hover:text-red-800 px-3 py-2 text-sm font-medium"
                    >
                      Remove
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- S3 Auto-Download Settings -->
        <div class="bg-white shadow rounded-lg p-6 mt-6">
          <div class="flex justify-between items-center mb-4">
            <div>
              <h2 class="text-xl font-semibold">S3 Auto-Download Settings</h2>
              <p class="text-sm text-gray-600 mt-1">Configure where S3 files are saved when using "Save to Local" button</p>
            </div>
          </div>
          
          <%= if @s3_path_edit_mode do %>
            <form phx-submit="save_s3_path" class="space-y-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">
                  Local Download Path
                </label>
                <input
                  type="text"
                  name="path"
                  value={@s3_auto_download_path}
                  placeholder="/app/Documents/DXNN_Main/DXNN-Dashboard/Databases/AWS_v1"
                  class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-purple-500 font-mono text-sm"
                  required
                  autofocus
                />
                <p class="text-xs text-gray-500 mt-1">
                  Files will be downloaded directly to this path (no ZIP extraction needed)
                </p>
              </div>
              <div class="flex gap-2">
                <button
                  type="button"
                  phx-click="cancel_s3_path_edit"
                  class="bg-gray-300 text-gray-700 px-4 py-2 rounded-md hover:bg-gray-400 transition"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="bg-purple-600 text-white px-4 py-2 rounded-md hover:bg-purple-700 transition"
                >
                  Save Path
                </button>
              </div>
            </form>
          <% else %>
            <div class="flex items-center justify-between p-4 border border-gray-200 rounded-lg bg-gray-50">
              <div class="flex-1 min-w-0">
                <div class="text-sm font-medium text-gray-700 mb-1">Current Path:</div>
                <div class="font-mono text-sm text-gray-900 truncate" title={@s3_auto_download_path}>
                  <%= @s3_auto_download_path %>
                </div>
              </div>
              <button
                phx-click="toggle_s3_path_edit"
                class="ml-4 bg-purple-600 text-white px-4 py-2 rounded-md hover:bg-purple-700 transition text-sm"
              >
                ✏️ Edit
              </button>
            </div>
            <div class="mt-3 p-3 bg-blue-50 border border-blue-200 rounded">
              <p class="text-blue-800 text-sm">
                <strong>Note:</strong> This path is used by the "💾 Save to Local" button in S3 Explorer.
                Files are downloaded directly without creating ZIP archives.
              </p>
            </div>
          <% end %>
        </div>

        <!-- Copy Experiment Section -->
        <div class="bg-white shadow rounded-lg p-6 mt-6">
          <div class="mb-4">
            <h2 class="text-xl font-semibold">Copy Experiment</h2>
            <p class="text-sm text-gray-600 mt-1">Copy an active DXNN-Trader-v2 experiment to the dashboard database</p>
          </div>

          <form phx-submit="copy_experiment" class="space-y-4">
            <!-- Source Path -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">
                Source Path (DXNN-Trader-v2 Directory)
              </label>
              <div class="flex gap-2">
                <input
                  type="text"
                  name="source_path"
                  value={@copy_source_path}
                  phx-change="validate_copy_source"
                  placeholder="/Users/qendrim/Documents/DXNN_Main/DXNN-Trader-v2"
                  class="flex-1 px-4 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent font-mono text-sm"
                  disabled={@copying}
                />
                <button
                  type="button"
                  phx-click="browse_copy_source"
                  disabled={@copying}
                  class="px-4 py-2 bg-gray-600 text-white rounded-md hover:bg-gray-700 transition disabled:bg-gray-400"
                >
                  📁 Browse
                </button>
              </div>
              <%= if @copy_validation_error do %>
                <p class="mt-2 text-sm text-red-600">
                  <%= @copy_validation_error %>
                </p>
              <% end %>
              <p class="mt-2 text-sm text-gray-500">
                Must contain: Mnesia.nonode@nohost/, logs/, config.erl, and exp_runner.erl
              </p>
            </div>

            <!-- Destination Path -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">
                Destination Directory
              </label>
              <div class="flex gap-2">
                <input
                  type="text"
                  name="destination_path"
                  value={@copy_destination_path}
                  phx-change="update_copy_destination"
                  class="flex-1 px-4 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent font-mono text-sm"
                  disabled={@copying}
                />
                <button
                  type="button"
                  phx-click="browse_copy_destination"
                  disabled={@copying}
                  class="px-4 py-2 bg-gray-600 text-white rounded-md hover:bg-gray-700 transition disabled:bg-gray-400"
                >
                  📁 Browse
                </button>
              </div>
              <p class="mt-2 text-sm text-gray-500">
                A timestamped folder will be created here
              </p>
            </div>

            <!-- Copy Button -->
            <div class="flex justify-end">
              <button
                type="submit"
                disabled={@copying || @copy_validation_error != nil || String.trim(@copy_source_path) == ""}
                class="bg-orange-600 text-white px-6 py-2 rounded-md hover:bg-orange-700 transition disabled:bg-gray-400 disabled:cursor-not-allowed flex items-center gap-2"
              >
                <%= if @copying do %>
                  <svg class="animate-spin h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  Copying...
                <% else %>
                  📋 Copy Experiment
                <% end %>
              </button>
            </div>
          </form>

          <!-- Copy Result -->
          <%= if @copy_result do %>
            <div class={"mt-4 p-4 rounded-md #{if match?({:ok, _}, @copy_result), do: "bg-green-50 border border-green-200", else: "bg-red-50 border border-red-200"}"}>
              <%= case @copy_result do %>
                <% {:ok, new_path} -> %>
                  <div class="flex items-start gap-3">
                    <span class="text-2xl">✅</span>
                    <div class="flex-1">
                      <h3 class="font-semibold text-green-900 mb-2">Copy Successful!</h3>
                      <p class="text-sm text-green-800 mb-2">Experiment copied to:</p>
                      <code class="block bg-green-100 text-green-900 px-3 py-2 rounded text-sm break-all">
                        <%= new_path %>
                      </code>
                    </div>
                  </div>
                <% {:error, reason} -> %>
                  <div class="flex items-start gap-3">
                    <span class="text-2xl">❌</span>
                    <div class="flex-1">
                      <h3 class="font-semibold text-red-900 mb-2">Copy Failed</h3>
                      <p class="text-sm text-red-800"><%= reason %></p>
                    </div>
                  </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- Copy Folder Browser Modal -->
        <%= if @show_copy_browser do %>
          <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50" phx-click="close_copy_browser">
            <div class="bg-white rounded-lg shadow-xl max-w-3xl w-full mx-4 max-h-[80vh] flex flex-col" phx-click="stop_propagation">
              <div class="flex justify-between items-center p-4 border-b">
                <h3 class="text-lg font-semibold">
                  <%= if @copy_browser_mode == :source, do: "Select Source Folder", else: "Select Destination Folder" %>
                </h3>
                <button phx-click="close_copy_browser" class="text-gray-500 hover:text-gray-700">
                  <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                  </svg>
                </button>
              </div>

              <div class="p-4 bg-gray-50 border-b">
                <div class="flex items-center gap-2 text-sm">
                  <span class="font-medium">Current:</span>
                  <code class="flex-1 bg-white px-3 py-1 rounded border"><%= @copy_browse_path %></code>
                  <%= if @copy_browse_path != "/app" do %>
                    <button
                      phx-click="navigate_copy_to"
                      phx-value-path={Path.dirname(@copy_browse_path)}
                      class="px-3 py-1 bg-gray-600 text-white rounded hover:bg-gray-700 text-sm"
                    >
                      ⬆️ Up
                    </button>
                  <% end %>
                </div>
              </div>

              <div class="flex-1 overflow-y-auto p-4">
                <%= if Enum.empty?(@copy_browse_folders) do %>
                  <p class="text-gray-500 text-center py-8">No folders found</p>
                <% else %>
                  <div class="space-y-2">
                    <%= for folder <- @copy_browse_folders do %>
                      <div class="flex items-center gap-2 p-3 border rounded hover:bg-gray-50">
                        <div class="flex-1 flex items-center gap-2">
                          <span class="text-2xl">📁</span>
                          <span class="font-medium"><%= folder.name %></span>
                          <%= if folder.has_required do %>
                            <span class="text-xs bg-green-100 text-green-700 px-2 py-0.5 rounded">✓ Valid</span>
                          <% end %>
                        </div>
                        <div class="flex gap-2">
                          <button
                            phx-click="navigate_copy_to"
                            phx-value-path={folder.path}
                            class="px-3 py-1 bg-blue-600 text-white rounded hover:bg-blue-700 text-sm"
                          >
                            Open
                          </button>
                          <button
                            phx-click="select_copy_folder"
                            phx-value-path={folder.path}
                            class="px-3 py-1 bg-green-600 text-white rounded hover:bg-green-700 text-sm"
                          >
                            Select
                          </button>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>

              <div class="p-4 border-t bg-gray-50">
                <button
                  phx-click="select_copy_folder"
                  phx-value-path={@copy_browse_path}
                  class="w-full px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700"
                >
                  Select Current Folder
                </button>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Add Existing Experiment Modal -->
        <%= if @show_add_modal do %>
          <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
            <div class="bg-white rounded-lg p-6 max-w-lg w-full mx-4">
              <h3 class="text-lg font-semibold mb-4">Add Existing Experiment</h3>
              <form phx-submit="add_experiment">
                <div class="mb-4">
                  <label class="block text-sm font-medium text-gray-700 mb-2">
                    Experiment Name
                  </label>
                  <input
                    type="text"
                    name="name"
                    placeholder="run_2026_03_10"
                    class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                    required
                    autofocus
                  />
                  <p class="text-xs text-gray-500 mt-1">
                    A friendly name for this experiment
                  </p>
                </div>
                <div class="mb-4">
                  <label class="block text-sm font-medium text-gray-700 mb-2">
                    Folder Path
                  </label>
                  <div class="flex gap-2">
                    <input
                      type="text"
                      name="path"
                      placeholder="/app/Documents/DXNN_Main/DXNN-Dashboard/Databases/AWS_v1/lineage_id/run_id"
                      class="flex-1 px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono text-sm"
                      required
                    />
                    <button
                      type="button"
                      phx-click="show_browser"
                      phx-value-mode="add"
                      class="bg-gray-600 text-white px-4 py-2 rounded-md hover:bg-gray-700 transition"
                    >
                      📁 Browse
                    </button>
                  </div>
                  <p class="text-xs text-gray-500 mt-1">
                    Full path to a run folder or direct Mnesia folder
                  </p>
                </div>
                <div class="flex gap-2">
                  <button
                    type="button"
                    phx-click="close_add_modal"
                    class="flex-1 bg-gray-300 text-gray-700 px-4 py-2 rounded-md hover:bg-gray-400 transition"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    class="flex-1 bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition"
                  >
                    Add
                  </button>
                </div>
              </form>
            </div>
          </div>
        <% end %>

        <!-- Create New Experiment Modal -->
        <%= if @show_create_modal do %>
          <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
            <div class="bg-white rounded-lg p-6 max-w-lg w-full mx-4">
              <h3 class="text-lg font-semibold mb-4">Create New Experiment</h3>
              <form phx-submit="create_experiment">
                <div class="mb-4">
                  <label class="block text-sm font-medium text-gray-700 mb-2">
                    Experiment Name
                  </label>
                  <input
                    type="text"
                    name="name"
                    placeholder="my_experiment"
                    class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-green-500"
                    required
                    autofocus
                  />
                  <p class="text-xs text-gray-500 mt-1">
                    Name for the new experiment
                  </p>
                </div>
                <div class="mb-4">
                  <label class="block text-sm font-medium text-gray-700 mb-2">
                    Folder Path
                  </label>
                  <div class="flex gap-2">
                    <input
                      type="text"
                      name="path"
                      placeholder="/app/Documents/Databases/my_experiment"
                      class="flex-1 px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-green-500 font-mono text-sm"
                      required
                    />
                    <button
                      type="button"
                      phx-click="show_browser"
                      phx-value-mode="create"
                      class="bg-gray-600 text-white px-4 py-2 rounded-md hover:bg-gray-700 transition"
                    >
                      📁 Browse
                    </button>
                  </div>
                  <p class="text-xs text-gray-500 mt-1">
                    Full path where the new experiment folder will be created
                  </p>
                </div>
                <div class="flex gap-2">
                  <button
                    type="button"
                    phx-click="close_create_modal"
                    class="flex-1 bg-gray-300 text-gray-700 px-4 py-2 rounded-md hover:bg-gray-400 transition"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    class="flex-1 bg-green-600 text-white px-4 py-2 rounded-md hover:bg-green-700 transition"
                  >
                    Create
                  </button>
                </div>
              </form>
            </div>
          </div>
        <% end %>

        <!-- Folder Browser Modal -->
        <%= if @show_browser do %>
          <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
            <div class="bg-white rounded-lg p-6 max-w-3xl w-full mx-4 max-h-[80vh] flex flex-col">
              <div class="flex justify-between items-center mb-4">
                <h3 class="text-lg font-semibold">Select Folder</h3>
                <button
                  phx-click="close_browser"
                  class="text-gray-500 hover:text-gray-700"
                >
                  ✕
                </button>
              </div>
              
              <div class="mb-4 flex items-center gap-2">
                <span class="text-sm text-gray-600">Current:</span>
                <code class="flex-1 bg-gray-100 px-3 py-2 rounded text-sm font-mono"><%= @current_path %></code>
                <%= if @current_path != "/" do %>
                  <button
                    phx-click="navigate_to"
                    phx-value-path={@parent_path}
                    class="bg-gray-500 text-white px-3 py-2 rounded hover:bg-gray-600 transition text-sm"
                  >
                    ⬆️ Up
                  </button>
                <% end %>
              </div>
              
              <div class="flex-1 overflow-y-auto border border-gray-200 rounded">
                <%= if Enum.empty?(@directories) do %>
                  <p class="text-gray-500 text-center py-8">No directories found</p>
                <% else %>
                  <div class="divide-y divide-gray-200">
                    <%= for dir <- @directories do %>
                      <div class="flex items-center justify-between p-3 hover:bg-gray-50">
                        <div class="flex items-center gap-3 flex-1 min-w-0">
                          <span class="text-2xl">📁</span>
                          <div class="flex-1 min-w-0">
                            <div class="font-medium truncate"><%= dir.name %></div>
                            <%= if dir.loadable_run do %>
                              <span class="text-xs text-green-600">✓ Loadable run bundle</span>
                            <% end %>
                          </div>
                        </div>
                        <div class="flex gap-2 ml-4">
                          <button
                            phx-click="navigate_to"
                            phx-value-path={dir.path}
                            class="bg-blue-500 text-white px-3 py-1 rounded hover:bg-blue-600 transition text-sm"
                          >
                            Open
                          </button>
                          <button
                            phx-click="select_folder"
                            phx-value-path={dir.path}
                            phx-value-name={dir.name}
                            class="bg-green-600 text-white px-3 py-1 rounded hover:bg-green-700 transition text-sm"
                          >
                            Select
                          </button>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
              
              <div class="mt-4 flex justify-end">
                <button
                  phx-click="close_browser"
                  class="bg-gray-300 text-gray-700 px-4 py-2 rounded-md hover:bg-gray-400 transition"
                >
                  Cancel
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
