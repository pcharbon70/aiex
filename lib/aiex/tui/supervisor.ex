defmodule Aiex.TUI.Supervisor do
  @moduledoc """
  Supervisor for TUI communication infrastructure.

  Manages the TCP server and event bridge for Rust TUI integration.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # Check if TUI server is enabled
    tui_config = Application.get_env(:aiex, :tui, [])
    enabled = Keyword.get(tui_config, :enabled, true)

    children =
      if enabled do
        [
          # TCP server for TUI connections
          {Aiex.TUI.Server, Keyword.merge(tui_config, opts)},

          # Event bridge for PG -> TUI events
          {Aiex.TUI.EventBridge, []},

          # Command handler supervisor
          {DynamicSupervisor, strategy: :one_for_one, name: Aiex.TUI.CommandSupervisor}
        ]
      else
        []
      end

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
