defmodule DxnnAnalyzerWeb.Layouts do
  @moduledoc "Application layout and navigation."
  use DxnnAnalyzerWeb, :html

  embed_templates "layouts/*"

  defp navigation do
    [
      %{
        label: "Workspace",
        items: [
          %{
            label: "Dashboard",
            path: ~p"/",
            icon: "grid",
            views: [
              DxnnAnalyzerWeb.DashboardLive,
              DxnnAnalyzerWeb.AgentListLive,
              DxnnAnalyzerWeb.AgentInspectorLive,
              DxnnAnalyzerWeb.PopulationListLive,
              DxnnAnalyzerWeb.SpecieListLive,
              DxnnAnalyzerWeb.TopologyViewerLive,
              DxnnAnalyzerWeb.GraphViewerLive,
              DxnnAnalyzerWeb.ComparatorLive,
              DxnnAnalyzerWeb.ContextArtifactsLive
            ]
          },
          %{
            label: "Analytics",
            path: ~p"/analytics",
            icon: "chart",
            views: [DxnnAnalyzerWeb.AgentPerformanceLive]
          },
          %{
            label: "Experiments",
            path: ~p"/settings",
            icon: "flask",
            views: [DxnnAnalyzerWeb.SettingsLive]
          }
        ]
      },
      %{
        label: "Storage",
        items: [
          %{
            label: "Oracle Object Storage",
            path: ~p"/oracle-artifacts",
            icon: "folder",
            views: [DxnnAnalyzerWeb.OracleArtifactsLive]
          },
          %{
            label: "GCS Storage",
            path: ~p"/gcp-storage",
            icon: "folder",
            views: [DxnnAnalyzerWeb.GCPStorageLive]
          },
          %{
            label: "S3 Experiments",
            path: ~p"/s3-experiments",
            icon: "layers",
            views: [DxnnAnalyzerWeb.S3ExperimentsLive]
          },
          %{
            label: "S3 Explorer",
            path: ~p"/s3-explorer",
            icon: "folder",
            views: [DxnnAnalyzerWeb.S3ExplorerLive]
          }
        ]
      },
      %{
        label: "Infrastructure",
        items: [
          %{
            label: "AWS Deployment",
            path: ~p"/aws-deployment",
            icon: "server",
            views: [DxnnAnalyzerWeb.AWSDeploymentLive, DxnnAnalyzerWeb.InstanceDetailsLive]
          },
          %{
            label: "Oracle Instances",
            path: ~p"/oracle-instances",
            icon: "server",
            views: [DxnnAnalyzerWeb.OracleInstancesLive]
          },
          %{
            label: "Oracle DXNN",
            path: ~p"/oracle-dxnn",
            icon: "server",
            views: [DxnnAnalyzerWeb.OracleDxnnLive]
          },
          %{
            label: "GCP Instances",
            path: ~p"/gcp-instances",
            icon: "server",
            views: [DxnnAnalyzerWeb.GCPInstancesLive]
          },
          %{
            label: "GCP DXNN",
            path: ~p"/gcp-dxnn",
            icon: "server",
            views: [DxnnAnalyzerWeb.GCPDxnnLive]
          },
          %{
            label: "AWS Spot Pricing",
            path: ~p"/spot-pricing",
            icon: "chart",
            views: [DxnnAnalyzerWeb.SpotPricingLive]
          },
          %{
            label: "Oracle Spot Pricing",
            path: ~p"/oracle-spot-pricing",
            icon: "chart",
            views: [DxnnAnalyzerWeb.OracleSpotPricingLive]
          }
        ]
      }
    ]
  end
end
