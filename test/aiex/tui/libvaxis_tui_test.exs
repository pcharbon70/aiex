defmodule Aiex.Tui.LibvaxisTuiTest do
  use ExUnit.Case, async: true
  
  alias Aiex.Tui.LibvaxisTui
  
  @moduletag :tui
  
  describe "start_link/1" do
    test "starts the GenServer successfully" do
      assert {:ok, pid} = LibvaxisTui.start_link(pg_group: :test_tui_group)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end
  
  describe "message handling" do
    setup do
      {:ok, pid} = LibvaxisTui.start_link(pg_group: :test_tui_group)
      {:ok, pid: pid}
    end
    
    test "stores and retrieves messages", %{pid: pid} do
      # Get initial messages (should have welcome message)
      messages = GenServer.call(pid, :get_messages)
      assert length(messages) == 1
      assert hd(messages).type == :system
      
      # Send a new message
      :ok = GenServer.call(pid, {:send_message, "Test message"})
      
      # Verify message was added
      messages = GenServer.call(pid, :get_messages)
      assert length(messages) == 2
      assert List.last(messages).content == "Test message"
      assert List.last(messages).type == :user
      
      GenServer.stop(pid)
    end
    
    test "updates input buffer", %{pid: pid} do
      # Update input
      GenServer.cast(pid, {:update_input, "Hello"})
      
      # Give it time to process
      Process.sleep(10)
      
      # Get state (we'll need to add a debug function for this in real implementation)
      state = :sys.get_state(pid)
      assert state.input_buffer == "Hello"
      assert state.cursor_pos == 5
      
      GenServer.stop(pid)
    end
  end
  
  describe "subscriptions" do
    setup do
      {:ok, pid} = LibvaxisTui.start_link(pg_group: :test_tui_group)
      {:ok, pid: pid}
    end
    
    test "allows process subscription", %{pid: pid} do
      # Subscribe
      :ok = GenServer.call(pid, :subscribe)
      
      # Verify we're in subscribers list
      state = :sys.get_state(pid)
      assert self() in state.subscribers
      
      GenServer.stop(pid)
    end
  end
  
  describe "pg group integration" do
    test "joins pg group on init" do
      pg_group = :test_tui_pg_group
      {:ok, pid} = LibvaxisTui.start_link(pg_group: pg_group)
      
      # Verify process joined the group
      members = :pg.get_members(pg_group)
      assert pid in members
      
      GenServer.stop(pid)
    end
  end
  
  describe "state management" do
    setup do
      {:ok, pid} = LibvaxisTui.start_link(pg_group: :test_tui_group)
      {:ok, pid: pid}
    end
    
    test "initializes with correct default state", %{pid: pid} do
      state = :sys.get_state(pid)
      
      assert state.vaxis == nil
      assert length(state.messages) == 1
      assert state.input_buffer == ""
      assert state.cursor_pos == 0
      assert state.focused_panel == :input
      assert state.context == %{}
      assert state.status.connected == false
      assert state.subscribers == []
      assert is_binary(state.session_id)
      assert state.pg_group == :test_tui_group
      
      GenServer.stop(pid)
    end
  end
  
  describe "key press handling" do
    setup do
      {:ok, pid} = LibvaxisTui.start_link(pg_group: :test_tui_group)
      {:ok, pid: pid}
    end
    
    test "handles character input", %{pid: pid} do
      # Simulate key press for 'a'
      send(pid, {:key_press, %{codepoint: ?a, modifiers: %{ctrl: false, alt: false, shift: false}}})
      Process.sleep(10)
      
      state = :sys.get_state(pid)
      assert state.input_buffer == "a"
      assert state.cursor_pos == 1
      
      GenServer.stop(pid)
    end
    
    test "handles backspace", %{pid: pid} do
      # First add some text
      GenServer.cast(pid, {:update_input, "test"})
      Process.sleep(10)
      
      # Simulate backspace
      send(pid, {:key_press, %{codepoint: 127, modifiers: %{ctrl: false, alt: false, shift: false}}})
      Process.sleep(10)
      
      state = :sys.get_state(pid)
      assert state.input_buffer == "tes"
      assert state.cursor_pos == 3
      
      GenServer.stop(pid)
    end
    
    test "handles tab for focus switching", %{pid: pid} do
      # Initial focus should be :input
      state = :sys.get_state(pid)
      assert state.focused_panel == :input
      
      # Press tab
      send(pid, {:key_press, %{codepoint: ?\t, modifiers: %{ctrl: false, alt: false, shift: false}}})
      Process.sleep(10)
      
      state = :sys.get_state(pid)
      assert state.focused_panel == :chat
      
      GenServer.stop(pid)
    end
  end
end