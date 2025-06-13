defmodule Aiex.Performance.DistributedAnalyzerTest do
  use ExUnit.Case, async: false
  
  alias Aiex.Performance.DistributedAnalyzer

  setup do
    # Ensure clean state
    :ok
  end

  describe "distributed analyzer" do
    test "starts successfully" do
      assert {:ok, pid} = DistributedAnalyzer.start_link()
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "performs local node analysis" do
      result = DistributedAnalyzer.local_node_analysis()
      
      assert %{memory: memory, processes: processes, system: system} = result
      assert is_map(memory)
      assert is_map(processes)
      assert is_map(system)
      
      # Check memory stats
      assert memory.total > 0
      assert memory.processes > 0
      
      # Check process stats
      assert processes.count > 0
      assert processes.limit > 0
      assert is_list(processes.memory_hogs)
    end

    test "analyzes cluster with single node" do
      {:ok, pid} = DistributedAnalyzer.start_link()
      
      {:ok, metrics} = DistributedAnalyzer.analyze_cluster()
      
      assert is_map(metrics)
      assert Map.has_key?(metrics, node())
      assert is_map(metrics[node()])
      
      GenServer.stop(pid)
    end

    test "finds hot processes" do
      {:ok, pid} = DistributedAnalyzer.start_link()
      
      # Create some test processes with different resource usage
      test_procs = for i <- 1..5 do
        spawn(fn ->
          # Create some memory usage
          _data = :binary.copy(<<0>>, i * 1000)
          receive do
            :stop -> :ok
          end
        end)
      end
      
      {:ok, hot_procs} = DistributedAnalyzer.find_hot_processes(3)
      
      assert is_list(hot_procs)
      assert length(hot_procs) <= 3
      
      # Cleanup
      Enum.each(test_procs, &send(&1, :stop))
      GenServer.stop(pid)
    end

    test "performs memory analysis" do
      {:ok, pid} = DistributedAnalyzer.start_link()
      
      {:ok, analysis} = DistributedAnalyzer.analyze_memory()
      
      assert %{timestamp: _, nodes: nodes, total_cluster_memory: _} = analysis
      assert is_map(nodes)
      assert Map.has_key?(nodes, node())
      
      GenServer.stop(pid)
    end

    test "performs GC analysis" do
      {:ok, pid} = DistributedAnalyzer.start_link()
      
      {:ok, gc_analysis} = DistributedAnalyzer.analyze_gc()
      
      assert %{timestamp: _, nodes: nodes, recommendations: recs} = gc_analysis
      assert is_map(nodes)
      assert is_list(recs)
      
      GenServer.stop(pid)
    end

    test "gets process info for valid pid" do
      {:ok, pid} = DistributedAnalyzer.start_link()
      
      {:ok, info} = DistributedAnalyzer.process_info(self())
      
      assert is_map(info)
      assert Map.has_key?(info, :status)
      assert Map.has_key?(info, :current_function)
      
      GenServer.stop(pid)
    end

    test "handles process info for invalid pid" do
      {:ok, pid} = DistributedAnalyzer.start_link()
      
      # Create and kill a process
      test_pid = spawn(fn -> :ok end)
      Process.sleep(10)
      
      {:ok, info} = DistributedAnalyzer.process_info(test_pid)
      assert %{error: "Process not found"} = info
      
      GenServer.stop(pid)
    end

    test "periodic analysis runs automatically" do
      {:ok, pid} = DistributedAnalyzer.start_link()
      
      # Should have empty metrics initially
      {:ok, initial_metrics} = DistributedAnalyzer.get_metrics()
      assert initial_metrics == %{}
      
      # Wait for periodic analysis (using a shorter interval for testing)
      send(pid, :periodic_analysis)
      Process.sleep(100)
      
      # Metrics should be populated after periodic analysis
      {:ok, updated_metrics} = DistributedAnalyzer.get_metrics()
      assert map_size(updated_metrics) > 0
      
      GenServer.stop(pid)
    end
  end

  describe "hot process detection" do
    test "identifies processes with high memory usage" do
      # Create a process with significant memory
      memory_hog = spawn(fn ->
        # Allocate ~10MB
        _data = :binary.copy(<<0>>, 10_000_000)
        receive do
          :stop -> :ok
        end
      end)
      
      Process.sleep(100)
      
      hot_procs = DistributedAnalyzer.local_hot_processes(5)
      
      # Should find our memory hog
      assert Enum.any?(hot_procs, fn {pid, info} ->
        pid == memory_hog and Keyword.get(info, :type) == :memory
      end)
      
      send(memory_hog, :stop)
    end

    test "identifies processes with large message queues" do
      # Create a process with a large message queue
      queue_hog = spawn(fn ->
        receive do
          :stop -> :ok
        after
          60_000 -> :ok
        end
      end)
      
      # Fill its message queue
      for i <- 1..1000, do: send(queue_hog, {:message, i})
      
      Process.sleep(100)
      
      hot_procs = DistributedAnalyzer.local_hot_processes(5)
      
      # Should find our queue hog
      assert Enum.any?(hot_procs, fn {pid, info} ->
        pid == queue_hog and Keyword.get(info, :type) == :queue
      end)
      
      send(queue_hog, :stop)
    end
  end

  describe "scheduler analysis" do
    test "gets scheduler statistics" do
      {:ok, pid} = DistributedAnalyzer.start_link()
      
      {:ok, metrics} = DistributedAnalyzer.analyze_cluster()
      node_data = metrics[node()]
      
      assert Map.has_key?(node_data, :schedulers)
      schedulers = node_data.schedulers
      
      # Should have data for each scheduler
      assert map_size(schedulers) == :erlang.system_info(:logical_processors)
      
      # Each scheduler should have usage between 0 and 1
      Enum.each(schedulers, fn {_id, usage} ->
        assert usage >= 0.0 and usage <= 1.0
      end)
      
      GenServer.stop(pid)
    end
  end
end