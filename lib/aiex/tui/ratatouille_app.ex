defmodule Aiex.TUI.RatatouilleApp do
  @moduledoc """
  Main Ratatouille TUI application implementing The Elm Architecture (TEA) pattern.
  
  This module provides a sophisticated terminal user interface for the Aiex coding
  assistant with chat-focused layout, real-time context awareness, and seamless
  integration with the distributed OTP application.
  """
  
  # Only implement Ratatouille.App behaviour if Ratatouille is available
  if Code.ensure_loaded?(Ratatouille.App) do
    @behaviour Ratatouille.App
  end
  
  alias Aiex.TUI.{State, EventHandler}
  alias Aiex.TUI.Communication.OTPBridge
  alias Aiex.InterfaceGateway
  
  require Logger
  
  @interface_id :tui_interface
  
  ## Ratatouille App callbacks
  
  @impl true
  def init(_context) do
    # Initialize TUI state
    initial_state = State.new()
    
    # Register with InterfaceGateway
    interface_config = %{
      type: :tui,
      session_id: "tui_session_#{System.unique_integer([:positive])}",
      user_id: nil,
      capabilities: [:text_input, :text_output, :real_time_updates],
      settings: %{
        layout: :chat_focused,
        panels: [:conversation, :context, :status, :actions]
      }
    }
    
    case InterfaceGateway.register_interface(__MODULE__, interface_config) do
      {:ok, interface_id} ->
        Logger.info("TUI registered with InterfaceGateway: #{interface_id}")
        
        # Subscribe to pg events for real-time updates
        :pg.join(:aiex_events, :tui_updates, self())
        
        updated_state = %{initial_state | interface_id: interface_id}
        {updated_state, Ratatouille.Command.new(fn -> :initial_load_complete end)}
        
      {:error, reason} ->
        Logger.error("Failed to register TUI interface: #{reason}")
        {initial_state, Ratatouille.Command.none()}
    end
  end

  @impl true
  def update(model, msg) do
    EventHandler.handle_event(model, msg)
  end

  @impl true
  def render(model) do
    View.render(model)
  end

  @impl true
  def subscribe(_model) do
    # Subscribe to periodic updates for real-time features
    [
      Ratatouille.Runtime.Subscription.interval(100, :tick),
      Ratatouille.Runtime.Subscription.interval(1000, :status_update),
      Ratatouille.Runtime.Subscription.interval(5000, :context_refresh)
    ]
  end
  
  ## Public API for OTP integration
  
  @doc """
  Sends a message to the TUI application.
  """
  def send_message(message) do
    send(self(), {:tui_message, message})
  end
  
  @doc """
  Updates the TUI with new context information.
  """
  def update_context(context) do
    send(self(), {:context_update, context})
  end
  
  @doc """
  Notifies TUI of AI response.
  """
  def ai_response(response) do
    send(self(), {:ai_response, response})
  end
end