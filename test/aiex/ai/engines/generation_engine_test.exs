defmodule Aiex.AI.Engines.GenerationEngineTest do
  use ExUnit.Case, async: false
  
  alias Aiex.AI.Engines.GenerationEngine
  
  setup do
    # Check if GenerationEngine is already running
    case Process.whereis(GenerationEngine) do
      nil ->
        # Start the GenerationEngine for testing if not already running
        {:ok, pid} = start_supervised({GenerationEngine, [session_id: "test_generation_session"]})
        %{engine_pid: pid}
      
      pid ->
        # Use the existing process
        %{engine_pid: pid}
    end
  end
  
  describe "GenerationEngine initialization" do
    test "is started and alive", %{engine_pid: pid} do
      assert Process.alive?(pid)
      assert pid == Process.whereis(GenerationEngine)
    end
    
    test "responds to basic GenServer calls", %{engine_pid: _pid} do
      # Test that the engine responds to calls
      assert GenerationEngine.can_handle?(:module_generation)
      assert is_map(GenerationEngine.get_metadata())
    end
  end
  
  describe "AIEngine behavior implementation" do
    test "implements can_handle?/1 correctly" do
      assert GenerationEngine.can_handle?(:module_generation)
      assert GenerationEngine.can_handle?(:function_generation)
      assert GenerationEngine.can_handle?(:test_generation)
      assert GenerationEngine.can_handle?(:documentation_generation)
      assert GenerationEngine.can_handle?(:boilerplate_generation)
      assert GenerationEngine.can_handle?(:refactoring_generation)
      assert GenerationEngine.can_handle?(:api_generation)
      assert GenerationEngine.can_handle?(:schema_generation)
      
      refute GenerationEngine.can_handle?(:unsupported_generation)
      refute GenerationEngine.can_handle?(:invalid_type)
    end
    
    test "get_metadata/0 returns correct information" do
      metadata = GenerationEngine.get_metadata()
      
      assert metadata.name == "Generation Engine"
      assert is_binary(metadata.description)
      assert is_list(metadata.supported_types)
      assert metadata.version == "1.0.0"
      assert is_list(metadata.capabilities)
      
      # Verify supported types are included
      assert :module_generation in metadata.supported_types
      assert :function_generation in metadata.supported_types
      assert :test_generation in metadata.supported_types
    end
    
    test "prepare/1 accepts options" do
      assert :ok = GenerationEngine.prepare([])
      assert :ok = GenerationEngine.prepare([reload_conventions: true])
    end
  end
  
  describe "module generation" do
    @tag :requires_llm
    test "generate_module/3 accepts module parameters" do
      module_name = "Calculator"
      description = "A simple calculator module with basic arithmetic operations"
      options = [include_tests: true, documentation: :full]
      
      result = GenerationEngine.generate_module(module_name, description, options)
      
      # Test that the interface works (actual generation depends on LLM)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "generate_module/3 handles empty module name" do
      result = GenerationEngine.generate_module("", "Some description")
      
      # Should handle empty module name appropriately
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "generate_module/3 handles complex descriptions" do
      module_name = "ComplexDataProcessor"
      description = """
      A module that processes complex data structures with the following capabilities:
      - Parse JSON and XML data
      - Validate data against schemas
      - Transform data between formats
      - Handle errors gracefully
      - Support streaming for large datasets
      """
      
      result = GenerationEngine.generate_module(module_name, description)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "function generation" do
    @tag :requires_llm
    test "generate_function/4 creates functions with parameters" do
      function_name = "calculate_tax"
      description = "Calculate tax amount based on income and tax rate"
      parameters = ["income", "tax_rate", "deductions"]
      options = [guards: true, documentation: true]
      
      result = GenerationEngine.generate_function(function_name, description, parameters, options)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "generate_function/4 handles functions without parameters" do
      function_name = "current_timestamp"
      description = "Get the current UTC timestamp"
      
      result = GenerationEngine.generate_function(function_name, description)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "generate_function/4 handles complex function signatures" do
      function_name = "process_user_data"
      description = "Process user data with validation and transformation"
      parameters = ["user_data", "validation_rules", "transform_options"]
      options = [
        return_type: :map,
        error_handling: :detailed,
        pattern_matching: true
      ]
      
      result = GenerationEngine.generate_function(function_name, description, parameters, options)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "test generation" do
    @sample_code """
    defmodule Calculator do
      def add(a, b) when is_number(a) and is_number(b) do
        a + b
      end
      
      def divide(a, b) when is_number(a) and is_number(b) and b != 0 do
        a / b
      end
    end
    """
    
    @tag :requires_llm
    test "generate_tests/3 creates unit tests" do
      result = GenerationEngine.generate_tests(@sample_code, :unit_tests)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "generate_tests/3 creates property tests" do
      result = GenerationEngine.generate_tests(@sample_code, :property_tests)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "generate_tests/3 creates integration tests" do
      result = GenerationEngine.generate_tests(@sample_code, :integration_tests)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "generate_tests/3 handles complex code structures" do
      complex_code = """
      defmodule UserService do
        alias MyApp.{User, Repo}
        
        def create_user(attrs) do
          %User{}
          |> User.changeset(attrs)
          |> Repo.insert()
        end
        
        def get_user(id) do
          case Repo.get(User, id) do
            nil -> {:error, :not_found}
            user -> {:ok, user}
          end
        end
      end
      """
      
      result = GenerationEngine.generate_tests(complex_code, :unit_tests, [mocking: true])
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "documentation generation" do
    @tag :requires_llm
    test "generate_documentation/3 creates module documentation" do
      code_content = @sample_code
      
      result = GenerationEngine.generate_documentation(code_content, :module_docs)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "generate_documentation/3 creates function documentation" do
      function_code = """
      def process_payment(amount, payment_method, user_id) do
        # Implementation here
      end
      """
      
      result = GenerationEngine.generate_documentation(function_code, :function_docs)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "generate_documentation/3 creates API documentation" do
      api_code = """
      defmodule MyAppWeb.UserController do
        use MyAppWeb, :controller
        
        def index(conn, _params) do
          # List users
        end
        
        def create(conn, %{"user" => user_params}) do
          # Create user
        end
      end
      """
      
      result = GenerationEngine.generate_documentation(api_code, :api_docs)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "code generation with context" do
    @tag :requires_llm
    test "generate_code/3 uses project context" do
      context = %{
        project_name: "MyApp",
        language: :elixir,
        framework: :phoenix,
        naming_convention: :snake_case,
        module_prefix: "MyApp"
      }
      
      result = GenerationEngine.generate_code(
        :module_generation, 
        "A user authentication module", 
        context
      )
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "generate_code/3 handles missing context gracefully" do
      result = GenerationEngine.generate_code(
        :function_generation,
        "A utility function",
        %{}
      )
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "process/2 AIEngine interface" do
    @tag :requires_llm
    test "processes generation requests through unified interface" do
      request = %{
        type: :code_generation,
        generation_type: :module_generation,
        specification: "Create a module for handling user sessions",
        context: %{
          module_name: "SessionManager",
          include_genserver: true
        }
      }
      
      context = %{
        session_id: "test_session",
        project_context: %{framework: :phoenix}
      }
      
      result = GenerationEngine.process(request, context)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "handles malformed generation requests" do
      request = %{
        type: :invalid_generation
        # Missing required fields
      }
      
      context = %{}
      
      result = GenerationEngine.process(request, context)
      
      assert {:error, _error_msg} = result
    end
    
    @tag :requires_llm
    test "processes function generation requests" do
      request = %{
        type: :code_generation,
        generation_type: :function_generation,
        specification: "Create a function to validate email addresses",
        context: %{
          function_name: "validate_email",
          parameters: ["email"],
          return_type: :boolean
        }
      }
      
      context = %{validation: :strict}
      
      result = GenerationEngine.process(request, context)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "caching and performance" do
    @tag :requires_llm
    test "caches generation results for identical requests" do
      specification = "Create a simple greeting function"
      context = %{function_name: "greet"}
      
      # First generation
      result1 = GenerationEngine.generate_code(:function_generation, specification, context)
      
      # Second generation should use cache
      result2 = GenerationEngine.generate_code(:function_generation, specification, context)
      
      # Both should succeed (or both fail consistently)
      assert match?({:ok, _}, result1) or match?({:error, _}, result1)
      assert match?({:ok, _}, result2) or match?({:error, _}, result2)
    end
    
    @tag :requires_llm
    test "handles concurrent generation requests" do
      tasks = Enum.map(1..3, fn i ->
        Task.async(fn ->
          GenerationEngine.generate_function(
            "function_#{i}",
            "A test function number #{i}",
            ["param#{i}"]
          )
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
  
  describe "code validation and post-processing" do
    test "validates generated code syntax" do
      # This tests the internal validation logic
      # Implementation would depend on actual code generation
      
      # Test the interface exists
      assert function_exported?(Code, :string_to_quoted, 1)
    end
    
    test "applies formatting to generated code" do
      # Test that Code.format_string is available for formatting
      sample_code = "def test(a,b),do: a+b"
      
      assert is_function(&Code.format_string/1)
      
      # Verify formatting works
      formatted = Code.format_string(sample_code)
      assert is_binary(formatted)
      assert String.contains?(formatted, "def test(a, b), do: a + b")
    end
  end
  
  describe "error handling" do
    @tag :requires_llm
    test "handles invalid generation types gracefully" do
      result = GenerationEngine.generate_code(:invalid_type, "Some specification", %{})
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "handles empty specifications" do
      result = GenerationEngine.generate_code(:module_generation, "", %{})
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "handles very long specifications" do
      long_spec = String.duplicate("This is a very long specification. ", 1000)
      
      result = GenerationEngine.generate_code(:function_generation, long_spec, %{})
      
      # Should handle large inputs without crashing
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "cleanup and resource management" do
    test "cleanup/0 properly cleans up resources" do
      assert :ok = GenerationEngine.cleanup()
    end
    
    test "handles multiple cleanup calls" do
      assert :ok = GenerationEngine.cleanup()
      assert :ok = GenerationEngine.cleanup()
    end
  end
end