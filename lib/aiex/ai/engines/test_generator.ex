defmodule Aiex.AI.Engines.TestGenerator do
  @moduledoc """
  Comprehensive test generation engine that creates intelligent test suites
  for Elixir code including unit tests, integration tests, property-based tests,
  and test data generation.
  
  This engine integrates with existing LLM coordination and context management
  to provide context-aware test generation with high coverage and quality.
  """
  
  use GenServer
  require Logger
  
  @behaviour Aiex.AI.Behaviours.AIEngine
  
  alias Aiex.LLM.ModelCoordinator
  alias Aiex.LLM.Templates.TemplateEngine
  alias Aiex.Context.Manager, as: ContextManager
  alias Aiex.Events.EventBus
  alias Aiex.Semantic.Chunker
  
  # Test generation types supported by this engine
  @supported_types [
    :unit_tests,           # Basic unit tests for functions
    :integration_tests,    # Integration tests for modules
    :property_tests,       # Property-based tests with StreamData
    :edge_case_tests,      # Tests for edge cases and error conditions
    :performance_tests,    # Performance and load tests
    :doc_tests,            # Documentation tests
    :mock_tests,           # Tests with mocks and stubs
    :test_data_generation, # Generate test data and fixtures
    :test_suite_analysis,  # Analyze existing test coverage
    :regression_tests      # Generate regression test cases
  ]
  
  @test_frameworks [:ex_unit, :property_based, :benchmark, :wallaby]
  @coverage_levels [:basic, :comprehensive, :exhaustive]
  
  defstruct [
    :session_id,
    :test_cache,
    :test_templates,
    :coverage_analyzer,
    :test_patterns
  ]
  
  ## Public API
  
  @doc """
  Starts the TestGenerator engine.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Generates tests for the given code.
  
  ## Examples
  
      iex> TestGenerator.generate_tests(code, :unit_tests)
      {:ok, %{tests: [...], coverage: %{...}, ...}}
      
      iex> TestGenerator.generate_tests(code, :all, coverage: :comprehensive)
      {:ok, %{test_suite: [...], metadata: %{...}, ...}}
  """
  def generate_tests(code_content, test_type \\ :unit_tests, options \\ []) do
    GenServer.call(__MODULE__, {:generate_tests, code_content, test_type, options}, 60_000)
  end
  
  @doc """
  Generates tests for a specific function.
  """
  def generate_function_tests(function_code, function_name, options \\ []) do
    GenServer.call(__MODULE__, {:generate_function_tests, function_code, function_name, options})
  end
  
  @doc """
  Generates tests for an entire module.
  """
  def generate_module_tests(module_code, options \\ []) do
    GenServer.call(__MODULE__, {:generate_module_tests, module_code, options}, 45_000)
  end
  
  @doc """
  Analyzes existing test coverage and suggests improvements.
  """
  def analyze_test_coverage(code_path, test_path, options \\ []) do
    GenServer.call(__MODULE__, {:analyze_coverage, code_path, test_path, options}, 30_000)
  end
  
  @doc """
  Generates test data and fixtures for testing.
  """
  def generate_test_data(schema_or_spec, data_type, options \\ []) do
    GenServer.call(__MODULE__, {:generate_test_data, schema_or_spec, data_type, options})
  end
  
  @doc """
  Creates a complete test suite for a project.
  """
  def generate_project_tests(project_path, options \\ []) do
    GenServer.call(__MODULE__, {:generate_project_tests, project_path, options}, 120_000)
  end
  
  ## AIEngine Behavior Implementation
  
  @impl Aiex.AI.Behaviours.AIEngine
  def process(request, context) do
    GenServer.call(__MODULE__, {:process_request, request, context})
  end
  
  @impl Aiex.AI.Behaviours.AIEngine
  def can_handle?(request_type) do
    request_type in @supported_types or request_type == :test_generation
  end
  
  @impl Aiex.AI.Behaviours.AIEngine
  def get_metadata do
    %{
      name: "Test Generator",
      description: "Comprehensive test generation engine for Elixir applications",
      supported_types: @supported_types,
      test_frameworks: @test_frameworks,
      coverage_levels: @coverage_levels,
      version: "1.0.0",
      capabilities: [
        "Unit test generation with ExUnit",
        "Property-based test generation with StreamData",
        "Integration test creation",
        "Edge case and error condition testing",
        "Performance test generation",
        "Documentation test creation",
        "Mock and stub generation",
        "Test data and fixture generation",
        "Coverage analysis and improvement",
        "Regression test creation"
      ]
    }
  end
  
  @impl Aiex.AI.Behaviours.AIEngine
  def prepare(options \\ []) do
    GenServer.call(__MODULE__, {:prepare, options})
  end
  
  @impl Aiex.AI.Behaviours.AIEngine
  def cleanup do
    GenServer.call(__MODULE__, :cleanup)
  end
  
  ## GenServer Implementation
  
  @impl GenServer
  def init(opts) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())
    
    # Initialize caches and templates
    test_cache = :ets.new(:test_generation_cache, [:set, :private])
    test_templates = initialize_test_templates()
    test_patterns = initialize_test_patterns()
    
    state = %__MODULE__{
      session_id: session_id,
      test_cache: test_cache,
      test_templates: test_templates,
      coverage_analyzer: %{},
      test_patterns: test_patterns
    }
    
    Logger.info("TestGenerator started with session_id: #{session_id}")
    
    EventBus.publish("ai.engine.test_generator.started", %{
      session_id: session_id,
      timestamp: DateTime.utc_now()
    })
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:generate_tests, code_content, test_type, options}, _from, state) do
    result = perform_test_generation(code_content, test_type, options, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:generate_function_tests, function_code, function_name, options}, _from, state) do
    result = generate_function_test_suite(function_code, function_name, options, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:generate_module_tests, module_code, options}, _from, state) do
    result = generate_module_test_suite(module_code, options, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:analyze_coverage, code_path, test_path, options}, _from, state) do
    result = perform_coverage_analysis(code_path, test_path, options, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:generate_test_data, schema_or_spec, data_type, options}, _from, state) do
    result = perform_test_data_generation(schema_or_spec, data_type, options, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:generate_project_tests, project_path, options}, _from, state) do
    result = perform_project_test_generation(project_path, options, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:process_request, request, context}, _from, state) do
    result = process_test_generation_request(request, context, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:prepare, options}, _from, state) do
    case prepare_test_generator(options, state) do
      {:ok, updated_state} -> {:reply, :ok, updated_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call(:cleanup, _from, state) do
    :ets.delete(state.test_cache)
    
    EventBus.publish("ai.engine.test_generator.stopped", %{
      session_id: state.session_id,
      timestamp: DateTime.utc_now()
    })
    
    {:reply, :ok, state}
  end
  
  ## Private Implementation
  
  defp perform_test_generation(code_content, test_type, options, state) do
    start_time = System.monotonic_time(:millisecond)
    
    # Check cache for similar test generation
    cache_key = generate_cache_key(code_content, test_type, options)
    
    case :ets.lookup(state.test_cache, cache_key) do
      [{^cache_key, cached_result}] ->
        Logger.debug("Cache hit for test generation: #{test_type}")
        {:ok, cached_result}
        
      [] ->
        case execute_test_generation(code_content, test_type, options, state) do
          {:ok, result} ->
            # Cache the result
            :ets.insert(state.test_cache, {cache_key, result})
            
            # Record metrics
            duration = System.monotonic_time(:millisecond) - start_time
            record_test_generation_metrics(test_type, duration, byte_size(code_content))
            
            {:ok, result}
            
          {:error, reason} ->
            Logger.warning("Test generation failed: #{reason}")
            {:error, reason}
        end
    end
  end
  
  defp execute_test_generation(code_content, test_type, options, state) do
    # Get enhanced project context
    project_context = get_enhanced_project_context(options, state)
    
    # Analyze code structure for test generation
    code_analysis = analyze_code_for_testing(code_content)
    
    # Generate test generation prompt
    prompt = generate_test_prompt(code_content, test_type, code_analysis, project_context, options)
    
    # Prepare LLM request
    llm_request = %{
      type: :test_generation,
      test_type: test_type,
      prompt: prompt,
      context: project_context,
      options: %{
        temperature: 0.4,  # Moderate creativity for diverse test cases
        max_tokens: get_max_tokens_for_test_type(test_type)
      }
    }
    
    case ModelCoordinator.process_request(llm_request) do
      {:ok, llm_response} ->
        # Process and structure the test generation response
        case post_process_test_generation(llm_response, test_type, code_analysis, options) do
          {:ok, processed_tests} ->
            structured_result = structure_test_result(processed_tests, test_type, code_analysis)
            {:ok, structured_result}
            
          {:error, reason} ->
            {:error, "Test post-processing failed: #{reason}"}
        end
        
      {:error, reason} ->
        {:error, "LLM request failed: #{reason}"}
    end
  end
  
  defp generate_function_test_suite(function_code, function_name, options, state) do
    # Enhanced function-specific test generation
    enhanced_options = Keyword.merge(options, [
      function_name: function_name,
      test_type: :unit_tests,
      focus: :function_testing
    ])
    
    perform_test_generation(function_code, :unit_tests, enhanced_options, state)
  end
  
  defp generate_module_test_suite(module_code, options, state) do
    # Generate comprehensive module test suite
    test_types = Keyword.get(options, :test_types, [:unit_tests, :integration_tests, :edge_case_tests])
    
    results = Enum.map(test_types, fn test_type ->
      case perform_test_generation(module_code, test_type, options, state) do
        {:ok, result} -> {test_type, result}
        {:error, _} -> {test_type, nil}
      end
    end)
    
    successful_results = Enum.filter(results, fn {_type, result} -> result != nil end) |> Map.new()
    
    {:ok, %{
      module_tests: successful_results,
      test_types: test_types,
      coverage_estimate: estimate_test_coverage(successful_results),
      timestamp: DateTime.utc_now()
    }}
  end
  
  defp perform_coverage_analysis(code_path, test_path, options, state) do
    # Analyze existing test coverage
    with {:ok, code_content} <- File.read(code_path),
         {:ok, test_content} <- File.read(test_path) do
      
      code_analysis = analyze_code_for_testing(code_content)
      test_analysis = analyze_existing_tests(test_content)
      
      coverage_report = generate_coverage_report(code_analysis, test_analysis)
      improvement_suggestions = suggest_coverage_improvements(coverage_report, code_analysis)
      
      {:ok, %{
        coverage_report: coverage_report,
        improvement_suggestions: improvement_suggestions,
        code_analysis: code_analysis,
        test_analysis: test_analysis,
        timestamp: DateTime.utc_now()
      }}
    else
      {:error, reason} -> {:error, "Failed to read files: #{reason}"}
    end
  end
  
  defp perform_test_data_generation(schema_or_spec, data_type, options, state) do
    # Generate test data based on schema or specification
    data_prompt = generate_test_data_prompt(schema_or_spec, data_type, options)
    
    llm_request = %{
      type: :test_data_generation,
      prompt: data_prompt,
      options: %{
        temperature: 0.6,  # Higher creativity for diverse test data
        max_tokens: 2000
      }
    }
    
    case ModelCoordinator.process_request(llm_request) do
      {:ok, llm_response} ->
        case parse_test_data_response(llm_response, data_type) do
          {:ok, test_data} ->
            {:ok, %{
              test_data: test_data,
              data_type: data_type,
              generation_method: "ai_generated",
              timestamp: DateTime.utc_now()
            }}
            
          {:error, reason} ->
            {:error, "Test data parsing failed: #{reason}"}
        end
        
      {:error, reason} ->
        {:error, "Test data generation failed: #{reason}"}
    end
  end
  
  defp perform_project_test_generation(project_path, options, state) do
    # Use semantic chunker to process project files
    case Chunker.chunk_directory(project_path, options) do
      {:ok, file_chunks} ->
        # Generate tests for each significant file
        file_test_results = Enum.map(file_chunks, fn chunk ->
          case generate_module_test_suite(chunk.content, options, state) do
            {:ok, result} -> Map.put(result, :file_path, chunk.file_path)
            {:error, reason} -> %{file_path: chunk.file_path, error: reason}
          end
        end)
        
        # Generate project-wide integration tests
        integration_tests = generate_project_integration_tests(file_chunks, options, state)
        
        project_summary = generate_project_test_summary(file_test_results, integration_tests)
        
        {:ok, %{
          files_processed: length(file_chunks),
          file_test_results: file_test_results,
          integration_tests: integration_tests,
          project_summary: project_summary,
          timestamp: DateTime.utc_now()
        }}
        
      {:error, reason} ->
        {:error, "Failed to chunk project: #{reason}"}
    end
  end
  
  defp generate_test_prompt(code_content, test_type, code_analysis, project_context, options) do
    # Use the template system for consistent, structured test generation prompts
    template_context = %{
      intent: :workflow,
      workflow_template: "workflow_generate_tests",
      code: code_content,
      test_type: test_type,
      code_analysis: code_analysis,
      project_context: project_context,
      coverage_requirements: get_coverage_requirements(options),
      interface: Map.get(project_context, :interface, :ai_engine)
    }
    
    case TemplateEngine.render_for_intent(:workflow, template_context) do
      {:ok, rendered_prompt} -> 
        rendered_prompt
      {:error, reason} ->
        Logger.warning("Template rendering failed, falling back to legacy prompt: #{reason}")
        generate_legacy_test_prompt(code_content, test_type, code_analysis, project_context, options)
    end
  end
  
  # Fallback to legacy prompt generation if template system fails
  defp generate_legacy_test_prompt(code_content, test_type, code_analysis, project_context, options) do
    base_prompt = get_base_test_prompt(test_type)
    context_info = format_context_for_prompt(project_context)
    analysis_info = format_analysis_for_prompt(code_analysis)
    coverage_requirements = get_coverage_requirements(options)
    
    """
    #{base_prompt}
    
    Project Context:
    #{context_info}
    
    Code Analysis:
    #{analysis_info}
    
    Coverage Requirements:
    #{coverage_requirements}
    
    Code to Test:
    ```elixir
    #{code_content}
    ```
    
    Please generate comprehensive tests following ExUnit conventions and best practices.
    Include setup, teardown, and helper functions as needed.
    """
  end
  
  defp get_base_test_prompt(:unit_tests) do
    """
    Generate comprehensive unit tests for this Elixir code. Include:
    - Tests for all public functions
    - Happy path scenarios
    - Edge cases and boundary conditions
    - Error handling and invalid inputs
    - Pattern matching scenarios
    - Guard clause testing
    Use ExUnit and follow Elixir testing best practices.
    """
  end
  
  defp get_base_test_prompt(:integration_tests) do
    """
    Generate integration tests for this Elixir code. Include:
    - Tests that verify module interactions
    - End-to-end workflow testing
    - External dependency testing with mocks
    - State management and side effects
    - Database integration (if applicable)
    - API endpoint testing (if applicable)
    Focus on testing how components work together.
    """
  end
  
  defp get_base_test_prompt(:property_tests) do
    """
    Generate property-based tests using StreamData for this Elixir code. Include:
    - Property definitions that should always hold
    - Generator functions for test data
    - Invariant testing
    - Round-trip property testing
    - Shrinking-friendly generators
    - Performance property testing
    Focus on properties that reveal bugs through random testing.
    """
  end
  
  defp get_base_test_prompt(:edge_case_tests) do
    """
    Generate edge case and error condition tests for this Elixir code. Include:
    - Boundary value testing (min/max values)
    - Null/nil value handling
    - Empty collections and strings
    - Invalid input types
    - Concurrent access scenarios
    - Resource exhaustion scenarios
    - Network failure simulations
    Focus on scenarios that commonly cause failures.
    """
  end
  
  defp get_base_test_prompt(:performance_tests) do
    """
    Generate performance and load tests for this Elixir code. Include:
    - Benchmarking critical functions
    - Memory usage testing
    - Concurrent load testing
    - Timeout scenario testing
    - Resource leak detection
    - Scalability testing
    Use :timer.tc/1 and consider Benchee for comprehensive benchmarking.
    """
  end
  
  defp get_base_test_prompt(:doc_tests) do
    """
    Generate documentation tests (doctests) for this Elixir code. Include:
    - Examples in @doc strings that can be tested
    - Clear, executable examples
    - Edge case examples in documentation
    - Error condition examples
    - Usage pattern demonstrations
    Ensure examples are realistic and helpful for users.
    """
  end
  
  defp get_base_test_prompt(:mock_tests) do
    """
    Generate tests with mocks and stubs for this Elixir code. Include:
    - External dependency mocking
    - Behavior verification with mocks
    - Stub creation for complex dependencies
    - Side effect testing
    - Callback verification
    Use Mox or similar mocking libraries following Elixir best practices.
    """
  end
  
  defp get_base_test_prompt(_) do
    """
    Generate comprehensive tests for this Elixir code.
    Include unit tests, edge cases, and error handling.
    Follow ExUnit conventions and Elixir testing best practices.
    """
  end
  
  defp analyze_code_for_testing(code_content) do
    %{
      functions: extract_functions(code_content),
      modules: extract_modules(code_content),
      dependencies: extract_dependencies(code_content),
      complexity: estimate_test_complexity(code_content),
      patterns: identify_testable_patterns(code_content),
      error_paths: identify_error_paths(code_content)
    }
  end
  
  defp extract_functions(code_content) do
    # Extract function signatures and information
    Regex.scan(~r/def\s+(\w+)\s*\(([^)]*)\)/, code_content)
    |> Enum.map(fn [_, name, params] ->
      %{
        name: name,
        parameters: parse_parameters(params),
        arity: count_parameters(params)
      }
    end)
  end
  
  defp extract_modules(code_content) do
    Regex.scan(~r/defmodule\s+([\w.]+)/, code_content)
    |> Enum.map(fn [_, name] -> name end)
  end
  
  defp extract_dependencies(code_content) do
    # Extract aliases and imports
    aliases = Regex.scan(~r/alias\s+([\w.]+)/, code_content) |> Enum.map(fn [_, dep] -> dep end)
    imports = Regex.scan(~r/import\s+([\w.]+)/, code_content) |> Enum.map(fn [_, dep] -> dep end)
    
    %{aliases: aliases, imports: imports}
  end
  
  defp estimate_test_complexity(code_content) do
    # Estimate testing complexity based on code patterns
    function_count = Regex.scan(~r/def\s+\w+/, code_content) |> length()
    pattern_count = Regex.scan(~r/case\s+|with\s+|if\s+/, code_content) |> length()
    guard_count = Regex.scan(~r/when\s+/, code_content) |> length()
    
    %{
      function_count: function_count,
      branching_complexity: pattern_count + guard_count,
      estimated_test_cases: function_count * 3 + pattern_count * 2
    }
  end
  
  defp identify_testable_patterns(code_content) do
    patterns = []
    
    patterns = if String.contains?(code_content, "GenServer"), do: ["genserver" | patterns], else: patterns
    patterns = if String.contains?(code_content, "Agent"), do: ["agent" | patterns], else: patterns
    patterns = if String.contains?(code_content, "with "), do: ["with_statement" | patterns], else: patterns
    patterns = if String.contains?(code_content, "case "), do: ["pattern_matching" | patterns], else: patterns
    
    patterns
  end
  
  defp identify_error_paths(code_content) do
    error_patterns = [
      %{pattern: "raise ", type: "exception"},
      %{pattern: "{:error,", type: "error_tuple"},
      %{pattern: "throw ", type: "throw"},
      %{pattern: "exit ", type: "exit"}
    ]
    
    Enum.filter(error_patterns, fn %{pattern: pattern} ->
      String.contains?(code_content, pattern)
    end)
  end
  
  defp parse_parameters(params_string) do
    params_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end
  
  defp count_parameters(params_string) do
    if String.trim(params_string) == "", do: 0, else: length(parse_parameters(params_string))
  end
  
  defp post_process_test_generation(llm_response, test_type, code_analysis, options) do
    # Clean and structure the test generation response
    cleaned_response = clean_test_response(llm_response)
    
    # Parse and validate the generated tests
    case parse_test_response(cleaned_response, test_type) do
      {:ok, tests} ->
        # Validate test syntax and structure
        validated_tests = validate_generated_tests(tests, code_analysis)
        
        # Add test metadata
        enhanced_tests = enhance_tests_with_metadata(validated_tests, test_type, options)
        
        {:ok, enhanced_tests}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp clean_test_response(response) do
    response
    |> String.trim()
    |> String.replace(~r/```elixir\n/, "")
    |> String.replace(~r/```/, "")
  end
  
  defp parse_test_response(response, test_type) do
    # In production, this would include sophisticated parsing
    # For now, return a structured response
    {:ok, %{
      test_module: "GeneratedTest",
      test_cases: [
        %{
          name: "test_example",
          description: "Example test case",
          code: response,
          type: test_type
        }
      ],
      setup_code: "",
      helper_functions: []
    }}
  end
  
  defp validate_generated_tests(tests, _code_analysis) do
    # Validate test syntax and completeness
    # In production, this would include AST parsing and validation
    tests
  end
  
  defp enhance_tests_with_metadata(tests, test_type, options) do
    Map.merge(tests, %{
      test_type: test_type,
      generation_options: options,
      estimated_coverage: estimate_coverage_from_tests(tests),
      test_count: count_test_cases(tests)
    })
  end
  
  defp estimate_coverage_from_tests(tests) do
    test_count = count_test_cases(tests)
    %{
      estimated_line_coverage: min(test_count * 15, 95),
      estimated_branch_coverage: min(test_count * 10, 85),
      test_case_count: test_count
    }
  end
  
  defp count_test_cases(tests) do
    length(tests[:test_cases] || [])
  end
  
  defp structure_test_result(tests, test_type, code_analysis) do
    %{
      test_type: test_type,
      generated_tests: tests,
      code_analysis: code_analysis,
      quality_score: calculate_test_quality_score(tests),
      timestamp: DateTime.utc_now(),
      metadata: %{
        engine: "test_generator",
        version: "1.0.0"
      }
    }
  end
  
  defp calculate_test_quality_score(tests) do
    # Calculate quality score based on various factors
    test_count = count_test_cases(tests)
    coverage = estimate_coverage_from_tests(tests)
    
    base_score = min(test_count * 10, 70)
    coverage_bonus = (coverage.estimated_line_coverage || 0) * 0.3
    
    Float.round(base_score + coverage_bonus, 1)
  end
  
  defp analyze_existing_tests(test_content) do
    %{
      test_modules: extract_test_modules(test_content),
      test_functions: extract_test_functions(test_content),
      setup_functions: extract_setup_functions(test_content),
      test_patterns: identify_test_patterns(test_content)
    }
  end
  
  defp extract_test_modules(test_content) do
    Regex.scan(~r/defmodule\s+([\w.]+Test)/, test_content)
    |> Enum.map(fn [_, name] -> name end)
  end
  
  defp extract_test_functions(test_content) do
    Regex.scan(~r/test\s+"([^"]+)"/, test_content)
    |> Enum.map(fn [_, name] -> name end)
  end
  
  defp extract_setup_functions(test_content) do
    setup_patterns = ["setup do", "setup_all do", "setup :"]
    
    Enum.filter(setup_patterns, fn pattern ->
      String.contains?(test_content, pattern)
    end)
  end
  
  defp identify_test_patterns(test_content) do
    patterns = []
    
    patterns = if String.contains?(test_content, "assert "), do: ["assertions" | patterns], else: patterns
    patterns = if String.contains?(test_content, "refute "), do: ["refutations" | patterns], else: patterns
    patterns = if String.contains?(test_content, "assert_raise"), do: ["exception_testing" | patterns], else: patterns
    patterns = if String.contains?(test_content, "Mock"), do: ["mocking" | patterns], else: patterns
    
    patterns
  end
  
  defp generate_coverage_report(code_analysis, test_analysis) do
    total_functions = length(code_analysis.functions)
    test_count = length(test_analysis.test_functions)
    
    %{
      total_functions: total_functions,
      test_count: test_count,
      estimated_coverage: if(total_functions > 0, do: min(test_count / total_functions * 100, 100), else: 0),
      coverage_gaps: identify_coverage_gaps(code_analysis, test_analysis)
    }
  end
  
  defp identify_coverage_gaps(code_analysis, test_analysis) do
    function_names = Enum.map(code_analysis.functions, & &1.name)
    tested_patterns = test_analysis.test_functions
    
    # Simple gap identification - in production this would be more sophisticated
    potentially_untested = function_names -- tested_patterns
    
    %{
      potentially_untested_functions: potentially_untested,
      missing_error_handling_tests: length(code_analysis.error_paths) - count_error_tests(test_analysis),
      missing_edge_case_tests: estimate_missing_edge_cases(code_analysis, test_analysis)
    }
  end
  
  defp count_error_tests(test_analysis) do
    Enum.count(test_analysis.test_patterns, fn pattern -> pattern == "exception_testing" end)
  end
  
  defp estimate_missing_edge_cases(_code_analysis, _test_analysis) do
    # Estimate missing edge case tests
    5  # Placeholder
  end
  
  defp suggest_coverage_improvements(coverage_report, code_analysis) do
    suggestions = []
    
    suggestions = if coverage_report.estimated_coverage < 80 do
      ["Increase overall test coverage to at least 80%" | suggestions]
    else
      suggestions
    end
    
    suggestions = if length(coverage_report.coverage_gaps.potentially_untested_functions) > 0 do
      ["Add tests for untested functions: #{Enum.join(coverage_report.coverage_gaps.potentially_untested_functions, ", ")}" | suggestions]
    else
      suggestions
    end
    
    suggestions = if coverage_report.coverage_gaps.missing_error_handling_tests > 0 do
      ["Add #{coverage_report.coverage_gaps.missing_error_handling_tests} error handling tests" | suggestions]
    else
      suggestions
    end
    
    suggestions
  end
  
  defp estimate_test_coverage(test_results) do
    total_tests = test_results
    |> Map.values()
    |> Enum.sum(fn result -> count_test_cases(result.generated_tests || %{}) end)
    
    %{
      total_test_cases: total_tests,
      estimated_line_coverage: min(total_tests * 12, 90),
      coverage_confidence: if(total_tests > 10, do: :high, else: :medium)
    }
  end
  
  defp generate_project_integration_tests(file_chunks, options, state) do
    # Generate integration tests that span multiple modules
    integration_prompt = generate_integration_test_prompt(file_chunks, options)
    
    llm_request = %{
      type: :integration_test_generation,
      prompt: integration_prompt,
      options: %{
        temperature: 0.4,
        max_tokens: 3000
      }
    }
    
    case ModelCoordinator.process_request(llm_request) do
      {:ok, llm_response} ->
        case parse_test_response(llm_response, :integration_tests) do
          {:ok, tests} -> tests
          {:error, _} -> %{}
        end
        
      {:error, _} -> %{}
    end
  end
  
  defp generate_integration_test_prompt(file_chunks, _options) do
    module_summaries = Enum.map(file_chunks, fn chunk ->
      "#{chunk.file_path}: #{extract_module_summary(chunk.content)}"
    end) |> Enum.join("\n")
    
    """
    Generate integration tests for this Elixir project that test module interactions.
    
    Project Modules:
    #{module_summaries}
    
    Focus on:
    - Cross-module function calls
    - Data flow between modules
    - End-to-end scenarios
    - External dependency integration
    - Error propagation across modules
    
    Create comprehensive integration test suites.
    """
  end
  
  defp extract_module_summary(content) do
    # Extract a brief summary of what the module does
    case Regex.run(~r/@moduledoc\s+"([^"]+)"/, content) do
      [_, doc] -> String.slice(doc, 0, 100) <> "..."
      _ -> "Module without documentation"
    end
  end
  
  defp generate_project_test_summary(file_test_results, integration_tests) do
    total_files = length(file_test_results)
    successful_files = Enum.count(file_test_results, fn result -> not Map.has_key?(result, :error) end)
    
    total_test_cases = file_test_results
    |> Enum.sum(fn result ->
      case result do
        %{module_tests: tests} -> 
          tests |> Map.values() |> Enum.sum(fn test -> count_test_cases(test.generated_tests || %{}) end)
        _ -> 0
      end
    end)
    
    %{
      total_files_processed: total_files,
      successful_files: successful_files,
      total_test_cases_generated: total_test_cases,
      integration_tests_generated: count_test_cases(integration_tests),
      estimated_project_coverage: calculate_project_coverage(file_test_results)
    }
  end
  
  defp calculate_project_coverage(file_test_results) do
    coverages = Enum.map(file_test_results, fn result ->
      case result do
        %{coverage_estimate: %{estimated_line_coverage: coverage}} -> coverage
        _ -> 0
      end
    end)
    
    if length(coverages) > 0 do
      Enum.sum(coverages) / length(coverages)
    else
      0
    end
  end
  
  defp generate_test_data_prompt(schema_or_spec, data_type, options) do
    """
    Generate test data for the following specification:
    
    Data Type: #{data_type}
    Schema/Specification:
    #{inspect(schema_or_spec)}
    
    Options: #{inspect(options)}
    
    Generate diverse test data including:
    - Valid data examples
    - Edge cases and boundary values
    - Invalid data for negative testing
    - Performance test data (if requested)
    
    Return the data in Elixir format that can be used directly in tests.
    """
  end
  
  defp parse_test_data_response(llm_response, data_type) do
    # Parse the generated test data
    {:ok, %{
      valid_data: [],
      edge_cases: [],
      invalid_data: [],
      data_type: data_type,
      raw_response: llm_response
    }}
  end
  
  defp process_test_generation_request(request, context, state) do
    test_type = Map.get(request, :test_type, :unit_tests)
    code_content = Map.get(request, :content)
    options = Map.get(request, :options, [])
    
    if code_content do
      enhanced_options = Keyword.merge(options, context: context)
      perform_test_generation(code_content, test_type, enhanced_options, state)
    else
      {:error, "No code content provided"}
    end
  end
  
  defp get_enhanced_project_context(options, _state) do
    # Get base project context
    base_context = case ContextManager.get_context("default") do
      {:ok, ctx} -> ctx
      {:error, _} -> %{}
    end
    
    # Add test-specific context
    Map.merge(base_context, Map.get(options, :context, %{}))
  end
  
  defp format_context_for_prompt(context) when is_map(context) do
    context
    |> Map.take([:project_name, :language, :framework, :dependencies, :testing_framework])
    |> Enum.map(fn {key, value} -> "#{key}: #{inspect(value)}" end)
    |> Enum.join("\n")
  end
  
  defp format_context_for_prompt(_), do: "No context available"
  
  defp format_analysis_for_prompt(analysis) do
    """
    Functions to test: #{length(analysis.functions)}
    Modules: #{length(analysis.modules)}
    Complexity score: #{analysis.complexity.estimated_test_cases}
    Testable patterns: #{Enum.join(analysis.patterns, ", ")}
    Error paths: #{length(analysis.error_paths)}
    """
  end
  
  defp get_coverage_requirements(options) do
    coverage_level = Keyword.get(options, :coverage, :basic)
    
    case coverage_level do
      :basic -> "Basic coverage with happy path and main error cases"
      :comprehensive -> "Comprehensive coverage including edge cases and all error paths"
      :exhaustive -> "Exhaustive coverage with property-based tests and performance testing"
      _ -> "Standard test coverage"
    end
  end
  
  defp initialize_test_templates do
    %{
      unit_test: load_unit_test_templates(),
      integration_test: load_integration_test_templates(),
      property_test: load_property_test_templates()
    }
  end
  
  defp initialize_test_patterns do
    %{
      genserver: load_genserver_test_patterns(),
      supervisor: load_supervisor_test_patterns(),
      phoenix: load_phoenix_test_patterns()
    }
  end
  
  defp load_unit_test_templates, do: %{}
  defp load_integration_test_templates, do: %{}
  defp load_property_test_templates, do: %{}
  defp load_genserver_test_patterns, do: %{}
  defp load_supervisor_test_patterns, do: %{}
  defp load_phoenix_test_patterns, do: %{}
  
  defp prepare_test_generator(options, state) do
    case ModelCoordinator.force_health_check() do
      :ok -> {:ok, "healthy"}
      :ok ->
        updated_state = if Keyword.get(options, :reload_templates, false) do
          %{state | 
            test_templates: initialize_test_templates(),
            test_patterns: initialize_test_patterns()
          }
        else
          state
        end
        
        {:ok, updated_state}
        
      {:error, reason} ->
        {:error, "LLM coordinator not ready: #{reason}"}
    end
  end
  
  defp get_max_tokens_for_test_type(:unit_tests), do: 3000
  defp get_max_tokens_for_test_type(:integration_tests), do: 4000
  defp get_max_tokens_for_test_type(:property_tests), do: 3500
  defp get_max_tokens_for_test_type(:performance_tests), do: 2500
  defp get_max_tokens_for_test_type(_), do: 3000
  
  defp generate_cache_key(code_content, test_type, options) do
    content_hash = :crypto.hash(:sha256, code_content) |> Base.encode16()
    options_hash = :crypto.hash(:sha256, inspect(options)) |> Base.encode16()
    "test_gen_#{test_type}_#{content_hash}_#{options_hash}"
  end
  
  defp record_test_generation_metrics(test_type, duration_ms, code_size_bytes) do
    EventBus.publish("ai.engine.test_generator.metrics", %{
      test_type: test_type,
      duration_ms: duration_ms,
      code_size_bytes: code_size_bytes,
      timestamp: DateTime.utc_now()
    })
  end
  
  defp generate_session_id do
    "test_generator_" <> Base.encode16(:crypto.strong_rand_bytes(8))
  end
end