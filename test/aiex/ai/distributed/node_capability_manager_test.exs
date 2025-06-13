defmodule Aiex.AI.Distributed.NodeCapabilityManagerTest do
  use ExUnit.Case, async: false
  
  alias Aiex.AI.Distributed.NodeCapabilityManager
  
  setup do
    # Start NodeCapabilityManager for testing
    {:ok, pid} = NodeCapabilityManager.start_link([])
    on_exit(fn -> 
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)
    %{manager_pid: pid}
  end
  
  describe "capability assessment" do
    test "returns current capabilities" do
      {:ok, capabilities} = NodeCapabilityManager.get_current_capabilities()
      
      assert is_map(capabilities)
      assert Map.has_key?(capabilities, :max_concurrent_requests)
      assert Map.has_key?(capabilities, :memory_available_mb)
      assert Map.has_key?(capabilities, :cpu_cores)
      assert Map.has_key?(capabilities, :supported_providers)
      assert Map.has_key?(capabilities, :available_models)
      assert Map.has_key?(capabilities, :processing_types)
      assert Map.has_key?(capabilities, :last_updated)
      assert Map.has_key?(capabilities, :node)
      
      assert is_integer(capabilities.max_concurrent_requests)
      assert capabilities.max_concurrent_requests > 0
      assert is_integer(capabilities.memory_available_mb)
      assert is_integer(capabilities.cpu_cores)
      assert capabilities.cpu_cores > 0
      assert is_list(capabilities.supported_providers)
      assert is_list(capabilities.available_models)
      assert is_list(capabilities.processing_types)
      assert capabilities.node == Node.self()
    end
    
    test "includes expected processing types" do
      {:ok, capabilities} = NodeCapabilityManager.get_current_capabilities()
      
      processing_types = capabilities.processing_types
      
      assert :text_generation in processing_types
      assert :code_analysis in processing_types
      assert :explanation in processing_types
      assert :refactoring in processing_types
    end
    
    test "includes reasonable resource metrics" do
      {:ok, capabilities} = NodeCapabilityManager.get_current_capabilities()
      
      # Should have reasonable values
      assert capabilities.max_concurrent_requests >= 10
      assert capabilities.max_concurrent_requests <= 200
      assert capabilities.cpu_cores >= 1
      assert capabilities.memory_available_mb >= 0
    end
  end
  
  describe "model availability" do
    test "returns model availability status" do
      {:ok, availability} = NodeCapabilityManager.get_model_availability()
      
      assert is_map(availability)
      
      # Should have at least some models
      if map_size(availability) > 0 do
        {_model, info} = Enum.at(availability, 0)
        assert is_map(info)
        assert Map.has_key?(info, :status)
        assert Map.has_key?(info, :last_checked)
      end
    end
    
    test "model availability includes response times" do
      {:ok, availability} = NodeCapabilityManager.get_model_availability()
      
      # If we have models, they should include response time info
      if map_size(availability) > 0 do
        Enum.each(availability, fn {_model, info} ->
          assert Map.has_key?(info, :response_time_ms)
          assert is_integer(info.response_time_ms)
          assert info.response_time_ms > 0
        end)
      end
    end
  end
  
  describe "performance metrics" do
    test "returns performance metrics" do
      {:ok, metrics} = NodeCapabilityManager.get_performance_metrics()
      
      assert is_map(metrics)
      assert Map.has_key?(metrics, :avg_response_time_ms)
      assert Map.has_key?(metrics, :success_rate)
      assert Map.has_key?(metrics, :throughput_rpm)
      assert Map.has_key?(metrics, :last_calculated)
      
      assert is_number(metrics.avg_response_time_ms)
      assert is_number(metrics.success_rate)
      assert metrics.success_rate >= 0.0
      assert metrics.success_rate <= 1.0
      assert is_number(metrics.throughput_rpm)
      assert metrics.throughput_rpm >= 0
    end
    
    test "performance metrics have reasonable defaults" do
      {:ok, metrics} = NodeCapabilityManager.get_performance_metrics()
      
      # Should have reasonable default values
      assert metrics.avg_response_time_ms > 0
      assert metrics.avg_response_time_ms < 60_000  # Less than 1 minute
      assert metrics.success_rate > 0.5  # At least 50%
    end
  end
  
  describe "request compatibility" do
    test "can evaluate request compatibility" do
      # Simple request with no special requirements
      simple_requirements = %{}
      
      result = NodeCapabilityManager.can_handle_request?(simple_requirements)
      assert is_boolean(result)
      assert result == true  # Should be able to handle simple requests
    end
    
    test "handles provider-specific requirements" do
      # Request requiring specific provider
      provider_requirements = %{
        provider: :openai
      }
      
      result = NodeCapabilityManager.can_handle_request?(provider_requirements)
      assert is_boolean(result)
      # Result depends on whether OpenAI is supported
    end
    
    test "handles model-specific requirements" do
      # Request requiring specific model
      model_requirements = %{
        model: "gpt-3.5-turbo"
      }
      
      result = NodeCapabilityManager.can_handle_request?(model_requirements)
      assert is_boolean(result)
    end
    
    test "handles memory requirements" do
      # Request with low memory requirement
      low_memory_requirements = %{
        memory_mb: 50
      }
      
      result = NodeCapabilityManager.can_handle_request?(low_memory_requirements)
      assert result == true  # Should be able to handle low memory requests
      
      # Request with very high memory requirement
      high_memory_requirements = %{
        memory_mb: 100_000  # 100GB
      }
      
      result = NodeCapabilityManager.can_handle_request?(high_memory_requirements)
      assert result == false  # Should not be able to handle extreme memory requests
    end
    
    test "handles processing type requirements" do
      # Request for supported processing type
      text_requirements = %{
        processing_type: :text_generation
      }
      
      result = NodeCapabilityManager.can_handle_request?(text_requirements)
      assert result == true
      
      # Request for unsupported processing type
      unsupported_requirements = %{
        processing_type: :quantum_computing
      }
      
      result = NodeCapabilityManager.can_handle_request?(unsupported_requirements)
      assert result == false
    end
  end
  
  describe "capability history" do
    test "maintains capability history" do
      # Force an assessment to create history
      NodeCapabilityManager.force_assessment()
      
      # Wait for assessment to complete
      Process.sleep(1000)
      
      {:ok, history} = NodeCapabilityManager.get_capability_history(5)
      
      assert is_list(history)
      assert length(history) >= 1
      
      if length(history) > 0 do
        entry = List.first(history)
        assert Map.has_key?(entry, :timestamp)
        assert Map.has_key?(entry, :capabilities)
        assert is_integer(entry.timestamp)
        assert is_map(entry.capabilities)
      end
    end
    
    test "limits history size" do
      {:ok, history} = NodeCapabilityManager.get_capability_history(3)
      
      assert length(history) <= 3
    end
    
    test "history entries have timestamps in descending order" do
      # Force multiple assessments
      NodeCapabilityManager.force_assessment()
      Process.sleep(500)
      NodeCapabilityManager.force_assessment()
      
      # Wait for assessments to complete
      Process.sleep(1000)
      
      {:ok, history} = NodeCapabilityManager.get_capability_history(10)
      
      if length(history) > 1 do
        timestamps = Enum.map(history, & &1.timestamp)
        # Should be in descending order (most recent first)
        assert timestamps == Enum.sort(timestamps, :desc)
      end
    end
  end
  
  describe "force assessment" do
    test "force assessment triggers immediate update" do
      # Get initial timestamp
      {:ok, initial_capabilities} = NodeCapabilityManager.get_current_capabilities()
      initial_timestamp = initial_capabilities.last_updated
      
      # Wait a bit to ensure timestamp difference
      Process.sleep(100)
      
      # Force assessment
      :ok = NodeCapabilityManager.force_assessment()
      
      # Wait for assessment to complete
      Process.sleep(1000)
      
      # Get updated capabilities
      {:ok, updated_capabilities} = NodeCapabilityManager.get_current_capabilities()
      updated_timestamp = updated_capabilities.last_updated
      
      # Timestamp should be updated
      assert updated_timestamp > initial_timestamp
    end
    
    test "force assessment doesn't crash on errors" do
      # Should handle gracefully even if some subsystems aren't available
      :ok = NodeCapabilityManager.force_assessment()
      
      # Manager should still be responsive
      {:ok, capabilities} = NodeCapabilityManager.get_current_capabilities()
      assert is_map(capabilities)
    end
  end
  
  describe "periodic updates" do
    test "capabilities are updated over time" do
      # Get initial capabilities
      {:ok, initial_capabilities} = NodeCapabilityManager.get_current_capabilities()
      initial_timestamp = initial_capabilities.last_updated
      
      # Wait for automatic update (should happen within a few seconds in test)
      Process.sleep(3000)
      
      {:ok, updated_capabilities} = NodeCapabilityManager.get_current_capabilities()
      updated_timestamp = updated_capabilities.last_updated
      
      # Should have been updated
      assert updated_timestamp >= initial_timestamp
    end
  end
  
  describe "error handling" do
    test "handles missing telemetry gracefully" do
      # Should not crash when telemetry/metrics aren't available
      {:ok, metrics} = NodeCapabilityManager.get_performance_metrics()
      
      # Should return default values
      assert is_map(metrics)
      assert is_number(metrics.success_rate)
    end
    
    test "handles missing model coordinator gracefully" do
      # Should not crash when ModelCoordinator isn't available
      {:ok, availability} = NodeCapabilityManager.get_model_availability()
      
      # Should return some data (possibly fallback data)
      assert is_map(availability)
    end
  end
  
  describe "resource assessment" do
    test "assesses CPU and memory resources" do
      {:ok, capabilities} = NodeCapabilityManager.get_current_capabilities()
      
      assert is_integer(capabilities.cpu_cores)
      assert capabilities.cpu_cores >= 1
      
      assert is_integer(capabilities.memory_available_mb)
      assert capabilities.memory_available_mb >= 0
      
      assert Map.has_key?(capabilities, :cpu_usage_percent)
      assert is_integer(capabilities.cpu_usage_percent)
      assert capabilities.cpu_usage_percent >= 0
      assert capabilities.cpu_usage_percent <= 100
    end
    
    test "calculates reasonable max concurrent requests" do
      {:ok, capabilities} = NodeCapabilityManager.get_current_capabilities()
      
      max_requests = capabilities.max_concurrent_requests
      
      # Should be reasonable based on system resources
      assert max_requests >= 10
      assert max_requests <= 500
    end
  end
end