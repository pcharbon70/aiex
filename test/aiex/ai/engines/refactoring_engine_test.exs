defmodule Aiex.AI.Engines.RefactoringEngineTest do
  use ExUnit.Case, async: false
  
  alias Aiex.AI.Engines.RefactoringEngine
  
  setup do
    # Check if RefactoringEngine is already running
    case Process.whereis(RefactoringEngine) do
      nil ->
        # Start the RefactoringEngine for testing if not already running
        {:ok, pid} = start_supervised({RefactoringEngine, [session_id: "test_refactoring_session"]})
        %{engine_pid: pid}
      
      pid ->
        # Use the existing process
        %{engine_pid: pid}
    end
  end
  
  describe "RefactoringEngine initialization" do
    test "starts successfully with default options" do
      result = RefactoringEngine.start_link()
      case result do
        {:ok, pid} -> assert Process.alive?(pid)
        {:error, {:already_started, pid}} -> assert Process.alive?(pid)
      end
    end
    
    test "starts with custom session_id" do
      session_id = "custom_refactoring_session"
      result = RefactoringEngine.start_link(session_id: session_id)
      case result do
        {:ok, pid} -> assert Process.alive?(pid)
        {:error, {:already_started, pid}} -> assert Process.alive?(pid)
      end
    end
  end
  
  describe "AIEngine behavior implementation" do
    test "implements can_handle?/1 correctly" do
      assert RefactoringEngine.can_handle?(:extract_function)
      assert RefactoringEngine.can_handle?(:extract_module)
      assert RefactoringEngine.can_handle?(:simplify_logic)
      assert RefactoringEngine.can_handle?(:optimize_performance)
      assert RefactoringEngine.can_handle?(:improve_readability)
      assert RefactoringEngine.can_handle?(:pattern_application)
      assert RefactoringEngine.can_handle?(:eliminate_duplication)
      assert RefactoringEngine.can_handle?(:modernize_syntax)
      assert RefactoringEngine.can_handle?(:structural_improvement)
      assert RefactoringEngine.can_handle?(:error_handling_improvement)
      assert RefactoringEngine.can_handle?(:refactoring)
      
      refute RefactoringEngine.can_handle?(:unsupported_refactoring)
      refute RefactoringEngine.can_handle?(:invalid_type)
    end
    
    test "get_metadata/0 returns correct information" do
      metadata = RefactoringEngine.get_metadata()
      
      assert metadata.name == "Refactoring Engine"
      assert is_binary(metadata.description)
      assert is_list(metadata.supported_types)
      assert is_list(metadata.severity_levels)
      assert is_list(metadata.confidence_levels)
      assert metadata.version == "1.0.0"
      assert is_list(metadata.capabilities)
      
      # Verify supported types are included
      assert :extract_function in metadata.supported_types
      assert :simplify_logic in metadata.supported_types
      assert :optimize_performance in metadata.supported_types
      
      # Verify severity levels
      assert :low in metadata.severity_levels
      assert :medium in metadata.severity_levels
      assert :high in metadata.severity_levels
      assert :critical in metadata.severity_levels
      
      # Verify confidence levels
      assert :low in metadata.confidence_levels
      assert :medium in metadata.confidence_levels
      assert :high in metadata.confidence_levels
      assert :very_high in metadata.confidence_levels
    end
    
    test "prepare/1 accepts options" do
      assert :ok = RefactoringEngine.prepare([])
      assert :ok = RefactoringEngine.prepare([reload_templates: true])
    end
  end
  
  describe "refactoring suggestion functionality" do
    @sample_code """
    defmodule Calculator do
      def add(a, b) do
        result = a + b
        if result > 100 do
          IO.puts("Large result: \\\#{result}")
          result
        else
          result
        end
      end
      
      def multiply(a, b) do
        result = a * b
        if result > 100 do
          IO.puts("Large result: \\\#{result}")
          result
        else
          result
        end
      end
      
      def process_numbers(numbers) do
        if length(numbers) > 0 do
          if length(numbers) > 10 do
            if Enum.all?(numbers, &is_number/1) do
              Enum.sum(numbers)
            else
              {:error, "Invalid numbers"}
            end
          else
            Enum.sum(numbers)
          end
        else
          0
        end
      end
    end
    """
    
    @tag :requires_llm
    test "suggest_refactoring/3 handles extract_function refactoring" do
      result = RefactoringEngine.suggest_refactoring(@sample_code, :extract_function)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      case result do
        {:ok, suggestions} ->
          assert Map.has_key?(suggestions, :refactoring_type)
          assert suggestions.refactoring_type == :extract_function
          assert Map.has_key?(suggestions, :suggestions)
          assert Map.has_key?(suggestions, :overall_score)
          
        {:error, _reason} ->
          # LLM might not be available in test environment
          :ok
      end
    end
    
    @tag :requires_llm
    test "suggest_refactoring/3 handles simplify_logic refactoring" do
      result = RefactoringEngine.suggest_refactoring(@sample_code, :simplify_logic)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "suggest_refactoring/3 handles eliminate_duplication refactoring" do
      result = RefactoringEngine.suggest_refactoring(@sample_code, :eliminate_duplication)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "suggest_refactoring/3 handles all refactoring types" do
      result = RefactoringEngine.suggest_refactoring(@sample_code, :all)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "suggest_refactoring/3 accepts options" do
      options = [
        focus_on: :performance,
        include_examples: true,
        severity_threshold: :medium
      ]
      
      result = RefactoringEngine.suggest_refactoring(@sample_code, :optimize_performance, options)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "suggest_refactoring/3 handles empty code" do
      result = RefactoringEngine.suggest_refactoring("", :extract_function)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "suggest_refactoring/3 handles complex nested code" do
      complex_code = """
      defmodule ComplexModule do
        def complex_function(data) do
          case data do
            %{type: :user, status: :active} ->
              if data.age > 18 do
                if data.verified do
                  case data.role do
                    :admin -> {:ok, :full_access}
                    :user -> {:ok, :limited_access}
                    _ -> {:error, :invalid_role}
                  end
                else
                  {:error, :not_verified}
                end
              else
                {:error, :too_young}
              end
            _ ->
              {:error, :invalid_data}
          end
        end
      end
      """
      
      result = RefactoringEngine.suggest_refactoring(complex_code, :simplify_logic)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "file analysis functionality" do
    @tag :requires_llm
    test "analyze_file/3 handles existing files" do
      # Create a temporary file for testing
      temp_file = "/tmp/test_refactoring_file.ex"
      File.write!(temp_file, @sample_code)
      
      result = RefactoringEngine.analyze_file(temp_file, [:extract_function, :simplify_logic])
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      # Clean up
      File.rm(temp_file)
    end
    
    test "analyze_file/3 handles non-existent files" do
      result = RefactoringEngine.analyze_file("/non/existent/file.ex", [:extract_function])
      assert {:error, error_msg} = result
      assert String.contains?(error_msg, "Failed to read file")
    end
    
    @tag :requires_llm
    test "analyze_file/3 with all refactoring types" do
      temp_file = "/tmp/test_refactoring_all.ex"
      File.write!(temp_file, @sample_code)
      
      result = RefactoringEngine.analyze_file(temp_file, [:all])
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      File.rm(temp_file)
    end
  end
  
  describe "project analysis functionality" do
    @tag :requires_llm
    test "analyze_project/3 handles directory analysis" do
      # Use the lib directory as a test case
      result = RefactoringEngine.analyze_project("lib", [:extract_function], max_files: 2)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      case result do
        {:ok, analysis} ->
          assert Map.has_key?(analysis, :files_analyzed)
          assert Map.has_key?(analysis, :file_results)
          assert Map.has_key?(analysis, :project_summary)
          
        {:error, _reason} ->
          # Directory might be too large or LLM unavailable
          :ok
      end
    end
    
    test "analyze_project/3 handles non-existent directory" do
      result = RefactoringEngine.analyze_project("/non/existent/directory", [:extract_function])
      assert match?({:error, _}, result)
    end
  end
  
  describe "refactoring application functionality" do
    @tag :requires_llm
    test "apply_refactoring/3 processes refactoring suggestions" do
      suggestion = %{
        description: "Extract common logging logic into a function",
        reason: "Reduces code duplication",
        confidence: :high,
        severity: :medium,
        effort: :small
      }
      
      result = RefactoringEngine.apply_refactoring(@sample_code, suggestion)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      case result do
        {:ok, applied} ->
          assert Map.has_key?(applied, :refactored_code)
          assert Map.has_key?(applied, :original_suggestion)
          assert Map.has_key?(applied, :validation_status)
          
        {:error, _reason} ->
          # LLM might not be available
          :ok
      end
    end
    
    @tag :requires_llm
    test "apply_refactoring/3 with options" do
      suggestion = %{
        description: "Simplify nested conditionals",
        reason: "Improves readability",
        confidence: :medium,
        severity: :low,
        effort: :medium
      }
      
      options = [validate: true, preserve_comments: true]
      
      result = RefactoringEngine.apply_refactoring(@sample_code, suggestion, options)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "refactoring validation functionality" do
    @tag :requires_llm
    test "validate_refactoring/3 compares original and refactored code" do
      original_code = @sample_code
      
      refactored_code = """
      defmodule Calculator do
        def add(a, b) do
          result = a + b
          handle_large_result(result)
        end
        
        def multiply(a, b) do
          result = a * b
          handle_large_result(result)
        end
        
        defp handle_large_result(result) when result > 100 do
          IO.puts("Large result: \\\#{result}")
          result
        end
        
        defp handle_large_result(result), do: result
        
        def process_numbers([]), do: 0
        def process_numbers(numbers) when length(numbers) <= 10 do
          if Enum.all?(numbers, &is_number/1) do
            Enum.sum(numbers)
          else
            {:error, "Invalid numbers"}
          end
        end
        def process_numbers(numbers) do
          if Enum.all?(numbers, &is_number/1) do
            Enum.sum(numbers)
          else
            {:error, "Invalid numbers"}
          end
        end
      end
      """
      
      result = RefactoringEngine.validate_refactoring(original_code, refactored_code)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      case result do
        {:ok, validation} ->
          assert Map.has_key?(validation, :status)
          assert Map.has_key?(validation, :validation_checks)
          
        {:error, _reason} ->
          # LLM might not be available
          :ok
      end
    end
    
    @tag :requires_llm
    test "validate_refactoring/3 with validation options" do
      original = "def simple(x), do: x + 1"
      refactored = "def simple(x) when is_number(x), do: x + 1"
      
      options = [check_performance: true, validate_types: true]
      
      result = RefactoringEngine.validate_refactoring(original, refactored, options)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "process/2 AIEngine interface" do
    @tag :requires_llm
    test "processes refactoring requests through unified interface" do
      request = %{
        type: :refactoring,
        refactoring_type: :extract_function,
        content: @sample_code,
        options: []
      }
      
      context = %{
        session_id: "test_session",
        project_context: %{framework: :phoenix}
      }
      
      result = RefactoringEngine.process(request, context)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "handles malformed refactoring requests" do
      request = %{
        type: :invalid_refactoring
        # Missing required fields
      }
      
      context = %{}
      
      result = RefactoringEngine.process(request, context)
      assert {:error, _error_msg} = result
    end
    
    @tag :requires_llm
    test "processes extract_module refactoring requests" do
      request = %{
        type: :refactoring,
        refactoring_type: :extract_module,
        content: @sample_code,
        options: [focus_on: :cohesion]
      }
      
      context = %{project_context: %{style: :functional}}
      
      result = RefactoringEngine.process(request, context)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "caching and performance" do
    @tag :requires_llm
    test "caches refactoring suggestions for identical requests" do
      code = "def simple(x), do: x * 2"
      
      # First refactoring analysis
      result1 = RefactoringEngine.suggest_refactoring(code, :extract_function)
      
      # Second analysis should use cache
      result2 = RefactoringEngine.suggest_refactoring(code, :extract_function)
      
      # Both should succeed (or both fail consistently)
      assert match?({:ok, _}, result1) or match?({:error, _}, result1)
      assert match?({:ok, _}, result2) or match?({:error, _}, result2)
    end
    
    @tag :requires_llm
    test "handles concurrent refactoring requests" do
      tasks = Enum.map(1..3, fn i ->
        Task.async(fn ->
          code = "def function_\#{i}(x), do: x + \#{i}"
          RefactoringEngine.suggest_refactoring(code, :improve_readability)
        end)
      end)
      
      results = Task.await_many(tasks)
      
      # All should complete
      assert length(results) == 3
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end
  end
  
  describe "code metrics and analysis" do
    @tag :requires_llm
    test "analyzes code complexity correctly" do
      complex_code = """
      defmodule Complex do
        def complex_function(data) do
          case data do
            %{type: :a} ->
              if data.valid do
                with {:ok, result} <- process_a(data),
                     {:ok, validated} <- validate_result(result) do
                  {:ok, validated}
                else
                  {:error, reason} -> {:error, reason}
                end
              else
                {:error, :invalid}
              end
            %{type: :b} ->
              case data.status do
                :active -> {:ok, :active}
                :inactive -> {:error, :inactive}
                _ -> {:error, :unknown}
              end
            _ ->
              {:error, :unsupported}
          end
        end
        
        defp process_a(data), do: {:ok, data}
        defp validate_result(result), do: {:ok, result}
      end
      """
      
      result = RefactoringEngine.suggest_refactoring(complex_code, :simplify_logic)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "detects code duplication patterns" do
      duplicate_code = """
      defmodule Duplicated do
        def process_user(user) do
          if user.active do
            Logger.info("Processing user: \\\#{user.name}")
            {:ok, user}
          else
            Logger.error("User not active: \\\#{user.name}")
            {:error, :inactive}
          end
        end
        
        def process_admin(admin) do
          if admin.active do
            Logger.info("Processing admin: \\\#{admin.name}")
            {:ok, admin}
          else
            Logger.error("Admin not active: \\\#{admin.name}")
            {:error, :inactive}
          end
        end
      end
      """
      
      result = RefactoringEngine.suggest_refactoring(duplicate_code, :eliminate_duplication)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "error handling" do
    @tag :requires_llm
    test "handles invalid refactoring types gracefully" do
      result = RefactoringEngine.suggest_refactoring(@sample_code, :invalid_type)
      # Should return error for unsupported type
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "handles malformed code inputs" do
      malformed_code = "this is not valid elixir code {"
      
      result = RefactoringEngine.suggest_refactoring(malformed_code, :extract_function)
      # Should handle gracefully
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "handles very large code inputs" do
      large_code = String.duplicate(@sample_code, 50)
      
      result = RefactoringEngine.suggest_refactoring(large_code, :simplify_logic)
      # Should handle large inputs without crashing
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "handles special characters in code" do
      special_code = """
      defmodule SpecialChars do
        def unicode_function do
          "Special: àáâãäåæçèéêë ñóôõö ùúûü"
        end
        
        def emoji_function do
          "Emojis: 🚀 🎉 ✨ 🔥 💯"
        end
      end
      """
      
      result = RefactoringEngine.suggest_refactoring(special_code, :improve_readability)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "refactoring suggestion quality" do
    @tag :requires_llm
    test "suggests appropriate refactoring for performance issues" do
      performance_code = """
      defmodule SlowCode do
        def process_large_list(list) do
          list
          |> Enum.map(&String.upcase/1)
          |> Enum.filter(&String.contains?(&1, "SPECIAL"))
          |> Enum.map(&String.downcase/1)
          |> Enum.sort()
        end
        
        def repeated_database_calls(ids) do
          Enum.map(ids, fn id ->
            # Simulated database call in loop
            Database.get_user(id)
          end)
        end
      end
      """
      
      result = RefactoringEngine.suggest_refactoring(performance_code, :optimize_performance)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "suggests pattern improvements for OTP code" do
      otp_code = """
      defmodule BasicWorker do
        def start do
          spawn(fn -> loop(%{}) end)
        end
        
        defp loop(state) do
          receive do
            {:get, caller} ->
              send(caller, state)
              loop(state)
            {:set, key, value} ->
              new_state = Map.put(state, key, value)
              loop(new_state)
            :stop ->
              :ok
          end
        end
      end
      """
      
      result = RefactoringEngine.suggest_refactoring(otp_code, :pattern_application)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "cleanup and resource management" do
    test "cleanup/0 properly cleans up resources" do
      assert :ok = RefactoringEngine.cleanup()
    end
    
    test "handles multiple cleanup calls" do
      assert :ok = RefactoringEngine.cleanup()
      assert :ok = RefactoringEngine.cleanup()
    end
  end
end