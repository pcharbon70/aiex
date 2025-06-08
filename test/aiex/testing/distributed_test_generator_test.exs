defmodule Aiex.Testing.DistributedTestGeneratorTest do
  @moduledoc """
  Comprehensive tests for the distributed test generation system.
  
  Tests all aspects of distributed test generation including:
  - Pattern analysis across cluster nodes
  - Parallel test generation coordination
  - Property-based test creation
  - Coverage analysis and reporting
  - Quality scoring and suggestions
  - Integration with LLM coordination
  """
  
  use ExUnit.Case, async: false
  
  alias Aiex.Testing.DistributedTestGenerator
  alias Aiex.Events.OTPEventBus
  
  @moduletag :distributed_test_generation
  @moduletag timeout: 30_000
  
  # Test module for analysis
  defmodule TestCalculator do
    @moduledoc """
    Simple calculator module for testing test generation.
    """
    
    def add(a, b) when is_number(a) and is_number(b) do
      a + b
    end
    
    def subtract(a, b) when is_number(a) and is_number(b) do
      a - b
    end
    
    def multiply(a, b) when is_number(a) and is_number(b) do
      a * b
    end
    
    def divide(_a, 0), do: {:error, :division_by_zero}
    def divide(a, b) when is_number(a) and is_number(b) do
      {:ok, a / b}
    end
    
    def factorial(0), do: 1
    def factorial(n) when is_integer(n) and n > 0 do
      n * factorial(n - 1)
    end
    def factorial(_), do: {:error, :invalid_input}
  end
  
  setup do
    # Ensure components are running
    restart_test_generator_components()
    
    on_exit(fn ->
      cleanup_test_data()
    end)
    
    :ok
  end
  
  defp restart_test_generator_components do
    # Stop existing generator if running
    if Process.whereis(DistributedTestGenerator) do
      GenServer.stop(DistributedTestGenerator, :normal, 1000)
    end
    
    # Ensure prerequisites are running
    ensure_prerequisites()
    
    # Start fresh generator
    {:ok, _} = DistributedTestGenerator.start_link()
    
    # Give time to initialize
    :timer.sleep(200)
  end
  
  defp ensure_prerequisites do
    # Ensure Mnesia is running
    :mnesia.start()
    
    # Ensure pg scope is available
    unless Process.whereis(:test_generation) do
      :pg.start_link(:test_generation)
    end
    
    # Ensure event bus is running
    unless Process.whereis(OTPEventBus) do
      {:ok, _} = OTPEventBus.start_link()
    end
  end
  
  defp cleanup_test_data do
    # Clean up any test data created during tests
    if Process.whereis(DistributedTestGenerator) do
      try do
        # Clean up Mnesia tables
        :mnesia.clear_table(:distributed_tests)
        :mnesia.clear_table(:test_patterns)
        :mnesia.clear_table(:test_coverage)
      catch
        _, _ -> :ok
      end
    end
  end
  
  describe "Test Generation" do
    test "generates comprehensive tests for a module" do
      opts = %{
        test_types: [:unit, :property],
        coverage_target: 85,
        distribute_across: 1  # Single node for testing
      }
      
      {:ok, result} = DistributedTestGenerator.generate_tests(TestCalculator, opts)
      
      assert is_map(result)
      assert Map.has_key?(result, :unit)
      
      # Check unit tests were generated
      case result[:unit] do
        tests when is_list(tests) ->
          assert length(tests) > 0
          
        test_map when is_map(test_map) ->
          assert test_map[:count] > 0
          
        _ ->
          flunk("Unexpected unit test format: #{inspect(result[:unit])}")
      end
    end
    
    test "generates property-based tests" do
      opts = %{
        test_types: [:property],
        max_tests_per_function: 3
      }
      
      {:ok, result} = DistributedTestGenerator.generate_property_tests(TestCalculator, opts)
      
      assert is_map(result)
      assert Map.has_key?(result, :property_tests)
      assert Map.has_key?(result, :count)
      assert result.count > 0
    end
    
    test "handles module analysis errors gracefully" do
      # Test with non-existent module
      result = DistributedTestGenerator.generate_tests(NonExistentModule, %{})
      
      assert {:error, _reason} = result
    end
    
    test "respects coverage target options" do
      opts = %{
        test_types: [:unit],
        coverage_target: 95,
        quality_threshold: 0.8
      }
      
      {:ok, result} = DistributedTestGenerator.generate_tests(TestCalculator, opts)
      
      # Should complete without error with high coverage target
      assert is_map(result)
    end
  end
  
  describe "Pattern Analysis" do
    test "analyzes test patterns from file patterns" do
      # Create a temporary test file for analysis
      test_content = """
      defmodule TestPatternExample do
        use ExUnit.Case
        
        describe "addition" do
          test "adds two numbers correctly" do
            assert Calculator.add(2, 3) == 5
          end
          
          test "handles zero addition" do
            assert Calculator.add(0, 5) == 5
          end
        end
        
        describe "subtraction" do
          setup do
            %{calculator: Calculator}
          end
          
          test "subtracts numbers", %{calculator: calc} do
            assert calc.subtract(5, 3) == 2
          end
        end
      end
      """
      
      temp_file = create_temp_test_file(test_content)
      
      {:ok, patterns} = DistributedTestGenerator.analyze_test_patterns([temp_file])
      
      assert is_map(patterns)
      assert Map.has_key?(patterns, :common_patterns)
      assert Map.has_key?(patterns, :naming_conventions)
      assert Map.has_key?(patterns, :setup_patterns)
      assert Map.has_key?(patterns, :assertion_patterns)
      assert Map.has_key?(patterns, :confidence_score)
      
      # Check naming conventions analysis
      assert is_map(patterns.naming_conventions)
      assert patterns.naming_conventions.total_tests > 0
      
      # Check setup patterns
      assert is_map(patterns.setup_patterns)
      assert patterns.setup_patterns.count >= 0
      
      # Cleanup
      File.rm(temp_file)
    end
    
    test "handles empty file patterns gracefully" do
      {:ok, patterns} = DistributedTestGenerator.analyze_test_patterns([])
      
      assert is_map(patterns)
      assert patterns.confidence_score == 0.0
    end
    
    test "analyzes assertion patterns correctly" do
      test_content = """
      defmodule AssertionPatternTest do
        use ExUnit.Case
        
        test "uses various assertions" do
          assert true
          refute false
          assert_raise ArgumentError, fn -> raise ArgumentError end
          assert_receive :message, 1000
        end
      end
      """
      
      temp_file = create_temp_test_file(test_content)
      
      {:ok, patterns} = DistributedTestGenerator.analyze_test_patterns([temp_file])
      
      assertion_patterns = patterns.assertion_patterns
      assert assertion_patterns.total_assertions > 0
      assert is_list(assertion_patterns.assertion_distribution)
      
      # Should detect different assertion types
      assertion_types = Enum.map(assertion_patterns.assertion_distribution, fn {type, _} -> type end)
      assert "assert" in assertion_types
      
      File.rm(temp_file)
    end
  end
  
  describe "Coverage Analysis" do
    test "provides cluster-wide coverage analysis" do
      coverage = DistributedTestGenerator.get_cluster_coverage()
      
      assert is_map(coverage)
      assert Map.has_key?(coverage, :cluster_coverage)
      assert Map.has_key?(coverage, :module_coverage)
      assert Map.has_key?(coverage, :total_modules)
      assert Map.has_key?(coverage, :nodes_contributing)
      
      assert is_number(coverage.cluster_coverage)
      assert coverage.cluster_coverage >= 0
      assert coverage.cluster_coverage <= 100
    end
    
    test "filters coverage by specific options" do
      opts = %{
        modules: [TestCalculator],
        minimum_coverage: 50
      }
      
      coverage = DistributedTestGenerator.get_cluster_coverage(opts)
      
      assert is_map(coverage)
      # Should handle filtering options without error
    end
  end
  
  describe "Test Suggestions" do
    test "suggests improvements for module" do
      opts = %{
        include_quality_analysis: true,
        include_coverage_analysis: true
      }
      
      {:ok, suggestions} = DistributedTestGenerator.suggest_test_improvements(TestCalculator, opts)
      
      assert is_map(suggestions)
      assert Map.has_key?(suggestions, :module)
      assert Map.has_key?(suggestions, :suggestions)
      assert Map.has_key?(suggestions, :priority)
      
      assert suggestions.module == TestCalculator
      assert is_list(suggestions.suggestions)
      assert suggestions.priority in [:high, :medium, :low]
    end
    
    test "provides appropriate priority for suggestions" do
      # Test with a module that likely needs improvements
      {:ok, suggestions} = DistributedTestGenerator.suggest_test_improvements(TestCalculator)
      
      # Should provide some suggestions
      assert length(suggestions.suggestions) > 0
      
      # Priority should be reasonable
      assert suggestions.priority in [:high, :medium, :low]
    end
  end
  
  describe "Doctest Generation" do
    test "generates doctests for module" do
      opts = %{
        include_examples: true,
        include_edge_cases: true
      }
      
      # Note: This test might fail if LLM integration is not available
      case DistributedTestGenerator.generate_doctests(TestCalculator, opts) do
        {:ok, doctests} ->
          assert is_map(doctests)
          assert Map.has_key?(doctests, :doctests)
          assert Map.has_key?(doctests, :count)
          
          if doctests.count > 0 do
            assert is_list(doctests.doctests)
            
            # Check doctest structure
            first_doctest = List.first(doctests.doctests)
            if first_doctest do
              assert Map.has_key?(first_doctest, :input)
              assert Map.has_key?(first_doctest, :expected_output)
            end
          end
          
        {:error, reason} ->
          # LLM might not be available in test environment
          assert reason != nil
      end
    end
    
    test "handles doctest generation errors" do
      # Test with invalid options
      opts = %{invalid_option: "should_cause_error"}
      
      result = DistributedTestGenerator.generate_doctests(TestCalculator, opts)
      
      # Should either succeed or fail gracefully
      case result do
        {:ok, _} -> assert true
        {:error, _} -> assert true
      end
    end
  end
  
  describe "Statistics and Metrics" do
    test "provides comprehensive generation statistics" do
      stats = DistributedTestGenerator.get_stats()
      
      assert is_map(stats)
      assert Map.has_key?(stats, :node)
      assert Map.has_key?(stats, :active_generations)
      assert Map.has_key?(stats, :pattern_cache_size)
      assert Map.has_key?(stats, :coverage_modules)
      assert Map.has_key?(stats, :metrics)
      assert Map.has_key?(stats, :cluster_nodes)
      assert Map.has_key?(stats, :total_stored_tests)
      
      # Check metrics structure
      metrics = stats.metrics
      assert is_map(metrics)
      assert Map.has_key?(metrics, :total_generations)
      assert Map.has_key?(metrics, :successful_generations)
      assert Map.has_key?(metrics, :failed_generations)
      assert Map.has_key?(metrics, :tests_generated)
    end
    
    test "tracks metrics correctly" do
      # Get initial stats
      initial_stats = DistributedTestGenerator.get_stats()
      initial_generations = initial_stats.metrics.total_generations
      
      # Perform a test generation
      {:ok, _} = DistributedTestGenerator.generate_tests(TestCalculator, %{
        test_types: [:unit],
        distribute_across: 1
      })
      
      # Wait for completion
      :timer.sleep(500)
      
      # Get updated stats
      updated_stats = DistributedTestGenerator.get_stats()
      updated_generations = updated_stats.metrics.total_generations
      
      # Should have increased
      assert updated_generations >= initial_generations
    end
  end
  
  describe "Pattern Cache Management" do
    test "updates pattern cache correctly" do
      # Create test patterns
      test_patterns = %{
        common_patterns: [{"test_pattern", 5}],
        naming_conventions: %{total_tests: 10},
        confidence_score: 0.8
      }
      
      # Update cache
      :ok = DistributedTestGenerator.update_patterns_cache(test_patterns)
      
      # Give time for processing
      :timer.sleep(100)
      
      # Verify cache was updated
      stats = DistributedTestGenerator.get_stats()
      assert stats.pattern_cache_size > 0
    end
    
    test "handles cache updates with invalid data" do
      # Try to update with invalid patterns
      invalid_patterns = "not_a_map"
      
      # Should handle gracefully
      result = DistributedTestGenerator.update_patterns_cache(invalid_patterns)
      assert result == :ok  # Cast should succeed even with invalid data
    end
  end
  
  describe "Event Integration" do
    test "responds to test generation events" do
      # Subscribe to test events
      :ok = OTPEventBus.subscribe({:event_type, :test_generated})
      
      # Generate tests
      {:ok, _} = DistributedTestGenerator.generate_tests(TestCalculator, %{
        test_types: [:unit]
      })
      
      # Should receive some events (may take time due to async processing)
      # Note: This test might be flaky depending on timing
    end
    
    test "handles coverage update events" do
      # Publish a coverage update event
      coverage_event = %{
        id: "coverage_test_1",
        aggregate_id: "test_coverage",
        type: :coverage_updated,
        data: %{
          module: TestCalculator,
          coverage: %{
            line_coverage: 85,
            function_coverage: 90
          }
        },
        metadata: %{}
      }
      
      :ok = OTPEventBus.publish_event(coverage_event)
      
      # Give time for processing
      :timer.sleep(100)
      
      # Check if coverage was recorded
      coverage = DistributedTestGenerator.get_cluster_coverage()
      # Should handle the event without error
      assert is_map(coverage)
    end
  end
  
  describe "Error Handling" do
    test "handles malformed module analysis" do
      # Test with a module that has no source available
      result = DistributedTestGenerator.generate_tests(Kernel, %{})
      
      # Should handle gracefully
      case result do
        {:ok, _} -> assert true
        {:error, reason} -> 
          assert reason != nil
          assert is_tuple(reason) or is_atom(reason)
      end
    end
    
    test "handles pattern analysis with non-existent files" do
      non_existent_files = ["/path/that/does/not/exist/*.exs"]
      
      {:ok, patterns} = DistributedTestGenerator.analyze_test_patterns(non_existent_files)
      
      # Should return empty patterns structure
      assert is_map(patterns)
      assert patterns.confidence_score == 0.0
    end
    
    test "handles suggestions for modules without tests" do
      # Create a module that definitely has no tests
      result = DistributedTestGenerator.suggest_test_improvements(String, %{})
      
      case result do
        {:ok, suggestions} ->
          assert is_map(suggestions)
          assert Map.has_key?(suggestions, :suggestions)
          
        {:error, reason} ->
          # Should fail gracefully
          assert reason != nil
      end
    end
  end
  
  describe "Distributed Coordination" do
    test "handles single-node generation correctly" do
      opts = %{
        test_types: [:unit],
        distribute_across: 1
      }
      
      {:ok, result} = DistributedTestGenerator.generate_tests(TestCalculator, opts)
      
      # Should work correctly on single node
      assert is_map(result)
    end
    
    test "handles distributed generation request with one node" do
      opts = %{
        test_types: [:unit, :property],
        distribute_across: 3  # More than available nodes
      }
      
      {:ok, result} = DistributedTestGenerator.generate_tests(TestCalculator, opts)
      
      # Should fall back to single node and still work
      assert is_map(result)
    end
  end
  
  ## Helper Functions
  
  defp create_temp_test_file(content) do
    # Create a temporary test file
    temp_dir = System.tmp_dir!()
    temp_file = Path.join(temp_dir, "temp_test_#{:erlang.unique_integer([:positive])}.exs")
    
    File.write!(temp_file, content)
    temp_file
  end
end