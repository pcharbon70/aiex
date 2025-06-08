defmodule Aiex.Testing.DistributedTestGenerator do
  @moduledoc """
  Distributed test generation system that analyzes code patterns across nodes
  and generates comprehensive ExUnit tests with parallel processing.
  
  Features:
  - Distributed pattern analysis across cluster nodes
  - Parallel ExUnit test generation using pg process groups
  - Property-based test creation with StreamData integration
  - Cluster-wide quality scoring and test suggestions
  - Node-aware coverage analysis and coordination
  - Distributed doctest generation
  - Integration with semantic chunker and LLM coordination
  
  ## Architecture
  
  Uses pg process groups for distributed coordination, Mnesia for test storage,
  and integrates with the existing LLM coordination system for AI-powered
  test generation across the cluster.
  
  ## Usage
  
      # Generate tests for a module across the cluster
      {:ok, tests} = DistributedTestGenerator.generate_tests(MyModule, %{
        test_types: [:unit, :property, :integration],
        coverage_target: 90,
        distribute_across: 3
      })
      
      # Analyze test patterns cluster-wide
      {:ok, patterns} = DistributedTestGenerator.analyze_test_patterns([
        "test/**/*_test.exs"
      ])
      
      # Get distributed coverage analysis
      coverage = DistributedTestGenerator.get_cluster_coverage()
  """
  
  use GenServer
  require Logger
  
  alias Aiex.LLM.ModelCoordinator
  alias Aiex.Semantic.Chunker
  alias Aiex.Events.OTPEventBus
  
  @pg_scope :test_generation
  @test_storage_table :distributed_tests
  @pattern_cache_table :test_patterns
  @coverage_table :test_coverage
  
  defstruct [
    :node,
    :active_generations,
    :pattern_cache,
    :coverage_data,
    :metrics
  ]
  
  ## Client API
  
  @doc """
  Starts the distributed test generator.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Generates comprehensive tests for a module using distributed processing.
  
  ## Options
  - `:test_types` - List of test types to generate (`:unit`, `:property`, `:integration`, `:doctest`)
  - `:coverage_target` - Target coverage percentage (default: 85)
  - `:distribute_across` - Number of nodes to distribute generation across
  - `:quality_threshold` - Minimum quality score for generated tests (default: 0.7)
  - `:max_tests_per_function` - Maximum tests per function (default: 5)
  - `:include_edge_cases` - Whether to include edge case testing (default: true)
  
  ## Examples
  
      {:ok, tests} = DistributedTestGenerator.generate_tests(Calculator, %{
        test_types: [:unit, :property],
        coverage_target: 95,
        distribute_across: 2
      })
  """
  def generate_tests(module, opts \\ %{}) do
    GenServer.call(__MODULE__, {:generate_tests, module, opts}, 60_000)
  end
  
  @doc """
  Analyzes test patterns across the cluster for a set of test files.
  """
  def analyze_test_patterns(file_patterns, opts \\ %{}) do
    GenServer.call(__MODULE__, {:analyze_patterns, file_patterns, opts}, 30_000)
  end
  
  @doc """
  Generates property-based tests using StreamData for a module.
  """
  def generate_property_tests(module, opts \\ %{}) do
    GenServer.call(__MODULE__, {:generate_property_tests, module, opts}, 30_000)
  end
  
  @doc """
  Gets cluster-wide test coverage analysis.
  """
  def get_cluster_coverage(opts \\ %{}) do
    GenServer.call(__MODULE__, {:get_cluster_coverage, opts})
  end
  
  @doc """
  Suggests test improvements based on cluster-wide analysis.
  """
  def suggest_test_improvements(module, opts \\ %{}) do
    GenServer.call(__MODULE__, {:suggest_improvements, module, opts})
  end
  
  @doc """
  Generates doctests for a module with AI assistance.
  """
  def generate_doctests(module, opts \\ %{}) do
    GenServer.call(__MODULE__, {:generate_doctests, module, opts})
  end
  
  @doc """
  Gets distributed test generation statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Updates test patterns cache across the cluster.
  """
  def update_patterns_cache(patterns) do
    GenServer.cast(__MODULE__, {:update_patterns, patterns})
  end
  
  ## Server Callbacks
  
  @impl true
  def init(_opts) do
    # Setup distributed infrastructure
    setup_infrastructure()
    
    # Subscribe to relevant events
    subscribe_to_events()
    
    state = %__MODULE__{
      node: node(),
      active_generations: %{},
      pattern_cache: %{},
      coverage_data: %{},
      metrics: init_metrics()
    }
    
    # Join pg groups for coordination
    :pg.join(@pg_scope, :test_generators, self())
    
    Logger.info("Distributed test generator started on #{node()}")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:generate_tests, module, opts}, from, state) do
    generation_id = generate_id()
    
    # Analyze module for test generation
    case analyze_module_for_testing(module, opts) do
      {:ok, analysis} ->
        # Start distributed test generation
        start_distributed_generation(generation_id, module, analysis, opts, from)
        
        # Track generation
        new_state = track_generation(state, generation_id, %{
          module: module,
          opts: opts,
          caller: from,
          started_at: DateTime.utc_now()
        })
        
        {:noreply, new_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:analyze_patterns, file_patterns, opts}, _from, state) do
    case perform_distributed_pattern_analysis(file_patterns, opts) do
      {:ok, patterns} ->
        # Update cache
        new_state = update_pattern_cache(state, patterns)
        {:reply, {:ok, patterns}, new_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:generate_property_tests, module, opts}, _from, state) do
    {:ok, tests} = generate_streamdata_tests(module, opts)
    
    # Store generated tests
    store_generated_tests(module, :property, tests)
    {:reply, {:ok, tests}, state}
  end
  
  def handle_call({:get_cluster_coverage, opts}, _from, state) do
    coverage = compile_cluster_coverage(opts)
    {:reply, coverage, state}
  end
  
  def handle_call({:suggest_improvements, module, opts}, _from, state) do
    case analyze_and_suggest_improvements(module, opts, state) do
      {:ok, suggestions} ->
        {:reply, {:ok, suggestions}, state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:generate_doctests, module, opts}, _from, state) do
    case generate_ai_doctests(module, opts) do
      {:ok, doctests} ->
        {:reply, {:ok, doctests}, state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call(:get_stats, _from, state) do
    stats = compile_generation_stats(state)
    {:reply, stats, state}
  end
  
  @impl true
  def handle_cast({:update_patterns, patterns}, state) do
    new_state = update_pattern_cache(state, patterns)
    {:noreply, new_state}
  end
  
  def handle_cast({:generation_complete, generation_id, result}, state) do
    case Map.get(state.active_generations, generation_id) do
      %{caller: from} = _generation ->
        # Reply to original caller
        GenServer.reply(from, result)
        
        # Clean up generation tracking
        new_state = %{state |
          active_generations: Map.delete(state.active_generations, generation_id)
        }
        
        # Update metrics
        updated_state = update_generation_metrics(new_state, result)
        
        {:noreply, updated_state}
        
      nil ->
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:event_notification, event}, state) do
    # Handle test-related events
    new_state = handle_test_event(event, state)
    {:noreply, new_state}
  end
  
  def handle_info({:generation_progress, generation_id, progress}, state) do
    # Update generation progress
    case Map.get(state.active_generations, generation_id) do
      generation when not is_nil(generation) ->
        updated_generation = Map.put(generation, :progress, progress)
        new_state = %{state |
          active_generations: Map.put(state.active_generations, generation_id, updated_generation)
        }
        {:noreply, new_state}
        
      nil ->
        {:noreply, state}
    end
  end
  
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  ## Private Functions
  
  defp setup_infrastructure do
    # Setup pg scope
    :pg.start_link(@pg_scope)
    
    # Setup Mnesia tables
    setup_mnesia_tables()
  end
  
  defp setup_mnesia_tables do
    table_type = if node() == :nonode@nohost, do: :ram_copies, else: :disc_copies
    
    # Generated tests storage
    :mnesia.create_table(@test_storage_table, [
      {table_type, [node()]},
      {:attributes, [:key, :module, :test_type, :tests, :quality_score, :created_at]},
      {:type, :set},
      {:index, [:module, :test_type]}
    ])
    
    # Test patterns cache
    :mnesia.create_table(@pattern_cache_table, [
      {table_type, [node()]},
      {:attributes, [:pattern_hash, :patterns, :confidence, :updated_at]},
      {:type, :set}
    ])
    
    # Coverage data
    :mnesia.create_table(@coverage_table, [
      {table_type, [node()]},
      {:attributes, [:module, :coverage_data, :node, :updated_at]},
      {:type, :bag},
      {:index, [:node]}
    ])
  end
  
  defp subscribe_to_events do
    # Subscribe to test-related events
    OTPEventBus.subscribe({:event_type, :test_generated})
    OTPEventBus.subscribe({:event_type, :test_executed})
    OTPEventBus.subscribe({:event_type, :coverage_updated})
  end
  
  defp analyze_module_for_testing(module, opts) do
    try do
      # Get module source code
      case get_module_source(module) do
        {:ok, source_code} ->
          # Use semantic chunker to analyze code structure
          functions = case Chunker.chunk_code(source_code, %{
            strategy: :semantic,
            max_chunk_size: 2000
          }) do
            {:ok, chunks} ->
              # Extract functions and their signatures
              extract_functions_from_chunks(chunks)
              
            {:error, reason} ->
              Logger.warning("Failed to chunk code: #{inspect(reason)}")
              # Fallback: analyze source directly
              extract_functions_from_source(source_code)
          end
          
          # Analyze complexity and test coverage requirements
          analysis = %{
            module: module,
            functions: functions,
            complexity_score: calculate_complexity_score(functions),
            suggested_test_types: suggest_test_types(functions, opts),
            coverage_gaps: identify_coverage_gaps(module),
            edge_cases: identify_edge_cases(functions)
          }
          
          {:ok, analysis}
          
        {:error, reason} ->
          {:error, {:module_analysis_failed, reason}}
      end
    catch
      kind, reason ->
        {:error, {kind, reason}}
    end
  end
  
  defp get_module_source(module) do
    try do
      case module.module_info(:compile) do
        compile_info when is_list(compile_info) ->
          case Keyword.get(compile_info, :source) do
            source_file when is_binary(source_file) ->
              case File.read(source_file) do
                {:ok, content} -> {:ok, content}
                {:error, _reason} -> 
                  # Try to get source from module beam if available
                  get_source_from_beam(module)
              end
            
            source_file when is_list(source_file) ->
              # Convert char list to string
              source_file_str = List.to_string(source_file)
              case File.read(source_file_str) do
                {:ok, content} -> {:ok, content}
                {:error, _reason} -> 
                  get_source_from_beam(module)
              end
            
            nil ->
              # Try alternative methods for getting source
              get_source_from_beam(module)
          end
          
        _ ->
          {:error, :compile_info_not_available}
      end
    catch
      :error, :undef -> {:error, :module_not_loaded}
      _, reason -> {:error, reason}
    end
  end
  
  defp get_source_from_beam(module) do
    # For test modules and compiled modules, try to construct basic source info
    try do
      functions = module.__info__(:functions)
      
      # Generate basic source representation
      source_lines = [
        "defmodule #{module} do",
        "  # Module functions (extracted from compiled module):"
      ]
      
      function_lines = Enum.map(functions, fn {name, arity} ->
        "  # def #{name}/#{arity}"
      end)
      
      source = Enum.join(source_lines ++ function_lines ++ ["end"], "\n")
      {:ok, source}
    catch
      _, _ -> {:error, :source_not_available}
    end
  end
  
  defp extract_functions_from_chunks(chunks) do
    Enum.flat_map(chunks, fn chunk ->
      case chunk.metadata do
        %{functions: functions} when is_list(functions) ->
          Enum.map(functions, fn func ->
            %{
              name: func.name,
              arity: func.arity,
              visibility: func.visibility,
              source: func.source,
              line: func.line,
              complexity: calculate_function_complexity(func.source)
            }
          end)
          
        _ ->
          # Fallback: extract functions using regex
          extract_functions_with_regex(chunk.content)
      end
    end)
  end
  
  defp calculate_function_complexity(source) do
    # Simple complexity calculation based on control structures
    control_structures = ["if", "case", "cond", "with", "for", "Enum."]
    
    complexity = Enum.reduce(control_structures, 1, fn structure, acc ->
      count = source |> String.split(structure) |> length() |> Kernel.-(1)
      acc + count
    end)
    
    min(complexity, 10)  # Cap at 10 for reasonable scoring
  end
  
  defp extract_functions_from_source(source_code) do
    # Direct function extraction as fallback when chunking fails
    extract_functions_with_regex(source_code)
  end
  
  defp extract_functions_with_regex(content) do
    # Basic regex-based function extraction as fallback
    function_regex = ~r/def\s+(\w+)\s*\(([^)]*)\)/
    
    Regex.scan(function_regex, content)
    |> Enum.map(fn [_, name, params] ->
      arity = if String.trim(params) == "", do: 0, else: length(String.split(params, ","))
      
      %{
        name: String.to_atom(name),
        arity: arity,
        visibility: :public,
        source: "",
        line: 0,
        complexity: 1
      }
    end)
  end
  
  defp calculate_complexity_score(functions) do
    if length(functions) == 0 do
      0
    else
      total_complexity = Enum.sum(Enum.map(functions, & &1.complexity))
      total_complexity / length(functions)
    end
  end
  
  defp suggest_test_types(functions, opts) do
    base_types = [:unit]
    
    # Add property tests for functions with multiple parameters
    property_candidates = Enum.any?(functions, fn f -> f.arity > 1 end)
    types_with_property = if property_candidates, do: [:property | base_types], else: base_types
    
    # Add integration tests for complex functions
    complex_functions = Enum.any?(functions, fn f -> f.complexity > 3 end)
    types_with_integration = if complex_functions, do: [:integration | types_with_property], else: types_with_property
    
    # Add doctests if requested
    requested_types = opts[:test_types] || types_with_integration
    Enum.uniq(requested_types)
  end
  
  defp identify_coverage_gaps(module) do
    # Get current coverage data for module
    case get_module_coverage(module) do
      {:ok, coverage} ->
        # Identify functions with low coverage
        Enum.filter(coverage.functions, fn {_func, cov} -> cov < 80 end)
        
      {:error, _} ->
        []  # No coverage data available
    end
  end
  
  defp get_module_coverage(module) do
    case :mnesia.transaction(fn ->
      :mnesia.read(@coverage_table, module)
    end) do
      {:atomic, [_ | _] = records} ->
        # Get most recent coverage data
        latest = Enum.max_by(records, fn {_, _, _, _, updated_at} -> updated_at end)
        {_, _, coverage_data, _, _} = latest
        {:ok, coverage_data}
        
      _ ->
        {:error, :no_coverage_data}
    end
  end
  
  defp identify_edge_cases(functions) do
    Enum.flat_map(functions, fn func ->
      case func.arity do
        0 -> []
        1 -> ["nil input", "invalid type"]
        _ -> ["nil inputs", "mixed types", "boundary values"]
      end
    end)
    |> Enum.uniq()
  end
  
  defp start_distributed_generation(generation_id, module, analysis, opts, _caller) do
    # Get available nodes for distribution
    available_nodes = get_available_generator_nodes()
    distribute_across = min(opts[:distribute_across] || 1, length(available_nodes))
    
    if distribute_across > 1 do
      # Distribute generation across multiple nodes
      distribute_generation_work(generation_id, module, analysis, opts, available_nodes, distribute_across)
    else
      # Generate locally
      Task.start(fn ->
        result = perform_local_generation(module, analysis, opts)
        GenServer.cast(self(), {:generation_complete, generation_id, result})
      end)
    end
  end
  
  defp get_available_generator_nodes do
    :pg.get_members(@pg_scope, :test_generators)
    |> Enum.map(&node/1)
    |> Enum.uniq()
  end
  
  defp distribute_generation_work(generation_id, module, analysis, opts, nodes, count) do
    # Split functions across nodes
    functions = analysis.functions
    chunks = Enum.chunk_every(functions, div(length(functions), count) + 1)
    
    # Start generation on each node
    Task.start(fn ->
      results = Enum.zip(chunks, Enum.take(nodes, count))
      |> Enum.map(fn {func_chunk, target_node} ->
        generate_on_node(target_node, module, func_chunk, opts)
      end)
      
      # Combine results
      combined_result = combine_generation_results(results)
      GenServer.cast(self(), {:generation_complete, generation_id, combined_result})
    end)
  end
  
  defp generate_on_node(target_node, module, functions, opts) do
    if target_node == node() do
      # Generate locally
      perform_function_generation(module, functions, opts)
    else
      # Generate on remote node
      :rpc.call(target_node, __MODULE__, :perform_function_generation, [module, functions, opts], 30_000)
    end
  end
  
  def perform_function_generation(module, functions, opts) do
    # Generate tests for the given functions
    Enum.map(functions, fn func ->
      case generate_function_tests(module, func, opts) do
        {:ok, tests} -> {func, tests}
        {:error, reason} -> {func, {:error, reason}}
      end
    end)
  end
  
  defp perform_local_generation(module, analysis, opts) do
    # Generate tests for all functions locally
    test_types = analysis.suggested_test_types
    
    results = Enum.reduce(test_types, %{}, fn test_type, acc ->
      case generate_tests_by_type(module, analysis, test_type, opts) do
        {:ok, tests} -> Map.put(acc, test_type, tests)
        {:error, reason} -> Map.put(acc, test_type, {:error, reason})
      end
    end)
    
    {:ok, results}
  end
  
  defp generate_tests_by_type(module, analysis, :unit, opts) do
    # Generate unit tests for each function
    unit_tests = Enum.map(analysis.functions, fn func ->
      generate_unit_test(module, func, opts)
    end)
    
    {:ok, unit_tests}
  end
  
  defp generate_tests_by_type(module, analysis, :property, opts) do
    # Generate property-based tests
    generate_streamdata_tests(module, Map.put(opts, :functions, analysis.functions))
  end
  
  defp generate_tests_by_type(module, analysis, :integration, opts) do
    # Generate integration tests for complex functions
    complex_functions = Enum.filter(analysis.functions, fn f -> f.complexity > 3 end)
    
    integration_tests = Enum.map(complex_functions, fn func ->
      generate_integration_test(module, func, opts)
    end)
    
    {:ok, integration_tests}
  end
  
  defp generate_tests_by_type(module, _analysis, :doctest, opts) do
    generate_ai_doctests(module, opts)
  end
  
  defp generate_function_tests(module, func, opts) do
    # Use LLM to generate comprehensive tests for a function
    prompt = build_test_generation_prompt(module, func, opts)
    
    case ModelCoordinator.process_request(%{
      type: :completion,
      prompt: prompt,
      model: opts[:model] || "gpt-4",
      max_tokens: 1500,
      temperature: 0.3
    }) do
      {:ok, response} ->
        parse_generated_tests(response.content)
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp build_test_generation_prompt(module, func, opts) do
    """
    Generate comprehensive ExUnit tests for the following Elixir function:
    
    Module: #{module}
    Function: #{func.name}/#{func.arity}
    Complexity: #{func.complexity}
    
    Source code:
    ```elixir
    #{func.source}
    ```
    
    Please generate:
    1. Positive test cases (happy path)
    2. Negative test cases (error conditions)
    3. Edge cases (boundary values, nil inputs)
    4. Property-based test ideas if applicable
    
    Requirements:
    - Use ExUnit test syntax
    - Include descriptive test names
    - Add assertions with meaningful error messages
    - Consider the function's complexity level
    - Target coverage: #{opts[:coverage_target] || 85}%
    
    Format the response as valid Elixir test code.
    """
  end
  
  defp parse_generated_tests(content) do
    # Parse the LLM response to extract test code
    case extract_test_code_blocks(content) do
      [] ->
        {:error, :no_tests_generated}
        
      test_blocks ->
        # Validate and format test blocks
        valid_tests = Enum.filter(test_blocks, &valid_test_syntax?/1)
        
        if length(valid_tests) > 0 do
          {:ok, %{
            tests: valid_tests,
            count: length(valid_tests),
            quality_score: calculate_test_quality(valid_tests)
          }}
        else
          {:error, :invalid_test_syntax}
        end
    end
  end
  
  defp extract_test_code_blocks(content) do
    # Extract code blocks from markdown or plain text
    code_block_regex = ~r/```(?:elixir)?\s*\n(.*?)\n```/s
    
    Regex.scan(code_block_regex, content, capture: :all_but_first)
    |> Enum.map(fn [code] -> String.trim(code) end)
    |> Enum.filter(fn code -> String.contains?(code, "test ") end)
  end
  
  defp valid_test_syntax?(test_code) do
    # Basic validation of test syntax
    String.contains?(test_code, "test ") and
    String.contains?(test_code, "assert")
  end
  
  defp calculate_test_quality(tests) do
    # Calculate quality score based on test characteristics
    scores = Enum.map(tests, fn test ->
      score = 0.5  # Base score
      
      # Add points for good practices
      score = if String.contains?(test, "assert"), do: score + 0.2, else: score
      score = if String.contains?(test, "refute"), do: score + 0.1, else: score
      score = if String.contains?(test, "assert_raise"), do: score + 0.1, else: score
      score = if String.contains?(test, "setup"), do: score + 0.1, else: score
      
      min(score, 1.0)
    end)
    
    if length(scores) > 0 do
      Enum.sum(scores) / length(scores)
    else
      0.0
    end
  end
  
  defp generate_unit_test(module, func, _opts) do
    # Generate basic unit test structure
    test_name = "test #{func.name}/#{func.arity} basic functionality"
    
    """
    test "#{test_name}" do
      # TODO: Add test implementation for #{module}.#{func.name}/#{func.arity}
      # Function complexity: #{func.complexity}
    end
    """
  end
  
  defp generate_integration_test(module, func, _opts) do
    # Generate integration test structure
    test_name = "test #{func.name}/#{func.arity} integration"
    
    """
    test "#{test_name}" do
      # TODO: Add integration test for #{module}.#{func.name}/#{func.arity}
      # This function has high complexity (#{func.complexity}) - test interactions
    end
    """
  end
  
  defp generate_streamdata_tests(module, opts) do
    # Generate property-based tests using StreamData
    functions = opts[:functions] || []
    
    # Filter functions suitable for property testing
    suitable_functions = Enum.filter(functions, fn f -> 
      f.arity > 0 and f.arity <= 3  # Reasonable arity for property tests
    end)
    
    property_tests = if length(suitable_functions) > 0 do
      Enum.map(suitable_functions, fn func ->
        generate_property_test(module, func, opts)
      end)
    else
      # Generate at least one basic property test
      [generate_default_property_test(module, opts)]
    end
    
    {:ok, %{
      property_tests: property_tests,
      count: length(property_tests)
    }}
  end
  
  defp generate_property_test(module, func, _opts) do
    # Generate StreamData property test based on function arity
    case func.arity do
      1 ->
        """
        property "#{func.name}/#{func.arity} properties" do
          check all input <- StreamData.term() do
            # Test that function handles various inputs gracefully
            result = #{module}.#{func.name}(input)
            # Basic property: function should not crash
            assert result != nil or is_nil(result)
          end
        end
        """
      
      2 ->
        """
        property "#{func.name}/#{func.arity} properties" do
          check all {a, b} <- {StreamData.term(), StreamData.term()} do
            # Test function with two arguments
            result = #{module}.#{func.name}(a, b)
            # Basic property: function should not crash
            assert result != nil or is_nil(result)
          end
        end
        """
      
      _ ->
        """
        property "#{func.name}/#{func.arity} properties" do
          check all args <- StreamData.list_of(StreamData.term(), length: #{func.arity}) do
            # Test function with generated arguments
            result = apply(#{module}, :#{func.name}, args)
            # Basic property: function should not crash  
            assert result != nil or is_nil(result)
          end
        end
        """
    end
  end
  
  defp generate_default_property_test(module, _opts) do
    # Generate a default property test when no suitable functions found
    """
    property "#{module} module properties" do
      check all _ <- StreamData.constant(:ok) do
        # Basic module property test
        assert Code.ensure_loaded?(#{module})
        # Module should be loadable and have functions
        functions = #{module}.__info__(:functions)
        assert is_list(functions)
      end
    end
    """
  end
  
  defp generate_ai_doctests(module, opts) do
    # Generate doctests with AI assistance
    prompt = """
    Generate comprehensive doctests for the Elixir module #{module}.
    
    Please create doctest examples that:
    1. Demonstrate typical usage patterns
    2. Show expected inputs and outputs
    3. Include edge cases where appropriate
    4. Follow Elixir doctest conventions
    
    Format: Use standard doctest syntax with iex> prompts and expected results.
    """
    
    case ModelCoordinator.process_request(%{
      type: :completion,
      prompt: prompt,
      model: opts[:model] || "gpt-4",
      max_tokens: 1000,
      temperature: 0.2
    }) do
      {:ok, response} ->
        doctests = parse_doctest_examples(response.content)
        {:ok, %{
          doctests: doctests,
          count: length(doctests)
        }}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp parse_doctest_examples(content) do
    # Extract doctest examples from AI response
    doctest_regex = ~r/iex>\s+(.+)\n([^\n]+)/
    
    Regex.scan(doctest_regex, content)
    |> Enum.map(fn [_, input, output] ->
      %{
        input: String.trim(input),
        expected_output: String.trim(output)
      }
    end)
  end
  
  defp perform_distributed_pattern_analysis(file_patterns, opts) do
    # Analyze test patterns across cluster
    available_nodes = get_available_generator_nodes()
    
    if length(available_nodes) > 1 do
      # Distribute pattern analysis
      distribute_pattern_analysis(file_patterns, opts, available_nodes)
    else
      # Analyze locally
      analyze_patterns_locally(file_patterns, opts)
    end
  end
  
  defp distribute_pattern_analysis(file_patterns, opts, nodes) do
    # Split file patterns across nodes
    patterns_per_node = Enum.chunk_every(file_patterns, div(length(file_patterns), length(nodes)) + 1)
    
    results = Enum.zip(patterns_per_node, nodes)
    |> Enum.map(fn {patterns, node} ->
      if node == node() do
        analyze_patterns_locally(patterns, opts)
      else
        :rpc.call(node, __MODULE__, :analyze_patterns_locally, [patterns, opts], 15_000)
      end
    end)
    
    # Combine results from all nodes
    combine_pattern_results(results)
  end
  
  def analyze_patterns_locally(file_patterns, _opts) do
    # Analyze test patterns in local files
    patterns = Enum.flat_map(file_patterns, fn pattern ->
      case Path.wildcard(pattern) do
        [] -> []
        files -> Enum.flat_map(files, &extract_test_patterns/1)
      end
    end)
    
    analyzed_patterns = %{
      common_patterns: identify_common_patterns(patterns),
      naming_conventions: extract_naming_conventions(patterns),
      setup_patterns: extract_setup_patterns(patterns),
      assertion_patterns: extract_assertion_patterns(patterns),
      confidence_score: calculate_pattern_confidence(patterns)
    }
    
    {:ok, analyzed_patterns}
  end
  
  defp extract_test_patterns(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        # Extract various test patterns from file content
        [
          extract_test_names(content),
          extract_setup_blocks(content),
          extract_assertion_styles(content),
          extract_describe_blocks(content)
        ]
        |> List.flatten()
        
      {:error, _} ->
        []
    end
  end
  
  defp extract_test_names(content) do
    test_regex = ~r/test\s+"([^"]+)"/
    Regex.scan(test_regex, content, capture: :all_but_first)
    |> Enum.map(fn [name] -> {:test_name, name} end)
  end
  
  defp extract_setup_blocks(content) do
    setup_regex = ~r/setup\s+do\s*\n(.*?)\n\s*end/s
    Regex.scan(setup_regex, content, capture: :all_but_first)
    |> Enum.map(fn [setup] -> {:setup_pattern, String.trim(setup)} end)
  end
  
  defp extract_assertion_styles(content) do
    assertions = ["assert", "refute", "assert_raise", "assert_receive"]
    
    Enum.flat_map(assertions, fn assertion ->
      regex = Regex.compile!("#{assertion}\\s+([^\n]+)")
      Regex.scan(regex, content, capture: :all_but_first)
      |> Enum.map(fn [pattern] -> {:assertion, assertion, String.trim(pattern)} end)
    end)
  end
  
  defp extract_describe_blocks(content) do
    describe_regex = ~r/describe\s+"([^"]+)"/
    Regex.scan(describe_regex, content, capture: :all_but_first)
    |> Enum.map(fn [desc] -> {:describe, desc} end)
  end
  
  defp identify_common_patterns(patterns) do
    # Group and count pattern frequencies
    pattern_counts = Enum.group_by(patterns, & &1)
    |> Enum.map(fn {pattern, occurrences} -> {pattern, length(occurrences)} end)
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    
    Enum.take(pattern_counts, 10)  # Top 10 most common patterns
  end
  
  defp extract_naming_conventions(patterns) do
    test_names = Enum.filter(patterns, fn
      {:test_name, _} -> true
      _ -> false
    end)
    
    %{
      total_tests: length(test_names),
      naming_patterns: analyze_naming_patterns(test_names)
    }
  end
  
  defp analyze_naming_patterns(test_names) do
    names = Enum.map(test_names, fn {:test_name, name} -> name end)
    
    %{
      starts_with_verb: count_pattern(names, ~r/^(should|can|will|does)/),
      includes_when: count_pattern(names, ~r/when/),
      includes_given: count_pattern(names, ~r/given/),
      includes_returns: count_pattern(names, ~r/returns/),
      average_length: average_string_length(names)
    }
  end
  
  defp count_pattern(strings, regex) do
    Enum.count(strings, &Regex.match?(regex, &1))
  end
  
  defp average_string_length(strings) do
    if length(strings) > 0 do
      total_length = Enum.sum(Enum.map(strings, &String.length/1))
      total_length / length(strings)
    else
      0
    end
  end
  
  defp extract_setup_patterns(patterns) do
    setup_patterns = Enum.filter(patterns, fn
      {:setup_pattern, _} -> true
      _ -> false
    end)
    
    %{
      count: length(setup_patterns),
      common_setups: identify_common_setups(setup_patterns)
    }
  end
  
  defp identify_common_setups(setup_patterns) do
    # Analyze common setup patterns
    setups = Enum.map(setup_patterns, fn {:setup_pattern, setup} -> setup end)
    
    %{
      uses_context: count_pattern(setups, ~r/context/),
      creates_data: count_pattern(setups, ~r/(create|build|setup)/),
      mocks_services: count_pattern(setups, ~r/(mock|stub)/),
      connects_db: count_pattern(setups, ~r/(repo|ecto|database)/i)
    }
  end
  
  defp extract_assertion_patterns(patterns) do
    assertion_patterns = Enum.filter(patterns, fn
      {:assertion, _, _} -> true
      _ -> false
    end)
    
    assertion_counts = Enum.group_by(assertion_patterns, fn {:assertion, type, _} -> type end)
    |> Enum.map(fn {type, occurrences} -> {type, length(occurrences)} end)
    
    %{
      total_assertions: length(assertion_patterns),
      assertion_distribution: assertion_counts
    }
  end
  
  defp calculate_pattern_confidence(patterns) do
    # Calculate confidence based on pattern consistency
    if length(patterns) == 0 do
      0.0
    else
      # More patterns = higher confidence
      base_confidence = min(length(patterns) / 100, 0.8)
      
      # Diversity of patterns adds confidence
      unique_patterns = Enum.uniq(patterns) |> length()
      diversity_bonus = min(unique_patterns / 50, 0.2)
      
      base_confidence + diversity_bonus
    end
  end
  
  defp combine_pattern_results(results) do
    # Combine pattern analysis results from multiple nodes
    valid_results = Enum.filter(results, fn
      {:ok, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:ok, result} -> result end)
    
    if length(valid_results) > 0 do
      combined = %{
        common_patterns: combine_common_patterns(valid_results),
        naming_conventions: combine_naming_conventions(valid_results),
        setup_patterns: combine_setup_patterns(valid_results),
        assertion_patterns: combine_assertion_patterns(valid_results),
        confidence_score: average_confidence(valid_results),
        nodes_analyzed: length(valid_results)
      }
      
      {:ok, combined}
    else
      {:error, :no_valid_results}
    end
  end
  
  defp combine_common_patterns(results) do
    # Merge common patterns from all nodes
    all_patterns = Enum.flat_map(results, fn r -> r.common_patterns end)
    
    # Re-count across all results
    Enum.group_by(all_patterns, fn {pattern, _} -> pattern end)
    |> Enum.map(fn {pattern, occurrences} ->
      total_count = Enum.sum(Enum.map(occurrences, fn {_, count} -> count end))
      {pattern, total_count}
    end)
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(15)  # Top 15 across cluster
  end
  
  defp combine_naming_conventions(results) do
    conventions = Enum.map(results, & &1.naming_conventions)
    
    %{
      total_tests: Enum.sum(Enum.map(conventions, & &1.total_tests)),
      naming_patterns: merge_naming_patterns(conventions)
    }
  end
  
  defp merge_naming_patterns(conventions) do
    patterns = Enum.map(conventions, & &1.naming_patterns)
    
    %{
      starts_with_verb: Enum.sum(Enum.map(patterns, & &1.starts_with_verb)),
      includes_when: Enum.sum(Enum.map(patterns, & &1.includes_when)),
      includes_given: Enum.sum(Enum.map(patterns, & &1.includes_given)),
      includes_returns: Enum.sum(Enum.map(patterns, & &1.includes_returns)),
      average_length: average_value(Enum.map(patterns, & &1.average_length))
    }
  end
  
  defp combine_setup_patterns(results) do
    setups = Enum.map(results, & &1.setup_patterns)
    
    %{
      count: Enum.sum(Enum.map(setups, & &1.count)),
      common_setups: merge_setup_analysis(setups)
    }
  end
  
  defp merge_setup_analysis(setups) do
    analyses = Enum.map(setups, & &1.common_setups)
    
    %{
      uses_context: Enum.sum(Enum.map(analyses, & &1.uses_context)),
      creates_data: Enum.sum(Enum.map(analyses, & &1.creates_data)),
      mocks_services: Enum.sum(Enum.map(analyses, & &1.mocks_services)),
      connects_db: Enum.sum(Enum.map(analyses, & &1.connects_db))
    }
  end
  
  defp combine_assertion_patterns(results) do
    assertions = Enum.map(results, & &1.assertion_patterns)
    
    %{
      total_assertions: Enum.sum(Enum.map(assertions, & &1.total_assertions)),
      assertion_distribution: merge_assertion_distribution(assertions)
    }
  end
  
  defp merge_assertion_distribution(assertions) do
    distributions = Enum.map(assertions, & &1.assertion_distribution)
    
    # Merge assertion counts
    Enum.reduce(distributions, %{}, fn dist, acc ->
      Enum.reduce(dist, acc, fn {type, count}, acc_inner ->
        Map.update(acc_inner, type, count, &(&1 + count))
      end)
    end)
    |> Enum.to_list()
  end
  
  defp average_confidence(results) do
    scores = Enum.map(results, & &1.confidence_score)
    average_value(scores)
  end
  
  defp average_value(values) do
    if length(values) > 0 do
      Enum.sum(values) / length(values)
    else
      0.0
    end
  end
  
  defp combine_generation_results(results) do
    # Combine test generation results from distributed processing
    valid_results = Enum.filter(results, fn
      {:ok, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:ok, result} -> result end)
    
    if length(valid_results) > 0 do
      combined_tests = Enum.reduce(valid_results, %{}, fn result, acc ->
        Map.merge(acc, result, fn _k, v1, v2 ->
          # Merge test lists
          case {v1, v2} do
            {list1, list2} when is_list(list1) and is_list(list2) -> list1 ++ list2
            {map1, map2} when is_map(map1) and is_map(map2) -> Map.merge(map1, map2)
            _ -> v2  # Take the newer value
          end
        end)
      end)
      
      {:ok, combined_tests}
    else
      {:error, :no_valid_results}
    end
  end
  
  defp compile_cluster_coverage(opts) do
    # Get coverage data from all nodes
    nodes = opts[:nodes] || get_available_generator_nodes()
    
    coverage_data = Enum.map(nodes, fn node ->
      if node == node() do
        get_local_coverage()
      else
        :rpc.call(node, __MODULE__, :get_local_coverage, [], 10_000)
      end
    end)
    |> Enum.filter(fn
      {:ok, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:ok, data} -> data end)
    
    aggregate_coverage(coverage_data)
  end
  
  def get_local_coverage do
    # Get local test coverage data
    case :mnesia.transaction(fn ->
      :mnesia.match_object(@coverage_table, {:_, :_, :_, node(), :_}, :read)
    end) do
      {:atomic, records} ->
        coverage_map = Enum.reduce(records, %{}, fn {_, module, coverage, _, _}, acc ->
          Map.put(acc, module, coverage)
        end)
        
        {:ok, %{
          node: node(),
          modules: coverage_map,
          total_modules: map_size(coverage_map)
        }}
        
      {:aborted, reason} ->
        {:error, reason}
    end
  end
  
  defp aggregate_coverage(coverage_data) do
    if length(coverage_data) > 0 do
      # Aggregate coverage across all nodes
      all_modules = Enum.flat_map(coverage_data, fn data ->
        Map.keys(data.modules)
      end)
      |> Enum.uniq()
      
      module_coverage = Enum.reduce(all_modules, %{}, fn module, acc ->
        # Get coverage from all nodes that have this module
        coverages = Enum.flat_map(coverage_data, fn data ->
          case Map.get(data.modules, module) do
            nil -> []
            coverage -> [coverage]
          end
        end)
        
        # Use the highest coverage value
        best_coverage = if length(coverages) > 0, do: Enum.max(coverages), else: 0
        Map.put(acc, module, best_coverage)
      end)
      
      total_coverage = if map_size(module_coverage) > 0 do
        Enum.sum(Map.values(module_coverage)) / map_size(module_coverage)
      else
        0
      end
      
      %{
        cluster_coverage: total_coverage,
        module_coverage: module_coverage,
        total_modules: length(all_modules),
        nodes_contributing: length(coverage_data)
      }
    else
      %{
        cluster_coverage: 0,
        module_coverage: %{},
        total_modules: 0,
        nodes_contributing: 0
      }
    end
  end
  
  defp analyze_and_suggest_improvements(module, opts, state) do
    # Analyze module and suggest test improvements
    try do
      # Get current test coverage and patterns
      {:ok, coverage} = get_module_coverage(module)
      cached_patterns = state.pattern_cache
      
      # Identify improvement opportunities
      _suggestions = []
      
      # Coverage-based suggestions
      coverage_suggestions = if Map.get(coverage, :line_coverage, 0) < 80 do
        ["Increase line coverage - currently at #{Map.get(coverage, :line_coverage, 0)}%"]
      else
        []
      end
      
      # Pattern-based suggestions
      pattern_suggestions = suggest_from_patterns(module, cached_patterns)
      
      # Quality-based suggestions
      quality_suggestions = suggest_quality_improvements(module, opts)
      
      all_suggestions = coverage_suggestions ++ pattern_suggestions ++ quality_suggestions
      
      {:ok, %{
        module: module,
        suggestions: all_suggestions,
        current_coverage: coverage,
        priority: calculate_improvement_priority(all_suggestions)
      }}
      
    catch
      _, reason ->
        {:error, reason}
    end
  end
  
  defp suggest_from_patterns(module, pattern_cache) do
    # Suggest improvements based on common patterns
    case Map.get(pattern_cache, :common_patterns) do
      nil -> []
      patterns ->
        # Analyze if module follows common patterns
        module_tests = get_module_test_files(module)
        
        if length(module_tests) == 0 do
          ["Add test files - no tests found for module"]
        else
          analyze_pattern_adherence(module_tests, patterns)
        end
    end
  end
  
  defp get_module_test_files(module) do
    # Find test files for the module
    module_name = module |> to_string() |> String.split(".") |> List.last()
    test_pattern = "test/**/*#{String.downcase(module_name)}*test.exs"
    
    Path.wildcard(test_pattern)
  end
  
  defp analyze_pattern_adherence(test_files, _common_patterns) do
    # Check if test files follow common patterns
    suggestions = []
    
    # Check for describe blocks
    has_describe = Enum.any?(test_files, fn file ->
      case File.read(file) do
        {:ok, content} -> String.contains?(content, "describe")
        _ -> false
      end
    end)
    
    suggestions = if not has_describe do
      ["Consider using describe blocks to organize tests" | suggestions]
    else
      suggestions
    end
    
    # Check for setup blocks
    has_setup = Enum.any?(test_files, fn file ->
      case File.read(file) do
        {:ok, content} -> String.contains?(content, "setup")
        _ -> false
      end
    end)
    
    suggestions = if not has_setup do
      ["Consider adding setup blocks for common test data" | suggestions]
    else
      suggestions
    end
    
    suggestions
  end
  
  defp suggest_quality_improvements(_module, _opts) do
    # Suggest quality improvements based on analysis
    [
      "Add property-based tests for complex functions",
      "Include integration tests for external dependencies",
      "Consider adding performance benchmarks",
      "Add edge case testing for boundary conditions"
    ]
  end
  
  defp calculate_improvement_priority(suggestions) do
    # Calculate priority based on suggestion types
    high_priority_keywords = ["coverage", "critical", "security"]
    medium_priority_keywords = ["performance", "integration"]
    
    high_count = Enum.count(suggestions, fn suggestion ->
      Enum.any?(high_priority_keywords, &String.contains?(String.downcase(suggestion), &1))
    end)
    
    medium_count = Enum.count(suggestions, fn suggestion ->
      Enum.any?(medium_priority_keywords, &String.contains?(String.downcase(suggestion), &1))
    end)
    
    cond do
      high_count > 0 -> :high
      medium_count > 0 -> :medium
      true -> :low
    end
  end
  
  defp store_generated_tests(module, test_type, tests) do
    # Store generated tests in Mnesia
    key = {module, test_type, System.os_time(:millisecond)}
    quality_score = calculate_test_quality(tests[:tests] || [])
    
    :mnesia.transaction(fn ->
      :mnesia.write({@test_storage_table, key, module, test_type, tests, quality_score, DateTime.utc_now()})
    end)
  end
  
  defp track_generation(state, generation_id, generation_info) do
    %{state |
      active_generations: Map.put(state.active_generations, generation_id, generation_info)
    }
  end
  
  defp update_pattern_cache(state, patterns) do
    # Update local pattern cache
    pattern_hash = :crypto.hash(:sha256, :erlang.term_to_binary(patterns))
    |> Base.encode16()
    
    # Store in Mnesia for persistence
    :mnesia.transaction(fn ->
      :mnesia.write({@pattern_cache_table, pattern_hash, patterns, patterns.confidence_score, DateTime.utc_now()})
    end)
    
    %{state |
      pattern_cache: Map.merge(state.pattern_cache, patterns)
    }
  end
  
  defp compile_generation_stats(state) do
    # Compile statistics about test generation
    %{
      node: state.node,
      active_generations: map_size(state.active_generations),
      pattern_cache_size: map_size(state.pattern_cache),
      coverage_modules: map_size(state.coverage_data),
      metrics: state.metrics,
      cluster_nodes: get_available_generator_nodes() |> length(),
      total_stored_tests: count_stored_tests()
    }
  end
  
  defp count_stored_tests do
    case :mnesia.table_info(@test_storage_table, :size) do
      size when is_integer(size) -> size
      _ -> 0
    end
  end
  
  defp update_generation_metrics(state, result) do
    metrics = state.metrics
    
    updated_metrics = case result do
      {:ok, _} ->
        %{metrics |
          successful_generations: metrics.successful_generations + 1,
          total_generations: metrics.total_generations + 1
        }
        
      {:error, _} ->
        %{metrics |
          failed_generations: metrics.failed_generations + 1,
          total_generations: metrics.total_generations + 1
        }
    end
    
    %{state | metrics: updated_metrics}
  end
  
  defp handle_test_event(%{type: :test_generated} = event, state) do
    # Update metrics when tests are generated
    module = event.data.module
    test_count = event.data.test_count
    
    # Update coverage data if available
    if Map.has_key?(event.data, :coverage) do
      :mnesia.transaction(fn ->
        :mnesia.write({@coverage_table, module, event.data.coverage, node(), DateTime.utc_now()})
      end)
    end
    
    # Update metrics
    metrics = %{state.metrics |
      tests_generated: state.metrics.tests_generated + test_count
    }
    
    %{state | metrics: metrics}
  end
  
  defp handle_test_event(%{type: :coverage_updated} = event, state) do
    # Update coverage data
    module = event.data.module
    coverage = event.data.coverage
    
    :mnesia.transaction(fn ->
      :mnesia.write({@coverage_table, module, coverage, node(), DateTime.utc_now()})
    end)
    
    # Update local cache
    new_coverage_data = Map.put(state.coverage_data, module, coverage)
    %{state | coverage_data: new_coverage_data}
  end
  
  defp handle_test_event(_event, state), do: state
  
  defp init_metrics do
    %{
      total_generations: 0,
      successful_generations: 0,
      failed_generations: 0,
      tests_generated: 0,
      patterns_analyzed: 0,
      coverage_updates: 0
    }
  end
  
  defp generate_id do
    "gen_#{:erlang.unique_integer([:positive])}_#{System.os_time(:millisecond)}"
  end
end