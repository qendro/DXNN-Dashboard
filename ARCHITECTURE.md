# DXNN Analyzer Web Interface - Architecture

## System Overview

This document describes the technical architecture of the DXNN Analyzer Web Interface, a Phoenix LiveView application that provides a modern web UI for the Erlang-based DXNN Analyzer.

## Technology Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Frontend | Phoenix LiveView, Tailwind CSS, D3.js | Real-time UI, styling, visualization |
| Backend | Elixir/Phoenix, Erlang/OTP | Web server, analysis engine |
| Database | Mnesia, ETS | Persistent storage, in-memory cache |
| Deployment | Docker, Docker Compose | Containerization, orchestration |
| Real-time | WebSockets (Phoenix Channels) | Bidirectional communication |

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         Browser (Client)                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  Dashboard   │  │  Agent List  │  │   Inspector  │          │
│  │   LiveView   │  │   LiveView   │  │   LiveView   │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│         │                  │                  │                  │
│         └──────────────────┼──────────────────┘                  │
│                            │                                     │
└────────────────────────────┼─────────────────────────────────────┘
                             │
                             │ WebSocket (Phoenix Channel)
                             │
┌────────────────────────────┼─────────────────────────────────────┐
│                    Phoenix Server (Elixir)                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    Phoenix Endpoint                       │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐         │  │
│  │  │  Router    │→ │ LiveView   │→ │  PubSub    │         │  │
│  │  │            │  │  Processes │  │            │         │  │
│  │  └────────────┘  └────────────┘  └────────────┘         │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              │ GenServer Calls                   │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              AnalyzerBridge (GenServer)                   │  │
│  │  • Data format conversion (Elixir ↔ Erlang)             │  │
│  │  • Timeout management (30-60s)                           │  │
│  │  • Error handling and formatting                         │  │
│  │  • Code path management                                   │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Erlang Interop
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   DXNN Analyzer (Erlang)                         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    analyzer.erl                           │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐         │  │
│  │  │  mnesia_   │  │  agent_    │  │ topology_  │         │  │
│  │  │  loader    │  │  inspector │  │  mapper    │         │  │
│  │  └────────────┘  └────────────┘  └────────────┘         │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐         │  │
│  │  │ mutation_  │  │ comparator │  │  stats_    │         │  │
│  │  │ analyzer   │  │            │  │ collector  │         │  │
│  │  └────────────┘  └────────────┘  └────────────┘         │  │
│  │  ┌────────────┐  ┌────────────┐                          │  │
│  │  │population_ │  │  master_   │                          │  │
│  │  │  builder   │  │  database  │                          │  │
│  │  └────────────┘  └────────────┘                          │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              │ ETS Operations                    │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              ETS Tables (In-Memory Cache)                 │  │
│  │  • Context 1: exp1_agent, exp1_neuron, ...              │  │
│  │  • Context 2: exp2_agent, exp2_neuron, ...              │  │
│  │  • Master: master_agent, master_neuron, ...             │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Mnesia Operations
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Mnesia Database (Disk)                          │
│  • Agent records        • Sensor records                         │
│  • Cortex records       • Actuator records                       │
│  • Neuron records       • Substrate records                      │
│  • Population records   • Specie records                         │
└─────────────────────────────────────────────────────────────────┘
```

## Component Layers

### Layer 1: Browser Layer (Client)

**LiveView Pages** render UI and handle user interactions:

| Page | Route | Purpose |
|------|-------|---------|
| DashboardLive | `/` | Load/manage contexts, view summaries |
| AgentListLive | `/agents` | Browse and filter agents |
| AgentInspectorLive | `/agents/:id` | Detailed agent view |
| TopologyViewerLive | `/topology/:id` | Network visualization |
| ComparatorLive | `/compare` | Multi-agent comparison |
| MasterDatabaseLive | `/master` | Master database management |

**Key Features:**
- Real-time updates via WebSocket
- Automatic DOM diffing and patching
- No manual JavaScript for most interactions
- Form handling and validation
- Client-side hooks for D3.js visualizations

**LiveView State Example:**
```elixir
socket.assigns = %{
  contexts: [...],           # Loaded contexts
  selected_context: "exp1",  # Current context
  agents: [...],             # Agent list
  selected_agents: MapSet,   # Selected for comparison
  loading: false,            # Loading indicator
  error: nil,                # Error message
  page: 1,                   # Current page
  total_pages: 10            # Total pages
}
```

### Layer 2: Phoenix Server Layer (Elixir)

**Components:**

**Endpoint** (`endpoint.ex`)
- HTTP/WebSocket handling
- Static asset serving
- Session management
- CSRF protection

**Router** (`router.ex`)
- URL routing to LiveView modules
- Pipeline configuration
- Scope definitions

**LiveView Processes**
- One process per client connection
- Maintains session state
- Handles events and updates
- Automatic garbage collection

**PubSub**
- Broadcast updates to multiple clients
- Topic-based subscriptions
- Real-time synchronization

**Application Supervisor Tree:**
```
DxnnAnalyzerWeb.Application
├── Phoenix.PubSub
├── DxnnAnalyzerWeb.Telemetry
├── DxnnAnalyzerWeb.Endpoint
└── DxnnAnalyzerWeb.AnalyzerBridge
```

### Layer 3: Bridge Layer (Erlang ↔ Elixir)

**AnalyzerBridge GenServer** provides seamless integration between Elixir and Erlang.

**Responsibilities:**
1. **Code Path Management** - Adds Erlang beam files to code path
2. **Data Conversion** - Elixir maps ↔ Erlang records, strings ↔ charlists
3. **Timeout Management** - Handles long operations (30-60s)
4. **Error Formatting** - User-friendly error messages

**Data Flow Example:**
```
LiveView
  ↓ AnalyzerBridge.load_context("/path", "exp1")
GenServer.call
  ↓ Convert: "/path" → '/path', "exp1" → exp1
:analyzer.load('/path', exp1)
  ↓ Erlang processing
{ok, #mnesia_context{...}}
  ↓ Convert: record → map
{:ok, %{name: :exp1, path: "/path", ...}}
  ↓
LiveView receives formatted data
```

**Type Conversions:**
```elixir
# String ↔ Charlist
"hello" ↔ 'hello'

# Map ↔ Record
%{name: :exp1, path: "/path"} ↔ #mnesia_context{name=exp1, path="/path"}

# Atom ↔ Atom (same)
:exp1 ↔ exp1

# List ↔ List (element conversion)
[%{id: 1}, %{id: 2}] ↔ [#agent{id=1}, #agent{id=2}]
```

### Layer 4: Analyzer Layer (Erlang)

**Core Modules:**

| Module | Purpose | Key Functions |
|--------|---------|---------------|
| `analyzer.erl` | Main API | load/2, list_agents/1, find_best/2, inspect/2 |
| `mnesia_loader.erl` | Context management | load_folder/2, unload_context/1 |
| `agent_inspector.erl` | Agent analysis | inspect_agent/2, get_full_topology/2 |
| `topology_mapper.erl` | Network mapping | build_digraph/2, export_to_dot/3 |
| `mutation_analyzer.erl` | Evolution tracking | parse_evo_hist/2, display_mutations/2 |
| `comparator.erl` | Agent comparison | compare_agents/2, calculate_similarity/3 |
| `stats_collector.erl` | Statistics | collect_stats/1, generate_summary/1 |
| `population_builder.erl` | Population creation | create_population/4, validate_population/1 |
| `master_database.erl` | Master DB | create_empty/1, add_to_context/3, save/2 |

**Module Dependencies:**
```
analyzer.erl (API)
    ├── mnesia_loader.erl (context management)
    ├── agent_inspector.erl
    │   └── topology_mapper.erl
    ├── mutation_analyzer.erl
    ├── comparator.erl
    │   └── agent_inspector.erl
    ├── stats_collector.erl
    ├── population_builder.erl
    │   └── agent_inspector.erl
    └── master_database.erl
        └── mnesia_loader.erl
```

### Layer 5: Data Layer

**ETS Tables (In-Memory Cache):**
- Fast O(1) lookups
- One set of tables per context
- Isolated contexts
- Concurrent reads without locking
- Automatic cleanup on context unload

**Table Structure per Context:**
```erlang
{ContextName}_agent      % Agent records
{ContextName}_cortex     % Cortex records
{ContextName}_neuron     % Neuron records
{ContextName}_sensor     % Sensor records
{ContextName}_actuator   % Actuator records
{ContextName}_substrate  % Substrate records
{ContextName}_population % Population records
{ContextName}_specie     % Specie records
```

**Mnesia Database (Persistent Storage):**
- ACID transactions
- Record-based storage
- Native Erlang term format
- Distributed capability
- Source data (read-only)
- Output data (write-only)

## Data Flow Examples

### Loading a Context

```
User clicks "Load Context" with path and name
  ↓
DashboardLive.handle_event("load_context", %{"path" => path, "name" => name})
  ↓
AnalyzerBridge.load_context(path, name)
  ↓
GenServer.call → :analyzer.load(charlist_path, atom_name)
  ↓
mnesia_loader:load_folder(charlist_path, atom_name)
  ↓
1. Create temp directory
2. Copy Mnesia files to temp
3. Start Mnesia with temp directory
4. Wait for tables to load
5. Read all records from Mnesia tables
6. Create ETS tables for context
7. Copy records to ETS
8. Store context metadata
9. Cleanup temp directory
  ↓
Return {ok, #mnesia_context{}}
  ↓
Bridge formats to Elixir map
  ↓
LiveView updates socket.assigns.contexts
  ↓
Template re-renders with new context
  ↓
Browser receives DOM diff via WebSocket
  ↓
UI updates (no page refresh)
```

### Viewing Agents

```
User navigates to /agents?context=exp1
  ↓
AgentListLive.handle_params(%{"context" => "exp1"})
  ↓
AnalyzerBridge.list_agents(context: "exp1", limit: 50)
  ↓
GenServer.call → :analyzer.list_agents([{context, exp1}, {limit, 50}])
  ↓
agent_inspector:query_agents(exp1, Options)
  ↓
Query ETS table: exp1_agent
  ↓
ets:foldl(fun(Agent, Acc) -> [Agent | Acc] end, [], exp1_agent)
  ↓
Sort by fitness, limit to 50
  ↓
Return [#agent{}, #agent{}, ...]
  ↓
Bridge converts records to maps
  ↓
LiveView assigns agents to socket
  ↓
Template renders agent table
  ↓
Browser displays agent list
```

### Inspecting Agent Topology

```
User clicks "View Topology" on agent
  ↓
AgentInspectorLive.handle_event("view_topology", %{"id" => id})
  ↓
AnalyzerBridge.get_topology(id, context)
  ↓
GenServer.call → :agent_inspector.get_full_topology(agent_id, context)
  ↓
1. Read agent record from ETS
2. Read cortex using agent.cx_id
3. Read all neurons using cortex.neuron_ids
4. Read all sensors using cortex.sensor_ids
5. Read all actuators using cortex.actuator_ids
6. Read substrate if agent.substrate_id exists
  ↓
Return topology map:
#{
    agent => #agent{},
    cortex => #cortex{},
    neurons => [#neuron{}],
    sensors => [#sensor{}],
    actuators => [#actuator{}],
    substrate => #substrate{} | undefined
}
  ↓
Bridge converts to Elixir map
  ↓
LiveView assigns topology to socket
  ↓
Template renders with phx-hook="NetworkGraph"
  ↓
D3.js hook receives data and renders visualization
  ↓
Interactive graph displayed in browser
```

### Saving to Master Database

```
User selects agents and clicks "Save to Master Database"
  ↓
AgentListLive.handle_event("save_to_master", %{"agent_ids" => ids})
  ↓
AnalyzerBridge.add_to_master(ids, source_context, "master")
  ↓
GenServer.call → :master_database.add_to_context(ids, source_context, master)
  ↓
For each agent_id:
  1. Get full topology from source context (ETS)
  2. Copy agent record to master context (ETS)
  3. Copy cortex record
  4. Copy all neurons
  5. Copy all sensors
  6. Copy all actuators
  7. Copy substrate if exists
  ↓
Return {ok, Count}
  ↓
LiveView shows success message
  ↓
User can now view master database or save to disk
```

## Master Database Architecture

### Purpose

The Master Database provides a centralized repository for curating elite agents across multiple experiments.

**Use Cases:**
- Build a collection of best-performing agents
- Maintain a "hall of fame" across all experiments
- Prepare agents for deployment to live trading
- Compare agents from different experimental runs

### Storage Structure

```
./data/
└── MasterDatabase/
    └── Mnesia.nonode@nohost/
        ├── agent.DCD
        ├── cortex.DCD
        ├── neuron.DCD
        ├── sensor.DCD
        ├── actuator.DCD
        ├── substrate.DCD
        ├── population.DCD
        └── specie.DCD
```

### Data Flow

```
Source Context (ETS)
    ↓ Read agent topology
Agent Data (in-memory)
    ↓ Copy to master context
Master Context (ETS)
    ↓ Save when ready
Master Database (Mnesia on disk)
    ↓ Deploy or load as context
DXNN-Trader or Analysis
```

### Key Features

1. **Non-destructive** - Original contexts remain unchanged
2. **Full topology preservation** - All neurons, sensors, actuators copied
3. **Duplicate detection** - Won't add same agent twice
4. **DXNN-Trader compatible** - Can deploy master database directly
5. **Context loading** - Can load master as a regular context for analysis

### Implementation

**Erlang Module (`master_database.erl`):**
```erlang
create_empty(ContextName) -> {ok, Context}
add_to_context(AgentIds, SourceContext, MasterContext) -> {ok, Count}
save(ContextName, OutputPath) -> ok
load(MnesiaPath, ContextName) -> {ok, Context}
export_for_deployment(AgentIds, PopId, OutputPath) -> {ok, Path}
```

**Bridge Functions:**
```elixir
load_master(path, name)
create_empty_master(name)
add_to_master(ids, source_context, master_context)
save_master(context, output_path)
export_for_deployment(ids, pop_id, output_path)
```

**Workflow:**
```
1. Load Context A (experiment 1)
2. Create empty master context "master_elite"
3. Select top 5 agents from Context A
4. Add to master_elite (ETS → ETS, fast)
5. Load Context B (experiment 2)
6. Select top 3 agents from Context B
7. Add to master_elite (ETS → ETS, fast)
8. Analyze master_elite (8 elite agents, all in ETS)
9. Save master_elite to disk (ETS → Mnesia)
10. Deploy to DXNN-Trader or export subset
```

## Concurrency Model

### Multiple Users

```
User A (Browser)          User B (Browser)
     ↓                         ↓
LiveView Process A      LiveView Process B
     ↓                         ↓
     └─────────┬───────────────┘
               ↓
        AnalyzerBridge (Single GenServer)
               ↓
        Erlang Analyzer (Concurrent)
               ↓
        ETS Tables (Concurrent Reads)
```

**Key Points:**
- Each user has their own LiveView process
- AnalyzerBridge serializes calls (single GenServer)
- Erlang analyzer functions run concurrently
- ETS allows concurrent reads without locking
- Scales well for read-heavy workloads

**Bottlenecks:**
- Single AnalyzerBridge GenServer (can be pooled)
- Large agent lists without pagination
- Complex topology rendering

### Scalability Strategies

1. **Add more Phoenix nodes** - Distributed Erlang cluster
2. **Load balance WebSocket connections** - HAProxy, Nginx
3. **Cache frequently accessed data** - ETS or Redis
4. **Implement pagination** - Limit results per page
5. **Use PubSub** - Real-time updates across nodes
6. **Pool bridge GenServers** - Multiple bridge processes

## Performance Characteristics

### Strengths

- **Fast ETS lookups** - O(1) complexity
- **Efficient LiveView updates** - DOM diffing minimizes data transfer
- **Concurrent operations** - Erlang's lightweight processes
- **No database queries** - Data cached in ETS
- **Real-time updates** - WebSocket push

### Bottlenecks

- Single AnalyzerBridge GenServer (serializes calls)
- Large agent lists (1000+) without pagination
- Complex topology rendering (many nodes/edges)
- Initial context loading from disk (I/O bound)

### Optimization Techniques

**1. Pagination:**
```elixir
list_agents(context: exp1, limit: 50, offset: 0)
```

**2. Lazy Loading:**
```elixir
# Load topology only when viewed
get_topology(agent_id, context)
```

**3. Filtering:**
```elixir
# Reduce data transfer
list_agents(context: exp1, min_fitness: 0.7, limit: 20)
```

**4. Caching:**
```elixir
# Cache frequently accessed data
@cache_ttl 60_000  # 1 minute
```

**5. Streaming:**
```elixir
# Use LiveView streams for large lists
stream(socket, :agents, agents)
```

**6. Debouncing:**
```javascript
// Debounce search input
phx-debounce="300"
```

## Security Considerations

### Current Implementation

- CSRF protection enabled
- Signed session cookies
- WebSocket origin checking
- No authentication (designed for local use)

### Production Recommendations

1. **Authentication** - Add user accounts and session management
2. **Authorization** - Role-based access control
3. **HTTPS** - Enforce SSL/TLS in production
4. **Firewall** - Restrict access to trusted networks
5. **Rate Limiting** - Prevent abuse (Plug.RateLimiter)
6. **Audit Logging** - Track user actions
7. **Input Validation** - Sanitize all user inputs
8. **Secret Management** - Use environment variables for secrets

## Extension Points

### Adding New Features

**1. New LiveView Page:**
```elixir
# Create lib/dxnn_analyzer_web/live/my_feature_live.ex
defmodule DxnnAnalyzerWeb.MyFeatureLive do
  use DxnnAnalyzerWeb, :live_view
  
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :data, [])}
  end
  
  def render(assigns) do
    ~H"""
    <div>My Feature</div>
    """
  end
end

# Add route in router.ex
live "/my-feature", MyFeatureLive, :index
```

**2. New Analyzer Function:**
```erlang
% Add to dxnn_analyzer/src/analyzer.erl
my_function(Arg, Context) ->
    % Implementation
    {ok, Result}.
```

```elixir
# Add to analyzer_bridge.ex
def my_function(arg, context) do
  GenServer.call(__MODULE__, {:my_function, arg, context})
end

def handle_call({:my_function, arg, context}, _from, state) do
  result = :analyzer.my_function(arg, context)
  {:reply, format_result(result), state}
end
```

**3. New Component:**
```elixir
# Create in components/
defmodule DxnnAnalyzerWeb.MyComponent do
  use Phoenix.Component
  
  attr :data, :map, required: true
  
  def my_component(assigns) do
    ~H"""
    <div><%= @data %></div>
    """
  end
end
```

**4. New D3.js Visualization:**
```javascript
// assets/js/my_viz.js
export const MyViz = {
  mounted() {
    this.renderViz();
  },
  
  renderViz() {
    const data = JSON.parse(this.el.dataset.viz);
    // D3.js rendering
  }
};
```

### Integration Options

1. **External Services** - Add HTTP client for API calls (HTTPoison, Finch)
2. **Background Jobs** - Use Oban for async processing
3. **Real-Time Updates** - PubSub for multi-client synchronization
4. **REST API** - Add JSON endpoints for external tools
5. **GraphQL** - Add Absinthe for flexible queries
6. **File Upload** - Add file upload for Mnesia folders
7. **Export** - Add PDF/CSV export capabilities

## Testing Strategy

### Unit Tests

```elixir
# Test LiveView logic
test "loads context successfully", %{conn: conn} do
  {:ok, view, _html} = live(conn, "/")
  
  view
  |> form("#load-context-form", %{path: "/test", name: "test"})
  |> render_submit()
  
  assert render(view) =~ "Context loaded"
end
```

### Integration Tests

```elixir
# Test full flow
test "user can load and view agents", %{conn: conn} do
  {:ok, view, _} = live(conn, "/")
  # Load context
  # Navigate to agents
  # Verify agents displayed
end
```

### E2E Tests

- Use Wallaby or Hound
- Test browser interactions
- Verify WebSocket connections
- Test JavaScript hooks

## Monitoring

### Telemetry Events

Phoenix emits events for monitoring:
```elixir
[:phoenix, :endpoint, :start]
[:phoenix, :endpoint, :stop]
[:phoenix, :live_view, :mount, :start]
[:phoenix, :live_view, :mount, :stop]
[:phoenix, :router_dispatch, :start]
[:phoenix, :router_dispatch, :stop]
```

### Key Metrics

**Performance:**
- Response times
- LiveView mount duration
- Bridge call duration
- ETS query times

**Usage:**
- Active connections
- Contexts loaded
- Agents viewed
- Comparisons performed

**Errors:**
- Failed context loads
- Bridge timeouts
- Erlang errors
- WebSocket disconnects

## Docker Deployment

### Multi-Stage Build

```dockerfile
# Stage 1: Build Erlang Analyzer
FROM erlang:26-alpine AS erlang-builder
# Compile Erlang analyzer

# Stage 2: Build Elixir Web Interface
FROM elixir:1.16-alpine AS elixir-builder
# Compile Elixir web interface

# Stage 3: Runtime
FROM elixir:1.16-alpine AS runtime
# Minimal runtime image
```

### Docker Compose

```yaml
services:
  dxnn_analyzer_web:
    build: .
    ports:
      - "4000:4000"
    volumes:
      - ./DXNN-Trader-V2:/app/DXNN-Trader-V2:ro
      - ./data:/app/data
    environment:
      - SECRET_KEY_BASE=...
```

### Best Practices

1. **Multi-stage builds** - Minimize image size
2. **Non-root user** - Security
3. **Volume mounts** - Persist data
4. **Environment variables** - Configuration
5. **Health checks** - Monitoring
6. **Resource limits** - Prevent resource exhaustion

## Summary

The architecture provides:

✓ **Clean separation of concerns** across layers  
✓ **Seamless Erlang ↔ Elixir integration** via bridge pattern  
✓ **Real-time updates** via Phoenix LiveView  
✓ **Scalable concurrent design** leveraging BEAM VM  
✓ **Extensible component structure** for new features  
✓ **Production-ready** with Docker support  
✓ **Multi-context support** for parallel analysis  
✓ **Master database** for elite agent curation  

The bridge pattern allows the Elixir web interface to leverage the existing Erlang analyzer without modification, while providing a modern, interactive user experience through Phoenix LiveView.

---

**Version:** 0.1.0  
**Last Updated:** 2024
