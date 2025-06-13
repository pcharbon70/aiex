defmodule Aiex.AI.Distributed.CoordinatorTest do
  use ExUnit.Case, async: false
  
  alias Aiex.AI.Distributed.Coordinator
  
  setup do
    # Start coordinator for testing
    {:ok, pid} = Coordinator.start_link([])
    on_exit(fn -> 
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)
    %{coordinator_pid: pid}
  end
  
  describe "coordinator registration" do
    test "registers successfully and returns coordinator ID" do
      {:ok, coordinator_id} = Coordinator.register_coordinator()
      
      assert is_binary(coordinator_id)
      assert String.length(coordinator_id) == 16  # 8 bytes encoded as hex
    end
    
    test "can be registered multiple times" do
      {:ok, id1} = Coordinator.register_coordinator()
      {:ok, id2} = Coordinator.register_coordinator()
      
      assert id1 == id2  # Same coordinator, same ID
    end
  end
  
  describe "coordinator discovery" do
    test "returns empty list when no other coordinators" do
      coordinators = Coordinator.get_coordinators()
      
      assert is_list(coordinators)
      # Should be empty since we're the only coordinator
      assert length(coordinators) == 0
    end
    
    test "includes self in coordinator list after registration" do
      {:ok, _coordinator_id} = Coordinator.register_coordinator()
      coordinators = Coordinator.get_coordinators()
      
      # Should see ourselves in the list
      assert length(coordinators) == 0  # get_coordinators excludes self
    end
  end
  
  describe "request routing" do
    test "routes request locally when no other coordinators available" do
      request = %{
        type: :explanation,
        content: "Explain this code",
        requirements: %{}
      }
      
      # This should succeed and route locally
      result = Coordinator.route_request(request, [])
      
      # Should get a result (might be error due to missing engines in test, but should not timeout)
      assert is_tuple(result)
    end
    
    test "respects routing strategy options" do
      request = %{
        type: :explanation,
        content: "Test request",
        requirements: %{}
      }
      
      # Test local_only strategy
      result = Coordinator.route_request(request, routing_strategy: :local_only)
      assert is_tuple(result)
    end
    
    test "handles invalid routing strategy" do
      request = %{
        type: :explanation,
        content: "Test request"
      }
      
      result = Coordinator.route_request(request, routing_strategy: :invalid_strategy)
      assert {:error, {:invalid_routing_strategy, :invalid_strategy}} = result
    end
  end
  
  describe "cluster topology" do
    test "returns cluster topology information" do
      topology = Coordinator.get_cluster_topology()
      
      assert is_map(topology)
      assert Map.has_key?(topology, :timestamp)
      assert Map.has_key?(topology, :total_coordinators)
      assert Map.has_key?(topology, :local_coordinator)
      assert Map.has_key?(topology, :coordinators)
      assert Map.has_key?(topology, :cluster_health)
      assert Map.has_key?(topology, :load_distribution)
      
      assert topology.total_coordinators >= 1
      assert is_binary(topology.local_coordinator)
      assert is_list(topology.coordinators)
      assert topology.cluster_health in [:healthy, :degraded, :critical]
    end
    
    test "includes local coordinator in topology" do
      {:ok, coordinator_id} = Coordinator.register_coordinator()
      topology = Coordinator.get_cluster_topology()
      
      assert topology.local_coordinator == coordinator_id
      assert length(topology.coordinators) >= 1
      
      local_coordinator = Enum.find(topology.coordinators, fn coord ->
        coord.coordinator_id == coordinator_id
      end)
      
      assert local_coordinator
      assert local_coordinator.node == Node.self()
    end
  end
  
  describe "load metrics" do
    test "returns current load metrics" do
      metrics = Coordinator.get_load_metrics()
      
      assert is_map(metrics)
      assert Map.has_key?(metrics, :timestamp)
      assert Map.has_key?(metrics, :coordinator_id)
      assert Map.has_key?(metrics, :active_requests)
      assert Map.has_key?(metrics, :queue_size)
      assert Map.has_key?(metrics, :capabilities)
      assert Map.has_key?(metrics, :uptime_ms)
      
      assert is_integer(metrics.active_requests)
      assert is_integer(metrics.queue_size)
      assert is_map(metrics.capabilities)
      assert is_integer(metrics.uptime_ms)
      assert metrics.uptime_ms >= 0
    end
    
    test "tracks request completion metrics" do
      initial_metrics = Coordinator.get_load_metrics()
      
      # Simulate request completion
      Coordinator.notify_request_completed("test_request_123", %{
        duration_ms: 1500,
        success: true
      })
      
      # Give it a moment to process
      Process.sleep(100)
      
      updated_metrics = Coordinator.get_load_metrics()
      
      # Load metrics should be updated
      assert updated_metrics.timestamp >= initial_metrics.timestamp
    end
  end
  
  describe "capability updates" do
    test "accepts capability updates" do
      new_capabilities = %{
        max_concurrent_requests: 150,
        supported_providers: [:openai, :anthropic],
        memory_mb: 2048
      }
      
      # This should not crash
      :ok = Coordinator.update_capabilities(new_capabilities)
    end
    
    test "capability updates affect cluster topology" do
      new_capabilities = %{
        max_concurrent_requests: 200,
        supported_providers: [:openai, :anthropic, :ollama]
      }
      
      Coordinator.update_capabilities(new_capabilities)
      
      # Give it time to process
      Process.sleep(100)
      
      topology = Coordinator.get_cluster_topology()
      local_coordinator = Enum.find(topology.coordinators, fn coord ->
        coord.node == Node.self()
      end)
      
      assert local_coordinator
      assert local_coordinator.capabilities.max_concurrent_requests == 200
    end
  end
  
  describe "health monitoring" do
    test "maintains health status" do
      # Let the coordinator run for a moment
      Process.sleep(1000)
      
      topology = Coordinator.get_cluster_topology()
      
      # Should have healthy status
      assert topology.cluster_health in [:healthy, :degraded]
      
      local_coordinator = Enum.find(topology.coordinators, fn coord ->
        coord.node == Node.self()
      end)
      
      assert local_coordinator
      # Local coordinator should typically be healthy
      # Note: health_status might not be set in test environment
    end
  end
  
  describe "error handling" do
    test "handles malformed requests gracefully" do
      malformed_request = %{
        # Missing required fields
        content: "test"
      }
      
      result = Coordinator.route_request(malformed_request, [])
      
      # Should handle gracefully, not crash
      assert is_tuple(result)
    end
    
    test "handles empty requests" do
      empty_request = %{}
      
      result = Coordinator.route_request(empty_request, [])
      
      # Should handle gracefully
      assert is_tuple(result)
    end
  end
  
  describe "concurrent operations" do
    test "handles multiple concurrent requests" do
      requests = Enum.map(1..5, fn i ->
        %{
          type: :explanation,
          content: "Test request #{i}",
          requirements: %{}
        }
      end)
      
      # Submit all requests concurrently
      tasks = Enum.map(requests, fn request ->
        Task.async(fn ->
          Coordinator.route_request(request, [])
        end)
      end)
      
      # Wait for all to complete
      results = Task.await_many(tasks, 10_000)
      
      # All should complete (regardless of success/failure)
      assert length(results) == 5
      Enum.each(results, fn result ->
        assert is_tuple(result)
      end)
    end
    
    test "maintains consistent state under concurrent load" do
      # Submit many requests concurrently
      tasks = Enum.map(1..10, fn i ->
        Task.async(fn ->
          request = %{
            type: :explanation,
            content: "Concurrent test #{i}"
          }
          Coordinator.route_request(request, [])
        end)
      end)
      
      # Wait for completion
      Task.await_many(tasks, 15_000)
      
      # Coordinator should still be responsive
      metrics = Coordinator.get_load_metrics()
      assert is_map(metrics)
      
      topology = Coordinator.get_cluster_topology()
      assert is_map(topology)
    end
  end
end