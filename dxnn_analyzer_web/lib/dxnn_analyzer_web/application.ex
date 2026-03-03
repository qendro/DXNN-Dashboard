defmodule DxnnAnalyzerWeb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DxnnAnalyzerWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:dxnn_analyzer_web, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: DxnnAnalyzerWeb.PubSub},
      DxnnAnalyzerWeb.Endpoint,
      {DxnnAnalyzerWeb.AnalyzerBridge, []},
      DxnnAnalyzerWeb.AWS.AWSDeploymentServer
    ]

    opts = [strategy: :one_for_one, name: DxnnAnalyzerWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    DxnnAnalyzerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
