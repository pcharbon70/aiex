defmodule Aiex.Release.DistributedReleaseTest do
  use ExUnit.Case, async: false
  
  alias Aiex.Release.DistributedRelease
  
  setup do
    # Stop existing release manager if running
    if Process.whereis(DistributedRelease) do
      GenServer.stop(DistributedRelease)
      Process.sleep(50)
    end
    
    # Start with test configuration
    {:ok, _pid} = DistributedRelease.start_link()
    
    on_exit(fn ->
      if Process.whereis(DistributedRelease) do
        GenServer.stop(DistributedRelease)
      end
    end)
    
    :ok
  end
  
  describe "version management" do
    test "gets current version" do
      version = DistributedRelease.get_version()
      assert is_binary(version)
      assert String.length(version) > 0
    end
    
    test "gets cluster status" do
      status = DistributedRelease.get_cluster_status()
      
      assert is_map(status)
      assert Map.has_key?(status, :local_version)
      assert Map.has_key?(status, :cluster_state)
      assert Map.has_key?(status, :node_versions)
      assert Map.has_key?(status, :update_in_progress)
    end
  end
  
  describe "health checks" do
    test "performs comprehensive health check" do
      result = DistributedRelease.health_check()
      
      assert is_map(result)
      assert Map.has_key?(result, :status)
      assert Map.has_key?(result, :checks)
      assert Map.has_key?(result, :duration_us)
      assert Map.has_key?(result, :timestamp)
      assert Map.has_key?(result, :node)
      assert Map.has_key?(result, :version)
      
      assert result.status in [:healthy, :unhealthy]
      assert is_integer(result.duration_us)
      assert result.duration_us > 0
    end
    
    test "registers custom health check" do
      custom_check = fn -> :ok end
      
      result = DistributedRelease.register_health_check(:custom_test, custom_check)
      assert result == :ok
      
      health_result = DistributedRelease.health_check()
      assert Map.has_key?(health_result.checks, :custom_test)
      assert health_result.checks[:custom_test] == :ok
    end
  end
  
  describe "deployment readiness" do
    test "checks deployment readiness" do
      ready = DistributedRelease.ready_for_deployment?()
      assert is_boolean(ready)
    end
  end
  
  describe "rolling updates" do
    test "starts rolling update" do
      new_version = "test-version-#{System.system_time()}"
      
      # This should work in test environment
      result = DistributedRelease.start_rolling_update(new_version, :gradual)
      assert result == :ok
      
      # Check update status
      status = DistributedRelease.get_update_status()
      assert status.in_progress == true
      
      # Wait a bit for the simulated update to complete
      Process.sleep(6000)
      
      # Check final status
      final_status = DistributedRelease.get_update_status()
      assert final_status.in_progress == false
    end
    
    test "prevents concurrent updates" do
      new_version = "test-version-#{System.system_time()}"
      
      # Start first update
      result1 = DistributedRelease.start_rolling_update(new_version, :immediate)
      assert result1 == :ok
      
      # Try to start second update
      result2 = DistributedRelease.start_rolling_update("another-version", :immediate)
      assert result2 == {:error, :update_in_progress}
    end
  end
  
  describe "rollback functionality" do
    test "rollback without previous update fails" do
      result = DistributedRelease.rollback()
      assert result == {:error, :no_rollback_data}
    end
    
    test "rollback after update works" do
      new_version = "test-version-#{System.system_time()}"
      
      # Start update to create rollback data
      DistributedRelease.start_rolling_update(new_version, :immediate)
      
      # Wait for update to complete
      Process.sleep(2000)
      
      # Attempt rollback
      result = DistributedRelease.rollback()
      assert result == :ok
    end
  end
end