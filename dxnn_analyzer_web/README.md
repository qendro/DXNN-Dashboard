# DXNN Analyzer Web Interface

Phoenix LiveView web interface for the DXNN Analyzer.

## Documentation

Please see the main project documentation:

- **[README.md](../README.md)** - Complete user guide, installation, and usage
- **[ARCHITECTURE.md](../ARCHITECTURE.md)** - Technical architecture and design
- **[AI_README.md](../AI_README.md)** - Guide for AI assistants and developers

## Quick Start

### With Docker (Recommended)

```bash
cd ..
docker-compose up -d
```

Access at `http://localhost:4000`

### Local Development

```bash
# Install dependencies
mix deps.get
cd assets && npm install && cd ..

# Compile Erlang analyzer
cd ../dxnn_analyzer && rebar3 compile && cd ../dxnn_analyzer_web

# Start server
mix phx.server
```

Access at `http://localhost:4000`

### Windows Quick Setup

```powershell
.\setup.ps1
.\start.ps1
```

## Project Structure

```
lib/
├── dxnn_analyzer_web/
│   ├── live/              # LiveView pages
│   ├── components/        # Reusable components
│   ├── analyzer_bridge.ex # Erlang ↔ Elixir bridge
│   ├── endpoint.ex        # Phoenix endpoint
│   └── router.ex          # Routes
assets/
├── js/                    # JavaScript
└── css/                   # Tailwind CSS
config/                    # Configuration files
```

## Features

- Dashboard for loading and managing Mnesia contexts
- Agent browser with filtering and search
- Detailed agent inspection
- **Interactive Graph Visualization** - D3.js powered neural network visualization with:
  - Multiple layout algorithms (hierarchical, force-directed, circular)
  - Interactive node selection and details
  - Real-time zoom and pan
  - Connection weight visualization
  - Layer structure analysis
- Neural network topology viewer (raw data)
- Multi-agent comparison
- **Master Database** - Curate and manage elite agents across experiments:
  - Select agents from any loaded context
  - Save to centralized master database
  - View and manage your collection
  - Load master database as a context for analysis
  - Export for deployment to DXNN-Trader
- Real-time updates via LiveView

## Development

```bash
# Start server with IEx
iex -S mix phx.server

# Run tests
mix test

# Format code
mix format

# Compile assets
cd assets && npm run deploy
```

## Configuration

Edit `config/dev.exs` or `config/prod.exs` to change settings:

```elixir
config :dxnn_analyzer_web, DxnnAnalyzerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000]
```

## License

Apache 2.0

## UI maintenance

The shared layout and navigation are in `lib/dxnn_analyzer_web/components/layouts*`.
Page headings and icons are in `core_components.ex`; shared styles are in
`assets/css/app.css`. Use these components and button variants for all pages.

Run `mix check` for formatting and Elixir tests, and `npm test` in `assets` for
JavaScript tests. Compile the Erlang analyzer first and add its build directory to
`ERL_LIBS` when developing locally. Tests supervise their own services and do not
invoke live cloud operations.

The standard Docker deployment is `../compose.sh up -d --build`, available on
http://localhost:4000. Its `data` directory links to the persistent `/app/data` volume,
which holds saved experiment links, settings, and cached downloads.

## GCP instances

**Infrastructure → GCP Instances** (`/gcp-instances`) launches and manages
Compute Engine VMs from `AWS-Deployment/config/*.yml` files that define
`project` and `machine_type` (see AWS-Deployment's README, "GCP"). Like the
Oracle page, every operation runs `AWS-Deployment/scripts/gcp_manager.py` in the
`aws-deployment:latest` image through `scripts/gcp_dashboard.py`, serialized by a
second `OCIServer` instance (`GCPBridge.server_opts/0`). Compose passes
`GCP_CREDENTIALS_FILE` (default:
`AWS-Deployment/output/gcp-auth/application_default_credentials.json`, written by
`AWS-Deployment/gcp-login.sh` and mounted read-only into the operation container
only), `GCP_AUTH` (`adc` or `metadata`) and optional
`GOOGLE_CLOUD_QUOTA_PROJECT`. Compute Engine's stopped state (`TERMINATED`) is
shown as `STOPPED`; **Reset** is a hard reset.

## Oracle preemptible pricing

Open **Infrastructure → Oracle Spot Pricing** (`/oracle-spot-pricing`) to compare
current public USD CPU and GPU rates. CPU Flex rows cover AMD, Intel, and Arm;
GPU rows include `VM.GPU.A10.1`, `VM.GPU.A10.2`, `VM.GPU3.1`, `VM.GPU2.1`, and
`BM.GPU.L40S.4`. Filter CPU/GPU rows and set Flex OCPUs, memory, and monthly hours
to recalculate sortable hourly, monthly, per-vCPU, per-GPU, and per-GB estimates.
GPU configurations are fixed; their instance price is the per-GPU rate multiplied
by GPU count, including host CPU and RAM. Prices load asynchronously
from [Oracle's public catalog](https://apexapps.oracle.com/pls/apex/cetools/api/v1/products/?currencyCode=USD)
without OCI or AWS credentials.

Preemptible estimates apply [Oracle's published 50% discount](https://docs.oracle.com/en-us/iaas/Content/Compute/Concepts/preemptible.htm)
to eligible shapes. GPU2/GPU3 have preemptible estimates; A10 is not listed in
Oracle's current preemptible support list, and bare metal is excluded. Those rows
show on-demand prices with unavailable spot prices. Estimates exclude storage,
network, paid images, taxes, account
discounts, and free-tier allowances, and do not verify regional capacity. Missing
or changed SKUs are shown as unavailable rather than zero-priced. The existing
AWS page remains at `/spot-pricing`, labelled **AWS Spot Pricing**.

### Local preview connections

`MIX_ENV=test mix run --no-start scripts/local_preview.exs` starts the local
preview with an exact LiveView origin allowlist for both `localhost` and
`127.0.0.1`. The internal HTTP port defaults to 4010 and the published port to
49417; override them with `DXNN_PREVIEW_PORT` and `DXNN_PREVIEW_PUBLIC_PORT` when
using a different Docker port mapping. Origin checking stays enabled. Production
local-host deployments similarly accept both loopback names on their configured
HTTP port.
