defmodule Aiex.Release.Supervisor do
  @moduledoc """
  Supervisor for release management components.
  
  Manages distributed release coordination, health endpoints, and deployment automation
  for production cluster operations.
  """
  
  use Supervisor
  require Logger
  
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    # Get release configuration
    release_config = Application.get_env(:aiex, :release, [])
    
    children = [
      # Distributed release coordination
      {Aiex.Release.DistributedRelease, []},
      
      # Health check endpoints
      health_endpoint_spec(release_config),
      
      # Deployment automation (only in production cluster mode)
      deployment_automation_spec(release_config)
    ]
    |> Enum.reject(&is_nil/1)
    
    Logger.info("Starting release supervisor with #{length(children)} components")
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  # Child specification builders
  
  defp health_endpoint_spec(config) do
    if Keyword.get(config, :health_endpoint_enabled, true) do
      health_config = [
        port: Keyword.get(config, :health_port, 8090)
      ]
      
      {Aiex.Release.HealthEndpoint, health_config}
    end
  end
  
  defp deployment_automation_spec(config) do
    # Only enable in cluster mode or if explicitly configured
    cluster_enabled = Application.get_env(:aiex, :cluster_enabled, false)
    automation_enabled = Keyword.get(config, :deployment_automation_enabled, cluster_enabled)
    
    if automation_enabled do
      {Aiex.Release.DeploymentAutomation, []}
    end
  end
end