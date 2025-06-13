defmodule Aiex.Telemetry.DistributedAggregator do
  @moduledoc """
  Distributed telemetry aggregation using pg process groups.
  
  Collects and aggregates metrics from all nodes in the cluster for centralized monitoring.
  Uses pg process groups for coordination and ensures data consistency across the cluster.
  """
  
  use GenServer
  require Logger
  
  alias Aiex.Events.EventBus
  
  @group_name :aiex_telemetry_aggregators
  @metrics_update_interval 5_000
  @retention_period_ms 300_000  # 5 minutes
  
  defstruct [
    :node_id,
    :metrics_ets,
    :aggregated_ets,
    :timer_ref,
    last_update: nil,
    peer_nodes: MapSet.new()
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc "Record a metric value on this node"
  def record_metric(key, value, metadata \\ %{}) do
    timestamp = System.system_time(:millisecond)
    metric = %{
      key: key,
      value: value,
      metadata: Map.merge(metadata, %{node: Node.self()}),
      timestamp: timestamp
    }
    
    GenServer.cast(__MODULE__, {:record_metric, metric})
  end
  
  @doc "Get current metrics for this node"
  def get_node_metrics(node \\ Node.self()) do
    GenServer.call(__MODULE__, {:get_node_metrics, node})
  end
  
  @doc "Get aggregated metrics across all nodes"
  def get_cluster_metrics do
    GenServer.call(__MODULE__, :get_cluster_metrics)
  end
  
  @doc "Get all metrics for a specific key across the cluster"
  def get_metric_history(key, duration_ms \\ 60_000) do
    GenServer.call(__MODULE__, {:get_metric_history, key, duration_ms})
  end
  
  @doc "Force a metrics sync across the cluster"
  def sync_cluster_metrics do
    GenServer.cast(__MODULE__, :sync_cluster_metrics)
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    node_id = Keyword.get(opts, :node_id, Node.self())
    
    # Create ETS tables
    metrics_ets = :ets.new(:node_metrics, [:ordered_set, :private])
    aggregated_ets = :ets.new(:aggregated_metrics, [:set, :private])
    
    # Join the telemetry process group
    if Process.whereis(:pg) do
      :pg.join(@group_name, self())
    end
    
    # Schedule periodic metrics update
    timer_ref = Process.send_after(self(), :update_metrics, @metrics_update_interval)
    
    state = %__MODULE__{
      node_id: node_id,
      metrics_ets: metrics_ets,
      aggregated_ets: aggregated_ets,
      timer_ref: timer_ref,
      last_update: System.system_time(:millisecond)
    }
    
    Logger.info("Distributed telemetry aggregator started on node #{node_id}")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:get_node_metrics, node}, _from, state) do
    metrics = get_metrics_for_node(state.metrics_ets, node)
    {:reply, {:ok, metrics}, state}
  end
  
  def handle_call(:get_cluster_metrics, _from, state) do
    # Get aggregated metrics from ETS
    aggregated = :ets.tab2list(state.aggregated_ets)
    |> Enum.into(%{})
    
    {:reply, {:ok, aggregated}, state}
  end
  
  def handle_call({:get_metric_history, key, duration_ms}, _from, state) do
    cutoff_time = System.system_time(:millisecond) - duration_ms
    
    history = :ets.select(state.metrics_ets, [
      {{:"$1", :"$2"}, 
       [{:andalso, {:>=, {:map_get, :timestamp, :"$2"}, cutoff_time},
                  {:==, {:map_get, :key, :"$2"}, key}}],
       [:"$2"]}
    ])
    |> Enum.sort_by(& &1.timestamp)
    
    {:reply, {:ok, history}, state}
  end
  
  @impl true
  def handle_cast({:record_metric, metric}, state) do
    # Store metric with timestamp as key for ordering
    key = {metric.timestamp, make_ref()}
    :ets.insert(state.metrics_ets, {key, metric})
    
    # Publish metric event
    EventBus.publish("telemetry:metric_recorded", %{
      node: state.node_id,
      metric: metric
    })
    
    {:noreply, state}
  end
  
  def handle_cast(:sync_cluster_metrics, state) do
    # Force immediate sync
    send(self(), :update_metrics)
    {:noreply, state}
  end
  
  def handle_cast({:sync_metrics_from_node, node, metrics}, state) do
    # Store metrics from another node
    Enum.each(metrics, fn metric ->
      key = {metric.timestamp, make_ref()}
      :ets.insert(state.metrics_ets, {key, metric})
    end)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:update_metrics, state) do
    # Clean up old metrics
    state = cleanup_old_metrics(state)
    
    # Sync with other nodes
    state = sync_with_cluster(state)
    
    # Update aggregated metrics
    state = update_aggregated_metrics(state)
    
    # Schedule next update
    timer_ref = Process.send_after(self(), :update_metrics, @metrics_update_interval)
    
    {:noreply, %{state | timer_ref: timer_ref, last_update: System.system_time(:millisecond)}}
  end
  
  @impl true
  def terminate(_reason, state) do
    # Leave the process group
    if Process.whereis(:pg) do
      :pg.leave(@group_name, self())
    end
    
    # Cancel timer
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end
    
    # Clean up ETS tables
    :ets.delete(state.metrics_ets)
    :ets.delete(state.aggregated_ets)
    
    :ok
  end
  
  # Private functions
  
  defp cleanup_old_metrics(state) do
    cutoff_time = System.system_time(:millisecond) - @retention_period_ms
    
    # Remove old metrics
    :ets.select_delete(state.metrics_ets, [
      {{:"$1", :"$2"}, 
       [{:<, {:map_get, :timestamp, :"$2"}, cutoff_time}],
       [true]}
    ])
    
    state
  end
  
  defp sync_with_cluster(state) do
    if Process.whereis(:pg) do
      # Get all aggregator processes in the cluster
      aggregators = :pg.get_members(@group_name)
      |> Enum.reject(&(&1 == self()))
      
      # Get recent metrics from this node to share
      recent_cutoff = System.system_time(:millisecond) - @metrics_update_interval
      recent_metrics = :ets.select(state.metrics_ets, [
        {{:"$1", :"$2"}, 
         [{:andalso, {:>=, {:map_get, :timestamp, :"$2"}, recent_cutoff},
                    {:==, {:map_get, :node, {:map_get, :metadata, :"$2"}}, Node.self()}}],
         [:"$2"]}
      ])
      
      # Send metrics to other aggregators
      Enum.each(aggregators, fn pid ->
        GenServer.cast(pid, {:sync_metrics_from_node, Node.self(), recent_metrics})
      end)
      
      # Update peer nodes list
      peer_nodes = aggregators
      |> Enum.map(&node/1)
      |> MapSet.new()
      
      %{state | peer_nodes: peer_nodes}
    else
      state
    end
  end
  
  defp update_aggregated_metrics(state) do
    # Get all current metrics
    all_metrics = :ets.tab2list(state.metrics_ets)
    |> Enum.map(&elem(&1, 1))
    
    # Group by metric key
    grouped_metrics = Enum.group_by(all_metrics, & &1.key)
    
    # Calculate aggregations for each metric key
    Enum.each(grouped_metrics, fn {key, metrics} ->
      aggregated = calculate_aggregations(metrics)
      :ets.insert(state.aggregated_ets, {key, aggregated})
    end)
    
    state
  end
  
  defp calculate_aggregations(metrics) do
    values = Enum.map(metrics, & &1.value)
    |> Enum.filter(&is_number/1)
    
    nodes = metrics
    |> Enum.map(&get_in(&1, [:metadata, :node]))
    |> Enum.uniq()
    |> length()
    
    %{
      count: length(metrics),
      sum: Enum.sum(values),
      avg: if(length(values) > 0, do: Enum.sum(values) / length(values), else: 0),
      min: if(length(values) > 0, do: Enum.min(values), else: nil),
      max: if(length(values) > 0, do: Enum.max(values), else: nil),
      nodes: nodes,
      latest_value: metrics |> Enum.max_by(& &1.timestamp) |> Map.get(:value),
      latest_timestamp: metrics |> Enum.max_by(& &1.timestamp) |> Map.get(:timestamp)
    }
  end
  
  defp get_metrics_for_node(metrics_ets, node) do
    :ets.select(metrics_ets, [
      {{:"$1", :"$2"}, 
       [{:==, {:map_get, :node, {:map_get, :metadata, :"$2"}}, node}],
       [:"$2"]}
    ])
    |> Enum.sort_by(& &1.timestamp)
  end
end