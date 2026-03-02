# Native Agent Performance Tracker Implementation Plan

## Intent

Replace the current Python Flask dashboard with a native Phoenix LiveView implementation that directly integrates with the Erlang DXNN-Trader system. This provides true real-time monitoring, eliminates log parsing overhead, and leverages the BEAM's distributed computing capabilities for a more robust and performant monitoring solution.

## Problem Statement

### Current Architecture Limitations

The existing Flask dashboard (`dashboard.py`) has several constraints:

1. **Polling-Based Updates**: Refreshes every 2-5 seconds by re-parsing log files
2. **Log Parsing Overhead**: Regex parsing of large log files on every request
3. **No True Real-Time**: Delayed updates due to polling interval
4. **Separate Technology Stack**: Python/Flask disconnected from Erlang runtime
5. **No Direct Data Access**: Must parse logs instead of querying Mnesia directly
6. **Limited Integration**: Cannot control or interact with training system

### What We're Building

A native Phoenix LiveView dashboard that:

- **Reads directly from Mnesia** - No log parsing, instant data access
- **Receives real-time events** - WebSocket push updates when agents evaluate
- **Runs on the BEAM** - Same VM as DXNN system, native Erlang interop
- **Enables bidirectional control** - Future: pause/resume training, adjust parameters
- **Scales with the system** - Distributed Erlang across multiple nodes

## Overall Approach

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    ERLANG DXNN SYSTEM                       │
│                                                             │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐            │
│  │ exoself  │───▶│   fx     │───▶│  qlog    │            │
│  │  .erl    │    │  .erl    │    │  .erl    │            │
│  └──────────┘    └──────────┘    └──────────┘            │
│       │                │                                   │
│       │                │ Fitness Evaluation                │
│       │                ▼                                   │
│       │         ┌─────────────┐                           │
│       │         │   Mnesia    │◀──────────────┐           │
│       │         │  Database   │               │           │
│       │         └─────────────┘               │           │
│       │                │                      │           │
│       │                │                      │           │
│       ▼                ▼                      │           │
│  ┌──────────────────────────────────┐        │           │
│  │    Phoenix PubSub Broadcast      │        │           │
│  │  (agent:evaluations channel)     │        │           │
│  └──────────────────────────────────┘        │           │
│                    │                          │           │
└────────────────────┼──────────────────────────┼───────────┘
                     │                          │
                     │                          │
┌────────────────────▼──────────────────────────▼───────────┐
│              PHOENIX LIVEVIEW DASHBOARD                    │
│                                                            │
│  ┌─────────────────────────────────────────────────────┐  │
│  │         AgentTracker Context (Elixir)               │  │
│  │  - Direct :mnesia queries                           │  │
│  │  - Agent performance aggregation                    │  │
│  │  - Real-time data transformation                    │  │
│  └─────────────────────────────────────────────────────┘  │
│                          │                                 │
│  ┌─────────────────────────────────────────────────────┐  │
│  │      AgentPerformanceLive (LiveView)                │  │
│  │  - Subscribe to PubSub events                       │  │
│  │  - Render agent table & charts                      │  │
│  │  - Handle real-time updates                         │  │
│  └─────────────────────────────────────────────────────┘  │
│                          │                                 │
│                          ▼                                 │
│                   WebSocket (Phoenix)                      │
│                          │                                 │
└──────────────────────────┼─────────────────────────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │   Browser   │
                    │  (uPlot.js) │
                    └─────────────┘
```

### Data Flow

#### 1. Agent Evaluation (Erlang Side)

```erlang
% fx.erl - After fitness calculation
Fitness = fitness_functions:calculate_fitness(U_S, U_A),

% Log to file (keep for debugging)
qlog:agent_trades(ExoSelf, ...),

% NEW: Broadcast to Phoenix
phoenix_pubsub:broadcast(
    'Elixir.Dxnn.PubSub',
    <<"agent:evaluations">>,
    {agent_evaluated, Agent_Id, Fitness, Metrics}
).
```

#### 2. LiveView Subscription (Elixir Side)

```elixir
# lib/dxnn_web/live/agent_performance_live.ex
def mount(_params, _session, socket) do
  if connected?(socket) do
    # Subscribe to real-time events
    Phoenix.PubSub.subscribe(Dxnn.PubSub, "agent:evaluations")
  end
  
  # Initial data load from Mnesia
  agents = AgentTracker.list_top_agents(50)
  
  {:ok, assign(socket, agents: agents)}
end

# Handle real-time updates
def handle_info({:agent_evaluated, agent_id, fitness, metrics}, socket) do
  # Update only the changed agent in the UI
  updated_agents = update_agent_in_list(socket.assigns.agents, agent_id, fitness)
  
  {:noreply, assign(socket, agents: updated_agents)}
end
```

#### 3. Browser Update (Client Side)

```javascript
// Phoenix LiveView handles this automatically via morphdom
// Differential DOM updates - only changed elements re-render
// Chart updates via LiveView hooks
```

### Key Components

#### Component 1: Mnesia Query Layer (Elixir)

**Purpose**: Provide efficient data access to agent records

**Location**: `lib/dxnn/agent_tracker.ex`

**Responsibilities**:
- Query Mnesia for agent records
- Aggregate fitness statistics
- Sort and filter agents by performance
- Fetch agent evaluation history

**Example Functions**:
```elixir
def list_top_agents(limit \\ 50)
def get_agent_details(agent_id)
def get_agent_history(agent_id)
def get_generation_stats(generation)
```

#### Component 2: Phoenix PubSub Integration (Erlang)

**Purpose**: Broadcast agent evaluation events to LiveView

**Location**: Modify `fx.erl`, `exoself.erl`

**Changes Required**:
- Add PubSub broadcast after fitness evaluation
- Include agent_id, fitness, and key metrics
- Non-blocking (fire-and-forget)

**Implementation**:
```erlang
% Helper function in qlog.erl or new module
broadcast_agent_evaluation(Agent_Id, Fitness, Metrics) ->
    case whereis('Elixir.Dxnn.PubSub') of
        undefined -> ok;  % Phoenix not running, skip
        _Pid ->
            'Elixir.Phoenix.PubSub':broadcast(
                'Elixir.Dxnn.PubSub',
                <<"agent:evaluations">>,
                {agent_evaluated, Agent_Id, Fitness, Metrics}
            )
    end.
```

#### Component 3: LiveView Dashboard (Elixir)

**Purpose**: Real-time web UI for agent monitoring

**Location**: `lib/dxnn_web/live/agent_performance_live.ex`

**Features**:
- Top 50 agents table (sortable)
- Real-time fitness chart (uPlot.js)
- Agent detail modal (click PID/Agent ID)
- Metric selector (fitness, profit, trades)
- Auto-updates via WebSocket

**Template Structure**:
```heex
<div class="agent-performance">
  <div class="controls">
    <select phx-change="change_metric">
      <option value="fitness">Fitness</option>
      <option value="realized_pl">Realized P/L</option>
    </select>
    <span>Total Agents: <%= @total_agents %></span>
  </div>
  
  <div id="chart" phx-hook="AgentChart"></div>
  
  <table>
    <thead>
      <tr>
        <th>Rank</th>
        <th>PID</th>
        <th>Agent ID</th>
        <th>Fitness</th>
        <th>Profit</th>
      </tr>
    </thead>
    <tbody id="agents" phx-update="replace">
      <%= for {agent, rank} <- Enum.with_index(@agents, 1) do %>
        <tr id={"agent-#{agent.id}"}>
          <td><%= rank %></td>
          <td phx-click="show_pid_details" phx-value-pid={agent.pid}>
            <%= agent.pid %>
          </td>
          <td><%= agent.id %></td>
          <td><%= agent.fitness %></td>
          <td><%= agent.profit %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
</div>
```

#### Component 4: Chart Integration (JavaScript Hook)

**Purpose**: Render performance charts with uPlot

**Location**: `assets/js/hooks/agent_chart.js`

**Responsibilities**:
- Initialize uPlot chart on mount
- Update chart data on LiveView pushes
- Handle zoom/pan interactions
- Maintain chart state across updates

```javascript
export const AgentChart = {
  mounted() {
    this.chart = new uPlot(opts, data, this.el);
    
    this.handleEvent("update_chart", ({data}) => {
      this.chart.setData(data);
    });
  },
  
  updated() {
    // Chart updates handled via events, not DOM updates
  }
}
```

## Implementation Phases

### Phase 1: Foundation (Week 1)

**Goal**: Proof of concept with basic real-time updates

**Tasks**:
1. Create Phoenix application structure
   - `mix phx.new dxnn_web --no-ecto`
   - Configure to run alongside Erlang system
2. Implement Mnesia query layer
   - `AgentTracker` context module
   - Basic agent listing and sorting
3. Create minimal LiveView page
   - Agent table only (no charts yet)
   - Static data from Mnesia
4. Test Mnesia connectivity
   - Verify can read agent records
   - Confirm data format matches expectations

**Success Criteria**:
- Phoenix app starts without errors
- Can query and display agents from Mnesia
- LiveView renders agent table correctly

### Phase 2: Real-Time Integration (Week 2)

**Goal**: Live updates when agents evaluate

**Tasks**:
1. Add Phoenix PubSub to Erlang
   - Modify `fx.erl` to broadcast events
   - Test event publishing works
2. Implement LiveView subscriptions
   - Subscribe to `agent:evaluations` channel
   - Handle incoming events
   - Update agent list in real-time
3. Add WebSocket connection handling
   - Graceful reconnection on disconnect
   - Show connection status indicator
4. Performance testing
   - Test with 100+ agents evaluating
   - Measure update latency
   - Optimize if needed

**Success Criteria**:
- Agent table updates within 100ms of evaluation
- No memory leaks during extended runs
- Handles 1000+ agents without lag

### Phase 3: Feature Parity (Week 3)

**Goal**: Match Flask dashboard functionality

**Tasks**:
1. Add chart visualization
   - Integrate uPlot.js via LiveView hooks
   - Implement metric selector
   - Add zoom/pan controls
2. Implement agent detail modal
   - PID instance details
   - Agent ID aggregated view
   - Evaluation history
3. Add generation statistics
   - Best/avg/min fitness per generation
   - Population size tracking
4. Style and polish
   - Match existing dashboard aesthetics
   - Responsive design
   - Loading states

**Success Criteria**:
- All Flask dashboard features replicated
- Charts render smoothly with 10k+ data points
- UI feels responsive and polished

### Phase 4: Advanced Features (Week 4+)

**Goal**: Leverage native integration for new capabilities

**Tasks**:
1. Agent control interface
   - Pause/resume individual agents
   - Terminate underperforming agents
   - Adjust mutation rates
2. Multi-node monitoring
   - Connect to distributed Erlang cluster
   - Aggregate stats across nodes
   - Node health monitoring
3. Historical analysis
   - Query past experiments from Mnesia
   - Compare runs side-by-side
   - Export data for analysis
4. Alerts and notifications
   - Fitness threshold alerts
   - Training completion notifications
   - Error/crash detection

**Success Criteria**:
- Can control training from dashboard
- Works across distributed nodes
- Provides insights beyond current dashboard

## Technical Decisions

### Why Phoenix LiveView?

**Pros**:
- Native Elixir/Erlang integration
- Real-time by default (WebSocket)
- Efficient differential rendering
- Runs on same VM as DXNN system
- No separate API layer needed
- Built-in presence and PubSub

**Cons**:
- Learning curve if team unfamiliar with Elixir
- Requires Phoenix application setup
- More complex than Flask for simple cases

**Decision**: Benefits outweigh costs for long-term maintainability and feature potential

### Why Direct Mnesia Access?

**Alternative**: Continue parsing logs

**Pros of Mnesia**:
- Data already there - no duplication
- Instant queries - no file I/O
- Transactional consistency
- Can query historical data efficiently
- Enables write operations (future control features)

**Cons of Mnesia**:
- Requires understanding Mnesia schema
- Must handle record format changes
- Tighter coupling to DXNN internals

**Decision**: Direct Mnesia access provides better performance and enables future features

### Why Keep Log Files?

Even with Mnesia access, we keep logging because:

1. **Debugging**: Text logs easier to grep/analyze
2. **Audit Trail**: Permanent record of all evaluations
3. **Backup**: Can reconstruct state from logs if Mnesia corrupted
4. **External Tools**: Other scripts may depend on logs
5. **Low Cost**: Logging is fast and disk is cheap

**Decision**: Keep all existing logging, add PubSub broadcasting alongside

## Migration Strategy

### Parallel Operation

Run both dashboards simultaneously during transition:

```
Port 5000: Flask Dashboard (existing)
Port 4000: Phoenix Dashboard (new)
```

**Benefits**:
- Zero downtime
- Can compare outputs
- Easy rollback if issues
- Gradual team adoption

### Cutover Plan

1. **Week 1-2**: Phoenix dashboard in beta
   - Team tests alongside Flask
   - Report any discrepancies
   - Fix bugs and polish

2. **Week 3**: Phoenix becomes primary
   - Update documentation
   - Train team on new features
   - Flask remains as backup

3. **Week 4+**: Deprecate Flask
   - Remove Flask from deployment
   - Archive Flask code
   - Full Phoenix adoption

### Rollback Plan

If critical issues arise:

1. Stop Phoenix application
2. Continue using Flask dashboard
3. Fix Phoenix issues offline
4. Redeploy when ready

**Risk Mitigation**:
- Extensive testing before cutover
- Gradual rollout to team
- Keep Flask code for 1 month after cutover

## Success Metrics

### Performance Targets

- **Update Latency**: < 100ms from evaluation to UI update
- **Query Performance**: < 50ms to fetch top 50 agents
- **Memory Usage**: < 100MB for Phoenix app
- **Concurrent Users**: Support 10+ simultaneous viewers
- **Data Points**: Handle 100k+ evaluations without slowdown

### Feature Completeness

- ✅ Real-time agent table updates
- ✅ Interactive performance charts
- ✅ Agent detail views (PID and Agent ID)
- ✅ Generation statistics
- ✅ Metric selection (fitness, profit, trades)
- ✅ Responsive design
- ✅ Connection status indicator

### User Experience

- **Perceived Speed**: Updates feel instant
- **Reliability**: No crashes during 24hr runs
- **Usability**: Team prefers over Flask dashboard
- **Insights**: Provides actionable training insights

## Future Enhancements

### Short Term (3-6 months)

1. **Agent Comparison Tool**
   - Select 2+ agents to compare
   - Side-by-side performance charts
   - Genotype diff visualization

2. **Training Control Panel**
   - Pause/resume population
   - Adjust mutation rates live
   - Emergency stop button

3. **Export Functionality**
   - Download agent data as CSV
   - Export charts as PNG/SVG
   - Generate training reports

### Long Term (6-12 months)

1. **Distributed Monitoring**
   - Multi-node cluster view
   - Cross-node agent migration
   - Load balancing visualization

2. **Machine Learning Insights**
   - Predict convergence time
   - Suggest hyperparameter adjustments
   - Anomaly detection

3. **Mobile App**
   - Phoenix LiveView Native
   - Push notifications
   - Remote training control

## Conclusion

This native implementation transforms the dashboard from a passive monitoring tool into an active training management interface. By leveraging Phoenix LiveView and direct Mnesia access, we gain real-time updates, better performance, and a foundation for advanced features that weren't possible with the Flask approach.

The phased implementation ensures we can validate each step before proceeding, with clear rollback options if needed. The end result will be a more powerful, maintainable, and integrated monitoring solution that grows with the DXNN-Trader system.
