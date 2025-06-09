defmodule Aiex.TUI.EventHandler do
  @moduledoc """
  Event handling for the Ratatouille TUI application.
  
  Implements the update logic of TEA pattern, handling keyboard input,
  OTP messages, and UI state transitions.
  """
  
  alias Aiex.TUI.State
  alias Aiex.InterfaceGateway
  
  require Logger
  
  @doc """
  Main event handler - processes all TUI events and returns updated state.
  """
  def handle_event(state, event) do
    start_time = System.monotonic_time(:millisecond)
    
    result = case event do
      # Keyboard events
      {:event, %{key: key}} -> handle_keyboard(state, key)
      
      # TUI lifecycle events
      :initial_load_complete -> handle_initial_load(state)
      :tick -> handle_tick(state)
      :status_update -> handle_status_update(state)
      :context_refresh -> handle_context_refresh(state)
      
      # OTP integration messages
      {:tui_message, message} -> handle_tui_message(state, message)
      {:context_update, context} -> handle_context_update(state, context)
      {:ai_response, response} -> handle_ai_response(state, response)
      
      # pg events
      {:pg_message, topic, message} -> handle_pg_message(state, topic, message)
      
      # Error handling
      {:error, reason} -> handle_error(state, reason)
      
      # Unknown events
      unknown -> handle_unknown_event(state, unknown)
    end
    
    # Update render time
    end_time = System.monotonic_time(:millisecond)
    render_time = end_time - start_time
    
    case result do
      {new_state, command} -> 
        {%{new_state | render_time: render_time}, command}
      new_state -> 
        %{new_state | render_time: render_time}
    end
  end
  
  ## Keyboard event handling
  
  defp handle_keyboard(state, key) do
    case {state.focus_state, key} do
      # Global shortcuts
      {_, :ctrl_c} -> handle_quit(state)
      {_, :ctrl_q} -> handle_quit(state)
      {_, :f1} -> toggle_context_panel(state)
      {_, :f2} -> toggle_actions_panel(state)
      {_, :tab} -> cycle_focus(state, :forward)
      {_, :shift_tab} -> cycle_focus(state, :backward)
      
      # Input handling
      {:input, :enter} -> handle_send_message(state)
      {:input, :ctrl_enter} -> handle_send_message(state)
      {:input, :escape} -> handle_clear_input(state)
      {:input, {:char, char}} -> handle_input_char(state, char)
      {:input, :backspace} -> handle_backspace(state)
      
      # Navigation in panels
      {:conversation, :up} -> scroll_conversation(state, :up)
      {:conversation, :down} -> scroll_conversation(state, :down)
      {:conversation, :page_up} -> scroll_conversation(state, :page_up)
      {:conversation, :page_down} -> scroll_conversation(state, :page_down)
      
      # Actions panel navigation
      {{:actions, _}, :up} -> navigate_actions(state, :up)
      {{:actions, _}, :down} -> navigate_actions(state, :down)
      {{:actions, index}, :enter} -> execute_action(state, index)
      
      # Quick action shortcuts
      {_, :ctrl_n} -> handle_new_conversation(state)
      {_, :ctrl_s} -> handle_save_conversation(state)
      {_, :ctrl_l} -> handle_clear_conversation(state)
      
      # Fallback
      _ -> state
    end
  end
  
  ## Specific keyboard handlers
  
  defp handle_quit(state) do
    Logger.info("TUI quit requested by user")
    
    # Unregister from InterfaceGateway
    if state.interface_id do
      InterfaceGateway.unregister_interface(state.interface_id)
    end
    
    {state, Ratatouille.Command.new(fn -> :quit end)}
  end
  
  defp handle_send_message(state) do
    if String.trim(state.current_input) != "" do
      message_content = String.trim(state.current_input)
      
      # Add user message to state
      new_state = 
        state
        |> State.add_message(:user, message_content)
        |> State.clear_input()
        |> State.set_status("Sending message to AI...")
      
      # Send to InterfaceGateway for AI processing
      if state.interface_id do
        request = %{
          id: generate_request_id(),
          type: :completion,
          content: message_content,
          context: %{
            conversation_id: state.conversation_id,
            project_context: state.project_context,
            file_context: state.file_context
          },
          options: []
        }
        
        case InterfaceGateway.submit_request(state.interface_id, request) do
          {:ok, _request_id} ->
            thinking_state = %{new_state | 
              progress_indicator: %{type: :thinking, message: "AI is thinking..."}
            }
            {thinking_state, Ratatouille.Command.none()}
            
          {:error, reason} ->
            error_state = 
              new_state
              |> State.add_message(:error, "Failed to send message: #{reason}")
              |> State.set_status("Ready")
            
            {error_state, Ratatouille.Command.none()}
        end
      else
        error_state = 
          new_state
          |> State.add_message(:error, "Not connected to AI interface")
          |> State.set_status("Ready")
        
        {error_state, Ratatouille.Command.none()}
      end
    else
      state
    end
  end
  
  defp handle_clear_input(state) do
    state
    |> State.clear_input()
    |> State.set_status("Input cleared")
  end
  
  defp handle_input_char(state, char) do
    State.update_input(state, state.current_input <> <<char::utf8>>)
  end
  
  defp handle_backspace(state) do
    new_input = 
      if String.length(state.current_input) > 0 do
        String.slice(state.current_input, 0..-2)
      else
        ""
      end
    
    State.update_input(state, new_input)
  end
  
  ## Panel management
  
  defp toggle_context_panel(state) do
    State.toggle_panel(state, :context)
  end
  
  defp toggle_actions_panel(state) do
    State.toggle_panel(state, :actions)
  end
  
  defp cycle_focus(state, direction) do
    available_panels = [:input, :conversation, :context, :actions]
    |> Enum.filter(fn panel ->
      case panel do
        :input -> true
        :conversation -> true
        :context -> state.panels_visible.context
        :actions -> state.panels_visible.actions
      end
    end)
    
    current_index = Enum.find_index(available_panels, &(&1 == state.focus_state))
    
    new_index = case direction do
      :forward -> rem((current_index || 0) + 1, length(available_panels))
      :backward -> rem((current_index || 0) - 1 + length(available_panels), length(available_panels))
    end
    
    new_focus = Enum.at(available_panels, new_index)
    %{state | focus_state: new_focus}
  end
  
  ## Conversation management
  
  defp handle_new_conversation(state) do
    new_conversation_id = generate_conversation_id()
    
    new_state = %{state |
      conversation_id: new_conversation_id,
      messages: [],
      message_count: 0,
      current_input: ""
    }
    |> State.set_status("Started new conversation")
    |> State.add_notification(:info, "New conversation started", 3000)
    
    {new_state, Ratatouille.Command.none()}
  end
  
  defp handle_save_conversation(state) do
    # TODO: Implement conversation saving
    state
    |> State.add_notification(:info, "Conversation save not yet implemented", 3000)
  end
  
  defp handle_clear_conversation(state) do
    new_state = %{state |
      messages: [],
      message_count: 0,
      current_input: ""
    }
    |> State.set_status("Conversation cleared")
    |> State.add_notification(:info, "Conversation history cleared", 3000)
    
    {new_state, Ratatouille.Command.none()}
  end
  
  ## Scroll and navigation
  
  defp scroll_conversation(state, direction) do
    # TODO: Implement conversation scrolling
    # For now, just acknowledge the action
    State.set_status(state, "Scrolling #{direction}")
  end
  
  defp navigate_actions(state, direction) do
    # TODO: Implement actions panel navigation
    State.set_status(state, "Navigating actions #{direction}")
  end
  
  defp execute_action(state, index) do
    # TODO: Implement action execution
    State.add_notification(state, :info, "Action #{index} executed", 3000)
  end
  
  ## TUI lifecycle events
  
  defp handle_initial_load(state) do
    Logger.info("TUI initial load complete")
    
    new_state = 
      state
      |> State.set_status("TUI loaded successfully")
      |> State.add_notification(:success, "Welcome to Aiex TUI", 5000)
    
    {new_state, Ratatouille.Command.none()}
  end
  
  defp handle_tick(state) do
    # Update last activity, cleanup expired notifications
    current_time = DateTime.utc_now()
    
    # Remove expired notifications
    active_notifications = Enum.filter(state.notifications, fn notification ->
      time_diff = DateTime.diff(current_time, notification.timestamp, :millisecond)
      time_diff < notification.duration
    end)
    
    %{state | 
      notifications: active_notifications,
      last_update: current_time
    }
  end
  
  defp handle_status_update(state) do
    # Periodic status updates
    if state.interface_id do
      State.set_status(state, "Connected - #{state.message_count} messages")
    else
      State.set_status(state, "Disconnected")
    end
  end
  
  defp handle_context_refresh(state) do
    # Refresh project context periodically
    # TODO: Implement context refresh logic
    state
  end
  
  ## OTP message handling
  
  defp handle_tui_message(state, message) do
    Logger.debug("TUI received message: #{inspect(message)}")
    
    case message do
      {:notification, type, content} ->
        State.add_notification(state, type, content, 5000)
        
      {:status, status_message} ->
        State.set_status(state, status_message)
        
      _ ->
        Logger.warning("Unknown TUI message: #{inspect(message)}")
        state
    end
  end
  
  defp handle_context_update(state, context) do
    Logger.debug("TUI context update: #{inspect(context)}")
    
    new_state = case context.type do
      :project -> State.update_project_context(state, context.data)
      :file -> State.update_file_context(state, context.data)
      _ -> state
    end
    
    State.add_notification(new_state, :info, "Context updated", 2000)
  end
  
  defp handle_ai_response(state, response) do
    Logger.debug("TUI AI response received")
    
    # Clear progress indicator
    new_state = %{state | progress_indicator: nil}
    
    # Add AI response message
    metadata = %{
      tokens_used: Map.get(response, :tokens_used),
      response_time: Map.get(response, :response_time),
      provider: Map.get(response, :provider)
    }
    
    new_state = State.add_message(new_state, :assistant, response.content, metadata)
    
    State.set_status(new_state, "AI response received")
  end
  
  defp handle_pg_message(state, topic, message) do
    Logger.debug("TUI pg message on #{topic}: #{inspect(message)}")
    
    case topic do
      :tui_updates -> handle_tui_update(state, message)
      :context_updates -> handle_context_update(state, message)
      _ -> state
    end
  end
  
  defp handle_tui_update(state, update) do
    # Handle real-time updates from other parts of the system
    case update do
      {:ai_thinking, _} -> 
        %{state | progress_indicator: %{type: :thinking, message: "AI is thinking..."}}
      
      {:ai_complete, _} -> 
        %{state | progress_indicator: nil}
      
      _ -> state
    end
  end
  
  ## Error handling
  
  defp handle_error(state, reason) do
    Logger.error("TUI error: #{reason}")
    
    state
    |> State.add_message(:error, "Error: #{reason}")
    |> State.add_notification(:error, "An error occurred", 5000)
    |> State.set_status("Error occurred")
  end
  
  defp handle_unknown_event(state, event) do
    Logger.debug("TUI unknown event: #{inspect(event)}")
    state
  end
  
  ## Utility functions
  
  defp generate_request_id do
    "req_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
  
  defp generate_conversation_id do
    "conv_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end