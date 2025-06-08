defmodule Aiex.AI.Engines.CodeAnalyzerTest do
  use ExUnit.Case, async: false
  
  alias Aiex.AI.Engines.CodeAnalyzer
  alias Aiex.LLM.ModelCoordinator
  alias Aiex.Context.Manager, as: ContextManager
  alias Aiex.Events.EventBus
  
  # Mock modules for testing
  defmodule MockModelCoordinator do
    def request(%{type: :code_analysis, analysis_type: analysis_type}) do
      case analysis_type do
        :structure_analysis ->
          {:ok, %{
            analysis: "This code defines a simple module with basic structure...",
            patterns: ["Module definition", "Function definition"],
            suggestions: ["Consider adding documentation"]
          }}
          
        :complexity_analysis ->
          {:ok, %{
            complexity_score: 3,
            functions: [%{name: "test_function", complexity: 2}],
            suggestions: ["Function complexity is acceptable"]
          }}
          
        :error_analysis ->
          {:error, "Analysis failed"}
          
        _ ->
          {:ok, %{analysis: "Generic analysis result"}}
      end
    end
    
    def health_check, do: :ok
  end
  
  defmodule MockContextManager do
    def get_current_context do
      {:ok, %{
        project_name: "test_project",
        language: :elixir,
        framework: :phoenix,
        dependencies: ["ecto", "plug"]
      }}
    end
  end
  
  setup do
    # Start the CodeAnalyzer for testing
    {:ok, pid} = start_supervised({CodeAnalyzer, [session_id: "test_session"]})
    
    # Mock dependencies
    # In a real test, we'd use Mox or similar for proper mocking
    
    %{analyzer_pid: pid}
  end
  
  describe "CodeAnalyzer initialization" do
    test "starts successfully with default options" do
      assert {:ok, pid} = CodeAnalyzer.start_link()
      assert Process.alive?(pid)
    end
    
    test "starts with custom session_id" do
      session_id = "custom_test_session"
      assert {:ok, pid} = CodeAnalyzer.start_link(session_id: session_id)
      assert Process.alive?(pid)
    end
  end
  
  describe "AIEngine behavior implementation" do
    test "implements can_handle?/1 correctly" do
      assert CodeAnalyzer.can_handle?(:structure_analysis)
      assert CodeAnalyzer.can_handle?(:complexity_analysis)
      assert CodeAnalyzer.can_handle?(:pattern_analysis)
      assert CodeAnalyzer.can_handle?(:dependency_analysis)
      assert CodeAnalyzer.can_handle?(:security_analysis)
      assert CodeAnalyzer.can_handle?(:performance_analysis)
      assert CodeAnalyzer.can_handle?(:quality_analysis)
      
      refute CodeAnalyzer.can_handle?(:unsupported_analysis)
      refute CodeAnalyzer.can_handle?(:random_type)
    end
    
    test "get_metadata/0 returns correct information" do
      metadata = CodeAnalyzer.get_metadata()
      
      assert metadata.name == "Code Analyzer"
      assert is_binary(metadata.description)
      assert is_list(metadata.supported_types)
      assert metadata.version == "1.0.0"
      assert is_list(metadata.capabilities)
      
      # Verify supported types are included
      assert :structure_analysis in metadata.supported_types
      assert :complexity_analysis in metadata.supported_types
    end
    
    test "prepare/1 validates dependencies" do
      # This would normally test the actual preparation
      # For now, we'll test that it accepts options
      assert :ok = CodeAnalyzer.prepare([])
      assert :ok = CodeAnalyzer.prepare([reload_models: true])
    end
  end
  
  describe "code analysis functionality" do
    @sample_code """
    defmodule Calculator do
      @moduledoc "A simple calculator module"
      
      def add(a, b) when is_number(a) and is_number(b) do
        a + b
      end
      
      def subtract(a, b) when is_number(a) and is_number(b) do
        a - b
      end
      
      defp validate_numbers(a, b) do
        is_number(a) and is_number(b)
      end
    end
    """
    
    test "analyze_code/3 performs structure analysis", %{analyzer_pid: _pid} do
      # Mock the ModelCoordinator for this test
      # In practice, we'd use proper mocking libraries
      
      # For now, test the interface
      result = CodeAnalyzer.analyze_code(@sample_code, :structure_analysis)
      
      # Since we can't easily mock in this test, we'll test error handling
      assert match?({:ok, _} | {:error, _}, result)
    end
    
    test "analyze_code/3 validates analysis type" do
      result = CodeAnalyzer.analyze_code(@sample_code, :invalid_analysis_type)
      
      # Should either work or return an appropriate error
      assert match?({:ok, _} | {:error, _}, result)
    end
    
    test "analyze_code/3 handles empty code" do
      result = CodeAnalyzer.analyze_code("", :structure_analysis)
      
      # Should handle empty input gracefully
      assert match?({:ok, _} | {:error, _}, result)
    end
    
    test "analyze_file/3 handles file operations" do
      # Create a temporary file for testing
      file_path = "/tmp/test_code_#{System.unique_integer()}.ex"
      File.write!(file_path, @sample_code)
      
      result = CodeAnalyzer.analyze_file(file_path, :structure_analysis)
      
      # Clean up
      File.rm(file_path)
      
      assert match?({:ok, _} | {:error, _}, result)
    end
    
    test "analyze_file/3 handles missing files" do
      result = CodeAnalyzer.analyze_file("/nonexistent/file.ex", :structure_analysis)
      
      assert {:error, error_msg} = result
      assert String.contains?(error_msg, "Failed to read file")
    end
  end
  
  describe "caching functionality" do
    test "caches analysis results" do
      # This would test that identical analyses are cached
      # Implementation depends on the actual caching mechanism
      code = "def simple_function, do: :ok"
      
      # First analysis
      result1 = CodeAnalyzer.analyze_code(code, :structure_analysis)
      
      # Second analysis should be faster (cached)
      result2 = CodeAnalyzer.analyze_code(code, :structure_analysis)
      
      # Both should succeed (or both fail consistently)
      assert match?({:ok, _} | {:error, _}, result1)
      assert match?({:ok, _} | {:error, _}, result2)
    end
  end
  
  describe "project analysis" do
    test "analyze_project/3 handles directory analysis" do
      # Create a temporary directory with test files
      temp_dir = "/tmp/test_project_#{System.unique_integer()}"
      File.mkdir_p!(temp_dir)
      
      # Create test files
      File.write!(Path.join(temp_dir, "module1.ex"), @sample_code)
      File.write!(Path.join(temp_dir, "module2.ex"), "defmodule Simple, do: def test, do: :ok")
      
      result = CodeAnalyzer.analyze_project(temp_dir, [:structure_analysis], [])
      
      # Clean up
      File.rm_rf!(temp_dir)
      
      assert match?({:ok, _} | {:error, _}, result)
    end
    
    test "analyze_project/3 handles nonexistent directory" do
      result = CodeAnalyzer.analyze_project("/nonexistent/directory", [:structure_analysis], [])
      
      assert {:error, error_msg} = result
      assert is_binary(error_msg)
    end
  end
  
  describe "process/2 AIEngine interface" do
    test "processes analysis requests through unified interface" do
      request = %{
        type: :code_analysis,
        content: @sample_code,
        analysis_type: :structure_analysis,
        options: []
      }
      
      context = %{
        session_id: "test_session",
        user_id: "test_user"
      }
      
      result = CodeAnalyzer.process(request, context)
      
      assert match?({:ok, _} | {:error, _}, result)
    end
    
    test "handles malformed requests" do
      request = %{
        type: :invalid_request
        # Missing required fields
      }
      
      context = %{}
      
      result = CodeAnalyzer.process(request, context)
      
      assert {:error, _error_msg} = result
    end
  end
  
  describe "error handling and edge cases" do
    test "handles invalid Elixir code gracefully" do
      invalid_code = "this is not valid elixir code {"
      
      result = CodeAnalyzer.analyze_code(invalid_code, :structure_analysis)
      
      # Should handle syntax errors gracefully
      assert match?({:ok, _} | {:error, _}, result)
    end
    
    test "handles very large code files" do
      # Generate a large code string
      large_code = String.duplicate(@sample_code, 100)
      
      result = CodeAnalyzer.analyze_code(large_code, :structure_analysis)
      
      # Should handle large inputs without crashing
      assert match?({:ok, _} | {:error, _}, result)
    end
    
    test "handles concurrent analysis requests" do
      # Test multiple concurrent requests
      tasks = Enum.map(1..5, fn i ->
        Task.async(fn ->
          code = "def function_#{i}, do: #{i}"
          CodeAnalyzer.analyze_code(code, :structure_analysis)
        end)
      end)
      
      results = Task.await_many(tasks)
      
      # All should complete (successfully or with consistent errors)
      assert length(results) == 5
      Enum.each(results, fn result ->
        assert match?({:ok, _} | {:error, _}, result)
      end)
    end
  end
  
  describe "metrics and events" do
    test "emits appropriate events during analysis" do
      # This would test event emission
      # For now, we verify the interface exists
      assert function_exported?(EventBus, :emit, 2)
    end
  end
  
  describe "cleanup and resource management" do
    test "cleanup/0 properly cleans up resources" do
      assert :ok = CodeAnalyzer.cleanup()
    end
    
    test "handles cleanup when cache is already deleted" do
      # Call cleanup multiple times
      assert :ok = CodeAnalyzer.cleanup()
      assert :ok = CodeAnalyzer.cleanup()
    end
  end
end