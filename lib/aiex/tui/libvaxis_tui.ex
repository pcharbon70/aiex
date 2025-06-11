defmodule Aiex.Tui.LibvaxisTui do
  @moduledoc """
  GenServer managing the Libvaxis Terminal User Interface.
  
  This module provides the high-level interface for the TUI, managing state,
  handling events from the Vaxis NIF, and coordinating with the rest of the
  Aiex distributed system.
  """
  
  use GenServer
  require Logger
  
  alias Aiex.Tui.LibvaxisNif
  alias Aiex.Context.Manager, as: ContextManager
  alias Aiex.LLM.ModelCoordinator
  alias Aiex.InterfaceGateway
  
  @type message :: %{
    id: String.t(),
    type: :user | :assistant | :system | :error,
    content: String.t(),
    timestamp: DateTime.t(),
    tokens: integer() | nil
  }
  
  @type state :: %{
    vaxis: term() | nil,
    messages: [message()],
    input_buffer: String.t(),
    cursor_pos: integer(),
    focused_panel: :chat | :input | :context | :status,
    context: map(),
    status: map(),
    subscribers: [pid()],
    session_id: String.t() | nil,
    pg_group: atom()
  }
  
  # Client API
  
  @doc """
  Start the TUI GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Send a message through the TUI.
  """
  def send_message(message) do
    GenServer.call(__MODULE__, {:send_message, message})
  end
  
  @doc """
  Get the current message history.
  """
  def get_messages do
    GenServer.call(__MODULE__, :get_messages)
  end
  
  @doc """
  Subscribe to TUI events.
  """
  def subscribe do
    GenServer.call(__MODULE__, :subscribe)
  end
  
  @doc """
  Update the input buffer (used for real-time input display).
  """
  def update_input(input) do
    GenServer.cast(__MODULE__, {:update_input, input})
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Join pg group for distributed events
    pg_group = Keyword.get(opts, :pg_group, :aiex_tui)
    :ok = :pg.join(pg_group, self())
    
    # Initialize state
    state = %{
      vaxis: nil,
      messages: [
        %{
          id: "welcome",
          type: :system,
          content: "🤖 Welcome to Aiex AI Assistant!\n\nI'm here to help you with coding, explanations, and analysis.",
          timestamp: DateTime.utc_now(),
          tokens: nil
        }
      ],
      input_buffer: "",
      cursor_pos: 0,
      focused_panel: :input,
      context: %{},
      status: %{
        connected: false,
        provider: nil,
        model: nil
      },
      subscribers: [],
      session_id: generate_session_id(),
      pg_group: pg_group
    }
    
    # Initialize Vaxis in a non-blocking way
    send(self(), :init_vaxis)
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:send_message, content}, _from, state) do
    # Create user message
    user_message = %{
      id: generate_message_id(),
      type: :user,
      content: content,
      timestamp: DateTime.utc_now(),
      tokens: nil
    }
    
    # Add to messages
    state = update_in(state.messages, &(&1 ++ [user_message]))
    
    # Clear input buffer
    state = %{state | input_buffer: "", cursor_pos: 0}
    
    # Render update
    render(state)
    
    # Send to AI asynchronously
    send(self(), {:process_ai_request, content})
    
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_call(:get_messages, _from, state) do
    {:reply, state.messages, state}
  end
  
  @impl true
  def handle_call(:subscribe, {pid, _}, state) do
    state = update_in(state.subscribers, &[pid | &1])
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_cast({:update_input, input}, state) do
    state = %{state | input_buffer: input, cursor_pos: String.length(input)}
    render(state)
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:init_vaxis, state) do
    case LibvaxisNif.init() do
      {:ok, vaxis} ->
        Logger.info("Vaxis initialized successfully")
        :ok = LibvaxisNif.start_event_loop(vaxis)
        
        # Update status
        state = put_in(state.status.connected, true)
        state = %{state | vaxis: vaxis}
        
        # Initial render
        render(state)
        
        # Get context
        send(self(), :update_context)
        
        {:noreply, state}
        
      {:error, reason} ->
        Logger.error("Failed to initialize Vaxis: #{inspect(reason)}")
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:key_press, key_data}, state) do
    state = handle_key_press(key_data, state)
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:resize, width, height}, state) do
    Logger.debug("Terminal resized to #{width}x#{height}")
    render(state)
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:mouse, mouse_data}, state) do
    # Handle mouse events if needed
    Logger.debug("Mouse event: #{inspect(mouse_data)}")
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:update_context, state) do
    # Get context from Context.Manager
    context = ContextManager.get_project_context()
    state = %{state | context: context}
    
    # Schedule next update
    Process.send_after(self(), :update_context, 5_000)
    
    render(state)
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:process_ai_request, content}, state) do
    # Send request through InterfaceGateway
    Task.start(fn ->
      case InterfaceGateway.handle_request(%{
        type: :chat,
        content: content,
        context: state.context,
        session_id: state.session_id
      }) do
        {:ok, response} ->
          send(self(), {:ai_response, response})
        {:error, error} ->
          send(self(), {:ai_error, error})
      end
    end)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:ai_response, response}, state) do
    # Create assistant message
    assistant_message = %{
      id: generate_message_id(),
      type: :assistant,
      content: response.content,
      timestamp: DateTime.utc_now(),
      tokens: response[:tokens]
    }
    
    # Add to messages
    state = update_in(state.messages, &(&1 ++ [assistant_message]))
    
    # Update status
    state = put_in(state.status.provider, response[:provider])
    state = put_in(state.status.model, response[:model])
    
    render(state)
    broadcast_update(state)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:ai_error, error}, state) do
    # Create error message
    error_message = %{
      id: generate_message_id(),
      type: :error,
      content: "Error: #{inspect(error)}",
      timestamp: DateTime.utc_now(),
      tokens: nil
    }
    
    state = update_in(state.messages, &(&1 ++ [error_message]))
    render(state)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:pg_event, event}, state) do
    # Handle distributed events from pg group
    Logger.debug("Received pg event: #{inspect(event)}")
    {:noreply, state}
  end
  
  # Private functions
  
  defp handle_key_press(%{codepoint: ?q, modifiers: %{ctrl: true}}, state) do
    # Ctrl+Q to quit
    Logger.info("Quitting TUI...")
    System.stop(0)
    state
  end
  
  defp handle_key_press(%{codepoint: ?\r}, state) when state.input_buffer != "" do
    # Enter key - send message
    GenServer.call(self(), {:send_message, state.input_buffer})
    state
  end
  
  defp handle_key_press(%{codepoint: ?\t}, state) do
    # Tab - switch focus
    next_panel = case state.focused_panel do
      :input -> :chat
      :chat -> :context
      :context -> :status
      :status -> :input
    end
    
    %{state | focused_panel: next_panel}
    |> render()
  end
  
  defp handle_key_press(%{codepoint: 127}, state) do
    # Backspace
    if state.cursor_pos > 0 do
      new_buffer = String.slice(state.input_buffer, 0, state.cursor_pos - 1) <>
                   String.slice(state.input_buffer, state.cursor_pos, String.length(state.input_buffer))
      state = %{state | input_buffer: new_buffer, cursor_pos: state.cursor_pos - 1}
      render(state)
      state
    else
      state
    end
  end
  
  defp handle_key_press(%{codepoint: codepoint}, state) when codepoint >= 32 and codepoint < 127 do
    # Regular character input
    char = <<codepoint::utf8>>
    new_buffer = String.slice(state.input_buffer, 0, state.cursor_pos) <>
                 char <>
                 String.slice(state.input_buffer, state.cursor_pos, String.length(state.input_buffer))
    
    state = %{state | input_buffer: new_buffer, cursor_pos: state.cursor_pos + 1}
    render(state)
    state
  end
  
  defp handle_key_press(_key_data, state) do
    # Ignore other keys for now
    state
  end
  
  defp render(%{vaxis: nil} = state), do: state
  defp render(state) do
    # Prepare data for rendering
    messages = prepare_messages(state.messages)
    status_info = prepare_status(state.status)
    
    # Call NIF to render
    case LibvaxisNif.render(state.vaxis, messages, state.input_buffer, status_info) do
      :ok -> :ok
      {:error, reason} -> 
        Logger.error("Render error: #{inspect(reason)}")
    end
    
    state
  end
  
  defp prepare_messages(messages) do
    # Format messages for display
    Enum.map(messages, fn msg ->
      %{
        type: msg.type,
        content: msg.content,
        timestamp: Calendar.strftime(msg.timestamp, "%H:%M")
      }
    end)
  end
  
  defp prepare_status(status) do
    %{
      connected: status.connected,
      provider: status.provider || "Not connected",
      model: status.model || "No model"
    }
  end
  
  defp broadcast_update(state) do
    # Broadcast to subscribers
    Enum.each(state.subscribers, fn pid ->
      send(pid, {:tui_update, state.messages})
    end)
    
    # Broadcast to pg group
    :pg.get_members(state.pg_group)
    |> Enum.reject(&(&1 == self()))
    |> Enum.each(fn pid ->
      send(pid, {:pg_event, {:message_update, state.session_id, List.last(state.messages)}})
    end)
  end
  
  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  
  defp generate_message_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end