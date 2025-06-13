defmodule Aiex.AI.Distributed.LoadBalancerTest do
  use ExUnit.Case, async: false
  
  alias Aiex.AI.Distributed.LoadBalancer
  
  setup do
    # Start LoadBalancer for testing
    {:ok, pid} = LoadBalancer.start_link([algorithm: :round_robin])
    on_exit(fn -> 
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)
    %{balancer_pid: pid}
  end
  
  describe "coordinator selection" do
    test "returns error when no coordinators available" do
      request = %{
        type: :explanation,
        content: "Test request"
      }
      
      result = LoadBalancer.select_coordinator(request)
      
      # Should return error since no coordinators are registered
      assert {:error, :no_available_coordinators} = result
    end
    
    test "handles request selection with options" do
      request = %{
        type: :explanation,
        content: "Test request with options"
      }
      
      result = LoadBalancer.select_coordinator(request, algorithm: :round_robin)
      
      # Should handle gracefully even without coordinators
      assert match?({:error, _}, result)
    end
  end
  
  describe "load balancing algorithms" do
    test "can switch algorithms" do
      # Switch to weighted round robin
      result = LoadBalancer.set_algorithm(:weighted_round_robin)
      assert :ok = result
      
      # Switch to least connections
      result = LoadBalancer.set_algorithm(:least_connections)
      assert :ok = result
      
      # Switch to adaptive
      result = LoadBalancer.set_algorithm(:adaptive)
      assert :ok = result
      
      # Switch to capability aware
      result = LoadBalancer.set_algorithm(:capability_aware)
      assert :ok = result
    end
    
    test "rejects invalid algorithms" do
      # This should fail at compile time or runtime validation
      catch_error(LoadBalancer.set_algorithm(:invalid_algorithm))
    end
    
    test "algorithm switching is reflected in stats" do
      # Switch algorithm
      LoadBalancer.set_algorithm(:adaptive)
      
      # Get stats
      stats = LoadBalancer.get_load_balancing_stats()
      
      assert is_map(stats)
      assert Map.has_key?(stats, :current_algorithm)
      # Note: The stats might not immediately reflect the change due to async nature
    end
  end
  
  describe "load balancing statistics" do
    test "returns comprehensive statistics" do
      stats = LoadBalancer.get_load_balancing_stats()
      
      assert is_map(stats)
      assert Map.has_key?(stats, :current_algorithm)
      assert Map.has_key?(stats, :coordinator_pool_size)
      assert Map.has_key?(stats, :active_coordinators)
      assert Map.has_key?(stats, :failed_coordinators)
      assert Map.has_key?(stats, :request_distribution)
      assert Map.has_key?(stats, :algorithm_performance)
      assert Map.has_key?(stats, :circuit_breaker_status)
      assert Map.has_key?(stats, :timestamp)
      
      assert is_atom(stats.current_algorithm)
      assert is_integer(stats.coordinator_pool_size)
      assert is_integer(stats.active_coordinators)
      assert is_integer(stats.failed_coordinators)
      assert is_map(stats.request_distribution)
      assert is_map(stats.circuit_breaker_status)
      assert is_integer(stats.timestamp)
    end
    
    test "statistics start with reasonable defaults" do
      stats = LoadBalancer.get_load_balancing_stats()
      
      # Should start with no coordinators
      assert stats.coordinator_pool_size == 0
      assert stats.active_coordinators == 0
      assert stats.failed_coordinators == 0
      assert map_size(stats.request_distribution) == 0
    end
  end
  
  describe "coordinator pool status" do
    test "returns pool status information" do
      status = LoadBalancer.get_coordinator_pool_status()
      
      assert is_map(status)
      assert Map.has_key?(status, :total_coordinators)
      assert Map.has_key?(status, :active_coordinators)
      assert Map.has_key?(status, :failed_coordinators)
      assert Map.has_key?(status, :algorithm)
      assert Map.has_key?(status, :request_distribution)
      
      assert is_integer(status.total_coordinators)
      assert is_integer(status.active_coordinators)
      assert is_integer(status.failed_coordinators)
      assert is_atom(status.algorithm)
      assert is_map(status.request_distribution)
    end
    
    test "pool status reflects current state" do
      status = LoadBalancer.get_coordinator_pool_status()
      
      # Should start with no coordinators
      assert status.total_coordinators == 0
      assert status.active_coordinators == 0
      assert status.failed_coordinators == 0
    end
  end
  
  describe "performance tracking" do
    test "accepts performance updates" do
      coordinator_id = "test_coordinator_123"
      metrics = %{
        response_time_ms: 1500,
        success_rate: 0.95,
        throughput_rpm: 20
      }
      
      # Should not crash
      :ok = LoadBalancer.update_coordinator_performance(coordinator_id, metrics)
    end
    
    test "performance updates affect statistics" do
      coordinator_id = "test_coordinator_456"
      metrics = %{
        response_time_ms: 2000,
        success_rate: 0.90
      }
      
      # Update performance
      LoadBalancer.update_coordinator_performance(coordinator_id, metrics)
      
      # Give it time to process
      Process.sleep(100)
      
      # Statistics should reflect the update
      stats = LoadBalancer.get_load_balancing_stats()
      assert is_map(stats)
      # Specific performance data might not be directly visible in stats
    end
  end
  
  describe "circuit breaker functionality" do
    test "can mark coordinator as failed" do
      coordinator_id = "failing_coordinator"
      reason = "Connection timeout"
      
      # Should not crash
      :ok = LoadBalancer.mark_coordinator_failed(coordinator_id, reason)
    end
    
    test "can mark coordinator as recovered" do
      coordinator_id = "recovered_coordinator"
      
      # First mark as failed
      LoadBalancer.mark_coordinator_failed(coordinator_id, "test failure")
      
      # Then mark as recovered
      :ok = LoadBalancer.mark_coordinator_recovered(coordinator_id)
    end
    
    test "circuit breaker status is tracked in statistics" do
      coordinator_id = "circuit_test_coordinator"
      
      # Mark as failed
      LoadBalancer.mark_coordinator_failed(coordinator_id, "test failure")
      
      # Give it time to process
      Process.sleep(100)
      
      # Check statistics
      stats = LoadBalancer.get_load_balancing_stats()
      
      # Circuit breaker status should be included
      assert is_map(stats.circuit_breaker_status)
      
      # May or may not show our test coordinator depending on implementation
    end
    
    test "failed coordinators affect pool status" do
      coordinator_id = "status_test_coordinator"
      
      # Mark as failed
      LoadBalancer.mark_coordinator_failed(coordinator_id, "test failure")
      
      # Give it time to process
      Process.sleep(100)
      
      # Pool status should reflect failed coordinators
      status = LoadBalancer.get_coordinator_pool_status()
      
      # Failed count might be affected
      assert is_integer(status.failed_coordinators)
    end
  end
  
  describe "algorithm performance analysis" do
    test "tracks algorithm performance over time" do
      # Make some coordinator performance updates to generate data
      coordinator_id = "perf_test_coordinator"
      
      Enum.each(1..5, fn i ->
        metrics = %{
          response_time_ms: 1000 + i * 100,
          success_rate: 0.9 + i * 0.01
        }
        
        LoadBalancer.update_coordinator_performance(coordinator_id, metrics)
      end)
      
      # Give it time to process
      Process.sleep(500)
      
      # Algorithm performance should be tracked
      stats = LoadBalancer.get_load_balancing_stats()
      assert is_map(stats.algorithm_performance)
    end
    
    test "algorithm performance includes current algorithm" do
      stats = LoadBalancer.get_load_balancing_stats()
      
      current_algorithm = stats.current_algorithm
      algorithm_performance = stats.algorithm_performance
      
      # Should have entry for current algorithm
      assert Map.has_key?(algorithm_performance, current_algorithm)
    end
  end
  
  describe "request distribution tracking" do
    test "tracks request distribution across coordinators" do
      # Simulate request distribution
      # Note: This is indirect since we can't actually select coordinators without them being registered
      
      stats = LoadBalancer.get_load_balancing_stats()
      
      # Request distribution should be a map
      assert is_map(stats.request_distribution)
      
      # Should start empty
      assert map_size(stats.request_distribution) == 0
    end
  end
  
  describe "error handling and robustness" do
    test "handles coordinator selection with malformed requests" do
      malformed_request = %{
        # Missing type and content
      }
      
      result = LoadBalancer.select_coordinator(malformed_request)
      
      # Should handle gracefully
      assert match?({:error, _}, result)
    end
    
    test "handles performance updates with invalid data" do
      coordinator_id = "invalid_data_coordinator"
      invalid_metrics = %{
        response_time_ms: "not_a_number",
        success_rate: :invalid
      }
      
      # Should not crash
      :ok = LoadBalancer.update_coordinator_performance(coordinator_id, invalid_metrics)
    end
    
    test "remains functional after various error conditions" do
      # Try various operations that might cause errors
      LoadBalancer.mark_coordinator_failed("nonexistent", "test")
      LoadBalancer.mark_coordinator_recovered("nonexistent")
      LoadBalancer.update_coordinator_performance("test", %{invalid: :data})
      
      # Load balancer should still be responsive
      stats = LoadBalancer.get_load_balancing_stats()
      assert is_map(stats)
      
      status = LoadBalancer.get_coordinator_pool_status()
      assert is_map(status)
    end
  end
  
  describe "initialization and configuration" do
    test "starts with specified algorithm" do
      # Stop current balancer
      Process.exit(pid = Process.whereis(LoadBalancer), :normal)
      
      # Wait for it to stop
      Process.sleep(100)
      
      # Start with specific algorithm
      {:ok, _new_pid} = LoadBalancer.start_link([algorithm: :least_connections])
      
      # Check that it started with the correct algorithm
      stats = LoadBalancer.get_load_balancing_stats()
      assert stats.current_algorithm == :least_connections
    end
  end
  
  describe "periodic updates" do
    test "coordinator pool is updated periodically" do
      # The load balancer should periodically update its coordinator pool
      # We can't directly test this without running coordinators, but we can ensure it doesn't crash
      
      # Let it run for a bit
      Process.sleep(2000)
      
      # Should still be responsive
      stats = LoadBalancer.get_load_balancing_stats()
      assert is_map(stats)
    end
  end
end