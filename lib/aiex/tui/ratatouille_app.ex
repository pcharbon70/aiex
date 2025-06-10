defmodule Aiex.TUI.RatatouilleApp do
  @moduledoc """
  Stub for Ratatouille TUI application.
  
  This module provides a placeholder implementation when Ratatouille is not available.
  The actual TUI functionality is provided by Ratatouille when it's properly installed.
  """
  
  alias Aiex.TUI.{State, EventHandler}
  alias Aiex.TUI.Communication.OTPBridge
  alias Aiex.InterfaceGateway
  
  require Logger
  
  @interface_id :tui_interface
  
  # Stub implementations when Ratatouille is not available
  
  def init(_context) do
    # Initialize minimal state
    initial_state = State.new()
    
    # Log that we're using stub implementation
    Logger.info("Ratatouille not available - using stub TUI implementation")
    
    # Return minimal state
    {initial_state, nil}
  end
  
  def update(state, _msg) do
    # No-op update
    state
  end
  
  def render(state) do
    # Delegate to stub view
    Aiex.TUI.View.render(state)
  end
  
  def handle_event(state, _event) do
    # No-op event handling
    {state, nil}
  end
  
  # Helper to check if Ratatouille is available
  def ratatouille_available? do
    Code.ensure_loaded?(Ratatouille.App)
  end
end