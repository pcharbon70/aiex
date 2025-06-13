defmodule Aiex.Telemetry.DistributedAggregatorTest do
  use ExUnit.Case, async: false
  
  alias Aiex.Telemetry.DistributedAggregator
  
  setup do
    # Stop existing aggregator if running
    if Process.whereis(DistributedAggregator) do
      GenServer.stop(DistributedAggregator)
      Process.sleep(50)
    end
    
    # Start the aggregator with test configuration
    {:ok, _pid} = DistributedAggregator.start_link(node_id: :test_node)
    
    on_exit(fn ->
      if Process.whereis(DistributedAggregator) do
        GenServer.stop(DistributedAggregator)
      end
    end)
    
    :ok
  end
  
  describe "metric recording" do
    test "records metrics with metadata" do
      DistributedAggregator.record_metric("test.counter", 1, %{type: "test"})
      DistributedAggregator.record_metric("test.counter", 2, %{type: "test"})
      
      # Allow time for processing
      Process.sleep(100)
      
      {:ok, metrics} = DistributedAggregator.get_node_metrics()
      
      assert length(metrics) == 2
      assert Enum.all?(metrics, &(&1.key == "test.counter"))
      assert Enum.map(metrics, & &1.value) == [1, 2]
    end
    
    test "includes node information in metadata" do
      DistributedAggregator.record_metric("test.metric", 42)
      
      Process.sleep(100)
      
      {:ok, metrics} = DistributedAggregator.get_node_metrics()
      
      assert length(metrics) == 1
      metric = List.first(metrics)
      assert metric.metadata.node == Node.self()
    end
  end
  
  describe "cluster metrics aggregation" do
    test "aggregates metrics from local node" do
      # Record multiple values for the same metric
      DistributedAggregator.record_metric("test.aggregation", 10)
      DistributedAggregator.record_metric("test.aggregation", 20)
      DistributedAggregator.record_metric("test.aggregation", 30)
      
      # Force update
      DistributedAggregator.sync_cluster_metrics()
      Process.sleep(200)
      
      {:ok, cluster_metrics} = DistributedAggregator.get_cluster_metrics()
      
      aggregated = Map.get(cluster_metrics, "test.aggregation")
      assert aggregated.count == 3
      assert aggregated.sum == 60
      assert aggregated.avg == 20.0
      assert aggregated.min == 10
      assert aggregated.max == 30
    end
  end
  
  describe "metric history" do
    test "retrieves metric history for a key" do
      # Record metrics over time
      DistributedAggregator.record_metric("test.history", 1)
      Process.sleep(50)
      DistributedAggregator.record_metric("test.history", 2)
      Process.sleep(50)
      DistributedAggregator.record_metric("test.history", 3)
      
      {:ok, history} = DistributedAggregator.get_metric_history("test.history", 60_000)
      
      assert length(history) == 3
      assert Enum.map(history, & &1.value) == [1, 2, 3]
      
      # Check timestamps are ordered
      timestamps = Enum.map(history, & &1.timestamp)
      assert timestamps == Enum.sort(timestamps)
    end
    
    test "filters history by duration" do
      DistributedAggregator.record_metric("test.duration", 1)
      
      # Get very short history (should be empty due to timing)
      {:ok, short_history} = DistributedAggregator.get_metric_history("test.duration", 1)
      
      # Get longer history (should include the metric)
      {:ok, long_history} = DistributedAggregator.get_metric_history("test.duration", 60_000)
      
      assert length(long_history) >= 1
    end
  end
end