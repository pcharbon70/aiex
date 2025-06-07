defmodule Aiex.IEx.CommandsTest do
  use ExUnit.Case, async: true
  
  alias Aiex.IEx.Commands
  alias Aiex.InterfaceGateway
  alias Aiex.Events.EventBus

  @moduletag :iex_commands

  setup do
    # Start required services for testing
    case start_supervised({EventBus, []}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
    
    {:ok, gateway_pid} = case start_supervised({InterfaceGateway, []}) do
      {:ok, gateway_pid} -> {:ok, gateway_pid}
      {:error, {:already_started, gateway_pid}} -> {:ok, gateway_pid}
    end
    
    %{gateway_pid: gateway_pid}
  end

  describe "enhanced help command" do
    test "h/2 with :ai flag provides enhanced documentation" do
      # Capture IO to test output
      import ExUnit.CaptureIO
      
      output = capture_io(fn ->
        Commands.h(String, :ai)
      end)
      
      assert String.contains?(output, "Enhanced Documentation")
      assert String.contains?(output, "AI Analysis")
    end

    test "h/2 handles function references" do
      import ExUnit.CaptureIO
      
      output = capture_io(fn ->
        Commands.h({Enum, :map}, :ai)
      end)
      
      assert String.contains?(output, "Enhanced Documentation")
    end

    test "h/2 handles modules without documentation" do
      import ExUnit.CaptureIO
      
      # Test with a module that might not have docs
      output = capture_io(fn ->
        Commands.h(__MODULE__, :ai)
      end)
      
      # Should not crash and should provide some output
      assert is_binary(output)
    end
  end

  describe "enhanced compilation command" do
    test "c/2 with :analyze flag processes single file" do
      import ExUnit.CaptureIO
      
      # Create a temporary test file
      test_file = "/tmp/test_module.ex"
      File.write!(test_file, """
      defmodule TestModule do
        def hello, do: :world
      end
      """)
      
      output = capture_io(fn ->
        Commands.c(test_file, :analyze)
      end)
      
      assert String.contains?(output, "Compilation Results with AI Analysis")
      assert String.contains?(output, test_file)
      
      # Cleanup
      File.rm(test_file)
    end

    test "c/2 with :analyze flag processes multiple files" do
      import ExUnit.CaptureIO
      
      # Create temporary test files
      test_files = ["/tmp/test1.ex", "/tmp/test2.ex"]
      
      Enum.each(test_files, fn file ->
        File.write!(file, """
        defmodule TestModule#{System.unique_integer()} do
          def test, do: :ok
        end
        """)
      end)
      
      output = capture_io(fn ->
        Commands.c(test_files, :analyze)
      end)
      
      assert String.contains?(output, "Compilation Results with AI Analysis")
      
      # Cleanup
      Enum.each(test_files, &File.rm/1)
    end

    test "c/2 handles compilation errors gracefully" do
      import ExUnit.CaptureIO
      
      # Create a file with syntax errors
      test_file = "/tmp/broken_module.ex"
      File.write!(test_file, "defmodule BrokenModule do\n  invalid syntax here\nend")
      
      output = capture_io(fn ->
        Commands.c(test_file, :analyze)
      end)
      
      # Should handle the error gracefully
      assert String.contains?(output, "Compilation Results")
      
      # Cleanup
      File.rm(test_file)
    end
  end

  describe "enhanced testing commands" do
    test "test/2 with :generate flag for module" do
      import ExUnit.CaptureIO
      
      output = capture_io(fn ->
        Commands.test(String, :generate)
      end)
      
      assert String.contains?(output, "Test Results with AI Generation")
      assert String.contains?(output, "Existing Tests")
    end

    test "test/2 with :analyze flag for module" do
      import ExUnit.CaptureIO
      
      output = capture_io(fn ->
        Commands.test(Enum, :analyze)
      end)
      
      assert String.contains?(output, "Test Analysis")
      assert String.contains?(output, "Test Results")
    end

    test "test/2 with :review flag for all tests" do
      import ExUnit.CaptureIO
      
      output = capture_io(fn ->
        Commands.test(:all, :review)
      end)
      
      assert String.contains?(output, "Complete Test Suite Review")
      assert String.contains?(output, "Overall Results")
      assert String.contains?(output, "AI Review")
    end
  end

  describe "search commands" do
    test "search/2 with :semantic flag" do
      import ExUnit.CaptureIO
      
      output = capture_io(fn ->
        Commands.search("GenServer.call", :semantic)
      end)
      
      assert String.contains?(output, "Semantic Search Results")
      assert String.contains?(output, "GenServer.call")
    end

    test "search/2 with :pattern flag" do
      import ExUnit.CaptureIO
      
      output = capture_io(fn ->
        Commands.search("error handling", :pattern)
      end)
      
      assert String.contains?(output, "Pattern Search Results")
      assert String.contains?(output, "error handling")
    end

    test "search/2 with :similar flag for modules" do
      import ExUnit.CaptureIO
      
      output = capture_io(fn ->
        Commands.search(GenServer, :similar)
      end)
      
      assert String.contains?(output, "Similar Modules")
      assert String.contains?(output, "GenServer")
    end
  end

  describe "debug commands" do
    test "debug_trace/2 with :ai flag" do
      import ExUnit.CaptureIO
      
      output = capture_io(fn ->
        Commands.debug_trace(self(), :ai)
      end)
      
      assert String.contains?(output, "AI-Enhanced Process Trace")
      assert String.contains?(output, "PID:")
    end

    test "debug_cluster/1 with :analyze flag" do
      import ExUnit.CaptureIO
      
      output = capture_io(fn ->
        Commands.debug_cluster(:analyze)
      end)
      
      assert String.contains?(output, "AI Cluster Analysis")
      assert String.contains?(output, "Health Score")
    end

    test "debug_performance/1 with :bottlenecks flag" do
      import ExUnit.CaptureIO
      
      output = capture_io(fn ->
        Commands.debug_performance(:bottlenecks)
      end)
      
      assert String.contains?(output, "Performance Bottleneck Analysis")
    end
  end

  describe "private helper functions" do
    test "compilation result formatting" do
      # Test the internal result formatting logic
      # This ensures the private functions work correctly
      
      # Create a simple test file to compile
      test_file = "/tmp/simple_test.ex"
      File.write!(test_file, """
      defmodule SimpleTest do
        def hello, do: :world
      end
      """)
      
      # This should not crash when processing
      import ExUnit.CaptureIO
      
      output = capture_io(fn ->
        Commands.c(test_file, :analyze)
      end)
      
      assert is_binary(output)
      
      # Cleanup
      File.rm(test_file)
    end

    test "test result analysis" do
      import ExUnit.CaptureIO
      
      # Should handle test analysis without crashing
      output = capture_io(fn ->
        Commands.test(String, :analyze)
      end)
      
      assert is_binary(output)
      assert String.contains?(output, "Test Analysis")
    end
  end

  describe "error handling" do
    test "handles invalid module references gracefully" do
      import ExUnit.CaptureIO
      
      output = capture_io(fn ->
        Commands.h(NonExistentModule, :ai)
      end)
      
      # Should not crash
      assert is_binary(output)
    end

    test "handles invalid file paths in compilation" do
      import ExUnit.CaptureIO
      
      output = capture_io(fn ->
        Commands.c("/nonexistent/file.ex", :analyze)
      end)
      
      # Should handle the error gracefully
      assert is_binary(output)
    end

    test "handles search errors gracefully" do
      import ExUnit.CaptureIO
      
      output = capture_io(fn ->
        Commands.search("", :semantic)
      end)
      
      # Should not crash on empty search
      assert is_binary(output)
    end
  end

  describe "output formatting consistency" do
    test "all commands produce formatted output" do
      import ExUnit.CaptureIO
      
      commands_to_test = [
        fn -> Commands.h(String, :ai) end,
        fn -> Commands.debug_cluster(:analyze) end,
        fn -> Commands.test(String, :generate) end,
        fn -> Commands.search("test", :semantic) end
      ]
      
      Enum.each(commands_to_test, fn command ->
        output = capture_io(command)
        
        # All outputs should be non-empty strings
        assert is_binary(output)
        assert String.length(output) > 0
        
        # Should contain some basic formatting
        assert String.contains?(output, "\n")
      end)
    end

    test "commands use consistent emoji and formatting" do
      import ExUnit.CaptureIO
      
      output = capture_io(fn ->
        Commands.test(:all, :review)
      end)
      
      # Should use consistent emoji formatting
      assert String.contains?(output, "📋") or String.contains?(output, "📊")
    end
  end

  describe "integration with AI helpers" do
    test "commands integrate with Aiex.IEx.Helpers" do
      # This tests that the commands properly use the underlying AI helpers
      import ExUnit.CaptureIO
      
      # The help command should use ai_explain internally
      output = capture_io(fn ->
        Commands.h({Enum, :map}, :ai)
      end)
      
      # Should show AI analysis
      assert String.contains?(output, "AI Analysis") or String.contains?(output, "🤖")
    end
  end
end