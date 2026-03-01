defmodule DxnnAnalyzerWeb.SettingsLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.AnalyzerBridge

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:experiments, [])
      |> assign(:show_add_modal, false)
      |> assign(:show_create_modal, false)
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
      results = Enum.map(unloaded_experiments, fn exp ->
        # Check if the path exists and has Mnesia files
        mnesia_path = Path.join(exp.path, "Mnesia.nonode@nohost")
        
        has_mnesia_files = case File.ls(exp.path) do
          {:ok, files} ->
            direct_files = Enum.any?(files, fn f -> 
              String.ends_with?(f, ".DCD") or 
              String.ends_with?(f, ".DCL") or 
              String.ends_with?(f, ".DAT")
            end)
            
            subdir_files = case File.ls(mnesia_path) do
              {:ok, subfiles} ->
                Enum.any?(subfiles, fn f -> 
                  String.ends_with?(f, ".DCD") or 
                  String.ends_with?(f, ".DCL") or 
                  String.ends_with?(f, ".DAT")
                end)
              _ -> false
            end
            
            direct_files or subdir_files
          _ -> false
        end
        
        if has_mnesia_files do
          case AnalyzerBridge.load_context(exp.path, exp.name) do
            {:ok, _} -> {:ok, exp.name}
            {:error, {:already_loaded, _}} -> {:ok, exp.name}
            {:error, reason} -> {:error, exp.name, reason}
          end
        else
          case AnalyzerBridge.create_empty_experiment(exp.name) do
            {:ok, _} -> {:ok, exp.name}
            {:error, reason} -> {:error, exp.name, reason}
          end
        end
      end)
      
      success_count = Enum.count(results, fn r -> match?({:ok, _}, r) end)
      total_count = length(unloaded_experiments)
      
      socket =
        socket
        |> load_experiments()
        |> put_flash(:info, "Loaded #{success_count} of #{total_count} experiments")
      
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("show_add_modal", _, socket) do
    {:noreply, assign(socket, :show_add_modal, true)}
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
      # Check if the path exists and has Mnesia files
      # Check both the path itself and the Mnesia.nonode@nohost subdirectory
      mnesia_path = Path.join(experiment.path, "Mnesia.nonode@nohost")
      
      has_mnesia_files = case File.ls(experiment.path) do
        {:ok, files} ->
          # Check if files are directly in the path
          direct_files = Enum.any?(files, fn f -> 
            String.ends_with?(f, ".DCD") or 
            String.ends_with?(f, ".DCL") or 
            String.ends_with?(f, ".DAT")
          end)
          
          # Or check if Mnesia.nonode@nohost subdirectory exists with files
          subdir_files = case File.ls(mnesia_path) do
            {:ok, subfiles} ->
              Enum.any?(subfiles, fn f -> 
                String.ends_with?(f, ".DCD") or 
                String.ends_with?(f, ".DCL") or 
                String.ends_with?(f, ".DAT")
              end)
            _ -> false
          end
          
          direct_files or subdir_files
        _ -> false
      end
      
      if has_mnesia_files do
        # Try to load the experiment
        case AnalyzerBridge.load_context(experiment.path, name) do
          {:ok, _} ->
            socket =
              socket
              |> load_experiments()
              |> put_flash(:info, "Experiment '#{name}' loaded successfully")
            {:noreply, socket}
          
          {:error, reason} ->
            socket =
              socket
              |> load_experiments()
              |> put_flash(:error, "Failed to load '#{name}': #{inspect(reason)}")
            {:noreply, socket}
        end
      else
        # Empty experiment - create it in memory
        case AnalyzerBridge.create_empty_experiment(name) do
          {:ok, _} ->
            socket =
              socket
              |> load_experiments()
              |> put_flash(:info, "Experiment '#{name}' loaded (empty)")
            {:noreply, socket}
          
          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to create empty experiment: #{inspect(reason)}")}
        end
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
        context && context.agent_count == 0
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
                class="bg-purple-600 text-white px-4 py-2 rounded-md hover:bg-purple-700 transition"
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
                    placeholder="Mnesia.nonode@nohost"
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
                  <input
                    type="text"
                    name="path"
                    placeholder="C:\Users\qbot7\OneDrive\Documents\DXNN\DXNN-Trader-V2\DXNN-Trader-v2\Mnesia.nonode@nohost"
                    class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono text-sm"
                    required
                  />
                  <p class="text-xs text-gray-500 mt-1">
                    Full path to the Mnesia database folder
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
                  <input
                    type="text"
                    name="path"
                    placeholder="C:\Users\qbot7\OneDrive\Documents\Databases\my_experiment"
                    class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-green-500 font-mono text-sm"
                    required
                  />
                  <p class="text-xs text-gray-500 mt-1">
                    Full path where the new Mnesia database will be created
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
      </div>
    </div>
    """
  end
end
