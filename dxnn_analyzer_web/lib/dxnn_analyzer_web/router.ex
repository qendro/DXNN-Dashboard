defmodule DxnnAnalyzerWeb.Router do
  use DxnnAnalyzerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DxnnAnalyzerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", DxnnAnalyzerWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/settings", SettingsLive, :index
    live "/agents", AgentListLive, :index
    live "/agents/:id", AgentInspectorLive, :show
    live "/topology/:id", TopologyViewerLive, :show
    live "/graph/:id", GraphViewerLive, :show
    live "/compare", ComparatorLive, :index
    live "/populations", PopulationListLive, :index
    live "/species", SpecieListLive, :index
    live "/aws-deployment", AWSDeploymentLive, :index
    live "/aws-deployment/instance/:instance_id", InstanceDetailsLive, :show
    live "/s3-experiments", S3ExperimentsLive, :index
  end

  if Application.compile_env(:dxnn_analyzer_web, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DxnnAnalyzerWeb.Telemetry
    end
  end
end
