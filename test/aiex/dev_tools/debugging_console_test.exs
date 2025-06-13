defmodule Aiex.DevTools.DebuggingConsoleTest do
  use ExUnit.Case, async: false
  
  alias Aiex.DevTools.DebuggingConsole
  
  setup do
    # Start DebuggingConsole for testing
    {:ok, pid} = DebuggingConsole.start_link([])
    on_exit(fn -> Process.exit(pid, :normal) end)
    :ok
  end
  
  describe "execute_command/1" do
    test "executes help command" do
      result = DebuggingConsole.execute_command("help")
      
      assert is_map(result)
      assert result.type == :help
      assert Map.has_key?(result, :content)
      assert String.contains?(result.content, "Aiex Debugging Console Commands")
    end
    
    test "executes nodes command" do
      result = DebuggingConsole.execute_command("nodes")
      
      assert is_map(result)
      assert result.type == :nodes
      assert Map.has_key?(result, :total)
      assert Map.has_key?(result, :nodes)
      assert is_integer(result.total)
      assert result.total >= 1
      assert is_list(result.nodes)
    end
    
    test "executes cluster command" do
      result = DebuggingConsole.execute_command("cluster")
      
      assert is_map(result)
      assert result.type == :cluster_overview
      assert Map.has_key?(result, :data)
      assert is_map(result.data)
    end
    
    test "executes memory command" do
      result = DebuggingConsole.execute_command("memory")
      
      assert is_map(result)
      assert result.type == :memory_analysis
      assert Map.has_key?(result, :data)
    end
    
    test "executes health command" do
      result = DebuggingConsole.execute_command("health")
      
      assert is_map(result)
      assert result.type == :health_report
      assert Map.has_key?(result, :data)
    end
    
    test "executes hot processes command with default limit" do
      result = DebuggingConsole.execute_command("hot")
      
      assert is_map(result)
      assert result.type == :hot_processes
      assert Map.has_key?(result, :data)
    end
    
    test "executes hot processes command with custom limit" do
      result = DebuggingConsole.execute_command("hot 5")
      
      assert is_map(result)
      assert result.type == :hot_processes
      assert Map.has_key?(result, :data)
    end
    
    test "executes processes command" do
      result = DebuggingConsole.execute_command("processes")
      
      assert is_map(result)
      assert result.type == :process_distribution
      assert Map.has_key?(result, :data)
    end
    
    test "executes processes command with pattern" do
      result = DebuggingConsole.execute_command("processes GenServer")
      
      assert is_map(result)
      assert result.type == :process_search
      assert Map.has_key?(result, :data)
    end
    
    test "executes exec command" do
      result = DebuggingConsole.execute_command("exec 1 + 1")
      
      assert is_map(result)
      assert result.type == :code_result
      assert Map.has_key?(result, :result)
      assert Map.has_key?(result, :code)
      assert result.code == "1 + 1"
      assert String.contains?(result.result, "2")
    end
    
    test "executes gc command" do
      result = DebuggingConsole.execute_command("gc")
      
      assert is_map(result)
      assert result.type == :success
      assert String.contains?(result.message, "garbage collection")
    end
    
    test "executes reset command" do
      result = DebuggingConsole.execute_command("reset")
      
      assert is_map(result)
      assert result.type == :success
      assert result.message == "Console state reset"
    end
    
    test "handles unknown commands" do
      result = DebuggingConsole.execute_command("unknown_command")
      
      assert is_map(result)
      assert result.type == :error
      assert String.contains?(result.message, "Unknown command")
    end
    
    test "handles empty commands" do
      result = DebuggingConsole.execute_command("")
      
      assert is_map(result)
      assert result.type == :empty
    end
    
    test "handles quit command" do
      result = DebuggingConsole.execute_command("quit")
      
      assert is_map(result)
      assert result.type == :quit
      assert result.message == "Goodbye!"
    end
  end
  
  describe "get_history/0" do
    test "returns command history" do
      # Execute some commands first
      DebuggingConsole.execute_command("help")
      DebuggingConsole.execute_command("nodes")
      
      history = DebuggingConsole.get_history()
      
      assert is_list(history)
      assert length(history) >= 2
      
      # Check history entry structure
      entry = List.first(history)
      assert Map.has_key?(entry, :timestamp)
      assert Map.has_key?(entry, :command)
      assert Map.has_key?(entry, :result)
      assert Map.has_key?(entry, :node)
    end
    
    test "maintains command order in history" do
      # Execute commands in specific order
      DebuggingConsole.execute_command("help")
      DebuggingConsole.execute_command("nodes")
      DebuggingConsole.execute_command("cluster")
      
      history = DebuggingConsole.get_history()
      
      # History should be in execution order (most recent first)
      commands = Enum.map(history, & &1.command)
      assert List.first(commands) == "help"
      assert "nodes" in commands
      assert "cluster" in commands
    end
  end
  
  describe "get_commands/0" do
    test "returns available commands map" do
      commands = DebuggingConsole.get_commands()
      
      assert is_map(commands)
      assert Map.has_key?(commands, "help")
      assert Map.has_key?(commands, "nodes")
      assert Map.has_key?(commands, "cluster")
      assert Map.has_key?(commands, "exec <code>")
      
      # Check command descriptions
      assert is_binary(commands["help"])
      assert String.length(commands["help"]) > 0
    end
  end
  
  describe "error handling" do
    test "handles invalid code execution gracefully" do
      result = DebuggingConsole.execute_command("exec invalid_syntax(")
      
      assert is_map(result)
      assert result.type == :error
      assert String.contains?(result.message, "Code execution failed")
    end
    
    test "handles node switching to invalid node" do
      result = DebuggingConsole.execute_command("node invalid@nonexistent")
      
      assert is_map(result)
      assert result.type == :error
      assert String.contains?(result.message, "Node not connected")
    end
    
    test "handles invalid hot processes limit" do
      # This should fail due to invalid integer conversion
      result = DebuggingConsole.execute_command("hot invalid")
      
      assert is_map(result)
      # Should either be an error or handle gracefully
      assert result.type in [:error, :hot_processes]
    end
  end
  
  describe "session management" do
    test "maintains session state across commands" do
      # Get initial history count
      initial_history = DebuggingConsole.get_history()
      initial_count = length(initial_history)
      
      # Execute a command
      DebuggingConsole.execute_command("help")
      
      # History should have increased
      updated_history = DebuggingConsole.get_history()
      assert length(updated_history) == initial_count + 1
    end
    
    test "reset command clears context but preserves history" do
      # Execute some commands
      DebuggingConsole.execute_command("help")
      history_before_reset = DebuggingConsole.get_history()
      
      # Reset console
      result = DebuggingConsole.execute_command("reset")
      assert result.type == :success
      
      # History should still contain the commands including reset
      history_after_reset = DebuggingConsole.get_history()
      assert length(history_after_reset) == length(history_before_reset) + 1
    end
  end
  
  describe "integration with cluster inspector" do
    test "inspect command uses cluster inspector" do
      result = DebuggingConsole.execute_command("inspect")
      
      assert is_map(result)
      assert result.type == :node_inspection
      assert Map.has_key?(result, :data)
    end
    
    test "ets command uses cluster inspector" do
      result = DebuggingConsole.execute_command("ets")
      
      assert is_map(result)
      assert result.type == :ets_distribution
      assert Map.has_key?(result, :data)
    end
    
    test "mnesia command uses cluster inspector" do
      result = DebuggingConsole.execute_command("mnesia")
      
      assert is_map(result)
      assert result.type == :mnesia_status
      assert Map.has_key?(result, :data)
    end
  end
end