defmodule Aiex.DevTools.SupervisorTest do
  use ExUnit.Case, async: false
  
  alias Aiex.DevTools.Supervisor, as: DevToolsSupervisor
  
  setup do
    # Ensure clean state
    if pid = Process.whereis(DevToolsSupervisor) do
      Supervisor.stop(pid)
    end
    
    :ok
  end
  
  describe "start_link/1" do
    test "starts successfully with default configuration" do
      {:ok, pid} = DevToolsSupervisor.start_link()
      
      assert is_pid(pid)
      assert Process.alive?(pid)
      assert Process.whereis(DevToolsSupervisor) == pid
      
      # Clean up
      Supervisor.stop(pid)
    end
    
    test "starts cluster inspector by default" do
      {:ok, _pid} = DevToolsSupervisor.start_link()
      
      # ClusterInspector should always be started
      cluster_inspector_pid = Process.whereis(Aiex.DevTools.ClusterInspector)
      assert is_pid(cluster_inspector_pid)
      assert Process.alive?(cluster_inspector_pid)
      
      # Clean up
      Supervisor.stop(DevToolsSupervisor)
    end
  end
  
  describe "status/0" do
    test "returns comprehensive status information" do
      {:ok, _pid} = DevToolsSupervisor.start_link()
      
      status = DevToolsSupervisor.status()
      
      assert is_map(status)
      assert Map.has_key?(status, :supervisor)
      assert Map.has_key?(status, :children_count)
      assert Map.has_key?(status, :components)
      assert Map.has_key?(status, :cluster_inspector)
      assert Map.has_key?(status, :debugging_console)
      assert Map.has_key?(status, :operational_docs)
      
      assert status.supervisor == DevToolsSupervisor
      assert is_integer(status.children_count)
      assert status.children_count >= 1  # At least ClusterInspector
      assert is_list(status.components)
      
      # Clean up
      Supervisor.stop(DevToolsSupervisor)
    end
    
    test "shows cluster inspector as running" do
      {:ok, _pid} = DevToolsSupervisor.start_link()
      
      status = DevToolsSupervisor.status()
      
      assert status.cluster_inspector == :running
      assert status.operational_docs == :available
      
      # Clean up
      Supervisor.stop(DevToolsSupervisor)
    end
  end
  
  describe "cluster_overview/0" do
    test "delegates to cluster inspector" do
      {:ok, _pid} = DevToolsSupervisor.start_link()
      
      overview = DevToolsSupervisor.cluster_overview()
      
      assert is_map(overview)
      assert Map.has_key?(overview, :local_node)
      assert Map.has_key?(overview, :total_nodes)
      assert Map.has_key?(overview, :cluster_health)
      
      # Clean up
      Supervisor.stop(DevToolsSupervisor)
    end
    
    test "returns error when cluster inspector not running" do
      # Don't start the supervisor
      result = DevToolsSupervisor.cluster_overview()
      
      assert result == {:error, :cluster_inspector_not_running}
    end
  end
  
  describe "quick_health_report/0" do
    test "generates health report when cluster inspector is running" do
      {:ok, _pid} = DevToolsSupervisor.start_link()
      
      report = DevToolsSupervisor.quick_health_report()
      
      assert is_map(report)
      assert Map.has_key?(report, :cluster_health)
      assert Map.has_key?(report, :nodes)
      assert Map.has_key?(report, :issues)
      assert Map.has_key?(report, :recommendations)
      
      # Clean up
      Supervisor.stop(DevToolsSupervisor)
    end
    
    test "returns error when cluster inspector not running" do
      result = DevToolsSupervisor.quick_health_report()
      
      assert result == {:error, :cluster_inspector_not_running}
    end
  end
  
  describe "generate_runbook/1" do
    test "generates runbook in markdown format by default" do
      runbook = DevToolsSupervisor.generate_runbook()
      
      assert is_binary(runbook)
      assert String.contains?(runbook, "# Aiex Operational Runbook")
      assert String.contains?(runbook, "Generated on")
    end
    
    test "generates runbook in specified format" do
      json_runbook = DevToolsSupervisor.generate_runbook(:json)
      
      assert is_binary(json_runbook)
      {:ok, parsed} = Jason.decode(json_runbook)
      assert Map.has_key?(parsed, "title")
      assert parsed["title"] == "Aiex Operational Runbook"
    end
  end
  
  describe "generate_troubleshooting_guide/1" do
    test "generates troubleshooting guide" do
      guide = DevToolsSupervisor.generate_troubleshooting_guide()
      
      assert is_binary(guide)
      assert String.contains?(guide, "# Aiex Troubleshooting Guide")
      assert String.contains?(guide, "Current Issues Detected")
    end
    
    test "generates troubleshooting guide in specified format" do
      json_guide = DevToolsSupervisor.generate_troubleshooting_guide(:json)
      
      assert is_binary(json_guide)
      {:ok, parsed} = Jason.decode(json_guide)
      assert Map.has_key?(parsed, "title")
      assert parsed["title"] == "Aiex Troubleshooting Guide"
    end
  end
  
  describe "execute_command/1" do
    test "executes command when debugging console is running" do
      # Configure to enable console
      Application.put_env(:aiex, :dev_tools, console_enabled: true)
      {:ok, _pid} = DevToolsSupervisor.start_link()
      
      # Wait a moment for console to start
      Process.sleep(100)
      
      result = DevToolsSupervisor.execute_command("help")
      
      assert is_map(result)
      assert result.type == :help
      
      # Clean up
      Application.delete_env(:aiex, :dev_tools)
      Supervisor.stop(DevToolsSupervisor)
    end
    
    test "returns error when console not running" do
      result = DevToolsSupervisor.execute_command("help")
      
      assert result == {:error, :console_not_running}
    end
  end
  
  describe "start_console/0" do
    test "starts interactive console when available" do
      # Configure to enable console
      Application.put_env(:aiex, :dev_tools, console_enabled: true)
      {:ok, _pid} = DevToolsSupervisor.start_link()
      
      # Wait a moment for console to start
      Process.sleep(100)
      
      result = DevToolsSupervisor.start_console()
      
      assert result == :ok
      
      # Clean up
      Application.delete_env(:aiex, :dev_tools)
      Supervisor.stop(DevToolsSupervisor)
    end
    
    test "returns error when console not running" do
      result = DevToolsSupervisor.start_console()
      
      assert result == {:error, :console_not_running}
    end
  end
  
  describe "configuration handling" do
    test "respects dev_tools enabled configuration" do
      # Set configuration
      Application.put_env(:aiex, :dev_tools, enabled: true, console_enabled: true)
      
      {:ok, _pid} = DevToolsSupervisor.start_link()
      
      status = DevToolsSupervisor.status()
      
      # Should have cluster inspector always
      assert status.cluster_inspector == :running
      
      # Clean up
      Application.delete_env(:aiex, :dev_tools)
      Supervisor.stop(DevToolsSupervisor)
    end
    
    test "handles missing configuration gracefully" do
      # Ensure no dev_tools config
      Application.delete_env(:aiex, :dev_tools)
      
      {:ok, _pid} = DevToolsSupervisor.start_link()
      
      status = DevToolsSupervisor.status()
      
      # Should still have cluster inspector (always started)
      assert status.cluster_inspector == :running
      
      # Clean up
      Supervisor.stop(DevToolsSupervisor)
    end
  end
  
  describe "supervision behavior" do
    test "restarts failed children" do
      {:ok, supervisor_pid} = DevToolsSupervisor.start_link()
      
      # Get the cluster inspector pid
      original_pid = Process.whereis(Aiex.DevTools.ClusterInspector)
      assert is_pid(original_pid)
      
      # Kill the cluster inspector
      Process.exit(original_pid, :kill)
      
      # Wait for restart
      Process.sleep(100)
      
      # Should be restarted with new pid
      new_pid = Process.whereis(Aiex.DevTools.ClusterInspector)
      assert is_pid(new_pid)
      assert new_pid != original_pid
      assert Process.alive?(new_pid)
      
      # Clean up
      Supervisor.stop(supervisor_pid)
    end
  end
  
  describe "integration" do
    test "all components work together" do
      {:ok, _pid} = DevToolsSupervisor.start_link()
      
      # Test cluster overview
      overview = DevToolsSupervisor.cluster_overview()
      assert is_map(overview)
      
      # Test health report
      health = DevToolsSupervisor.quick_health_report()
      assert is_map(health)
      
      # Test documentation generation
      runbook = DevToolsSupervisor.generate_runbook()
      assert is_binary(runbook)
      
      guide = DevToolsSupervisor.generate_troubleshooting_guide()
      assert is_binary(guide)
      
      # Clean up
      Supervisor.stop(DevToolsSupervisor)
    end
  end
end