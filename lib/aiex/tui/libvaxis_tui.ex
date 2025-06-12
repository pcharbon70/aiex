defmodule Aiex.Tui.LibvaxisTui do
  @moduledoc """
  GenServer managing the Libvaxis Terminal User Interface.
  
  This module provides the high-level interface for the TUI, managing state,
  handling events from the Vaxis NIF, and coordinating with the rest of the
  Aiex distributed system.
  """
  
  use GenServer
  require Logger
  
  # Use minimal NIF for now (switch to LibvaxisNif when Vaxis is ready)
  alias Aiex.Tui.LibvaxisNifMinimal, as: LibvaxisNif
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
    interface_id: String.t() | nil,
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
    # Join pg group for distributed events (with proper error handling)
    pg_group = Keyword.get(opts, :pg_group, :aiex_tui)
    
    # Attempt to join pg group, but don't fail if unavailable
    try do
      # Use pg:join/2 instead of pg:join/3 - let pg find its own scope
      case :pg.join(pg_group, self()) do
        :ok -> 
          Logger.debug("Successfully joined pg group: #{pg_group}")
        error ->
          Logger.debug("Could not join pg group #{pg_group}: #{inspect(error)}. Running without distributed events.")
      end
    catch
      :exit, reason ->
        Logger.debug("pg not available: #{inspect(reason)}. Running without distributed events.")
      error ->
        Logger.debug("pg error: #{inspect(error)}. Running without distributed events.")
    end
    
    session_id = generate_session_id()
    
    # Register with InterfaceGateway
    interface_config = %{
      type: :tui,
      session_id: session_id,
      user_id: nil,
      capabilities: [:text_output, :real_time_updates],
      settings: %{interactive: true}
    }
    
    interface_id = case InterfaceGateway.register_interface(__MODULE__, interface_config) do
      {:ok, id} -> 
        Logger.debug("Registered TUI with InterfaceGateway: #{id}")
        id
      {:error, reason} ->
        Logger.warning("Failed to register with InterfaceGateway: #{inspect(reason)}")
        nil
    end
    
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
      session_id: session_id,
      interface_id: interface_id,
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
    # Get basic context (for now, just use empty context until project context is implemented)
    context = %{
      current_file: nil,
      project_root: System.cwd(),
      last_updated: DateTime.utc_now()
    }
    state = %{state | context: context}
    
    # Schedule next update
    Process.send_after(self(), :update_context, 5_000)
    
    render(state)
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:process_ai_request, content}, %{interface_id: nil} = state) do
    # Interface not registered, send error
    send(self(), {:ai_error, "Interface not registered with gateway"})
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:process_ai_request, content}, state) do
    # Send request through InterfaceGateway
    Task.start(fn ->
      request = %{
        id: generate_message_id(),
        type: :completion,
        content: content,
        context: state.context,
        options: []
      }
      
      case InterfaceGateway.submit_request(state.interface_id, request) do
        {:ok, request_id} ->
          # For now, simulate a response since we need to check actual response handling
          send(self(), {:ai_response, %{
            content: "This is a placeholder response. AI integration pending.",
            provider: "mock",
            model: "test",
            tokens: 10
          }})
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
  
  defp handle_key_press(%{key: "escape", code: 27}, state) do
    # Escape to quit
    Logger.info("Quitting TUI...")
    System.stop(0)
    state
  end
  
  defp handle_key_press(%{key: "enter", code: 13}, state) when state.input_buffer != "" do
    # Enter key - send message
    GenServer.call(self(), {:send_message, state.input_buffer})
    state
  end
  
  defp handle_key_press(%{key: "tab", code: 9}, state) do
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
  
  defp handle_key_press(%{key: "backspace", code: 127}, state) do
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
  
  defp handle_key_press(%{key: "char", code: code}, state) when code >= 32 and code < 127 do
    # Regular character input
    char = <<code::utf8>>
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
    # Create a simple multi-panel display using IO
    output = create_tui_display(state)
    
    # Clear screen and display
    IO.write("\e[2J\e[H#{output}")
    
    state
  end
  
  defp format_message_line(message) do
    time = Calendar.strftime(message.timestamp, "%H:%M")
    type_icon = case message.type do
      :user -> "👤"
      :assistant -> "🤖"
      :system -> "ℹ️"
      :error -> "❌"
    end
    
    "#{time} #{type_icon} #{String.slice(message.content, 0, 60)}"
  end
  
  defp format_status_line(status) do
    connected = if status.connected, do: "✅", else: "❌"
    "Status: #{connected} Provider: #{status.provider || "None"}"
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
    
    # Broadcast to pg group (with comprehensive error handling)
    try do
      :pg.get_members(state.pg_group)
      |> Enum.reject(&(&1 == self()))
      |> Enum.each(fn pid ->
        send(pid, {:pg_event, {:message_update, state.session_id, List.last(state.messages)}})
      end)
    rescue
      error ->
        Logger.debug("Failed to broadcast to pg group: #{inspect(error)}")
    catch
      :exit, _reason ->
        # pg not available, skip broadcast
        :ok
      error ->
        Logger.debug("Failed to broadcast to pg group: #{inspect(error)}")
    end
  end
  
  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  
  defp generate_message_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  # Simple TUI display creation
  
  defp create_tui_display(state) do
    width = 80  # Standard terminal width
    height = 24  # Standard terminal height
    
    # Build display sections
    header = create_header(width)
    chat_section = create_chat_section(state.messages, height - 6, width)
    input_section = create_input_section(state.input_buffer, state.focused_panel, width)
    status_section = create_status_section(state.status, state.context, width)
    
    [header, chat_section, input_section, status_section]
    |> Enum.join("\n")
  end
  
  defp create_header(width) do
    title = " Aiex AI Assistant "
    border = String.duplicate("═", width)
    title_line = center_text(title, width, "═")
    
    "#{border}\n#{title_line}\n#{border}"
  end
  
  defp create_chat_section(messages, height, width) do
    border = "├" <> String.duplicate("─", width - 2) <> "┤"
    
    # Get last few messages that fit
    visible_messages = messages
    |> Enum.take(-height + 2)
    |> Enum.map(&format_message_simple/1)
    |> Enum.map(&truncate_line(&1, width - 4))
    
    # Pad with empty lines if needed
    padding_lines = max(0, height - 2 - length(visible_messages))
    empty_lines = List.duplicate("", padding_lines)
    
    message_lines = (visible_messages ++ empty_lines)
    |> Enum.map(&("│ #{String.pad_trailing(&1, width - 4)} │"))
    
    ([border] ++ message_lines ++ [border])
    |> Enum.join("\n")
  end
  
  defp create_input_section(input_buffer, focused_panel, width) do
    focus_indicator = if focused_panel == :input, do: "►", else: " "
    input_line = "#{focus_indicator} #{input_buffer}"
    truncated_input = truncate_line(input_line, width - 4)
    
    border = "├" <> String.duplicate("─", width - 2) <> "┤"
    input_display = "│ #{String.pad_trailing(truncated_input, width - 4)} │"
    hint = "│ #{String.pad_trailing("Tab: switch, Enter: send, Esc: quit", width - 4)} │"
    
    [border, input_display, hint, border]
    |> Enum.join("\n")
  end
  
  defp create_status_section(status, context, width) do
    provider_info = case {status.connected, status.provider} do
      {true, provider} when not is_nil(provider) -> "#{provider}"
      {true, _} -> "Connected"
      {false, _} -> "Disconnected"
    end
    
    project_info = case context[:project_root] do
      nil -> "No project"
      path -> "Project: #{Path.basename(path)}"
    end
    
    status_line = "Status: #{provider_info} | #{project_info}"
    truncated_status = truncate_line(status_line, width - 4)
    
    border = "└" <> String.duplicate("─", width - 2) <> "┘"
    status_display = "│ #{String.pad_trailing(truncated_status, width - 4)} │"
    
    [status_display, border]
    |> Enum.join("\n")
  end
  
  defp format_message_simple(message) do
    time = Calendar.strftime(message.timestamp, "%H:%M")
    type_icon = case message.type do
      :user -> "👤"
      :assistant -> "🤖"
      :system -> "ℹ️"
      :error -> "❌"
    end
    
    content = String.replace(message.content, ~r/\s+/, " ")
    "#{time} #{type_icon} #{content}"
  end
  
  defp center_text(text, width, fill_char \\ " ") do
    text_length = String.length(text)
    if text_length >= width do
      String.slice(text, 0, width)
    else
      padding = width - text_length
      left_padding = div(padding, 2)
      right_padding = padding - left_padding
      
      String.duplicate(fill_char, left_padding) <> text <> String.duplicate(fill_char, right_padding)
    end
  end
  
  defp truncate_line(text, max_length) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length - 3) <> "..."
    else
      text
    end
  end
end