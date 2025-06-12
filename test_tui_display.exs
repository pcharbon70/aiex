#!/usr/bin/env elixir

# Test script for TUI display rendering
# This tests our new multi-panel layout without starting the full application

defmodule TUITest do
  
  # Simplified versions of the TUI functions for testing
  def create_tui_display(messages, input_buffer, focused_panel, status, context) do
    width = 80  # Standard terminal width
    height = 24  # Standard terminal height
    
    # Build display sections
    header = create_header(width)
    chat_section = create_chat_section(messages, height - 6, width)
    input_section = create_input_section(input_buffer, focused_panel, width)
    status_section = create_status_section(status, context, width)
    
    [header, chat_section, input_section, status_section]
    |> Enum.join("\n")
  end
  
  def create_header(width) do
    title = " Aiex AI Assistant "
    border = String.duplicate("═", width)
    title_line = center_text(title, width, "═")
    
    "#{border}\n#{title_line}\n#{border}"
  end
  
  def create_chat_section(messages, height, width) do
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
  
  def create_input_section(input_buffer, focused_panel, width) do
    focus_indicator = if focused_panel == :input, do: "►", else: " "
    input_line = "#{focus_indicator} #{input_buffer}"
    truncated_input = truncate_line(input_line, width - 4)
    
    border = "├" <> String.duplicate("─", width - 2) <> "┤"
    input_display = "│ #{String.pad_trailing(truncated_input, width - 4)} │"
    hint = "│ #{String.pad_trailing("Tab: switch, Enter: send, Esc: quit", width - 4)} │"
    
    [border, input_display, hint, border]
    |> Enum.join("\n")
  end
  
  def create_status_section(status, context, width) do
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
  
  def format_message_simple(message) do
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
  
  def center_text(text, width, fill_char \\ " ") do
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
  
  def truncate_line(text, max_length) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length - 3) <> "..."
    else
      text
    end
  end
  
  # Test data
  def test_messages do
    [
      %{
        id: "welcome",
        type: :system,
        content: "Welcome to Aiex AI Assistant! I'm here to help you with coding, explanations, and analysis.",
        timestamp: DateTime.utc_now(),
        tokens: nil
      },
      %{
        id: "user_1",
        type: :user,
        content: "Hello! Can you help me understand how GenServers work in Elixir?",
        timestamp: DateTime.utc_now(),
        tokens: nil
      },
      %{
        id: "assistant_1",
        type: :assistant,
        content: "GenServers are a fundamental building block in Elixir's OTP. They provide a standardized way to build stateful server processes...",
        timestamp: DateTime.utc_now(),
        tokens: 150
      }
    ]
  end
  
  def test_status do
    %{
      connected: true,
      provider: "openai",
      model: "gpt-4"
    }
  end
  
  def test_context do
    %{
      project_root: "/home/user/my_project",
      current_file: "lib/my_module.ex"
    }
  end
  
  def run_test do
    # Clear screen and show our TUI
    IO.write("\e[2J\e[H")
    
    # Test with sample data
    messages = test_messages()
    input_buffer = "How do I handle state in GenServer?"
    focused_panel = :input
    status = test_status()
    context = test_context()
    
    # Generate and display the TUI
    display = create_tui_display(messages, input_buffer, focused_panel, status, context)
    IO.puts(display)
    
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("TUI Test Complete! This shows our multi-panel chat interface.")
    IO.puts("Features demonstrated:")
    IO.puts("- Header with centered title")
    IO.puts("- Chat panel with message history and timestamps")
    IO.puts("- Input panel with focus indicator (►)")
    IO.puts("- Status panel showing provider and project info")
    IO.puts("- Proper borders and layout")
  end
end

# Run the test
TUITest.run_test()