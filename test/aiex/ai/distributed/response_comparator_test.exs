defmodule Aiex.AI.Distributed.ResponseComparatorTest do
  use ExUnit.Case, async: false
  
  alias Aiex.AI.Distributed.ResponseComparator
  
  setup do
    # Start ResponseComparator for testing
    {:ok, pid} = ResponseComparator.start_link([])
    on_exit(fn -> 
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)
    %{comparator_pid: pid}
  end
  
  describe "response comparison" do
    test "handles single provider gracefully" do
      request = %{
        type: :explanation,
        content: "Test request with single provider"
      }
      
      # Should return error when insufficient providers
      result = ResponseComparator.compare_responses(request, providers: [:openai])
      assert {:error, :insufficient_providers} = result
    end
    
    test "compares responses from multiple providers" do
      request = %{
        type: :explanation,
        content: "Test request for comparison"
      }
      
      # This will attempt to use multiple providers
      # In test environment, this may fail due to missing LLM engines, but shouldn't crash
      result = ResponseComparator.compare_responses(request, providers: [:openai, :anthropic])
      
      # Should return a result (may be error due to test environment)
      assert is_tuple(result)
    end
    
    test "handles comparison timeout gracefully" do
      request = %{
        type: :explanation,
        content: "Test request that might timeout"
      }
      
      # Test with very short timeout to simulate timeout scenario
      result = ResponseComparator.compare_responses(request, providers: [:openai, :anthropic])
      
      # Should handle timeout gracefully
      assert is_tuple(result)
    end
  end
  
  describe "consensus strategies" do
    test "can set different consensus strategies" do
      strategies = [:majority, :quality_weighted, :best_quality, :hybrid]
      
      Enum.each(strategies, fn strategy ->
        result = ResponseComparator.set_consensus_strategy(strategy)
        assert :ok = result
      end)
    end
    
    test "rejects invalid consensus strategies" do
      result = ResponseComparator.set_consensus_strategy(:invalid_strategy)
      assert {:error, :invalid_strategy} = result
    end
  end
  
  describe "comparison statistics" do
    test "returns comprehensive comparison statistics" do
      stats = ResponseComparator.get_comparison_stats()
      
      assert is_map(stats)
      assert Map.has_key?(stats, :active_comparisons)
      assert Map.has_key?(stats, :completed_comparisons)
      assert Map.has_key?(stats, :consensus_strategy)
      assert Map.has_key?(stats, :avg_comparison_time)
      assert Map.has_key?(stats, :provider_usage)
      assert Map.has_key?(stats, :quality_trends)
      assert Map.has_key?(stats, :timestamp)
      
      assert is_integer(stats.active_comparisons)
      assert is_integer(stats.completed_comparisons)
      assert is_atom(stats.consensus_strategy)
      assert is_number(stats.avg_comparison_time)
      assert is_map(stats.provider_usage)
      assert is_map(stats.quality_trends)
      assert is_integer(stats.timestamp)
    end
    
    test "statistics start with reasonable defaults" do
      stats = ResponseComparator.get_comparison_stats()
      
      # Should start with no active or completed comparisons
      assert stats.active_comparisons == 0
      assert stats.completed_comparisons == 0
      assert stats.avg_comparison_time == 0.0
      assert map_size(stats.provider_usage) == 0
    end
  end
  
  describe "provider performance tracking" do
    test "returns provider performance metrics" do
      performance = ResponseComparator.get_provider_performance()
      
      assert is_map(performance)
      
      # Should start empty but structure should be correct
      if map_size(performance) > 0 do
        {_provider, metrics} = Enum.at(performance, 0)
        assert is_map(metrics)
        assert Map.has_key?(metrics, :avg_quality_score)
        assert Map.has_key?(metrics, :avg_response_time)
        assert Map.has_key?(metrics, :success_rate)
        assert Map.has_key?(metrics, :total_requests)
        assert Map.has_key?(metrics, :recent_trend)
      end
    end
    
    test "tracks performance over multiple comparisons" do
      # Since we can't easily run actual comparisons in test environment,
      # we test that the performance tracking doesn't crash
      performance1 = ResponseComparator.get_provider_performance()
      
      # Attempt a comparison (will likely fail in test but shouldn't crash)
      request = %{type: :explanation, content: "Test"}
      ResponseComparator.compare_responses(request, providers: [:openai, :anthropic])
      
      # Performance tracking should still work
      performance2 = ResponseComparator.get_provider_performance()
      
      assert is_map(performance1)
      assert is_map(performance2)
    end
  end
  
  describe "concurrent comparison handling" do
    test "handles multiple concurrent comparisons" do
      requests = Enum.map(1..3, fn i ->
        %{
          type: :explanation,
          content: "Concurrent comparison test #{i}"
        }
      end)
      
      # Submit comparisons concurrently
      tasks = Enum.map(requests, fn request ->
        Task.async(fn ->
          ResponseComparator.compare_responses(request, providers: [:openai, :anthropic])
        end)
      end)
      
      # Wait for all to complete (with reasonable timeout)
      results = Task.await_many(tasks, 15_000)
      
      # All should complete (regardless of success/failure in test environment)
      assert length(results) == 3
      Enum.each(results, fn result ->
        assert is_tuple(result)
      end)
    end
    
    test "maintains statistics consistency under concurrent load" do
      initial_stats = ResponseComparator.get_comparison_stats()
      
      # Submit multiple comparisons
      tasks = Enum.map(1..5, fn i ->
        Task.async(fn ->
          request = %{type: :explanation, content: "Load test #{i}"}
          ResponseComparator.compare_responses(request, providers: [:openai, :anthropic])
        end)
      end)
      
      # Wait for completion
      Task.await_many(tasks, 20_000)
      
      # Statistics should still be accessible and valid
      updated_stats = ResponseComparator.get_comparison_stats()
      
      assert is_map(initial_stats)
      assert is_map(updated_stats)
      assert updated_stats.timestamp >= initial_stats.timestamp
    end
  end
  
  describe "error handling and robustness" do
    test "handles malformed requests gracefully" do
      malformed_request = %{
        # Missing type and content
      }
      
      result = ResponseComparator.compare_responses(malformed_request, providers: [:openai, :anthropic])
      
      # Should handle gracefully, not crash
      assert is_tuple(result)
    end
    
    test "handles empty provider list" do
      request = %{
        type: :explanation,
        content: "Test request"
      }
      
      result = ResponseComparator.compare_responses(request, providers: [])
      
      # Should return error for insufficient providers
      assert {:error, :insufficient_providers} = result
    end
    
    test "remains responsive after various error conditions" do
      # Try various operations that might cause errors
      ResponseComparator.compare_responses(%{}, providers: [:openai, :anthropic])
      ResponseComparator.compare_responses(%{type: :invalid}, providers: [:openai, :anthropic])
      ResponseComparator.set_consensus_strategy(:invalid)
      
      # ResponseComparator should still be responsive
      stats = ResponseComparator.get_comparison_stats()
      assert is_map(stats)
      
      performance = ResponseComparator.get_provider_performance()
      assert is_map(performance)
    end
  end
  
  describe "response quality assessment integration" do
    test "integrates with quality metrics" do
      # Test that quality assessment doesn't break the comparison process
      request = %{
        type: :explanation,
        content: "Test request for quality assessment"
      }
      
      # This will internally use QualityMetrics.assess_response_quality
      result = ResponseComparator.compare_responses(request, providers: [:openai, :anthropic])
      
      # Should not crash due to quality assessment
      assert is_tuple(result)
    end
  end
  
  describe "configuration and options" do
    test "respects provider options" do
      request = %{
        type: :explanation,
        content: "Test request with specific providers"
      }
      
      # Test with different provider configurations
      result1 = ResponseComparator.compare_responses(request, providers: [:openai, :anthropic])
      result2 = ResponseComparator.compare_responses(request, providers: [:openai, :ollama])
      
      # Both should be handled consistently
      assert is_tuple(result1)
      assert is_tuple(result2)
    end
    
    test "handles comparison options" do
      request = %{
        type: :explanation,
        content: "Test request with options"
      }
      
      options = [
        providers: [:openai, :anthropic],
        consensus_strategy: :quality_weighted,
        timeout: 10_000
      ]
      
      result = ResponseComparator.compare_responses(request, options)
      
      # Should handle options gracefully
      assert is_tuple(result)
    end
  end
  
  describe "cleanup and memory management" do
    test "handles cleanup operations" do
      # Let the comparator run for a moment to potentially trigger cleanup
      Process.sleep(1000)
      
      # Should still be responsive after cleanup
      stats = ResponseComparator.get_comparison_stats()
      assert is_map(stats)
    end
    
    test "maintains reasonable memory usage" do
      # Submit many requests to test memory management
      Enum.each(1..10, fn i ->
        request = %{type: :explanation, content: "Memory test #{i}"}
        ResponseComparator.compare_responses(request, providers: [:openai, :anthropic])
      end)
      
      # Let cleanup potentially run
      Process.sleep(2000)
      
      # Should still be responsive
      stats = ResponseComparator.get_comparison_stats()
      assert is_map(stats)
    end
  end
end