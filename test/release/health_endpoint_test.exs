defmodule Aiex.Release.HealthEndpointTest do
  use ExUnit.Case, async: false
  
  alias Aiex.Release.HealthEndpoint
  
  @test_port 8091
  
  setup do
    # Stop existing health endpoint if running
    if Process.whereis(HealthEndpoint) do
      GenServer.stop(HealthEndpoint)
      Process.sleep(100)
    end
    
    # Start with test configuration
    {:ok, _pid} = HealthEndpoint.start_link(port: @test_port)
    
    # Wait for server to be ready
    Process.sleep(500)
    
    on_exit(fn ->
      if Process.whereis(HealthEndpoint) do
        GenServer.stop(HealthEndpoint)
      end
    end)
    
    :ok
  end
  
  describe "health status management" do
    test "default status is alive but not ready" do
      assert HealthEndpoint.alive? == true
      assert HealthEndpoint.ready? == false
    end
    
    test "can set readiness status" do
      HealthEndpoint.set_ready(true)
      assert HealthEndpoint.ready? == true
      
      HealthEndpoint.set_ready(false)
      assert HealthEndpoint.ready? == false
    end
    
    test "can set liveness status" do
      HealthEndpoint.set_alive(false)
      assert HealthEndpoint.alive? == false
      
      HealthEndpoint.set_alive(true)
      assert HealthEndpoint.alive? == true
    end
  end
  
  describe "health information" do
    test "gets comprehensive health info" do
      health_info = HealthEndpoint.get_health_info()
      
      assert is_map(health_info)
      assert Map.has_key?(health_info, :timestamp)
      assert Map.has_key?(health_info, :node)
      assert Map.has_key?(health_info, :ready)
      assert Map.has_key?(health_info, :alive)
      assert Map.has_key?(health_info, :uptime_ms)
      assert Map.has_key?(health_info, :version)
      assert Map.has_key?(health_info, :system)
      assert Map.has_key?(health_info, :cluster)
      
      # Check system health structure
      assert is_map(health_info.system)
      assert Map.has_key?(health_info.system, :memory)
      assert Map.has_key?(health_info.system, :processes)
      
      # Check cluster health structure
      assert is_map(health_info.cluster)
      assert Map.has_key?(health_info.cluster, :cluster_enabled)
      assert Map.has_key?(health_info.cluster, :connected_nodes)
    end
    
    test "gets health endpoint URL" do
      url = HealthEndpoint.get_health_url()
      assert url == "http://localhost:#{@test_port}"
    end
  end
  
  describe "HTTP endpoints" do
    test "health endpoint returns status" do
      # Set both ready and alive for healthy status
      HealthEndpoint.set_ready(true)
      HealthEndpoint.set_alive(true)
      
      {:ok, {status, _headers, body}} = :httpc.request("http://localhost:#{@test_port}/health")
      
      assert status == {200, 'OK'}
      
      {:ok, json} = Jason.decode(to_string(body))
      assert json["status"] == "healthy"
      assert json["ready"] == true
      assert json["alive"] == true
    end
    
    test "health endpoint returns unhealthy when not ready" do
      HealthEndpoint.set_ready(false)
      HealthEndpoint.set_alive(true)
      
      {:ok, {status, _headers, body}} = :httpc.request("http://localhost:#{@test_port}/health")
      
      assert status == {503, 'Service Unavailable'}
      
      {:ok, json} = Jason.decode(to_string(body))
      assert json["status"] == "unhealthy"
      assert json["ready"] == false
      assert json["alive"] == true
    end
    
    test "readiness endpoint" do
      HealthEndpoint.set_ready(true)
      
      {:ok, {status, _headers, body}} = :httpc.request("http://localhost:#{@test_port}/health/ready")
      
      assert status == {200, 'OK'}
      
      {:ok, json} = Jason.decode(to_string(body))
      assert json["status"] == "ready"
    end
    
    test "liveness endpoint" do
      HealthEndpoint.set_alive(true)
      
      {:ok, {status, _headers, body}} = :httpc.request("http://localhost:#{@test_port}/health/live")
      
      assert status == {200, 'OK'}
      
      {:ok, json} = Jason.decode(to_string(body))
      assert json["status"] == "alive"
    end
    
    test "detailed health endpoint" do
      HealthEndpoint.set_ready(true)
      HealthEndpoint.set_alive(true)
      
      {:ok, {status, _headers, body}} = :httpc.request("http://localhost:#{@test_port}/health/detailed")
      
      assert status == {200, 'OK'}
      
      {:ok, json} = Jason.decode(to_string(body))
      assert Map.has_key?(json, "timestamp")
      assert Map.has_key?(json, "node")
      assert Map.has_key?(json, "system")
      assert Map.has_key?(json, "cluster")
    end
    
    test "health metrics endpoint returns Prometheus format" do
      {:ok, {status, _headers, body}} = :httpc.request("http://localhost:#{@test_port}/metrics/health")
      
      assert status == {200, 'OK'}
      body_str = to_string(body)
      
      assert String.contains?(body_str, "# HELP")
      assert String.contains?(body_str, "# TYPE")
      assert String.contains?(body_str, "aiex_health_ready")
      assert String.contains?(body_str, "aiex_health_alive")
      assert String.contains?(body_str, "aiex_uptime_seconds")
    end
    
    test "unknown endpoint returns 404" do
      {:ok, {status, _headers, _body}} = :httpc.request("http://localhost:#{@test_port}/unknown")
      
      assert status == {404, 'Not Found'}
    end
  end
end