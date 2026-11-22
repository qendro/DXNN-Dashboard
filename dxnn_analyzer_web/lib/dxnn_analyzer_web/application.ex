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
      {DxnnAnalyzerWeb.ContextRegistry, []},
      {DxnnAnalyzerWeb.AnalyzerBridge, []},
      DxnnAnalyzerWeb.AWS.AWSDeploymentServer,
      {Task.Supervisor, name: DxnnAnalyzerWeb.OCI.TaskSupervisor},
      {DxnnAnalyzerWeb.OCI.OCIServer, []},
      {Task.Supervisor, name: DxnnAnalyzerWeb.GCP.TaskSupervisor},
      Supervisor.child_spec(
        {DxnnAnalyzerWeb.OCI.OCIServer, DxnnAnalyzerWeb.GCP.GCPBridge.server_opts()},
        id: DxnnAnalyzerWeb.GCP.Server
      )
    ]

    children =
      if System.get_env("DXNN_ENABLE_AWS", "true") == "false",
        do: Enum.reject(children, &(&1 == DxnnAnalyzerWeb.AWS.AWSDeploymentServer)),
        else: children

    children =
      if Application.get_env(:dxnn_analyzer_web, :start_services, true), do: children, else: []

    opts = [strategy: :one_for_one, name: DxnnAnalyzerWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    DxnnAnalyzerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
