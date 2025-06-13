defmodule Aiex.Performance.Dashboard do
  @moduledoc """
  Performance monitoring dashboard that aggregates metrics from all nodes.
  
  Provides real-time visibility into cluster performance, resource usage,
  and operational health.
  """

  use GenServer
  require Logger

  alias Aiex.Performance.{DistributedAnalyzer, DistributedBenchmarker}
  alias Aiex.Events.EventBus

  defmodule Metrics do
    @moduledoc false
    defstruct [
      :node_metrics,
      :cluster_health,
      :performance_trends,
      :alerts,
      :last_updated
    ]
  end

  defmodule State do
    @moduledoc false
    defstruct [
      :metrics,
      :update_interval,
      :update_timer,
      :alert_thresholds,
      :metric_history
    ]
  end

  # Client API

  @doc """
  Starts the performance dashboard.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets current dashboard metrics.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Gets performance trends over time.
  """
  def get_trends(duration \\ :hour) do
    GenServer.call(__MODULE__, {:get_trends, duration})
  end

  @doc """
  Gets current alerts.
  """
  def get_alerts do
    GenServer.call(__MODULE__, :get_alerts)
  end

  @doc """
  Sets alert thresholds.
  """
  def set_thresholds(thresholds) do
    GenServer.call(__MODULE__, {:set_thresholds, thresholds})
  end

  @doc """
  Forces an immediate metric update.
  """
  def refresh do
    GenServer.call(__MODULE__, :refresh)
  end

  @doc """
  Gets a summary report of cluster performance.
  """
  def summary_report do
    GenServer.call(__MODULE__, :summary_report)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    update_interval = Keyword.get(opts, :update_interval, 5_000)  # 5 seconds
    
    # Subscribe to performance events
    EventBus.subscribe(:performance_analysis)
    EventBus.subscribe(:benchmark_completed)
    
    # Default alert thresholds
    thresholds = %{
      memory_percent: 80,
      process_count_percent: 80,
      message_queue_length: 1000,
      scheduler_usage: 90,
      gc_runs_per_minute: 10000
    }
    
    state = %State{
      metrics: %Metrics{
        node_metrics: %{},
        cluster_health: :unknown,
        performance_trends: [],
        alerts: [],
        last_updated: nil
      },
      update_interval: update_interval,
      alert_thresholds: thresholds,
      metric_history: []
    }
    
    # Schedule first update
    send(self(), :update_metrics)
    
    {:ok, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, {:ok, state.metrics}, state}
  end

  @impl true
  def handle_call({:get_trends, duration}, _from, state) do
    trends = calculate_trends(state.metric_history, duration)
    {:reply, {:ok, trends}, state}
  end

  @impl true
  def handle_call(:get_alerts, _from, state) do
    {:reply, {:ok, state.metrics.alerts}, state}
  end

  @impl true
  def handle_call({:set_thresholds, thresholds}, _from, state) do
    new_state = %{state | alert_thresholds: Map.merge(state.alert_thresholds, thresholds)}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:refresh, _from, state) do
    new_metrics = gather_metrics(state)
    new_state = update_state_with_metrics(state, new_metrics)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:summary_report, _from, state) do
    report = generate_summary_report(state)
    {:reply, {:ok, report}, state}
  end

  @impl true
  def handle_info(:update_metrics, state) do
    # Gather metrics
    new_metrics = gather_metrics(state)
    
    # Update state
    new_state = update_state_with_metrics(state, new_metrics)
    
    # Schedule next update
    timer = Process.send_after(self(), :update_metrics, state.update_interval)
    
    {:noreply, %{new_state | update_timer: timer}}
  end

  @impl true
  def handle_info({:performance_event, event_type, data}, state) do
    # Handle performance events from EventBus
    new_state = case event_type do
      :performance_analysis ->
        handle_performance_analysis(state, data)
      :benchmark_completed ->
        handle_benchmark_completed(state, data)
      _ ->
        state
    end
    
    {:noreply, new_state}
  end

  # Private Functions

  defp gather_metrics(state) do
    # Get cluster metrics from analyzer
    {:ok, node_metrics} = DistributedAnalyzer.get_metrics()
    {:ok, hot_processes} = DistributedAnalyzer.find_hot_processes(5)
    
    # Calculate cluster health
    cluster_health = calculate_cluster_health(node_metrics)
    
    # Check for alerts
    alerts = check_alerts(node_metrics, hot_processes, state.alert_thresholds)
    
    %Metrics{
      node_metrics: node_metrics,
      cluster_health: cluster_health,
      performance_trends: state.metrics.performance_trends,
      alerts: alerts,
      last_updated: DateTime.utc_now()
    }
  end

  defp update_state_with_metrics(state, new_metrics) do
    # Add to history
    history_entry = %{
      timestamp: new_metrics.last_updated,
      metrics: new_metrics
    }
    
    # Keep last hour of history
    cutoff = DateTime.add(DateTime.utc_now(), -3600, :second)
    updated_history = [history_entry | state.metric_history]
    |> Enum.filter(fn entry ->
      DateTime.compare(entry.timestamp, cutoff) == :gt
    end)
    
    %{state | 
      metrics: new_metrics,
      metric_history: updated_history
    }
  end

  defp calculate_cluster_health(node_metrics) do
    if map_size(node_metrics) == 0 do
      :unknown
    else
      issues = Enum.flat_map(node_metrics, fn {_node, metrics} ->
        check_node_health(metrics)
      end)
      
      case length(issues) do
        0 -> :healthy
        n when n < 3 -> :degraded
        _ -> :critical
      end
    end
  end

  defp check_node_health(metrics) do
    issues = []
    
    # Check memory usage
    issues = case metrics[:memory] do
      %{total: total, processes: processes} when processes / total > 0.8 ->
        [:high_memory_usage | issues]
      _ -> issues
    end
    
    # Check process count
    issues = case metrics[:processes] do
      %{count: count, limit: limit} when count / limit > 0.8 ->
        [:high_process_count | issues]
      _ -> issues
    end
    
    # Check scheduler usage
    issues = case metrics[:schedulers] do
      schedulers when is_map(schedulers) ->
        avg_usage = schedulers
        |> Map.values()
        |> Enum.sum()
        |> Kernel./(map_size(schedulers))
        
        if avg_usage > 0.9, do: [:high_scheduler_usage | issues], else: issues
      _ -> issues
    end
    
    issues
  end

  defp check_alerts(node_metrics, hot_processes, thresholds) do
    alerts = []
    
    # Check each node
    alerts = Enum.flat_map(node_metrics, fn {node, metrics} ->
      node_alerts = []
      
      # Memory alerts
      node_alerts = case metrics[:memory] do
        %{total: total, processes: processes} ->
          percent = (processes / total) * 100
          if percent > thresholds.memory_percent do
            [%{
              type: :memory,
              severity: :warning,
              node: node,
              message: "Memory usage at #{Float.round(percent, 1)}%",
              value: percent
            } | node_alerts]
          else
            node_alerts
          end
        _ -> node_alerts
      end
      
      # Process count alerts
      node_alerts = case metrics[:processes] do
        %{count: count, limit: limit} ->
          percent = (count / limit) * 100
          if percent > thresholds.process_count_percent do
            [%{
              type: :process_count,
              severity: :warning,
              node: node,
              message: "Process count at #{Float.round(percent, 1)}% of limit",
              value: percent
            } | node_alerts]
          else
            node_alerts
          end
        _ -> node_alerts
      end
      
      node_alerts
    end) ++ alerts
    
    # Check hot processes
    alerts = Enum.reduce(hot_processes, alerts, fn {_pid, info}, acc ->
      case info[:message_queue] do
        queue_len when is_integer(queue_len) and queue_len > thresholds.message_queue_length ->
          [%{
            type: :message_queue,
            severity: :critical,
            node: info[:node],
            message: "Process #{inspect(info[:name])} has #{queue_len} messages queued",
            value: queue_len
          } | acc]
        _ -> acc
      end
    end)
    
    alerts
  end

  defp calculate_trends(history, duration) do
    # Get cutoff time based on duration
    cutoff = case duration do
      :minute -> DateTime.add(DateTime.utc_now(), -60, :second)
      :hour -> DateTime.add(DateTime.utc_now(), -3600, :second)
      :day -> DateTime.add(DateTime.utc_now(), -86400, :second)
    end
    
    # Filter history
    relevant_history = history
    |> Enum.filter(fn entry ->
      DateTime.compare(entry.timestamp, cutoff) == :gt
    end)
    
    if length(relevant_history) < 2 do
      %{insufficient_data: true}
    else
      # Calculate trends for key metrics
      %{
        memory_trend: calculate_metric_trend(relevant_history, [:memory, :total]),
        process_count_trend: calculate_metric_trend(relevant_history, [:processes, :count]),
        scheduler_usage_trend: calculate_scheduler_trend(relevant_history)
      }
    end
  end

  defp calculate_metric_trend(history, path) do
    values = history
    |> Enum.flat_map(fn entry ->
      entry.metrics.node_metrics
      |> Map.values()
      |> Enum.map(fn node_metrics ->
        get_in(node_metrics, path) || 0
      end)
    end)
    |> Enum.filter(&is_number/1)
    
    if length(values) > 1 do
      # Simple linear regression
      avg = Enum.sum(values) / length(values)
      first_half_avg = values |> Enum.take(div(length(values), 2)) |> Enum.sum() |> Kernel./(div(length(values), 2))
      second_half_avg = values |> Enum.drop(div(length(values), 2)) |> Enum.sum() |> Kernel./(length(values) - div(length(values), 2))
      
      trend = cond do
        second_half_avg > first_half_avg * 1.1 -> :increasing
        second_half_avg < first_half_avg * 0.9 -> :decreasing
        true -> :stable
      end
      
      %{
        current: List.last(values),
        average: avg,
        trend: trend,
        change_percent: ((second_half_avg - first_half_avg) / first_half_avg) * 100
      }
    else
      %{insufficient_data: true}
    end
  end

  defp calculate_scheduler_trend(history) do
    scheduler_usages = history
    |> Enum.map(fn entry ->
      entry.metrics.node_metrics
      |> Map.values()
      |> Enum.flat_map(fn node_metrics ->
        case node_metrics[:schedulers] do
          schedulers when is_map(schedulers) ->
            Map.values(schedulers)
          _ -> []
        end
      end)
    end)
    |> Enum.filter(fn usages -> length(usages) > 0 end)
    
    if length(scheduler_usages) > 1 do
      averages = Enum.map(scheduler_usages, fn usages ->
        Enum.sum(usages) / length(usages)
      end)
      
      calculate_metric_trend_from_values(averages)
    else
      %{insufficient_data: true}
    end
  end

  defp calculate_metric_trend_from_values(values) do
    avg = Enum.sum(values) / length(values)
    first_half_avg = values |> Enum.take(div(length(values), 2)) |> Enum.sum() |> Kernel./(div(length(values), 2))
    second_half_avg = values |> Enum.drop(div(length(values), 2)) |> Enum.sum() |> Kernel./(length(values) - div(length(values), 2))
    
    trend = cond do
      second_half_avg > first_half_avg * 1.1 -> :increasing
      second_half_avg < first_half_avg * 0.9 -> :decreasing
      true -> :stable
    end
    
    %{
      current: List.last(values),
      average: avg,
      trend: trend,
      change_percent: ((second_half_avg - first_half_avg) / first_half_avg) * 100
    }
  end

  defp generate_summary_report(state) do
    %{
      cluster_status: %{
        health: state.metrics.cluster_health,
        node_count: map_size(state.metrics.node_metrics),
        last_updated: state.metrics.last_updated
      },
      alerts: %{
        active: length(state.metrics.alerts),
        critical: Enum.count(state.metrics.alerts, & &1.severity == :critical),
        warning: Enum.count(state.metrics.alerts, & &1.severity == :warning)
      },
      resource_usage: calculate_resource_summary(state.metrics.node_metrics),
      performance_trends: calculate_trends(state.metric_history, :hour),
      recommendations: generate_recommendations(state)
    }
  end

  defp calculate_resource_summary(node_metrics) do
    total_memory = node_metrics
    |> Map.values()
    |> Enum.map(fn m -> get_in(m, [:memory, :total]) || 0 end)
    |> Enum.sum()
    
    used_memory = node_metrics
    |> Map.values()
    |> Enum.map(fn m -> get_in(m, [:memory, :processes]) || 0 end)
    |> Enum.sum()
    
    total_processes = node_metrics
    |> Map.values()
    |> Enum.map(fn m -> get_in(m, [:processes, :count]) || 0 end)
    |> Enum.sum()
    
    %{
      memory: %{
        total_mb: div(total_memory, 1_048_576),
        used_mb: div(used_memory, 1_048_576),
        percent_used: if(total_memory > 0, do: (used_memory / total_memory) * 100, else: 0)
      },
      processes: %{
        total: total_processes,
        per_node_average: if(map_size(node_metrics) > 0, do: div(total_processes, map_size(node_metrics)), else: 0)
      }
    }
  end

  defp generate_recommendations(state) do
    recommendations = []
    
    # Check for memory issues
    recommendations = if Enum.any?(state.metrics.alerts, & &1.type == :memory) do
      ["Consider increasing node memory or optimizing memory usage" | recommendations]
    else
      recommendations
    end
    
    # Check for process count issues
    recommendations = if Enum.any?(state.metrics.alerts, & &1.type == :process_count) do
      ["Process count is high - check for process leaks or increase process limit" | recommendations]
    else
      recommendations
    end
    
    # Check trends
    case calculate_trends(state.metric_history, :hour) do
      %{memory_trend: %{trend: :increasing, change_percent: change}} when change > 10 ->
        ["Memory usage trending up significantly (#{Float.round(change, 1)}%)" | recommendations]
      _ ->
        recommendations
    end
  end

  defp handle_performance_analysis(state, data) do
    # Performance analysis events can update metrics
    state
  end

  defp handle_benchmark_completed(state, data) do
    # Benchmark completion events can be tracked
    state
  end
end