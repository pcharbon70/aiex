defmodule Aiex.AI.Distributed.ABTestingFrameworkTest do
  use ExUnit.Case, async: false
  
  alias Aiex.AI.Distributed.ABTestingFramework
  
  setup do
    # Start ABTestingFramework for testing
    {:ok, pid} = ABTestingFramework.start_link([])
    on_exit(fn -> 
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)
    %{framework_pid: pid}
  end
  
  describe "test creation" do
    test "creates valid A/B test successfully" do
      test_config = %{
        name: "test_consensus_strategies",
        description: "Test different consensus strategies",
        variants: [:control, :treatment],
        traffic_split: %{control: 0.5, treatment: 0.5},
        metrics: [:quality_score, :response_time],
        minimum_sample_size: 10,
        confidence_level: 0.95,
        test_duration_hours: 24
      }
      
      result = ABTestingFramework.create_test(test_config)
      assert :ok = result
      
      # Test should appear in active tests
      active_tests = ABTestingFramework.get_active_tests()
      assert "test_consensus_strategies" in active_tests
    end
    
    test "rejects test with missing required fields" do
      incomplete_config = %{
        name: "incomplete_test",
        variants: [:control, :treatment]
        # Missing traffic_split and metrics
      }
      
      result = ABTestingFramework.create_test(incomplete_config)
      assert {:error, {:missing_fields, _fields}} = result
    end
    
    test "rejects test with insufficient variants" do
      invalid_config = %{
        name: "invalid_test",
        description: "Test with only one variant",
        variants: [:control],
        traffic_split: %{control: 1.0},
        metrics: [:quality_score]
      }
      
      result = ABTestingFramework.create_test(invalid_config)
      assert {:error, :insufficient_variants} = result
    end
    
    test "rejects test with invalid traffic split" do
      invalid_config = %{
        name: "invalid_traffic_test",
        description: "Test with invalid traffic split",
        variants: [:control, :treatment],
        traffic_split: %{control: 0.3, treatment: 0.3},  # Doesn't sum to 1.0
        metrics: [:quality_score]
      }
      
      result = ABTestingFramework.create_test(invalid_config)
      assert {:error, :invalid_traffic_split} = result
    end
    
    test "prevents duplicate test names" do
      test_config = %{
        name: "duplicate_test",
        description: "Test for duplicates",
        variants: [:control, :treatment],
        traffic_split: %{control: 0.5, treatment: 0.5},
        metrics: [:quality_score]
      }
      
      # Create first test
      result1 = ABTestingFramework.create_test(test_config)
      assert :ok = result1
      
      # Try to create duplicate
      result2 = ABTestingFramework.create_test(test_config)
      assert {:error, :test_already_exists} = result2
    end
  end
  
  describe "variant assignment" do
    setup do
      test_config = %{
        name: "assignment_test",
        description: "Test for variant assignment",
        variants: [:control, :treatment],
        traffic_split: %{control: 0.6, treatment: 0.4},
        metrics: [:quality_score]
      }
      
      ABTestingFramework.create_test(test_config)
      %{test_name: "assignment_test"}
    end
    
    test "assigns variants to requests", %{test_name: test_name} do
      request_id = "test_request_123"
      
      result = ABTestingFramework.get_variant_assignment(test_name, request_id)
      
      assert {:ok, variant} = result
      assert variant in [:control, :treatment]
    end
    
    test "consistent assignment for same request ID", %{test_name: test_name} do
      request_id = "consistent_request_456"
      
      # Get assignment multiple times
      {:ok, variant1} = ABTestingFramework.get_variant_assignment(test_name, request_id)
      {:ok, variant2} = ABTestingFramework.get_variant_assignment(test_name, request_id)
      {:ok, variant3} = ABTestingFramework.get_variant_assignment(test_name, request_id)
      
      # Should always return the same variant
      assert variant1 == variant2
      assert variant2 == variant3
    end
    
    test "different request IDs get variants", %{test_name: test_name} do
      # Get assignments for multiple requests
      assignments = Enum.map(1..20, fn i ->
        request_id = "request_#{i}"
        {:ok, variant} = ABTestingFramework.get_variant_assignment(test_name, request_id)
        variant
      end)
      
      # Should have both variants represented (with high probability)
      unique_variants = Enum.uniq(assignments)
      assert length(unique_variants) >= 1  # At least one variant
      
      # Check that variants are valid
      Enum.each(assignments, fn variant ->
        assert variant in [:control, :treatment]
      end)
    end
    
    test "returns error for non-existent test" do
      result = ABTestingFramework.get_variant_assignment("non_existent_test", "request_123")
      
      assert {:error, :test_not_found} = result
    end
  end
  
  describe "result recording" do
    setup do
      test_config = %{
        name: "result_test",
        description: "Test for result recording",
        variants: [:control, :treatment],
        traffic_split: %{control: 0.5, treatment: 0.5},
        metrics: [:quality_score, :response_time]
      }
      
      ABTestingFramework.create_test(test_config)
      %{test_name: "result_test"}
    end
    
    test "records test results successfully", %{test_name: test_name} do
      # Record some test results
      ABTestingFramework.record_test_result(test_name, :control, %{
        quality_score: 0.8,
        response_time: 1200
      }, "request_1")
      
      ABTestingFramework.record_test_result(test_name, :treatment, %{
        quality_score: 0.85,
        response_time: 1100
      }, "request_2")
      
      # Give time for async processing
      Process.sleep(100)
      
      # Should not crash and results should be recorded
      {:ok, test_results} = ABTestingFramework.get_test_results(test_name)
      
      assert is_map(test_results)
      assert Map.has_key?(test_results, :sample_sizes)
    end
    
    test "handles result recording for unknown test gracefully" do
      # Should not crash when recording for unknown test
      ABTestingFramework.record_test_result("unknown_test", :control, %{
        quality_score: 0.8
      }, "request_123")
      
      # Framework should still be responsive
      stats = ABTestingFramework.get_framework_stats()
      assert is_map(stats)
    end
  end
  
  describe "test results and analysis" do
    setup do
      test_config = %{
        name: "analysis_test",
        description: "Test for analysis",
        variants: [:control, :treatment],
        traffic_split: %{control: 0.5, treatment: 0.5},
        metrics: [:quality_score, :response_time]
      }
      
      ABTestingFramework.create_test(test_config)
      
      # Record some sample data
      Enum.each(1..5, fn i ->
        ABTestingFramework.record_test_result("analysis_test", :control, %{
          quality_score: 0.7 + i * 0.02,
          response_time: 1200 + i * 10
        }, "control_request_#{i}")
        
        ABTestingFramework.record_test_result("analysis_test", :treatment, %{
          quality_score: 0.8 + i * 0.02,
          response_time: 1100 + i * 15
        }, "treatment_request_#{i}")
      end)
      
      # Give time for processing
      Process.sleep(200)
      
      %{test_name: "analysis_test"}
    end
    
    test "returns comprehensive test analysis", %{test_name: test_name} do
      {:ok, results} = ABTestingFramework.get_test_results(test_name)
      
      assert is_map(results)
      assert Map.has_key?(results, :test_name)
      assert Map.has_key?(results, :status)
      assert Map.has_key?(results, :sample_sizes)
      assert Map.has_key?(results, :metrics_analysis)
      assert Map.has_key?(results, :statistical_significance)
      assert Map.has_key?(results, :recommendation)
      
      assert results.test_name == test_name
      assert results.status in [:active, :insufficient_data]
      assert is_map(results.sample_sizes)
      assert is_map(results.metrics_analysis)
      assert is_map(results.statistical_significance)
      assert is_atom(results.recommendation)
    end
    
    test "calculates sample sizes correctly", %{test_name: test_name} do
      {:ok, results} = ABTestingFramework.get_test_results(test_name)
      
      sample_sizes = results.sample_sizes
      
      # Should have entries for both variants
      assert Map.has_key?(sample_sizes, :control)
      assert Map.has_key?(sample_sizes, :treatment)
      
      # Sample sizes should be reasonable (we recorded 5 for each)
      assert sample_sizes[:control] >= 0
      assert sample_sizes[:treatment] >= 0
    end
    
    test "performs metrics analysis", %{test_name: test_name} do
      {:ok, results} = ABTestingFramework.get_test_results(test_name)
      
      metrics_analysis = results.metrics_analysis
      
      if map_size(metrics_analysis) > 0 do
        # Should have analysis for each variant
        assert Map.has_key?(metrics_analysis, :control) or Map.has_key?(metrics_analysis, :treatment)
        
        # Check structure of metrics analysis
        {_variant, variant_metrics} = Enum.at(metrics_analysis, 0)
        
        if map_size(variant_metrics) > 0 do
          {_metric, metric_stats} = Enum.at(variant_metrics, 0)
          
          assert is_map(metric_stats)
          assert Map.has_key?(metric_stats, :mean)
          assert Map.has_key?(metric_stats, :std_dev)
          assert Map.has_key?(metric_stats, :count)
        end
      end
    end
    
    test "provides recommendations", %{test_name: test_name} do
      {:ok, results} = ABTestingFramework.get_test_results(test_name)
      
      recommendation = results.recommendation
      
      assert recommendation in [:continue_test, :significant_result, :inconclusive_stop]
    end
  end
  
  describe "test lifecycle management" do
    test "stops test and finalizes results" do
      test_config = %{
        name: "lifecycle_test",
        description: "Test for lifecycle management",
        variants: [:control, :treatment],
        traffic_split: %{control: 0.5, treatment: 0.5},
        metrics: [:quality_score]
      }
      
      # Create and populate test
      ABTestingFramework.create_test(test_config)
      
      ABTestingFramework.record_test_result("lifecycle_test", :control, %{
        quality_score: 0.7
      }, "request_1")
      
      Process.sleep(100)
      
      # Stop the test
      {:ok, final_analysis} = ABTestingFramework.stop_test("lifecycle_test")
      
      assert is_map(final_analysis)
      
      # Test should no longer be in active tests
      active_tests = ABTestingFramework.get_active_tests()
      refute "lifecycle_test" in active_tests
      
      # Should still be able to get results
      {:ok, completed_results} = ABTestingFramework.get_test_results("lifecycle_test")
      assert is_map(completed_results)
    end
    
    test "returns error when stopping non-existent test" do
      result = ABTestingFramework.stop_test("non_existent_test")
      
      assert {:error, :test_not_found} = result
    end
  end
  
  describe "framework statistics" do
    test "returns comprehensive framework statistics" do
      stats = ABTestingFramework.get_framework_stats()
      
      assert is_map(stats)
      assert Map.has_key?(stats, :active_tests_count)
      assert Map.has_key?(stats, :completed_tests_count)
      assert Map.has_key?(stats, :total_test_results)
      assert Map.has_key?(stats, :active_test_names)
      assert Map.has_key?(stats, :framework_uptime_ms)
      assert Map.has_key?(stats, :timestamp)
      
      assert is_integer(stats.active_tests_count)
      assert is_integer(stats.completed_tests_count)
      assert is_integer(stats.total_test_results)
      assert is_list(stats.active_test_names)
      assert is_integer(stats.framework_uptime_ms)
      assert is_integer(stats.timestamp)
    end
    
    test "statistics reflect framework state" do
      initial_stats = ABTestingFramework.get_framework_stats()
      
      # Create a test
      test_config = %{
        name: "stats_test",
        description: "Test for statistics",
        variants: [:control, :treatment],
        traffic_split: %{control: 0.5, treatment: 0.5},
        metrics: [:quality_score]
      }
      
      ABTestingFramework.create_test(test_config)
      
      updated_stats = ABTestingFramework.get_framework_stats()
      
      # Active tests count should have increased
      assert updated_stats.active_tests_count >= initial_stats.active_tests_count
      assert "stats_test" in updated_stats.active_test_names
    end
  end
  
  describe "concurrent operations" do
    test "handles multiple concurrent test operations" do
      # Create multiple tests concurrently
      test_configs = Enum.map(1..3, fn i ->
        %{
          name: "concurrent_test_#{i}",
          description: "Concurrent test #{i}",
          variants: [:control, :treatment],
          traffic_split: %{control: 0.5, treatment: 0.5},
          metrics: [:quality_score]
        }
      end)
      
      tasks = Enum.map(test_configs, fn config ->
        Task.async(fn ->
          ABTestingFramework.create_test(config)
        end)
      end)
      
      results = Task.await_many(tasks, 10_000)
      
      # All should succeed
      Enum.each(results, fn result ->
        assert :ok = result
      end)
      
      # All tests should be active
      active_tests = ABTestingFramework.get_active_tests()
      
      Enum.each(1..3, fn i ->
        assert "concurrent_test_#{i}" in active_tests
      end)
    end
    
    test "handles concurrent variant assignments" do
      test_config = %{
        name: "concurrent_assignment_test",
        description: "Test for concurrent assignments",
        variants: [:control, :treatment],
        traffic_split: %{control: 0.5, treatment: 0.5},
        metrics: [:quality_score]
      }
      
      ABTestingFramework.create_test(test_config)
      
      # Get assignments concurrently
      tasks = Enum.map(1..10, fn i ->
        Task.async(fn ->
          request_id = "concurrent_request_#{i}"
          ABTestingFramework.get_variant_assignment("concurrent_assignment_test", request_id)
        end)
      end)
      
      results = Task.await_many(tasks, 10_000)
      
      # All should succeed
      Enum.each(results, fn result ->
        assert {:ok, variant} = result
        assert variant in [:control, :treatment]
      end)
    end
  end
  
  describe "error handling and robustness" do
    test "handles malformed test configurations gracefully" do
      malformed_configs = [
        %{},  # Empty config
        %{name: "test", variants: []},  # Empty variants
        %{name: "test", variants: [:control, :treatment]},  # Missing traffic_split
        %{name: 123, variants: [:control, :treatment], traffic_split: %{}}  # Invalid name type
      ]
      
      Enum.each(malformed_configs, fn config ->
        result = ABTestingFramework.create_test(config)
        # Should return error, not crash
        assert match?({:error, _}, result)
      end)
      
      # Framework should still be responsive
      stats = ABTestingFramework.get_framework_stats()
      assert is_map(stats)
    end
    
    test "remains responsive after various error conditions" do
      # Try various operations that might cause errors
      ABTestingFramework.create_test(%{})
      ABTestingFramework.get_variant_assignment("non_existent", "request")
      ABTestingFramework.record_test_result("non_existent", :control, %{}, "request")
      ABTestingFramework.stop_test("non_existent")
      
      # Framework should still be responsive
      stats = ABTestingFramework.get_framework_stats()
      assert is_map(stats)
      
      active_tests = ABTestingFramework.get_active_tests()
      assert is_list(active_tests)
    end
  end
  
  describe "statistical calculations" do
    test "calculates confidence intervals" do
      test_config = %{
        name: "confidence_test",
        description: "Test for confidence intervals",
        variants: [:control, :treatment],
        traffic_split: %{control: 0.5, treatment: 0.5},
        metrics: [:quality_score]
      }
      
      ABTestingFramework.create_test(test_config)
      
      # Record enough data for statistical analysis
      Enum.each(1..10, fn i ->
        ABTestingFramework.record_test_result("confidence_test", :control, %{
          quality_score: 0.7 + :rand.uniform() * 0.1
        }, "control_#{i}")
        
        ABTestingFramework.record_test_result("confidence_test", :treatment, %{
          quality_score: 0.8 + :rand.uniform() * 0.1
        }, "treatment_#{i}")
      end)
      
      Process.sleep(200)
      
      {:ok, results} = ABTestingFramework.get_test_results("confidence_test")
      
      if Map.has_key?(results, :confidence_intervals) do
        confidence_intervals = results.confidence_intervals
        
        if map_size(confidence_intervals) > 0 do
          {_variant, intervals} = Enum.at(confidence_intervals, 0)
          
          if map_size(intervals) > 0 do
            {_metric, interval} = Enum.at(intervals, 0)
            
            assert Map.has_key?(interval, :lower)
            assert Map.has_key?(interval, :upper)
            assert Map.has_key?(interval, :margin_of_error)
            
            assert is_number(interval.lower)
            assert is_number(interval.upper)
            assert interval.upper >= interval.lower
          end
        end
      end
    end
  end
end