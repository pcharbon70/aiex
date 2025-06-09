defmodule Aiex.TUI.Supervisor do
  @moduledoc """
  Supervisor for Ratatouille TUI application.
  
  Manages the Ratatouille runtime and TUI application lifecycle with
  OTP integration and distributed coordination.
  """
  
  use Supervisor
  require Logger
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    # Check if TUI is enabled
    tui_config = Application.get_env(:aiex, :tui, [])
    enabled = Keyword.get(tui_config, :enabled, true)
    
    children =
      if enabled do
        # Check if Ratatouille is available
        case Code.ensure_loaded(Ratatouille.Runtime.Supervisor) do
          {:module, _} ->
            Logger.info("Starting Ratatouille TUI application")
            
            [
              # Ratatouille runtime supervisor
              {Ratatouille.Runtime.Supervisor, 
               [
                 runtime: [
                   app: Aiex.TUI.RatatouilleApp,
                   quit_events: [
                     {:key, :ctrl_c},
                     {:key, :ctrl_q}
                   ],
                   shutdown: 1000
                 ]
               ]},
              
              # OTP Bridge for TUI-OTP communication
              {Aiex.TUI.Communication.OTPBridge, []},
              
              # Event bridge for pg events (reuse existing)
              {Aiex.TUI.EventBridge, []}
            ]
            
          {:error, :nofile} ->
            Logger.info("Ratatouille not available, starting Mock TUI")
            
            [
              # Mock TUI for development
              {Aiex.TUI.MockTUI, []},
              
              # OTP Bridge for TUI-OTP communication
              {Aiex.TUI.Communication.OTPBridge, []},
              
              # Event bridge for pg events (reuse existing)
              {Aiex.TUI.EventBridge, []}
            ]
        end
      else
        Logger.info("TUI disabled in configuration")
        []
      end
    
    Supervisor.init(children, strategy: :rest_for_one)
  end
  
  @doc """
  Starts the TUI in development mode.
  """
  def start_dev_tui do
    case Application.get_env(:aiex, :tui, []) do
      config when is_list(config) ->
        Application.put_env(:aiex, :tui, Keyword.put(config, :enabled, true))
        restart_tui()
        
      _ ->
        Application.put_env(:aiex, :tui, enabled: true)
        restart_tui()
    end
  end
  
  @doc """
  Stops the TUI application.
  """
  def stop_tui do
    Application.put_env(:aiex, :tui, enabled: false)
    restart_tui()
  end
  
  defp restart_tui do
    case Supervisor.restart_child(Aiex.Supervisor, __MODULE__) do
      {:ok, _child} -> :ok
      {:ok, _child, _info} -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end