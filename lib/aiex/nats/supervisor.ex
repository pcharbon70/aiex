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
    children = [
      # NATS connection management
      {Aiex.NATS.ConnectionManager, []},
      
      # Consumer supervisor for handling messages
      {Aiex.NATS.ConsumerSupervisor, []},
      
      # PG to NATS bridge
      {Aiex.NATS.PGBridge, [gnat_conn: :nats_conn]},
      
      # Command handler supervisor
      {DynamicSupervisor, strategy: :one_for_one, name: Aiex.NATS.CommandSupervisor}
    ]
    
    Supervisor.init(children, strategy: :rest_for_one)
  end
end