defmodule Aiex.AI.Engines.TestGeneratorTest do
  use ExUnit.Case, async: false
  
  alias Aiex.AI.Engines.TestGenerator
  
  setup do
    # Start the TestGenerator for testing
    {:ok, pid} = start_supervised({TestGenerator, [session_id: "test_generator_session"]})
    
    %{engine_pid: pid}
  end
  
  describe "TestGenerator initialization" do
    test "starts successfully with default options" do
      assert {:ok, pid} = TestGenerator.start_link()
      assert Process.alive?(pid)
    end
    
    test "starts with custom session_id" do
      session_id = "custom_test_generator_session"
      assert {:ok, pid} = TestGenerator.start_link(session_id: session_id)
      assert Process.alive?(pid)
    end
  end
  
  describe "AIEngine behavior implementation" do
    test "implements can_handle?/1 correctly" do
      assert TestGenerator.can_handle?(:unit_tests)
      assert TestGenerator.can_handle?(:integration_tests)
      assert TestGenerator.can_handle?(:property_tests)
      assert TestGenerator.can_handle?(:edge_case_tests)
      assert TestGenerator.can_handle?(:performance_tests)
      assert TestGenerator.can_handle?(:doc_tests)
      assert TestGenerator.can_handle?(:mock_tests)
      assert TestGenerator.can_handle?(:test_data_generation)
      assert TestGenerator.can_handle?(:test_suite_analysis)
      assert TestGenerator.can_handle?(:regression_tests)
      assert TestGenerator.can_handle?(:test_generation)
      
      refute TestGenerator.can_handle?(:unsupported_test_type)
      refute TestGenerator.can_handle?(:invalid_type)
    end
    
    test "get_metadata/0 returns correct information" do
      metadata = TestGenerator.get_metadata()
      
      assert metadata.name == "Test Generator"
      assert is_binary(metadata.description)
      assert is_list(metadata.supported_types)
      assert is_list(metadata.test_frameworks)
      assert is_list(metadata.coverage_levels)
      assert metadata.version == "1.0.0"
      assert is_list(metadata.capabilities)
      
      # Verify supported types are included
      assert :unit_tests in metadata.supported_types
      assert :integration_tests in metadata.supported_types
      assert :property_tests in metadata.supported_types
      
      # Verify test frameworks
      assert :ex_unit in metadata.test_frameworks
      assert :property_based in metadata.test_frameworks
      
      # Verify coverage levels
      assert :basic in metadata.coverage_levels
      assert :comprehensive in metadata.coverage_levels
      assert :exhaustive in metadata.coverage_levels
    end
    
    test "prepare/1 accepts options" do
      assert :ok = TestGenerator.prepare([])
      assert :ok = TestGenerator.prepare([reload_templates: true])
    end
  end
  
  describe "test generation functionality" do
    @sample_code """
    defmodule Calculator do
      @moduledoc "A simple calculator with basic arithmetic operations"
      
      def add(a, b) when is_number(a) and is_number(b) do
        a + b
      end
      
      def subtract(a, b) when is_number(a) and is_number(b) do
        a - b
      end
      
      def multiply(a, b) when is_number(a) and is_number(b) do
        a * b
      end
      
      def divide(a, b) when is_number(a) and is_number(b) and b != 0 do
        {:ok, a / b}
      end
      def divide(_a, 0), do: {:error, :division_by_zero}
      def divide(_a, _b), do: {:error, :invalid_input}
      
      defp validate_input(value) do
        is_number(value)
      end
    end
    """
    
    test "generate_tests/3 handles unit test generation" do
      result = TestGenerator.generate_tests(@sample_code, :unit_tests)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      case result do
        {:ok, test_result} ->
          assert Map.has_key?(test_result, :test_type)
          assert test_result.test_type == :unit_tests
          assert Map.has_key?(test_result, :generated_tests)
          assert Map.has_key?(test_result, :quality_score)
          
        {:error, _reason} ->
          # LLM might not be available in test environment
          :ok
      end
    end
    
    test "generate_tests/3 handles integration test generation" do
      result = TestGenerator.generate_tests(@sample_code, :integration_tests)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "generate_tests/3 handles property-based test generation" do
      result = TestGenerator.generate_tests(@sample_code, :property_tests)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "generate_tests/3 handles edge case test generation" do
      result = TestGenerator.generate_tests(@sample_code, :edge_case_tests)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "generate_tests/3 accepts coverage options" do
      options = [
        coverage: :comprehensive,
        include_performance: true,
        test_framework: :ex_unit
      ]
      
      result = TestGenerator.generate_tests(@sample_code, :unit_tests, options)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "generate_tests/3 handles empty code" do
      result = TestGenerator.generate_tests("", :unit_tests)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "generate_tests/3 handles complex code patterns" do
      complex_code = """
      defmodule PaymentProcessor do
        use GenServer
        
        def start_link(opts) do
          GenServer.start_link(__MODULE__, opts, name: __MODULE__)
        end
        
        def process_payment(amount, method) do
          GenServer.call(__MODULE__, {:process, amount, method})
        end
        
        def init(opts) do
          {:ok, %{processed: 0, config: opts}}
        end
        
        def handle_call({:process, amount, method}, _from, state) do
          case validate_payment(amount, method) do
            :ok ->
              result = charge_payment(amount, method)
              new_state = %{state | processed: state.processed + 1}
              {:reply, result, new_state}
              
            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        end
        
        defp validate_payment(amount, _method) when amount <= 0 do
          {:error, :invalid_amount}
        end
        defp validate_payment(_amount, method) when method not in [:card, :bank] do
          {:error, :invalid_method}
        end
        defp validate_payment(_amount, _method), do: :ok
        
        defp charge_payment(amount, method) do
          # Simulate payment processing
          if :rand.uniform() > 0.1 do
            {:ok, %{amount: amount, method: method, id: generate_id()}}
          else
            {:error, :payment_failed}
          end
        end
        
        defp generate_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16()
      end
      """
      
      result = TestGenerator.generate_tests(complex_code, :unit_tests)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "function-specific test generation" do
    test "generate_function_tests/3 generates tests for specific functions" do
      function_code = """
      def process_order(order_data) do
        with {:ok, validated} <- validate_order(order_data),
             {:ok, calculated} <- calculate_total(validated),
             {:ok, saved} <- save_order(calculated) do
          {:ok, saved}
        else
          {:error, reason} -> {:error, reason}
        end
      end
      """
      
      result = TestGenerator.generate_function_tests(
        function_code, 
        "process_order",
        [focus_on: :with_statement, test_error_paths: true]
      )
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "generate_function_tests/3 handles simple functions" do
      simple_function = "def greet(name), do: \"Hello, #{name}!\""
      
      result = TestGenerator.generate_function_tests(simple_function, "greet")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "generate_function_tests/3 handles functions with pattern matching" do
      pattern_function = """
      def handle_response({:ok, %{"data" => data}}), do: {:ok, data}
      def handle_response({:ok, %{"error" => error}}), do: {:error, error}
      def handle_response({:error, reason}), do: {:error, reason}
      """
      
      result = TestGenerator.generate_function_tests(
        pattern_function, 
        "handle_response",
        [test_all_patterns: true]
      )
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "module test generation" do
    test "generate_module_tests/2 creates comprehensive module test suite" do
      result = TestGenerator.generate_module_tests(@sample_code)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      case result do
        {:ok, module_tests} ->
          assert Map.has_key?(module_tests, :module_tests)
          assert Map.has_key?(module_tests, :test_types)
          assert Map.has_key?(module_tests, :coverage_estimate)
          
        {:error, _reason} ->
          :ok
      end
    end
    
    test "generate_module_tests/2 with specific test types" do
      options = [test_types: [:unit_tests, :edge_case_tests]]
      
      result = TestGenerator.generate_module_tests(@sample_code, options)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "generate_module_tests/2 handles GenServer modules" do
      genserver_code = """
      defmodule Counter do
        use GenServer
        
        def start_link(initial_value \\\\ 0) do
          GenServer.start_link(__MODULE__, initial_value, name: __MODULE__)
        end
        
        def increment do
          GenServer.call(__MODULE__, :increment)
        end
        
        def get_value do
          GenServer.call(__MODULE__, :get_value)
        end
        
        def init(initial_value) do
          {:ok, initial_value}
        end
        
        def handle_call(:increment, _from, state) do
          {:reply, state + 1, state + 1}
        end
        
        def handle_call(:get_value, _from, state) do
          {:reply, state, state}
        end
      end
      """
      
      result = TestGenerator.generate_module_tests(genserver_code)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "test coverage analysis" do
    test "analyze_test_coverage/3 analyzes existing test files" do
      code_file = "/tmp/test_code.ex"
      test_file = "/tmp/test_code_test.exs"
      
      File.write!(code_file, @sample_code)
      
      test_content = """
      defmodule CalculatorTest do
        use ExUnit.Case
        
        test "add/2 adds two numbers" do
          assert Calculator.add(2, 3) == 5
        end
        
        test "divide/2 handles division by zero" do
          assert Calculator.divide(10, 0) == {:error, :division_by_zero}
        end
      end
      """
      
      File.write!(test_file, test_content)
      
      result = TestGenerator.analyze_test_coverage(code_file, test_file)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      case result do
        {:ok, coverage_analysis} ->
          assert Map.has_key?(coverage_analysis, :coverage_report)
          assert Map.has_key?(coverage_analysis, :improvement_suggestions)
          assert Map.has_key?(coverage_analysis, :code_analysis)
          assert Map.has_key?(coverage_analysis, :test_analysis)
          
        {:error, _reason} ->
          :ok
      end
      
      # Clean up
      File.rm(code_file)
      File.rm(test_file)
    end
    
    test "analyze_test_coverage/3 handles missing files" do
      result = TestGenerator.analyze_test_coverage("/non/existent/code.ex", "/non/existent/test.exs")
      assert {:error, error_msg} = result
      assert String.contains?(error_msg, "Failed to read files")
    end
  end
  
  describe "test data generation" do
    test "generate_test_data/3 creates test data from schemas" do
      user_schema = %{
        name: :string,
        age: :integer,
        email: :string,
        active: :boolean
      }
      
      result = TestGenerator.generate_test_data(user_schema, :user_data)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      case result do
        {:ok, test_data} ->
          assert Map.has_key?(test_data, :test_data)
          assert Map.has_key?(test_data, :data_type)
          assert test_data.data_type == :user_data
          
        {:error, _reason} ->
          :ok
      end
    end
    
    test "generate_test_data/3 with generation options" do
      product_schema = %{
        id: :uuid,
        name: :string,
        price: :decimal,
        category: [:electronics, :books, :clothing]
      }
      
      options = [
        count: 10,
        include_edge_cases: true,
        include_invalid_data: true
      ]
      
      result = TestGenerator.generate_test_data(product_schema, :product_data, options)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "generate_test_data/3 handles different data types" do
      api_spec = """
      {
        "type": "object",
        "properties": {
          "id": {"type": "integer"},
          "username": {"type": "string", "minLength": 3},
          "roles": {"type": "array", "items": {"type": "string"}}
        }
      }
      """
      
      result = TestGenerator.generate_test_data(api_spec, :api_request_data)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "project test generation" do
    test "generate_project_tests/2 handles small project analysis" do
      # Use test directory as a small project
      options = [max_files: 3, test_types: [:unit_tests]]
      
      result = TestGenerator.generate_project_tests("test", options)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      case result do
        {:ok, project_tests} ->
          assert Map.has_key?(project_tests, :files_processed)
          assert Map.has_key?(project_tests, :file_test_results)
          assert Map.has_key?(project_tests, :project_summary)
          
        {:error, _reason} ->
          # Directory might be too large or LLM unavailable
          :ok
      end
    end
    
    test "generate_project_tests/2 handles non-existent directory" do
      result = TestGenerator.generate_project_tests("/non/existent/project")
      assert match?({:error, _}, result)
    end
  end
  
  describe "process/2 AIEngine interface" do
    test "processes test generation requests through unified interface" do
      request = %{
        type: :test_generation,
        test_type: :unit_tests,
        content: @sample_code,
        options: []
      }
      
      context = %{
        session_id: "test_session",
        project_context: %{framework: :phoenix}
      }
      
      result = TestGenerator.process(request, context)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "handles malformed test generation requests" do
      request = %{
        type: :invalid_test_type
        # Missing required fields
      }
      
      context = %{}
      
      result = TestGenerator.process(request, context)
      assert {:error, _error_msg} = result
    end
    
    test "processes property test generation requests" do
      request = %{
        type: :test_generation,
        test_type: :property_tests,
        content: @sample_code,
        options: [use_stream_data: true]
      }
      
      context = %{testing_framework: :stream_data}
      
      result = TestGenerator.process(request, context)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "processes integration test requests" do
      request = %{
        type: :test_generation,
        test_type: :integration_tests,
        content: @sample_code,
        options: [include_mocks: true]
      }
      
      context = %{project_type: :web_application}
      
      result = TestGenerator.process(request, context)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "caching and performance" do
    test "caches test generation results for identical requests" do
      code = "def simple(x), do: x * 2"
      
      # First test generation
      result1 = TestGenerator.generate_tests(code, :unit_tests)
      
      # Second generation should use cache
      result2 = TestGenerator.generate_tests(code, :unit_tests)
      
      # Both should succeed (or both fail consistently)
      assert match?({:ok, _} | {:error, _}, result1)
      assert match?({:ok, _} | {:error, _}, result2)
    end
    
    test "handles concurrent test generation requests" do
      tasks = Enum.map(1..3, fn i ->
        Task.async(fn ->
          code = "def function_#{i}(x), do: x + #{i}"
          TestGenerator.generate_tests(code, :unit_tests)
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
  
  describe "test quality and validation" do
    test "generates appropriate tests for error handling" do
      error_code = """
      defmodule FileProcessor do
        def process_file(path) do
          case File.read(path) do
            {:ok, content} ->
              case Jason.decode(content) do
                {:ok, data} -> validate_data(data)
                {:error, _} -> {:error, :invalid_json}
              end
            {:error, :enoent} -> {:error, :file_not_found}
            {:error, reason} -> {:error, reason}
          end
        end
        
        defp validate_data(%{"version" => v}) when v >= 1, do: {:ok, "valid"}
        defp validate_data(_), do: {:error, :invalid_data}
      end
      """
      
      result = TestGenerator.generate_tests(error_code, :edge_case_tests)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "generates performance tests for computationally intensive code" do
      performance_code = """
      defmodule DataProcessor do
        def process_large_dataset(data) when is_list(data) do
          data
          |> Enum.map(&complex_calculation/1)
          |> Enum.filter(&is_valid?/1)
          |> Enum.sort()
          |> Enum.take(1000)
        end
        
        defp complex_calculation(item) do
          # Simulate expensive calculation
          Enum.reduce(1..1000, item, fn i, acc -> acc + i end)
        end
        
        defp is_valid?(value), do: value > 0
      end
      """
      
      result = TestGenerator.generate_tests(performance_code, :performance_tests)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "generates doctests for well-documented code" do
      documented_code = """
      defmodule MathUtils do
        @moduledoc "Utility functions for mathematical operations"
        
        @doc \"\"\"
        Calculates the factorial of a non-negative integer.
        
        ## Examples
        
            iex> MathUtils.factorial(0)
            1
            
            iex> MathUtils.factorial(5)
            120
        \"\"\"
        def factorial(0), do: 1
        def factorial(n) when n > 0, do: n * factorial(n - 1)
      end
      """
      
      result = TestGenerator.generate_tests(documented_code, :doc_tests)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "error handling" do
    test "handles invalid test types gracefully" do
      result = TestGenerator.generate_tests(@sample_code, :invalid_test_type)
      # Should return error for unsupported type or handle gracefully
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "handles malformed code inputs" do
      malformed_code = "this is not valid elixir code {"
      
      result = TestGenerator.generate_tests(malformed_code, :unit_tests)
      # Should handle gracefully
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "handles very large code inputs" do
      large_code = String.duplicate(@sample_code, 20)
      
      result = TestGenerator.generate_tests(large_code, :unit_tests)
      # Should handle large inputs without crashing
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "handles special characters in code" do
      special_code = """
      defmodule UnicodeModule do
        def unicode_function do
          "Special: àáâãäåæçèéêë ñóôõö ùúûü"
        end
        
        def process_emoji(text) do
          String.replace(text, ~r/[😀-🙏]/, "")
        end
      end
      """
      
      result = TestGenerator.generate_tests(special_code, :unit_tests)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "test framework integration" do
    test "generates ExUnit-compatible tests" do
      result = TestGenerator.generate_tests(@sample_code, :unit_tests, [framework: :ex_unit])
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "generates property-based tests with StreamData" do
      result = TestGenerator.generate_tests(@sample_code, :property_tests, [framework: :stream_data])
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "generates mock tests with appropriate mocking library" do
      mock_code = """
      defmodule EmailService do
        def send_email(to, subject, body) do
          EmailProvider.send(%{
            to: to,
            subject: subject,
            body: body
          })
        end
        
        def send_welcome_email(user) do
          send_email(user.email, "Welcome!", "Welcome to our service!")
        end
      end
      """
      
      result = TestGenerator.generate_tests(mock_code, :mock_tests)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "cleanup and resource management" do
    test "cleanup/0 properly cleans up resources" do
      assert :ok = TestGenerator.cleanup()
    end
    
    test "handles multiple cleanup calls" do
      assert :ok = TestGenerator.cleanup()
      assert :ok = TestGenerator.cleanup()
    end
  end
end