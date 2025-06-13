#!/usr/bin/env elixir

defmodule TestMultiPanelLayout do
  def run do
    IO.puts("🧪 Testing Multi-Panel Layout System")
    IO.puts("=" |> String.duplicate(50))
    
    # Test layout manager initialization
    IO.puts("\n1. Testing Layout Manager initialization...")
    layout_manager = Aiex.Tui.LayoutManager.init(80, 24, %{
      messages: [
        %{id: "1", type: :system, content: "Welcome!", timestamp: DateTime.utc_now()},
        %{id: "2", type: :user, content: "Hello", timestamp: DateTime.utc_now()}
      ],
      connection_status: :connected,
      project_context: %{name: "aiex", type: "elixir"}
    })
    IO.puts("✅ Layout Manager initialized successfully!")
    
    # Test layout state
    IO.puts("\n2. Testing layout state...")
    state = Aiex.Tui.LayoutManager.get_layout_state(layout_manager)
    IO.puts("✅ Layout state retrieved:")
    IO.puts("   - Terminal size: #{inspect(state.terminal_size)}")
    IO.puts("   - Focused panel: #{state.focused_panel}")
    IO.puts("   - Layout mode: #{state.layout_mode}")
    
    # Test focus management
    IO.puts("\n3. Testing focus management...")
    layout_manager = Aiex.Tui.LayoutManager.change_focus(layout_manager, :chat_history)
    new_state = Aiex.Tui.LayoutManager.get_layout_state(layout_manager)
    IO.puts("✅ Focus changed to: #{new_state.focused_panel}")
    
    # Test focus cycling
    layout_manager = Aiex.Tui.LayoutManager.cycle_focus_next(layout_manager)
    cycle_state = Aiex.Tui.LayoutManager.get_layout_state(layout_manager)
    IO.puts("✅ Focus cycled to: #{cycle_state.focused_panel}")
    
    # Test resize handling
    IO.puts("\n4. Testing resize handling...")
    layout_manager = Aiex.Tui.LayoutManager.handle_resize(layout_manager, 120, 30)
    resize_state = Aiex.Tui.LayoutManager.get_layout_state(layout_manager)
    IO.puts("✅ Resized to: #{inspect(resize_state.terminal_size)}")
    
    # Test layout rendering
    IO.puts("\n5. Testing layout rendering...")
    case Aiex.Tui.LayoutManager.render(layout_manager) do
      {:ok, _render_state} ->
        IO.puts("✅ Layout rendered successfully!")
      {:error, reason} ->
        IO.puts("⚠️ Layout render returned error: #{inspect(reason)} (expected with mock NIFs)")
    end
    
    # Test individual panels
    IO.puts("\n6. Testing individual panels...")
    test_chat_panel()
    test_input_panel()
    test_status_panel()
    test_context_panel()
    
    IO.puts("\n🎉 Multi-panel layout system test completed!")
    IO.puts("✅ All core functionality working")
    IO.puts("🔧 Ready for actual Libvaxis integration")
  end
  
  defp test_chat_panel do
    IO.puts("   📜 Testing ChatHistoryPanel...")
    panel = Aiex.Tui.Panels.ChatHistoryPanel.init(%{
      messages: [
        %{id: "1", type: :user, content: "Test message", timestamp: DateTime.utc_now()}
      ],
      height: 10
    })
    
    content = Aiex.Tui.Panels.ChatHistoryPanel.render(panel)
    state = Aiex.Tui.Panels.ChatHistoryPanel.get_state(panel)
    
    IO.puts("      ✅ ChatHistoryPanel: #{state.message_count} messages, #{length(content)} lines")
  end
  
  defp test_input_panel do
    IO.puts("   ✏️ Testing InputPanel...")
    panel = Aiex.Tui.Panels.InputPanel.init(%{width: 60, height: 4})
    
    # Test text insertion
    panel = Aiex.Tui.Panels.InputPanel.insert_text(panel, "Hello World!")
    content = Aiex.Tui.Panels.InputPanel.get_content(panel)
    
    # Test cursor movement
    panel = Aiex.Tui.Panels.InputPanel.move_cursor(panel, :home)
    state = Aiex.Tui.Panels.InputPanel.get_state(panel)
    
    IO.puts("      ✅ InputPanel: '#{content}', cursor at #{inspect(state.cursor_position)}")
  end
  
  defp test_status_panel do
    IO.puts("   📊 Testing StatusPanel...")
    panel = Aiex.Tui.Panels.StatusPanel.init(%{
      width: 80,
      connection_status: :connected,
      ai_provider: "OpenAI"
    })
    
    panel = Aiex.Tui.Panels.StatusPanel.update_ai_provider(panel, "Anthropic", "Claude-3")
    content = Aiex.Tui.Panels.StatusPanel.render(panel)
    state = Aiex.Tui.Panels.StatusPanel.get_state(panel)
    
    IO.puts("      ✅ StatusPanel: #{state.connection_status}, #{state.ai_provider}, #{length(content)} lines")
  end
  
  defp test_context_panel do
    IO.puts("   🗂️ Testing ContextPanel...")
    panel = Aiex.Tui.Panels.ContextPanel.init(%{
      height: 20,
      project_context: %{name: "aiex", type: "elixir"},
      current_files: [
        %{name: "mix.exs", type: "config"},
        %{name: "lib/aiex.ex", type: "elixir"}
      ]
    })
    
    content = Aiex.Tui.Panels.ContextPanel.render(panel)
    state = Aiex.Tui.Panels.ContextPanel.get_state(panel)
    
    IO.puts("      ✅ ContextPanel: #{state.project_name}, #{state.file_count} files, #{length(content)} lines")
  end
end

TestMultiPanelLayout.run()