defmodule Aiex do
  @moduledoc """
  Aiex - AI-powered Elixir coding assistant.
  
  This module provides the main entry point and supervision tree for the Aiex application.
  """
  
  use Application
  
  @impl true
  def start(_type, _args) do
    children = [
      # Context Management
      Aiex.Context.Engine,
      
      # Sandbox Configuration
      Aiex.Sandbox.Config,
      
      # Audit Logger
      Aiex.Sandbox.AuditLogger
    ]
    
    opts = [strategy: :one_for_one, name: Aiex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
