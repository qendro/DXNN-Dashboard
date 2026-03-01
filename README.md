# DXNN Analyzer Web Interface

A modern Phoenix LiveView web application for analyzing DXNN (Deep eXtended Neural Network) trading agents. Provides real-time interactive analysis of neuroevolution experiments through your browser with seamless Erlang-Elixir integration.

## Overview

DXNN Analyzer Web Interface combines a powerful Erlang-based analysis engine with a modern Phoenix LiveView frontend to provide comprehensive tools for analyzing, comparing, and managing DXNN trading agents across multiple experiments.

**Key Components:**
- **Erlang Analyzer** (`dxnn_analyzer/`) - Core analysis engine with multi-context support
- **Phoenix Web Interface** (`dxnn_analyzer_web/`) - Real-time browser-based UI
- **Master Database** - Centralized repository for elite agents across experiments

## Features

### Analysis & Inspection
- **Multi-Context Management** - Load and analyze multiple Mnesia databases simultaneously
- **Agent Browser** - View, filter, and search agents with real-time updates
- **Deep Inspection** - Detailed analysis of fitness, topology, and evolution history
- **Topology Visualization** - Interactive neural network structure viewer with D3.js
- **Mutation Tracking** - Evolution history and mutation pattern analysis

### Comparison & Statistics
- **Multi-Agent Comparison** - Side-by-side comparison with similarity scoring
- **Statistical Analysis** - Comprehensive metrics and distribution analysis
- **Performance Metrics** - Fitness tracking, generation statistics, topology metrics

### Population Management
- **Master Database** - Curate elite agents across all experiments
- **Population Builder** - Create new populations from selected agents
- **Validation** - Comprehensive integrity checks on all outputs
- **DXNN-Trader Integration** - Full compatibility with DXNN-Trader format

### Real-Time Interface
- **LiveView Updates** - Instant UI updates without page refreshes
- **Interactive Dashboard** - Manage contexts and view summaries
- **Responsive Design** - Modern Tailwind CSS interface

## Quick Start

### Prerequisites

- **Docker & Docker Compose** (recommended) OR
- **Elixir 1.14+**, **Erlang/OTP 26+**, **Node.js 18+**, **Rebar3**

### Option 1: Docker (Recommended)

1. **Start the application:**
```bash
docker-compose up -d
```

2. **Access the interface:**
Open your browser to `http://localhost:4000`

3. **Load a context:**
   - Navigate to Dashboard
   - Path: `/app/DXNN-Trader-V2/DXNN-Trader-v2/Mnesia.nonode@nohost`
   - Name: `exp1`
   - Click "Load Context"

4. **Stop the application:**
```bash
docker-compose down
```

### Option 2: Local Development

1. **Install Elixir dependencies:**
```bash
cd dxnn_analyzer_web
mix deps.get
cd assets && npm install && cd ..
```

2. **Compile Erlang analyzer:**
```bash
cd ../dxnn_analyzer
rebar3 compile
cd ../dxnn_analyzer_web
```

3. **Start the server:**
```bash
mix phx.server
```

4. **Access at:** `http://localhost:4000`

### Windows Quick Setup

```powershell
cd dxnn_analyzer_web
.\setup.ps1
.\start.ps1
```

## Usage Guide

### Loading Contexts

A "context" is a loaded Mnesia database that you can analyze:

1. Navigate to Dashboard (`/`)
2. Enter Mnesia folder path (e.g., `./Databases/Mnesia.nonode@nohost`)
3. Provide context name (e.g., `exp1`, `experiment_2024`)
4. Click "Load Context"

The context loads into memory as ETS tables for fast querying. Original Mnesia files remain unchanged.

### Viewing & Filtering Agents

1. Click "View Agents" on a loaded context
2. Use filters:
   - **Show best N agents** - Display only top performers
   - **Sort by** - Fitness or generation
   - **Search** - Filter by ID or properties
3. Select agents using checkboxes
4. Actions:
   - **Inspect** - Detailed agent view
   - **Topology** - Network structure
   - **Compare** - Multi-agent comparison
   - **Save to Master** - Add to master database

### Agent Inspection

View comprehensive agent details:
- **Basic Info** - ID, fitness, generation, encoding type
- **Topology Summary** - Sensors, neurons, actuators, layers
- **Network Statistics** - Connections, depth, width, cycles
- **Evolution History** - Mutation timeline and patterns
- **Quick Actions** - View topology, compare with others

### Topology Visualization

Interactive neural network visualization:
- **Multiple Layouts** - Hierarchical, force-directed, circular
- **Interactive Nodes** - Click for details, drag to reposition
- **Connection Weights** - Visual representation of weights
- **Layer Analysis** - Structure and depth visualization
- **Zoom & Pan** - Navigate large networks

### Comparing Agents

Compare multiple agents side-by-side:

1. Select 2+ agents using checkboxes
2. Click "Compare Selected"
3. View comparison:
   - **Fitness Metrics** - Sorted performance comparison
   - **Topology Statistics** - Network structure differences
   - **Structural Similarity** - Similarity matrix (0.0-1.0)
   - **Evolution History** - Mutation patterns
   - **Common Mutations** - Shared evolutionary changes

### Master Database

Build and manage your collection of elite agents:

**Saving Agents:**
1. Load a context and view agents
2. Select agents using checkboxes
3. Click "Save to Master Database"
4. Agents are copied (originals unchanged)

**Viewing Master Database:**
1. Click "Master Database" in navigation
2. View all curated agents sorted by fitness
3. Select and remove agents as needed
4. Load as context for analysis

**Using Master Database:**
- **Load as Context** - Analyze using all analyzer features
- **Deploy to DXNN-Trader** - Copy `./data/MasterDatabase/Mnesia.nonode@nohost` to DXNN-Trader
- **Export Subset** - Create deployment-ready populations
- **Backup** - Regularly backup `./data/MasterDatabase/` folder

**Best Practices:**
- Curate after each experiment
- Keep only truly elite agents
- Use descriptive context names
- Regular backups of master database

## Docker Configuration

### Custom Mnesia Folder Location

Edit `docker-compose.yml` to mount your Mnesia folders:

```yaml
volumes:
  - /path/to/your/mnesia:/app/mnesia:ro
```

Then use path `/app/mnesia/Mnesia.nonode@nohost` in the interface.

### Environment Variables

Create `.env` file:

```bash
SECRET_KEY_BASE=your_generated_secret_key_min_64_chars
PHX_HOST=your-domain.com
PORT=4000
```

Run with custom configuration:
```bash
docker-compose --env-file .env up -d
```

### Development with Hot Reload

```bash
docker-compose --profile dev up dxnn_analyzer_dev
```

This mounts source code for live editing.

### Docker Commands

```bash
# View logs
docker-compose logs -f

# Rebuild after changes
docker-compose build
docker-compose up -d

# Stop and remove containers
docker-compose down
```

## Project Structure

```
.
├── dxnn_analyzer/              # Erlang analyzer (backend)
│   ├── src/                    # Erlang source files
│   │   ├── analyzer.erl            # Main API
│   │   ├── mnesia_loader.erl       # Context management
│   │   ├── agent_inspector.erl     # Agent analysis
│   │   ├── topology_mapper.erl     # Network mapping
│   │   ├── mutation_analyzer.erl   # Evolution tracking
│   │   ├── comparator.erl          # Agent comparison
│   │   ├── stats_collector.erl     # Statistics
│   │   ├── population_builder.erl  # Population creation
│   │   └── master_database.erl     # Master DB management
│   ├── include/                # Header files
│   │   ├── records.hrl             # Mnesia record definitions
│   │   └── analyzer_records.hrl    # Analyzer-specific records
│   ├── priv/examples/          # Example scripts
│   └── rebar.config            # Erlang build config
│
├── dxnn_analyzer_web/          # Phoenix web interface
│   ├── lib/
│   │   └── dxnn_analyzer_web/
│   │       ├── live/               # LiveView pages
│   │       │   ├── dashboard_live.ex       # Main dashboard
│   │       │   ├── agent_list_live.ex      # Agent listing
│   │       │   ├── agent_inspector_live.ex # Agent details
│   │       │   ├── topology_viewer_live.ex # Network topology
│   │       │   ├── comparator_live.ex      # Agent comparison
│   │       │   └── master_database_live.ex # Master DB management
│   │       ├── components/         # Reusable UI components
│   │       ├── analyzer_bridge.ex  # Erlang ↔ Elixir bridge
│   │       ├── application.ex      # Application supervisor
│   │       ├── endpoint.ex         # Phoenix endpoint
│   │       └── router.ex           # Route definitions
│   ├── assets/                 # Frontend assets
│   │   ├── js/
│   │   │   ├── app.js              # LiveView JavaScript
│   │   │   └── network_graph.js    # D3.js visualization
│   │   └── css/
│   │       └── app.css             # Tailwind CSS
│   ├── config/                 # Configuration
│   └── mix.exs                 # Elixir dependencies
│
├── Databases/                  # Sample Mnesia databases
├── Dockerfile                  # Production image
├── Dockerfile.dev              # Development image
├── docker-compose.yml          # Docker orchestration
├── README.md                   # This file
├── ARCHITECTURE.md             # Technical architecture
└── AI_README.md                # AI assistant guide
```

## Configuration

### Phoenix Configuration

Edit `dxnn_analyzer_web/config/dev.exs` or `config/prod.exs`:

```elixir
config :dxnn_analyzer_web, DxnnAnalyzerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  secret_key_base: "your-secret-key"
```

### Analyzer Bridge

The bridge automatically finds compiled Erlang modules in `../dxnn_analyzer/ebin`.

To use a different path, modify `lib/dxnn_analyzer_web/analyzer_bridge.ex`:

```elixir
analyzer_path = Path.expand("/custom/path/to/ebin")
```

## Troubleshooting

### Docker Issues

**Container won't start:**
```bash
docker-compose logs dxnn_analyzer_web
docker-compose build --no-cache
```

**Port already in use:**
```yaml
# Change port in docker-compose.yml
ports:
  - "4001:4000"
```

**Can't access Mnesia files:**
- Check volume mount in `docker-compose.yml`
- Ensure path is correct and readable
- Verify file permissions

### Local Development Issues

**"Analyzer module not found":**
```bash
cd dxnn_analyzer
rebar3 compile
ls ebin/*.beam  # Verify beam files exist
```

**"Port 4000 already in use":**
```bash
# Change port in config/dev.exs
# Or kill process (Unix): lsof -ti:4000 | xargs kill
# Windows: netstat -ano | findstr :4000
```

**Assets not loading:**
```bash
cd dxnn_analyzer_web/assets
npm install
npm run deploy
```

**Mix dependencies error:**
```bash
cd dxnn_analyzer_web
mix deps.clean --all
mix deps.get
```

### Runtime Issues

**Context fails to load:**
- Verify Mnesia path is correct
- Check file permissions
- Ensure Mnesia folder contains valid tables (*.DCD, *.DAT files)

**Slow performance with large populations:**
- Use "Show best agents only" filter
- Limit results to 50-100 agents
- Unload unused contexts to free memory

**WebSocket disconnects:**
- Check firewall settings
- Verify network stability
- Check browser console for errors

## Performance Considerations

### Recommended Limits

- **Agents per page:** 50-100
- **Concurrent contexts:** 5-10
- **Max agent selection:** 10 for comparison
- **Context size:** Up to 1000+ agents per context

### Optimization Tips

1. **Use filters** to reduce data transfer
2. **Unload unused contexts** to free memory
3. **Enable pagination** for large populations
4. **Use "best agents only"** filter
5. **Load master database** as context for analysis

### Memory Usage

- Each context: ~10-50 MB (depends on population size)
- Each LiveView connection: ~1-5 MB
- Erlang analyzer: ~50-200 MB base

## Production Deployment

### Generate Secret Key

```bash
mix phx.gen.secret
```

### Build Production Image

```bash
docker build -t dxnn_analyzer_web:latest .
```

### Run Production Container

```bash
docker run -d \
  -p 4000:4000 \
  -e SECRET_KEY_BASE="your-secret-key" \
  -e PHX_HOST="your-domain.com" \
  -v /path/to/mnesia:/app/mnesia:ro \
  --name dxnn_analyzer \
  dxnn_analyzer_web:latest
```

### Reverse Proxy (Nginx)

```nginx
server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://localhost:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Security

### Production Checklist

- [ ] Generate secure `SECRET_KEY_BASE` (min 64 characters)
- [ ] Use HTTPS in production
- [ ] Set proper `PHX_HOST`
- [ ] Configure firewall rules
- [ ] Implement authentication (if needed)
- [ ] Set up monitoring and logging
- [ ] Regular security updates
- [ ] Backup Mnesia data regularly

### Authentication (Optional)

For adding authentication, consider:
- [Pow](https://github.com/danschultzer/pow) - Complete authentication solution
- [Guardian](https://github.com/ueberauth/guardian) - Token-based authentication
- [Phx.Gen.Auth](https://hexdocs.pm/phoenix/mix_phx_gen_auth.html) - Phoenix built-in auth

## Development

### Running Tests

```bash
# Elixir tests
cd dxnn_analyzer_web
mix test
mix test --cover

# Erlang tests
cd dxnn_analyzer
rebar3 eunit
```

### Code Formatting

```bash
# Format Elixir code
cd dxnn_analyzer_web
mix format

# Check formatting
mix format --check-formatted
```

### Adding New Features

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed development guide.

## Integration with DXNN-Trader

### Workflow

1. **Run DXNN-Trader experiment**
2. **Copy Mnesia folder** for analysis
3. **Load in analyzer** and analyze agents
4. **Select best agents** based on fitness
5. **Create elite population** or save to master database
6. **Copy back to DXNN-Trader** for continued evolution

### Example Workflow

```bash
# After DXNN experiment
cp -r DXNN-Trader-V2/DXNN-Trader-v2/Mnesia.nonode@nohost ./experiment_backup/

# Use web interface to:
# 1. Load context from ./experiment_backup/Mnesia.nonode@nohost
# 2. Select top 10 agents
# 3. Save to master database or create new population

# Copy back to DXNN-Trader
rm -rf DXNN-Trader-V2/DXNN-Trader-v2/Mnesia.nonode@nohost
cp -r ./data/MasterDatabase/Mnesia.nonode@nohost DXNN-Trader-V2/DXNN-Trader-v2/
```

## Command-Line Usage (Erlang Analyzer)

For advanced users, the Erlang analyzer can be used directly:

```bash
cd dxnn_analyzer
make shell
```

```erlang
%% Start analyzer
analyzer:start().

%% Load context
analyzer:load("../Databases/Mnesia.nonode@nohost", exp1).

%% Find best agents
Best = analyzer:find_best(10, [{context, exp1}]).

%% Inspect agent
[Agent|_] = Best.
analyzer:inspect(Agent#agent.id, exp1).

%% Create population
Ids = [A#agent.id || A <- Best].
analyzer:create_population(Ids, elite, "./output/").
```

See `dxnn_analyzer/README.md` for complete Erlang API documentation.

## Resources

- [Phoenix Framework](https://www.phoenixframework.org/)
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/)
- [Elixir](https://elixir-lang.org/)
- [Erlang](https://www.erlang.org/)
- [Docker](https://www.docker.com/)
- [Tailwind CSS](https://tailwindcss.com/)
- [D3.js](https://d3js.org/)

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## Future Enhancements

- [ ] Advanced filtering and search capabilities
- [ ] Real-time evolution monitoring
- [ ] Export reports as PDF
- [ ] Multi-experiment comparison dashboard
- [ ] Mutation timeline visualization
- [ ] REST API for external tools
- [ ] Agent simulation and testing
- [ ] Performance prediction models

## License

Apache 2.0

## Support

For issues and questions:
- Check [Troubleshooting](#troubleshooting) section
- Review [ARCHITECTURE.md](ARCHITECTURE.md) for technical details
- Check Docker logs: `docker-compose logs -f`
- Review Phoenix logs in the terminal

## Acknowledgments

Built for the DXNN-Trader-V2 project, providing a modern web interface for neuroevolution analysis and agent management.

---

**Version:** 0.1.0  
**Last Updated:** 2024
