defmodule Aiex do
  @moduledoc """
  Aiex - Distributed AI-powered Elixir coding assistant.

  This module provides the main entry point and distributed supervision tree 
  for the Aiex application using OTP primitives for scalability and fault tolerance.
  """

  use Application

  @impl true
  def start(_type, _args) do
    # pg is started automatically by OTP, no need to start it manually

    children = [
      # Core infrastructure
      {Registry, keys: :unique, name: Aiex.Registry},
      {Horde.Registry, name: Aiex.HordeRegistry, keys: :unique},
      {Horde.DynamicSupervisor, name: Aiex.HordeSupervisor, strategy: :one_for_one},
      
      # Distributed event bus
      Aiex.Events.EventBus,
      
      # HTTP Client for LLM requests
      {Finch, name: AiexFinch},

      # Distributed context management
      Aiex.Context.DistributedEngine,
      {Horde.Registry, name: Aiex.Context.SessionRegistry, keys: :unique},
      Aiex.Context.Manager,
      Aiex.Context.SessionSupervisor,

      # Sandbox Configuration
      Aiex.Sandbox.Config,

      # Audit Logger
      Aiex.Sandbox.AuditLogger,

      # LLM Rate Limiter
      Aiex.LLM.RateLimiter,

      # LLM Client (optional - only start if configured)
      llm_client_spec(),
      
      # Cluster coordination (if libcluster is configured)
      cluster_supervisor()
    ]
    |> Enum.reject(&is_nil/1)

    opts = [strategy: :one_for_one, name: Aiex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Private functions

  defp cluster_supervisor do
    # Only start cluster supervisor if topology is configured
    case Application.get_env(:libcluster, :topologies) do
      nil -> nil
      topologies -> {Cluster.Supervisor, [topologies, [name: Aiex.ClusterSupervisor]]}
    end
  end

  defp llm_client_spec do
    # Only start LLM client if properly configured
    # For now, we'll skip it to allow basic CLI functionality
    # In a full implementation, this would check for API keys
    nil
  end
end
