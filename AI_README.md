# DXNN Analyzer Web Interface - AI Assistant Guide

This document provides comprehensive context for AI assistants working with the DXNN Analyzer Web Interface codebase.

## Project Overview

A Phoenix LiveView web application that provides a modern browser-based UI for the DXNN (Deep eXtended Neural Network) Analyzer, an Erlang-based tool for analyzing neuroevolution trading agents.

**Technology Stack:**
- **Frontend:** Phoenix LiveView, Tailwind CSS, D3.js
- **Backend:** Elixir/Phoenix, Erlang/OTP
- **Database:** Mnesia (via ETS cache)
- **Deployment:** Docker, Docker Compose
- **Real-time:** WebSockets (Phoenix Channels)

**Project Structure:**
- `dxnn_analyzer/` - Erlang analyzer (backend engine)
- `dxnn_analyzer_web/` - Phoenix web interface (frontend)
- `Databases/` - Sample Mnesia databases
- Docker configuration files for deployment

## Key Concepts

### 1. Phoenix LiveView

LiveView provides real-time, server-rendered HTML over WebSockets without writing JavaScript:

**Core Features:**
- Real-time updates without page refreshes
- One process per client maintains state
- Automatic DOM diffing minimizes data transfer
- Server-side rendering with client-side interactivity

**Example LiveView Module:**
```elixir
defmodule DxnnAnalyzerWeb.DashboardLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.AnalyzerBridge

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Load data only after WebSocket connection
      contexts = AnalyzerBridge.list_contexts()
      {:ok, assign(socket, :contexts, contexts)}
    else
      # Initial HTTP request
      {:ok, assign(socket, :contexts, [])}
    end
  end

  def handle_event("load_context", %{"path" => path, "name" => name}, socket) do
    case AnalyzerBridge.load_context(path, name) do
      {:ok, context} ->
        socket = put_flash(socket, :info, "Context loaded successfully")
        {:noreply, socket}
      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to load: #{reason}")
        {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-6">
      <h1 class="text-3xl font-bold mb-6">DXNN Analyzer Dashboard</h1>
      <%= for context <- @contexts do %>
        <div class="bg-white shadow rounded-lg p-4 mb-4">
          <h2 class="text-xl font-semibold"><%= context.name %></h2>
          <p class="text-gray-600"><%= context.agent_count %> agents</p>
        </div>
      <% end %>
    </div>
    """
  end
end
```

### 2. Erlang ↔ Elixir Bridge

The `AnalyzerBridge` GenServer provides seamless integration between Elixir and Erlang:

**Key Responsibilities:**
- Convert data structures (maps ↔ records, strings ↔ charlists)
- Manage Erlang code paths
- Handle timeouts for long operations
- Format errors for user display

**Bridge Pattern:**
```elixir
defmodule DxnnAnalyzerWeb.AnalyzerBridge do
  use GenServer

  # Public API (Elixir-friendly)
  def load_context(path, context_name) do
    GenServer.call(__MODULE__, {:load_context, path, context_name}, 30_000)
  end

  # GenServer callbacks
  def handle_call({:load_context, path, context}, _from, state) do
    # Convert to Erlang types
    path_charlist = String.to_charlist(path)
    context_atom = String.to_atom(context)
    
    # Call Erlang function
    result = :analyzer.load(path_charlist, context_atom)
    
    # Format result for Elixir
    formatted = format_context(result)
    {:reply, formatted, state}
  end

  # Data conversion
  defp format_context({:ok, context_record}) do
    {:ok, %{
      name: elem(context_record, 1),
      path: elem(context_record, 2) |> to_string(),
      agent_count: elem(context_record, 4),
      loaded_at: elem(context_record, 3)
    }}
  end
  defp format_context({:error, reason}), do: {:error, reason}
end
```

### 3. Mnesia and ETS

**Mnesia:** Persistent database on disk
- Stores agent, neuron, sensor, actuator records
- ACID transactions
- Distributed capability
- Native Erlang term storage

**ETS:** In-memory cache
- Fast O(1) lookups
- One table per context
- Concurrent reads without locking
- No disk I/O

**Data Flow:**
```
Mnesia (disk) → mnesia_loader → ETS (memory) → analyzer functions → Results
```

**Context Isolation:**
Each loaded context gets its own ETS tables:
- `{context_name}_agent`
- `{context_name}_cortex`
- `{context_name}_neuron`
- `{context_name}_sensor`
- `{context_name}_actuator`
- `{context_name}_substrate`
- `{context_name}_population`
- `{context_name}_specie`

### 4. Agent Records

Agents are stored as Erlang records defined in `dxnn_analyzer/include/records.hrl`:

```erlang
-record(agent, {
    id,                      % {agent, {Timestamp, Unique}}
    encoding_type,           % neural | substrate
    generation,              % integer()
    population_id,           % term()
    specie_id,              % term()
    cx_id,                  % Cortex ID
    fingerprint,            % term()
    constraint,             % #constraint{}
    evo_hist = [],          % [Mutation]
    fitness = 0,            % float()
    innovation_factor = 0,  % integer()
    substrate_id            % term() | undefined
}).

-record(neuron, {
    id,                     % {neuron, {Layer, Unique}}
    generation,             % integer()
    cx_id,                  % Cortex ID
    af,                     % Activation function
    input_idps = [],        % [{Id, Weights}]
    output_ids = [],        % [Id]
    ro_ids = []             % Recurrent output IDs
}).

-record(cortex, {
    id,                     % {cortex, Unique}
    agent_id,               % Agent ID
    neuron_ids = [],        % [NeuronId]
    sensor_ids = [],        % [SensorId]
    actuator_ids = []       % [ActuatorId]
}).
```

## Module Reference

### Erlang Analyzer Modules

**analyzer.erl** - Main API
```erlang
start() -> ok
stop() -> ok
load(MnesiaPath, ContextName) -> {ok, Context} | {error, Reason}
unload(ContextName) -> ok | {error, Reason}
list_contexts() -> [Context]
list_agents(Options) -> [Agent]
find_best(N, Options) -> [Agent]
inspect(AgentId, Context) -> {ok, Agent} | {error, Reason}
show_topology(AgentId, Context) -> ok
compare(AgentIds, Context) -> {ok, Comparison} | {error, Reason}
create_population(AgentIds, PopId, OutputFolder, Options) -> {ok, Path} | {error, Reason}
```

**mnesia_loader.erl** - Context Management
```erlang
load_folder(MnesiaPath, ContextName) -> {ok, Context} | {error, Reason}
unload_context(ContextName) -> ok | {error, Reason}
get_context(ContextName) -> {ok, Context} | {error, Reason}
```

**agent_inspector.erl** - Agent Analysis
```erlang
inspect_agent(AgentId, Context) -> {ok, Agent} | {error, Reason}
get_full_topology(AgentId, Context) -> Map | {error, Reason}
calculate_metrics(AgentId, Context) -> #topo_summary{} | {error, Reason}
```

**topology_mapper.erl** - Graph Operations
```erlang
build_digraph(AgentId, Context) -> {ok, Digraph} | {error, Reason}
analyze_structure(AgentId, Context) -> {ok, Analysis} | {error, Reason}
export_to_dot(AgentId, Context, Filename) -> ok | {error, Reason}
```

**mutation_analyzer.erl** - Evolution Tracking
```erlang
display_mutations(AgentId, Context) -> ok
parse_evo_hist(AgentId, Context) -> {ok, [#mutation_event{}]} | {error, Reason}
```

**population_builder.erl** - Population Creation
```erlang
create_population(AgentIds, PopId, OutputFolder, Options) -> {ok, Path} | {error, Reason}
validate_population(MnesiaDir) -> ok | {error, Reason}
```

**comparator.erl** - Agent Comparison
```erlang
compare_agents(AgentIds, Context) -> {ok, #agent_comparison{}} | {error, Reason}
calculate_similarity(AgentId1, AgentId2, Context) -> {ok, float()} | {error, Reason}
```

**stats_collector.erl** - Statistics
```erlang
collect_stats(Context) -> {ok, Map} | {error, Reason}
generate_summary(Context) -> {ok, Map} | {error, Reason}
```

**master_database.erl** - Master Database Management
```erlang
create_empty(ContextName) -> {ok, Context} | {error, Reason}
add_to_context(AgentIds, SourceContext, MasterContext) -> {ok, Count} | {error, Reason}
save(ContextName, OutputPath) -> ok | {error, Reason}
load(MnesiaPath, ContextName) -> {ok, Context} | {error, Reason}
```

### Elixir Phoenix Modules

**DxnnAnalyzerWeb.AnalyzerBridge** - Erlang Bridge
```elixir
start_link(opts) - Start the bridge GenServer
load_context(path, name) - Load Mnesia folder as context
unload_context(name) - Unload context and free memory
list_contexts() - Get all loaded contexts
list_agents(opts) - List agents with filters
find_best(n, opts) - Find top N agents
inspect_agent(id, context) - Get agent details
get_topology(id, context) - Get network topology
compare_agents(ids, context) - Compare multiple agents
create_population(ids, pop_id, output, opts) - Create new population
```

**LiveView Pages:**
- `DashboardLive` - Main dashboard for context management
- `AgentListLive` - Agent browser with filtering
- `AgentInspectorLive` - Detailed agent view
- `TopologyViewerLive` - Network topology visualization
- `ComparatorLive` - Multi-agent comparison
- `MasterDatabaseLive` - Master database management

## Common Development Tasks

### Adding a New LiveView Page

1. **Create the LiveView module:**
```elixir
# lib/dxnn_analyzer_web/live/my_feature_live.ex
defmodule DxnnAnalyzerWeb.MyFeatureLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.AnalyzerBridge

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :data, [])}
  end

  def handle_event("action", params, socket) do
    # Handle user action
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-6">
      <h1 class="text-3xl font-bold mb-6">My Feature</h1>
      <!-- Content here -->
    </div>
    """
  end
end
```

2. **Add route in router.ex:**
```elixir
# lib/dxnn_analyzer_web/router.ex
scope "/", DxnnAnalyzerWeb do
  pipe_through :browser
  
  live "/my-feature", MyFeatureLive, :index
end
```

3. **Add navigation link:**
```heex
<!-- lib/dxnn_analyzer_web/components/layouts/app.html.heex -->
<.link navigate={~p"/my-feature"} class="nav-link">
  My Feature
</.link>
```

### Adding a New Analyzer Function

1. **Add to Erlang analyzer (if needed):**
```erlang
% dxnn_analyzer/src/analyzer.erl
my_function(Arg, Context) ->
    % Implementation
    {ok, Result}.
```

2. **Add to bridge:**
```elixir
# lib/dxnn_analyzer_web/analyzer_bridge.ex
def my_function(arg, context) do
  GenServer.call(__MODULE__, {:my_function, arg, context})
end

def handle_call({:my_function, arg, context}, _from, state) do
  arg_charlist = String.to_charlist(arg)
  context_atom = String.to_atom(context)
  
  result = :analyzer.my_function(arg_charlist, context_atom)
  formatted = format_result(result)
  
  {:reply, formatted, state}
end
```

3. **Use in LiveView:**
```elixir
def handle_event("do_something", %{"arg" => arg}, socket) do
  result = AnalyzerBridge.my_function(arg, socket.assigns.context)
  {:noreply, assign(socket, :result, result)}
end
```

### Styling with Tailwind CSS

Use Tailwind utility classes directly in templates:

```heex
<!-- Card Component -->
<div class="bg-white shadow-lg rounded-lg p-6 mb-4">
  <h2 class="text-xl font-semibold text-gray-800 mb-2">Title</h2>
  <p class="text-gray-600">Content goes here</p>
</div>

<!-- Button -->
<button class="bg-blue-600 hover:bg-blue-700 text-white font-medium px-4 py-2 rounded-md transition-colors">
  Click Me
</button>

<!-- Grid Layout -->
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
  <div class="bg-white p-4 rounded shadow">Item 1</div>
  <div class="bg-white p-4 rounded shadow">Item 2</div>
  <div class="bg-white p-4 rounded shadow">Item 3</div>
</div>

<!-- Responsive Table -->
<div class="overflow-x-auto">
  <table class="min-w-full divide-y divide-gray-200">
    <thead class="bg-gray-50">
      <tr>
        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Header</th>
      </tr>
    </thead>
    <tbody class="bg-white divide-y divide-gray-200">
      <tr>
        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">Data</td>
      </tr>
    </tbody>
  </table>
</div>
```

After CSS changes:
```bash
cd dxnn_analyzer_web/assets
npm run deploy
```

### Adding D3.js Visualization

1. **Create JavaScript hook:**
```javascript
// assets/js/network_graph.js
export const NetworkGraph = {
  mounted() {
    const data = JSON.parse(this.el.dataset.topology);
    this.renderGraph(data);
  },
  
  updated() {
    const data = JSON.parse(this.el.dataset.topology);
    this.renderGraph(data);
  },
  
  renderGraph(data) {
    // D3.js visualization code
    const svg = d3.select(this.el).select("svg");
    // ... D3 rendering logic
  }
};
```

2. **Register hook in app.js:**
```javascript
// assets/js/app.js
import { NetworkGraph } from "./network_graph";

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: { NetworkGraph }
});
```

3. **Use in template:**
```heex
<div id="network-graph" 
     phx-hook="NetworkGraph" 
     data-topology={Jason.encode!(@topology)}>
  <svg width="800" height="600"></svg>
</div>
```

## Common Patterns

### Loading Data in LiveView

```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    # Load data only after WebSocket connection
    # This prevents loading data twice (HTTP + WebSocket)
    data = AnalyzerBridge.get_data()
    {:ok, assign(socket, :data, data)}
  else
    # Initial HTTP request - show loading state
    {:ok, assign(socket, :data, [], :loading, true)}
  end
end
```

### Handling Events

```elixir
def handle_event("button_click", params, socket) do
  # Process event
  result = do_something(params)
  
  # Update socket assigns
  socket = assign(socket, :result, result)
  
  # Optionally show flash message
  socket = put_flash(socket, :info, "Success!")
  
  {:noreply, socket}
end
```

### Navigation

```elixir
# Push navigate (updates URL, maintains LiveView connection)
{:noreply, push_navigate(socket, to: ~p"/agents")}

# Push patch (updates params, same LiveView instance)
{:noreply, push_patch(socket, to: ~p"/agents?context=exp1")}

# Redirect (full page load, new LiveView process)
{:noreply, redirect(socket, to: ~p"/agents")}
```

### Conditional Rendering

```heex
<%= if @loading do %>
  <div class="flex justify-center items-center p-8">
    <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
  </div>
<% else %>
  <div class="content">
    <%= for item <- @items do %>
      <div class="item"><%= item.name %></div>
    <% end %>
  </div>
<% end %>

<%= if @error do %>
  <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded">
    <%= @error %>
  </div>
<% end %>
```

### Form Handling

```heex
<.form for={%{}} phx-submit="submit_form">
  <div class="mb-4">
    <label class="block text-sm font-medium text-gray-700 mb-2">
      Context Name
    </label>
    <input 
      type="text" 
      name="context_name" 
      class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
      required
    />
  </div>
  
  <button type="submit" class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700">
    Submit
  </button>
</.form>
```

```elixir
def handle_event("submit_form", %{"context_name" => name}, socket) do
  # Process form submission
  {:noreply, socket}
end
```

## Debugging

### IEx (Interactive Elixir)

```bash
iex -S mix phx.server
```

In IEx:
```elixir
# Test bridge directly
DxnnAnalyzerWeb.AnalyzerBridge.start_analyzer()
DxnnAnalyzerWeb.AnalyzerBridge.list_contexts()

# Check if Erlang module is loaded
:code.which(:analyzer)
# Should return path to beam file

# Enable debug logging
require Logger
Logger.configure(level: :debug)

# Inspect LiveView state
:sys.get_state(pid)

# List all processes
Process.list() |> Enum.map(&Process.info/1)
```

### Docker Logs

```bash
# View all logs
docker-compose logs -f

# Specific service
docker-compose logs -f dxnn_analyzer_web

# Last 100 lines
docker-compose logs --tail=100 dxnn_analyzer_web

# Follow logs with timestamps
docker-compose logs -f --timestamps dxnn_analyzer_web
```

### Browser DevTools

**WebSocket Inspection:**
1. Open browser DevTools (F12)
2. Go to Network tab
3. Filter by WS (WebSocket)
4. Click on connection to see messages

**LiveView Events:**
- Look for `phx_join`, `phx_reply` messages
- Check for errors in Console tab
- Inspect DOM updates in Elements tab

### Common Issues

**"Analyzer module not found":**
```bash
# Ensure Erlang analyzer is compiled
cd dxnn_analyzer
rebar3 compile

# Check beam files exist
ls ebin/*.beam

# Verify code path in bridge
# lib/dxnn_analyzer_web/analyzer_bridge.ex
# Should add ../dxnn_analyzer/ebin to code path
```

**"Port already in use":**
```bash
# Change port in config/dev.exs
config :dxnn_analyzer_web, DxnnAnalyzerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4001]

# Or kill process
# Unix: lsof -ti:4000 | xargs kill
# Windows: netstat -ano | findstr :4000
```

**LiveView not connecting:**
- Check browser console for WebSocket errors
- Verify `secret_key_base` is set in config
- Check firewall settings
- Ensure endpoint is configured correctly

**Assets not loading:**
```bash
# Recompile assets
cd dxnn_analyzer_web/assets
npm install
npm run deploy

# Check priv/static/assets/ exists
ls ../priv/static/assets/
```

**Context fails to load:**
- Verify Mnesia path is correct
- Check file permissions
- Ensure Mnesia folder contains *.DCD, *.DAT files
- Check Erlang logs for detailed error

## Testing

### Unit Tests

```elixir
# test/dxnn_analyzer_web/live/dashboard_live_test.exs
defmodule DxnnAnalyzerWeb.DashboardLiveTest do
  use DxnnAnalyzerWeb.ConnCase
  import Phoenix.LiveViewTest

  test "renders dashboard", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "DXNN Analyzer Dashboard"
  end

  test "loads context", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    
    # Simulate form submission
    view
    |> form("#load-context-form", %{
      path: "/test/path",
      name: "test_context"
    })
    |> render_submit()
    
    # Assert flash message
    assert render(view) =~ "Context loaded"
  end
end
```

Run tests:
```bash
cd dxnn_analyzer_web
mix test
mix test --cover
mix test test/specific_test.exs
mix test --trace  # Show detailed test execution
```

### Integration Tests

```elixir
test "full workflow: load, view, inspect agent", %{conn: conn} do
  # Load context
  {:ok, view, _} = live(conn, "/")
  view |> element("#load-btn") |> render_click()
  
  # Navigate to agents
  {:ok, view, _} = live(conn, "/agents?context=test")
  assert render(view) =~ "Agents"
  
  # Inspect agent
  view |> element("#inspect-btn-1") |> render_click()
  assert render(view) =~ "Agent Details"
end
```

## Performance Tips

### For Large Populations (1000+ agents)

1. **Use pagination:**
```elixir
def handle_event("load_page", %{"page" => page}, socket) do
  offset = (page - 1) * 50
  agents = AnalyzerBridge.list_agents(
    context: socket.assigns.context,
    limit: 50,
    offset: offset
  )
  {:noreply, assign(socket, :agents, agents)}
end
```

2. **Filter early:**
```elixir
agents = AnalyzerBridge.list_agents(
  context: exp1,
  min_fitness: 0.7,
  sort: :fitness,
  limit: 50
)
```

3. **Lazy load details:**
```elixir
# Don't load topology until viewed
def handle_event("view_topology", %{"id" => id}, socket) do
  topology = AnalyzerBridge.get_topology(id, socket.assigns.context)
  {:noreply, assign(socket, :topology, topology)}
end
```

4. **Unload unused contexts:**
```elixir
def handle_event("unload_context", %{"name" => name}, socket) do
  AnalyzerBridge.unload_context(name)
  {:noreply, socket}
end
```

5. **Use streams for large lists:**
```elixir
def mount(_params, _session, socket) do
  {:ok, stream(socket, :agents, [])}
end

def handle_event("load_agents", _, socket) do
  agents = AnalyzerBridge.list_agents(context: exp1)
  {:noreply, stream(socket, :agents, agents)}
end
```

## Security Notes

### Current State
- Designed for local use
- No authentication by default
- CSRF protection enabled
- Signed session cookies
- WebSocket origin checking

### For Production
- Add authentication (Pow, Guardian, phx.gen.auth)
- Use HTTPS only
- Set strong `SECRET_KEY_BASE` (min 64 chars)
- Configure firewall rules
- Implement rate limiting
- Add audit logging
- Regular security updates

## Useful Commands

```bash
# Elixir/Phoenix
mix deps.get              # Install dependencies
mix compile               # Compile project
mix phx.server            # Start server
iex -S mix phx.server     # Start with IEx
mix format                # Format code
mix test                  # Run tests
mix phx.routes            # List all routes
mix phx.digest            # Compile assets for production

# Erlang
cd dxnn_analyzer
rebar3 compile            # Compile analyzer
rebar3 clean              # Clean build
rebar3 shell              # Start Erlang shell
rebar3 eunit              # Run tests

# Node/Assets
cd dxnn_analyzer_web/assets
npm install               # Install dependencies
npm run deploy            # Build production assets
npm run watch             # Watch for changes

# Docker
docker-compose up -d      # Start containers
docker-compose down       # Stop containers
docker-compose logs -f    # View logs
docker-compose build      # Rebuild images
docker-compose ps         # List containers
docker-compose exec dxnn_analyzer_web sh  # Shell into container
```

## Key Files to Know

**Configuration:**
- `dxnn_analyzer_web/config/dev.exs` - Development config
- `dxnn_analyzer_web/config/prod.exs` - Production config
- `dxnn_analyzer_web/config/runtime.exs` - Runtime config
- `dxnn_analyzer_web/mix.exs` - Elixir dependencies
- `dxnn_analyzer/rebar.config` - Erlang dependencies

**Core Logic:**
- `dxnn_analyzer_web/lib/dxnn_analyzer_web/analyzer_bridge.ex` - Erlang bridge
- `dxnn_analyzer_web/lib/dxnn_analyzer_web/router.ex` - Routes
- `dxnn_analyzer/src/analyzer.erl` - Main Erlang API
- `dxnn_analyzer/include/records.hrl` - Record definitions

**UI:**
- `dxnn_analyzer_web/lib/dxnn_analyzer_web/live/*.ex` - LiveView pages
- `dxnn_analyzer_web/lib/dxnn_analyzer_web/components/` - Components
- `dxnn_analyzer_web/lib/dxnn_analyzer_web/components/layouts/app.html.heex` - Layout
- `dxnn_analyzer_web/assets/css/app.css` - Styles
- `dxnn_analyzer_web/assets/js/app.js` - JavaScript

**Docker:**
- `Dockerfile` - Production image
- `Dockerfile.dev` - Development image
- `docker-compose.yml` - Orchestration

## Resources

- [Phoenix LiveView Docs](https://hexdocs.pm/phoenix_live_view/)
- [Phoenix Framework](https://www.phoenixframework.org/)
- [Elixir Lang](https://elixir-lang.org/)
- [Erlang Docs](https://www.erlang.org/docs)
- [Tailwind CSS](https://tailwindcss.com/)
- [D3.js](https://d3js.org/)

## Summary

This is a Phoenix LiveView application that bridges Elixir and Erlang to provide a modern web interface for DXNN agent analysis. The key is understanding:

1. **LiveView** - Real-time UI updates via WebSockets
2. **AnalyzerBridge** - Erlang ↔ Elixir integration layer
3. **ETS/Mnesia** - Multi-context data storage
4. **Docker** - Containerized deployment

When making changes:
- Focus on LiveView pages for UI
- Use the bridge for Erlang integration
- Apply Tailwind classes for styling
- Add D3.js hooks for visualizations
- Test with both local and Docker setups

The architecture is designed for extensibility - new features can be added by creating new LiveView pages, adding bridge functions, and implementing Erlang analyzer modules as needed.
