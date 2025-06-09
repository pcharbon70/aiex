defmodule Aiex.TUI.View do
  @moduledoc """
  Ratatouille view rendering for the Aiex TUI application.
  
  Implements the view layer of TEA pattern with sophisticated chat-focused layout,
  multi-panel interface, and rich text rendering capabilities.
  """
  
  import Ratatouille.View
  alias Aiex.TUI.State
  
  @doc """
  Main render function for the TUI application.
  """
  def render(state) do
    view(bottom_bar: render_status_bar(state)) do
      case state.layout_mode do
        :chat_focused -> render_chat_layout(state)
        :full_screen -> render_full_screen_layout(state)
        :minimal -> render_minimal_layout(state)
        _ -> render_chat_layout(state)
      end
    end
  end
  
  ## Layout rendering
  
  defp render_chat_layout(state) do
    row do
      # Left sidebar - Context panel (25% width)
      if state.panels_visible.context do
        column(size: 3) do
          render_context_panel(state)
        end
      end
      
      # Main content area (50-75% width)
      main_size = if state.panels_visible.context, do: 6, else: 9
      main_size = if state.panels_visible.actions, do: main_size - 3, else: main_size
      
      column(size: main_size) do
        # Chat conversation (70% height)
        row(size: 7) do
          render_conversation_panel(state)
        end
        
        # Input area (20% height)
        row(size: 2) do
          render_input_panel(state)
        end
        
        # Status/notifications (10% height)
        row(size: 1) do
          render_status_panel(state)
        end
      end
      
      # Right sidebar - Actions panel (25% width)
      if state.panels_visible.actions do
        column(size: 3) do
          render_actions_panel(state)
        end
      end
    end
  end
  
  defp render_full_screen_layout(state) do
    # Full screen conversation view
    render_conversation_panel(state)
  end
  
  defp render_minimal_layout(state) do
    row do
      column(size: 12) do
        row(size: 10) do
          render_conversation_panel(state)
        end
        row(size: 2) do
          render_input_panel(state)
        end
      end
    end
  end
  
  ## Panel rendering
  
  defp render_conversation_panel(state) do
    panel(title: conversation_title(state), height: :fill) do
      viewport(offset_y: calculate_scroll_offset(state)) do
        render_messages(state.messages)
      end
    end
  end
  
  defp render_input_panel(state) do
    panel(title: "Message (Ctrl+Enter to send)", height: :fill) do
      if state.focus_state == :input do
        text_input(
          value: state.current_input,
          focus: true,
          placeholder: "Ask me anything about your code...",
          multiline: true
        )
      else
        text(content: state.current_input || "Ask me anything about your code...")
      end
      
      # Show typing indicator or progress
      if state.progress_indicator do
        row do
          text(content: render_progress_indicator(state.progress_indicator))
        end
      end
    end
  end
  
  defp render_context_panel(state) do
    panel(title: "Project Context", height: :fill) do
      # Project information
      if not Enum.empty?(state.project_context) do
        row do
          text(content: "📁 Project: #{Map.get(state.project_context, :name, "Unknown")}")
        end
        
        if files = Map.get(state.project_context, :recent_files, []) do
          row do
            text(content: "📄 Recent files:")
          end
          
          for file <- Enum.take(files, 5) do
            row do
              text(content: "  • #{Path.basename(file)}")
            end
          end
        end
      else
        row do
          text(content: "No project context available")
        end
      end
      
      # File context
      if not Enum.empty?(state.file_context) do
        row do
          text(content: "🔍 Current context:")
        end
        
        if current_file = Map.get(state.file_context, :current_file) do
          row do
            text(content: "  File: #{Path.basename(current_file)}")
          end
        end
        
        if functions = Map.get(state.file_context, :functions, []) do
          row do
            text(content: "  Functions: #{length(functions)}")
          end
        end
      end
      
      # Quick actions
      row do
        text(content: "")
      end
      row do
        text(content: "⌨️  Quick actions:")
      end
      row do
        text(content: "  F1 - Toggle this panel")
      end
      row do
        text(content: "  F2 - Toggle actions")
      end
      row do
        text(content: "  Ctrl+N - New conversation")
      end
    end
  end
  
  defp render_actions_panel(state) do
    panel(title: "Quick Actions", height: :fill) do
      # AI Actions
      row do
        text(content: "🤖 AI Actions:")
      end
      
      actions = [
        "📊 Analyze current file",
        "🔄 Refactor selection", 
        "📖 Explain code",
        "🧪 Generate tests",
        "📝 Add documentation",
        "🔍 Find issues"
      ]
      
      for {action, index} <- Enum.with_index(actions) do
        row do
          if state.active_panel == :actions and state.focus_state == {:action, index} do
            text(content: "> #{action}", color: :yellow)
          else
            text(content: "  #{action}")
          end
        end
      end
      
      # Conversation management
      row do
        text(content: "")
      end
      row do
        text(content: "💬 Conversation:")
      end
      
      conversation_actions = [
        "🆕 New conversation",
        "💾 Save conversation", 
        "🗑️  Clear history",
        "📋 Export chat"
      ]
      
      for action <- conversation_actions do
        row do
          text(content: "  #{action}")
        end
      end
    end
  end
  
  defp render_status_panel(state) do
    panel(title: "Status", height: :fill) do
      row do
        if state.status_message do
          text(content: "📍 #{state.status_message}")
        else
          text(content: "📍 Ready")
        end
        
        # Show message count and performance info
        if state.message_count > 0 do
          text(content: " | 💬 #{state.message_count} messages")
        end
        
        if state.render_time > 0 do
          text(content: " | ⚡ #{state.render_time}ms")
        end
      end
      
      # Show notifications
      for notification <- Enum.take(state.notifications, 3) do
        row do
          icon = case notification.type do
            :error -> "❌"
            :warning -> "⚠️ "
            :success -> "✅"
            :info -> "ℹ️ "
            _ -> "📢"
          end
          
          text(content: "#{icon} #{notification.message}")
        end
      end
    end
  end
  
  ## Message rendering
  
  defp render_messages(messages) do
    for message <- messages do
      render_message(message)
    end
  end
  
  defp render_message(message) do
    # Message header with role and timestamp
    row do
      role_icon = case message.role do
        :user -> "👤"
        :assistant -> "🤖"
        :system -> "⚙️ "
        :error -> "❌"
        _ -> "💬"
      end
      
      timestamp = format_timestamp(message.timestamp)
      
      text(
        content: "#{role_icon} #{String.capitalize(to_string(message.role))} #{timestamp}",
        color: role_color(message.role),
        attributes: [:bold]
      )
      
      # Show token usage if available
      if message.tokens_used do
        text(content: " (#{message.tokens_used} tokens)", color: :cyan)
      end
      
      # Show response time if available
      if message.response_time do
        text(content: " [#{message.response_time}ms]", color: :magenta)
      end
    end
    
    # Message content with proper formatting
    render_message_content(message)
    
    # Separator
    row do
      text(content: "")
    end
  end
  
  defp render_message_content(message) do
    # Handle different content types
    cond do
      # Code blocks
      String.contains?(message.content, "```") ->
        render_code_message(message.content)
      
      # Long text - wrap properly
      String.length(message.content) > 80 ->
        render_wrapped_text(message.content)
      
      # Regular text
      true ->
        row do
          text(content: message.content)
        end
    end
  end
  
  defp render_code_message(content) do
    # Split by code blocks
    parts = String.split(content, ~r/```\w*\n?/, include_captures: true)
    
    for {part, index} <- Enum.with_index(parts) do
      if String.starts_with?(part, "```") do
        # This is a code block delimiter - skip
        nil
      else
        if rem(index, 2) == 1 do
          # This is code content
          panel(title: "Code", height: :content) do
            for line <- String.split(part, "\n") do
              row do
                text(content: line, color: :green, background: :black)
              end
            end
          end
        else
          # This is regular text
          for line <- String.split(part, "\n") do
            row do
              text(content: line)
            end
          end
        end
      end
    end
  end
  
  defp render_wrapped_text(content) do
    # Simple word wrapping - split long lines
    lines = String.split(content, "\n")
    
    for line <- lines do
      if String.length(line) > 80 do
        wrapped = wrap_text(line, 80)
        for wrapped_line <- wrapped do
          row do
            text(content: wrapped_line)
          end
        end
      else
        row do
          text(content: line)
        end
      end
    end
  end
  
  ## Status bar
  
  defp render_status_bar(state) do
    bar do
      left do
        label(content: "Aiex TUI")
        label(content: " | #{state.layout_mode}")
        
        if state.conversation_id do
          label(content: " | Conversation: #{String.slice(state.conversation_id, 0, 8)}")
        end
      end
      
      right do
        if state.interface_id do
          label(content: "Connected")
        else
          label(content: "Disconnected", color: :red)
        end
        
        label(content: " | #{format_time(DateTime.utc_now())}")
      end
    end
  end
  
  ## Utility functions
  
  defp conversation_title(state) do
    base_title = "AI Conversation"
    
    if state.message_count > 0 do
      "#{base_title} (#{state.message_count} messages)"
    else
      base_title
    end
  end
  
  defp calculate_scroll_offset(state) do
    # Auto-scroll to bottom if enabled
    if Map.get(state.preferences, :auto_scroll, true) do
      max(0, state.message_count - 10)  # Show last 10 messages
    else
      0
    end
  end
  
  defp render_progress_indicator(progress) do
    case progress.type do
      :thinking -> "🤔 AI is thinking..."
      :typing -> "⌨️  AI is typing..."
      :processing -> "⚙️  Processing..."
      :loading -> "📥 Loading..."
      _ -> "⏳ Please wait..."
    end
  end
  
  defp role_color(:user), do: :blue
  defp role_color(:assistant), do: :green  
  defp role_color(:system), do: :yellow
  defp role_color(:error), do: :red
  defp role_color(_), do: :white
  
  defp format_timestamp(datetime) do
    datetime
    |> DateTime.to_time()
    |> Time.to_string()
    |> String.slice(0, 8)
  end
  
  defp format_time(datetime) do
    datetime
    |> DateTime.to_time()
    |> Time.to_string()
    |> String.slice(0, 5)
  end
  
  defp wrap_text(text, width) do
    text
    |> String.split(" ")
    |> Enum.reduce({[], ""}, fn word, {lines, current_line} ->
      new_line = if current_line == "", do: word, else: current_line <> " " <> word
      
      if String.length(new_line) <= width do
        {lines, new_line}
      else
        {lines ++ [current_line], word}
      end
    end)
    |> case do
      {lines, ""} -> lines
      {lines, last_line} -> lines ++ [last_line]
    end
  end
end