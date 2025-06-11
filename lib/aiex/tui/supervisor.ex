defmodule Aiex.Tui.Supervisor do
  @moduledoc """
  Supervisor for the TUI subsystem.
  
  Manages the lifecycle of TUI components with proper fault isolation
  and restart strategies.
  """
  
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    children = [
      # TUI GenServer with restart strategy
      {Aiex.Tui.LibvaxisTui, [pg_group: :aiex_tui]}
    ]
    
    # One-for-one strategy: if TUI crashes, only restart TUI
    Supervisor.init(children, strategy: :one_for_one)
  end
end