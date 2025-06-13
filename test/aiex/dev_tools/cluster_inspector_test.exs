defmodule Aiex.DevTools.ClusterInspectorTest do
  use ExUnit.Case, async: false
  
  alias Aiex.DevTools.ClusterInspector
  
  setup do
    # Start ClusterInspector for testing
    {:ok, pid} = ClusterInspector.start_link([])
    on_exit(fn -> Process.exit(pid, :normal) end)
    :ok
  end
  
  describe "cluster_overview/0" do
    test "returns cluster overview with basic information" do
      overview = ClusterInspector.cluster_overview()
      
      assert is_map(overview)
      assert Map.has_key?(overview, :timestamp)
      assert Map.has_key?(overview, :local_node)
      assert Map.has_key?(overview, :total_nodes)
      assert Map.has_key?(overview, :cluster_health)
      assert Map.has_key?(overview, :system_overview)
      
      assert overview.local_node == Node.self()
      assert overview.total_nodes >= 1
      assert overview.cluster_health in [:healthy, :degraded, :critical]
    end
    
    test "includes system overview with metrics" do
      overview = ClusterInspector.cluster_overview()
      system = overview.system_overview
      
      assert is_integer(system.total_processes)
      assert is_integer(system.total_memory_mb)
      assert is_integer(system.total_ets_tables)
      assert system.total_processes > 0
      assert system.total_memory_mb > 0
    end
  end
  
  describe "inspect_node/1" do
    test "inspects local node successfully" do
      inspection = ClusterInspector.inspect_node()
      
      assert is_map(inspection)
      assert inspection.node == Node.self()
      assert inspection.status == :connected
      assert Map.has_key?(inspection, :system_info)
      assert Map.has_key?(inspection, :processes)
      assert Map.has_key?(inspection, :memory_breakdown)
    end
    
    test "handles non-existent node gracefully" do
      fake_node = :"nonexistent@localhost"
      inspection = ClusterInspector.inspect_node(fake_node)
      
      assert is_map(inspection)
      assert inspection.node == fake_node
      assert inspection.status == :disconnected
    end
  end
  
  describe "process_distribution/0" do
    test "returns process distribution across nodes" do
      distribution = ClusterInspector.process_distribution()
      
      assert is_map(distribution)
      assert Map.has_key?(distribution, :nodes)
      assert Map.has_key?(distribution, :total_processes)
      assert Map.has_key?(distribution, :distribution_balance)
      
      assert is_list(distribution.nodes)
      assert length(distribution.nodes) >= 1
      assert is_integer(distribution.total_processes)
      assert distribution.total_processes > 0
    end
    
    test "calculates distribution balance" do
      distribution = ClusterInspector.process_distribution()
      
      assert is_float(distribution.distribution_balance)
      assert distribution.distribution_balance >= 0.0
      assert distribution.distribution_balance <= 1.0
    end
  end
  
  describe "memory_analysis/0" do
    test "analyzes memory usage across cluster" do
      analysis = ClusterInspector.memory_analysis()
      
      assert is_map(analysis)
      assert Map.has_key?(analysis, :nodes)
      assert Map.has_key?(analysis, :cluster_total_mb)
      assert Map.has_key?(analysis, :memory_distribution)
      
      assert is_list(analysis.nodes)
      assert is_integer(analysis.cluster_total_mb)
      assert analysis.cluster_total_mb > 0
    end
    
    test "includes per-node memory breakdown" do
      analysis = ClusterInspector.memory_analysis()
      
      node_data = List.first(analysis.nodes)
      assert Map.has_key?(node_data, :node)
      assert Map.has_key?(node_data, :total_mb)
      assert Map.has_key?(node_data, :processes_mb)
      assert Map.has_key?(node_data, :system_mb)
    end
  end
  
  describe "hot_processes/1" do
    test "returns hot processes with default limit" do
      result = ClusterInspector.hot_processes()
      
      assert is_map(result)
      assert Map.has_key?(result, :limit)
      assert Map.has_key?(result, :hot_processes)
      assert result.limit == 10
      assert is_list(result.hot_processes)
    end
    
    test "respects custom limit" do
      result = ClusterInspector.hot_processes(5)
      
      assert result.limit == 5
      assert length(result.hot_processes) <= 5
    end
  end
  
  describe "health_report/0" do
    test "generates comprehensive health report" do
      report = ClusterInspector.health_report()
      
      assert is_map(report)
      assert Map.has_key?(report, :cluster_health)
      assert Map.has_key?(report, :nodes)
      assert Map.has_key?(report, :issues)
      assert Map.has_key?(report, :recommendations)
      assert Map.has_key?(report, :summary)
      
      assert report.cluster_health in [:healthy, :degraded, :critical]
      assert is_list(report.issues)
      assert is_list(report.recommendations)
    end
    
    test "provides actionable recommendations" do
      report = ClusterInspector.health_report()
      
      assert is_list(report.recommendations)
      assert length(report.recommendations) > 0
      
      # Should have at least one recommendation
      first_recommendation = List.first(report.recommendations)
      assert is_binary(first_recommendation)
      assert String.length(first_recommendation) > 0
    end
  end
  
  describe "find_processes/1" do
    test "finds processes by pattern" do
      result = ClusterInspector.find_processes("Supervisor")
      
      assert is_map(result)
      assert Map.has_key?(result, :pattern)
      assert Map.has_key?(result, :matches)
      assert Map.has_key?(result, :processes)
      
      assert result.pattern == "Supervisor"
      assert is_integer(result.matches)
      assert is_list(result.processes)
    end
    
    test "returns empty list for non-matching pattern" do
      result = ClusterInspector.find_processes("NonExistentPattern12345")
      
      assert result.matches == 0
      assert result.processes == []
    end
  end
  
  describe "test_coordination/0" do
    test "tests cluster coordination features" do
      result = ClusterInspector.test_coordination()
      
      assert is_map(result)
      assert Map.has_key?(result, :nodes_tested)
      assert Map.has_key?(result, :tests)
      assert Map.has_key?(result, :overall_status)
      
      assert is_list(result.nodes_tested)
      assert is_list(result.tests)
      assert result.overall_status in [:ok, :error]
    end
    
    test "includes specific test results" do
      result = ClusterInspector.test_coordination()
      
      test_names = Enum.map(result.tests, fn {name, _} -> name end)
      assert "pg groups" in test_names
      assert "distributed calls" in test_names
      assert "event bus" in test_names
      assert "telemetry aggregation" in test_names
    end
  end
end