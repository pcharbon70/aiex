defmodule Aiex.TUI.MockView do
  @moduledoc """
  Mock view implementation for when Ratatouille is not available.
  
  Provides console-based rendering simulation.
  """
  
  alias Aiex.TUI.State
  
  @doc """
  Renders state to console output instead of terminal UI.
  """
  def render(state) do
    render_to_console(state)
    :mock_view_rendered
  end
  
  defp render_to_console(state) do
    clear_screen()
    
    IO.puts("╔" <> String.duplicate("═", 78) <> "╗")
    IO.puts("║" <> center_text("AIEX AI CODING ASSISTANT - MOCK TUI", 78) <> "║")
    IO.puts("╠" <> String.duplicate("═", 78) <> "╣")
    
    # Status line
    status = state.status_message || "Ready"
    IO.puts("║ Status: " <> String.pad_trailing(status, 69) <> "║")
    
    # Message count and focus
    info = "Messages: #{state.message_count} | Focus: #{state.focus_state} | Active: #{state.active_panel}"
    IO.puts("║ " <> String.pad_trailing(info, 77) <> "║")
    
    IO.puts("╠" <> String.duplicate("═", 78) <> "╣")
    
    # Conversation area
    IO.puts("║" <> center_text("CONVERSATION", 78) <> "║")
    IO.puts("╠" <> String.duplicate("─", 78) <> "╣")
    
    # Show recent messages (last 5)
    recent_messages = Enum.take(state.messages, -5)
    
    if Enum.empty?(recent_messages) do
      IO.puts("║" <> center_text("No messages yet. Type something to start!", 78) <> "║")
    else
      for message <- recent_messages do
        render_console_message(message)
      end
    end
    
    # Pad to fill conversation area
    rendered_lines = length(recent_messages) * 2  # Each message takes 2 lines
    empty_lines = max(0, 8 - rendered_lines)
    for _ <- 1..empty_lines do
      IO.puts("║" <> String.duplicate(" ", 78) <> "║")
    end
    
    IO.puts("╠" <> String.duplicate("═", 78) <> "╣")
    
    # Input area
    IO.puts("║" <> center_text("INPUT AREA", 78) <> "║")
    IO.puts("╠" <> String.duplicate("─", 78) <> "╣")
    
    input_display = if String.length(state.current_input) > 70 do
      String.slice(state.current_input, 0, 67) <> "..."
    else
      state.current_input
    end
    
    input_line = "> " <> String.pad_trailing(input_display, 75)
    IO.puts("║ " <> input_line <> "║")
    
    # Progress indicator
    if state.progress_indicator do
      progress_text = case state.progress_indicator.type do
        :thinking -> "🤔 AI is thinking..."
        :typing -> "⌨️  AI is typing..."
        _ -> "⏳ Processing..."
      end
      IO.puts("║ " <> String.pad_trailing(progress_text, 77) <> "║")
    else
      IO.puts("║" <> String.duplicate(" ", 78) <> "║")
    end
    
    IO.puts("╠" <> String.duplicate("═", 78) <> "╣")
    
    # Context panel (if visible)
    if state.panels_visible.context do
      IO.puts("║" <> center_text("PROJECT CONTEXT", 78) <> "║")
      IO.puts("╠" <> String.duplicate("─", 78) <> "╣")
      
      if project_name = get_in(state.project_context, [:name]) do
        IO.puts("║ Project: " <> String.pad_trailing(project_name, 68) <> "║")
      end
      
      if current_file = get_in(state.file_context, [:current_file]) do
        file_name = Path.basename(current_file)
        IO.puts("║ File: " <> String.pad_trailing(file_name, 71) <> "║")
      end
      
      IO.puts("╠" <> String.duplicate("═", 78) <> "╣")
    end
    
    # Controls help
    IO.puts("║" <> center_text("CONTROLS: F1=Context F2=Actions Ctrl+C=Quit", 78) <> "║")
    IO.puts("╚" <> String.duplicate("═", 78) <> "╝")
    
    # Notifications
    for notification <- Enum.take(state.notifications, 2) do
      icon = case notification.type do
        :error -> "❌"
        :warning -> "⚠️ "
        :success -> "✅"
        :info -> "ℹ️ "
        _ -> "📢"
      end
      
      IO.puts("#{icon} #{notification.message}")
    end
    
    IO.puts("")
  end
  
  defp render_console_message(message) do
    role_icon = case message.role do
      :user -> "👤"
      :assistant -> "🤖"
      :system -> "⚙️ "
      :error -> "❌"
      _ -> "💬"
    end
    
    # Header line
    timestamp = format_time(message.timestamp)
    header = "#{role_icon} #{String.capitalize(to_string(message.role))} #{timestamp}"
    
    if message.tokens_used do
      header = header <> " (#{message.tokens_used} tokens)"
    end
    
    IO.puts("║ " <> String.pad_trailing(header, 77) <> "║")
    
    # Content line (truncated if too long)
    content = if String.length(message.content) > 75 do
      String.slice(message.content, 0, 72) <> "..."
    else
      message.content
    end
    
    IO.puts("║ " <> String.pad_trailing(content, 77) <> "║")
  end
  
  defp clear_screen do
    # Simple screen clear for console
    IO.puts("\n" <> String.duplicate("\n", 5))
  end
  
  defp center_text(text, width) do
    text_length = String.length(text)
    if text_length >= width do
      String.slice(text, 0, width)
    else
      padding = div(width - text_length, 2)
      left_pad = String.duplicate(" ", padding)
      right_pad = String.duplicate(" ", width - text_length - padding)
      left_pad <> text <> right_pad
    end
  end
  
  defp format_time(datetime) do
    datetime
    |> DateTime.to_time()
    |> Time.to_string()
    |> String.slice(0, 8)
  end
end