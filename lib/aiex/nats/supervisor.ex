defmodule Aiex.NATS.Supervisor do
  @moduledoc """
  Supervisor for NATS infrastructure components including connection management,
  consumer supervision, and PG-to-NATS bridging.
  
  This supervisor manages all NATS-related processes and provides fault tolerance
  for the messaging infrastructure that enables Rust TUI communication.
  """
  
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    # Check if we should start embedded NATS server
    nats_config = Application.get_env(:aiex, :nats, [])
    mode = Keyword.get(nats_config, :mode, :external)
    
    # Base children that always start
    base_children = [
      # Consumer supervisor for handling messages
      {Aiex.NATS.ConsumerSupervisor, []},
      
      # PG to NATS bridge
      {Aiex.NATS.PGBridge, [gnat_conn: :nats_conn]},
      
      # Command handler supervisor
      {DynamicSupervisor, strategy: :one_for_one, name: Aiex.NATS.CommandSupervisor}
    ]
    
    # Conditionally add server manager and connection manager
    children = case mode do
      :embedded ->
        [
          # Start embedded NATS server first
          {Aiex.NATS.ServerManager, []},
          # Then connection manager with a delay to let server start
          {Aiex.NATS.ConnectionManager, [startup_delay: 2000]}
          | base_children
        ]
        
      _ ->
        [
          # External NATS - just the connection manager
          {Aiex.NATS.ConnectionManager, []}
          | base_children
        ]
    end
    
    Supervisor.init(children, strategy: :rest_for_one)
  end
end