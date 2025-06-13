defmodule Aiex.Telemetry.Supervisor do
  @moduledoc """
  Supervisor for all telemetry and monitoring components.
  
  Manages the telemetry infrastructure including distributed aggregation,
  Prometheus export, structured logging, distributed tracing, and cluster dashboard.
  """
  
  use Supervisor
  require Logger
  
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    # Get telemetry configuration
    telemetry_config = Application.get_env(:aiex, :telemetry, [])
    
    children = [
      # Core telemetry aggregation
      {Aiex.Telemetry.DistributedAggregator, []},
      
      # Prometheus metrics export
      prometheus_exporter_spec(telemetry_config),
      
      # Distributed tracing
      distributed_tracer_spec(telemetry_config),
      
      # Cluster dashboard
      cluster_dashboard_spec(telemetry_config)
    ]
    |> Enum.reject(&is_nil/1)
    
    Logger.info("Starting telemetry supervisor with #{length(children)} components")
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  # Child specification builders
  
  defp prometheus_exporter_spec(config) do
    if Keyword.get(config, :prometheus_enabled, true) do
      prometheus_config = [
        port: Keyword.get(config, :prometheus_port, 9090)
      ]
      
      {Aiex.Telemetry.PrometheusExporter, prometheus_config}
    end
  end
  
  defp distributed_tracer_spec(config) do
    if Keyword.get(config, :tracing_enabled, true) do
      tracing_config = [
        sampling_rate: Keyword.get(config, :tracing_sampling_rate, 1.0),
        export_endpoint: Keyword.get(config, :tracing_export_endpoint),
        enabled: true
      ]
      
      {Aiex.Telemetry.DistributedTracer, tracing_config}
    end
  end
  
  defp cluster_dashboard_spec(config) do
    if Keyword.get(config, :dashboard_enabled, true) do
      dashboard_config = [
        port: Keyword.get(config, :dashboard_port, 8080),
        alert_rules: Keyword.get(config, :custom_alert_rules, [])
      ]
      
      {Aiex.Telemetry.ClusterDashboard, dashboard_config}
    end
  end
end