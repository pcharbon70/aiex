defmodule Aiex.Telemetry.ClusterDashboard do
  @moduledoc """
  Real-time cluster metrics dashboard with alerting and visualization.
  
  Provides a comprehensive view of cluster health, performance metrics,
  and operational status across all nodes.
  """
  
  use GenServer
  require Logger
  
  alias Aiex.Telemetry.DistributedAggregator
  alias Aiex.Events.EventBus
  
  @refresh_interval 5_000
  @alert_check_interval 10_000
  @dashboard_port 8080
  
  defstruct [
    :dashboard_server,
    :alert_rules,
    :active_alerts,
    :metrics_history,
    :last_refresh,
    refresh_timer: nil,
    alert_timer: nil
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc "Get current cluster status"
  def get_cluster_status do
    GenServer.call(__MODULE__, :get_cluster_status)
  end
  
  @doc "Get active alerts"
  def get_active_alerts do
    GenServer.call(__MODULE__, :get_active_alerts)
  end
  
  @doc "Add a custom alert rule"
  def add_alert_rule(rule) do
    GenServer.call(__MODULE__, {:add_alert_rule, rule})
  end
  
  @doc "Get dashboard URL"
  def get_dashboard_url do
    GenServer.call(__MODULE__, :get_dashboard_url)
  end
  
  @doc "Get metrics history for visualization"
  def get_metrics_history(duration_minutes \\ 60) do
    GenServer.call(__MODULE__, {:get_metrics_history, duration_minutes})
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, @dashboard_port)
    
    # Start dashboard HTTP server
    {:ok, server} = start_dashboard_server(port)
    
    # Initialize alert rules
    alert_rules = default_alert_rules() ++ Keyword.get(opts, :alert_rules, [])
    
    # Schedule periodic tasks
    refresh_timer = Process.send_after(self(), :refresh_metrics, @refresh_interval)
    alert_timer = Process.send_after(self(), :check_alerts, @alert_check_interval)
    
    state = %__MODULE__{
      dashboard_server: server,
      alert_rules: alert_rules,
      active_alerts: %{},
      metrics_history: :ets.new(:metrics_history, [:ordered_set, :private]),
      last_refresh: System.system_time(:millisecond),
      refresh_timer: refresh_timer,
      alert_timer: alert_timer
    }
    
    Logger.info("Cluster dashboard started on port #{port}")
    {:ok, state}
  end
  
  @impl true
  def handle_call(:get_cluster_status, _from, state) do
    status = build_cluster_status(state)
    {:reply, status, state}
  end
  
  def handle_call(:get_active_alerts, _from, state) do
    alerts = Map.values(state.active_alerts)
    {:reply, alerts, state}
  end
  
  def handle_call({:add_alert_rule, rule}, _from, state) do
    alert_rules = [rule | state.alert_rules]
    {:reply, :ok, %{state | alert_rules: alert_rules}}
  end
  
  def handle_call(:get_dashboard_url, _from, state) do
    url = "http://localhost:#{get_dashboard_port(state.dashboard_server)}"
    {:reply, url, state}
  end
  
  def handle_call({:get_metrics_history, duration_minutes}, _from, state) do
    cutoff_time = System.system_time(:millisecond) - (duration_minutes * 60 * 1000)
    
    history = :ets.select(state.metrics_history, [
      {{:"$1", :"$2"}, [{:>=, :"$1", cutoff_time}], [:"$2"]}
    ])
    |> Enum.sort_by(& &1.timestamp)
    
    {:reply, history, state}
  end
  
  @impl true
  def handle_info(:refresh_metrics, state) do
    # Collect current metrics
    {:ok, cluster_metrics} = DistributedAggregator.get_cluster_metrics()
    
    # Store in history
    timestamp = System.system_time(:millisecond)
    snapshot = %{
      timestamp: timestamp,
      cluster_metrics: cluster_metrics,
      node_count: length(Node.list()) + 1,
      system_info: collect_system_info()
    }
    
    :ets.insert(state.metrics_history, {timestamp, snapshot})
    
    # Clean old history (keep last 24 hours)
    cleanup_old_history(state.metrics_history)
    
    # Schedule next refresh
    refresh_timer = Process.send_after(self(), :refresh_metrics, @refresh_interval)
    
    {:noreply, %{state | last_refresh: timestamp, refresh_timer: refresh_timer}}
  end
  
  def handle_info(:check_alerts, state) do
    # Evaluate alert rules
    new_alerts = evaluate_alert_rules(state)
    
    # Compare with active alerts to detect new/resolved alerts
    {new_active_alerts, alert_events} = process_alert_changes(state.active_alerts, new_alerts)
    
    # Publish alert events
    Enum.each(alert_events, fn event ->
      EventBus.publish("dashboard:alert", event)
      log_alert_event(event)
    end)
    
    # Schedule next check
    alert_timer = Process.send_after(self(), :check_alerts, @alert_check_interval)
    
    {:noreply, %{state | active_alerts: new_active_alerts, alert_timer: alert_timer}}
  end
  
  @impl true
  def terminate(_reason, state) do
    # Stop HTTP server
    if state.dashboard_server do
      :cowboy.stop_listener(state.dashboard_server)
    end
    
    # Cancel timers
    if state.refresh_timer, do: Process.cancel_timer(state.refresh_timer)
    if state.alert_timer, do: Process.cancel_timer(state.alert_timer)
    
    # Clean up ETS
    :ets.delete(state.metrics_history)
    
    :ok
  end
  
  # Private functions
  
  defp start_dashboard_server(port) do
    dispatch = :cowboy_router.compile([
      {:_, [
        {"/", __MODULE__.IndexHandler, []},
        {"/api/status", __MODULE__.StatusHandler, []},
        {"/api/metrics", __MODULE__.MetricsHandler, []},
        {"/api/alerts", __MODULE__.AlertsHandler, []},
        {"/api/history", __MODULE__.HistoryHandler, []},
        {"/ws", __MODULE__.WebSocketHandler, []},
        {"/static/[...]", :cowboy_static, {:priv_dir, :aiex, "dashboard"}}
      ]}
    ])
    
    :cowboy.start_clear(:dashboard_http, [{:port, port}], %{
      env: %{dispatch: dispatch}
    })
  end
  
  defp get_dashboard_port({:ok, pid}) do
    :ranch.get_port(pid)
  end
  
  defp get_dashboard_port(_), do: @dashboard_port
  
  defp build_cluster_status(state) do
    {:ok, cluster_metrics} = DistributedAggregator.get_cluster_metrics()
    
    %{
      timestamp: System.system_time(:millisecond),
      nodes: %{
        total: length(Node.list()) + 1,
        connected: Node.list(),
        local: Node.self()
      },
      cluster_health: calculate_cluster_health(cluster_metrics),
      active_alerts: length(Map.values(state.active_alerts)),
      metrics: cluster_metrics,
      system: collect_system_info(),
      last_refresh: state.last_refresh
    }
  end
  
  defp collect_system_info do
    %{
      memory: :erlang.memory(),
      system_info: %{
        process_count: length(Process.list()),
        port_count: length(Port.list()),
        schedulers: :erlang.system_info(:schedulers),
        run_queue: :erlang.statistics(:run_queue)
      },
      node_info: %{
        uptime: :erlang.statistics(:wall_clock) |> elem(0),
        version: :erlang.system_info(:version)
      }
    }
  end
  
  defp calculate_cluster_health(metrics) do
    # Simple health scoring based on key metrics
    scores = [
      calculate_memory_health(metrics),
      calculate_process_health(metrics),
      calculate_network_health(metrics)
    ]
    
    avg_score = Enum.sum(scores) / length(scores)
    
    cond do
      avg_score >= 0.9 -> :healthy
      avg_score >= 0.7 -> :warning
      true -> :critical
    end
  end
  
  defp calculate_memory_health(metrics) do
    case Map.get(metrics, "memory.usage_percent") do
      %{latest_value: usage} when usage < 80 -> 1.0
      %{latest_value: usage} when usage < 90 -> 0.7
      %{latest_value: usage} when usage < 95 -> 0.4
      _ -> 0.1
    end
  end
  
  defp calculate_process_health(metrics) do
    case Map.get(metrics, "processes.count") do
      %{latest_value: count} when count < 1000 -> 1.0
      %{latest_value: count} when count < 5000 -> 0.8
      %{latest_value: count} when count < 10000 -> 0.5
      _ -> 0.2
    end
  end
  
  defp calculate_network_health(_metrics) do
    # Placeholder for network health calculation
    if length(Node.list()) > 0, do: 1.0, else: 0.8
  end
  
  defp default_alert_rules do
    [
      %{
        id: "high_memory_usage",
        name: "High Memory Usage",
        condition: fn metrics ->
          case Map.get(metrics, "memory.usage_percent") do
            %{latest_value: usage} when usage > 90 -> 
              {:alert, "Memory usage is #{usage}%"}
            _ -> 
              :ok
          end
        end,
        severity: :warning
      },
      %{
        id: "high_process_count",
        name: "High Process Count",
        condition: fn metrics ->
          case Map.get(metrics, "processes.count") do
            %{latest_value: count} when count > 10000 -> 
              {:alert, "Process count is #{count}"}
            _ -> 
              :ok
          end
        end,
        severity: :warning
      },
      %{
        id: "node_disconnected",
        name: "Node Disconnected",
        condition: fn _metrics ->
          expected_nodes = Application.get_env(:aiex, :expected_nodes, 1)
          current_nodes = length(Node.list()) + 1
          
          if current_nodes < expected_nodes do
            {:alert, "Only #{current_nodes}/#{expected_nodes} nodes connected"}
          else
            :ok
          end
        end,
        severity: :critical
      }
    ]
  end
  
  defp evaluate_alert_rules(state) do
    {:ok, cluster_metrics} = DistributedAggregator.get_cluster_metrics()
    
    Enum.flat_map(state.alert_rules, fn rule ->
      case rule.condition.(cluster_metrics) do
        {:alert, message} ->
          [%{
            id: rule.id,
            name: rule.name,
            message: message,
            severity: rule.severity,
            timestamp: System.system_time(:millisecond),
            node: Node.self()
          }]
          
        :ok ->
          []
      end
    end)
    |> Enum.into(%{}, &{&1.id, &1})
  end
  
  defp process_alert_changes(old_alerts, new_alerts) do
    # Find new alerts
    new_alert_ids = MapSet.new(Map.keys(new_alerts))
    old_alert_ids = MapSet.new(Map.keys(old_alerts))
    
    newly_triggered = MapSet.difference(new_alert_ids, old_alert_ids)
    newly_resolved = MapSet.difference(old_alert_ids, new_alert_ids)
    
    # Generate events
    events = []
    
    # New alert events
    new_events = Enum.map(newly_triggered, fn alert_id ->
      alert = Map.get(new_alerts, alert_id)
      %{type: :alert_triggered, alert: alert}
    end)
    
    # Resolved alert events
    resolved_events = Enum.map(newly_resolved, fn alert_id ->
      alert = Map.get(old_alerts, alert_id)
      %{type: :alert_resolved, alert: alert}
    end)
    
    all_events = events ++ new_events ++ resolved_events
    
    {new_alerts, all_events}
  end
  
  defp log_alert_event(%{type: :alert_triggered, alert: alert}) do
    Logger.warning("Alert triggered: #{alert.name} - #{alert.message}")
  end
  
  defp log_alert_event(%{type: :alert_resolved, alert: alert}) do
    Logger.info("Alert resolved: #{alert.name}")
  end
  
  defp cleanup_old_history(metrics_history) do
    # Keep last 24 hours
    cutoff_time = System.system_time(:millisecond) - (24 * 60 * 60 * 1000)
    
    :ets.select_delete(metrics_history, [
      {{:"$1", :"$2"}, [{:<, :"$1", cutoff_time}], [true]}
    ])
  end
end

# HTTP Handlers for Dashboard

defmodule Aiex.Telemetry.ClusterDashboard.IndexHandler do
  @moduledoc false
  
  def init(req, state) do
    html = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Aiex Cluster Dashboard</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            .metric { margin: 10px 0; padding: 10px; background: #f5f5f5; }
            .alert { margin: 10px 0; padding: 10px; background: #ffebee; border-left: 4px solid #f44336; }
            .healthy { color: green; }
            .warning { color: orange; }
            .critical { color: red; }
        </style>
    </head>
    <body>
        <h1>Aiex Cluster Dashboard</h1>
        <div id="status"></div>
        <script>
            function updateStatus() {
                fetch('/api/status')
                    .then(response => response.json())
                    .then(data => {
                        document.getElementById('status').innerHTML = 
                            '<h2>Cluster Status: <span class="' + data.cluster_health + '">' + 
                            data.cluster_health.toUpperCase() + '</span></h2>' +
                            '<p>Nodes: ' + data.nodes.total + ' (' + data.nodes.connected.length + ' connected)</p>' +
                            '<p>Active Alerts: ' + data.active_alerts + '</p>' +
                            '<p>Last Refresh: ' + new Date(data.last_refresh).toLocaleString() + '</p>';
                    });
            }
            updateStatus();
            setInterval(updateStatus, 5000);
        </script>
    </body>
    </html>
    """
    
    req = :cowboy_req.reply(200, %{"content-type" => "text/html"}, html, req)
    {:ok, req, state}
  end
end

defmodule Aiex.Telemetry.ClusterDashboard.StatusHandler do
  @moduledoc false
  
  def init(req, state) do
    status = Aiex.Telemetry.ClusterDashboard.get_cluster_status()
    
    req = :cowboy_req.reply(200, %{
      "content-type" => "application/json",
      "access-control-allow-origin" => "*"
    }, Jason.encode!(status), req)
    
    {:ok, req, state}
  end
end

defmodule Aiex.Telemetry.ClusterDashboard.MetricsHandler do
  @moduledoc false
  
  def init(req, state) do
    {:ok, metrics} = Aiex.Telemetry.DistributedAggregator.get_cluster_metrics()
    
    req = :cowboy_req.reply(200, %{
      "content-type" => "application/json",
      "access-control-allow-origin" => "*"
    }, Jason.encode!(metrics), req)
    
    {:ok, req, state}
  end
end

defmodule Aiex.Telemetry.ClusterDashboard.AlertsHandler do
  @moduledoc false
  
  def init(req, state) do
    alerts = Aiex.Telemetry.ClusterDashboard.get_active_alerts()
    
    req = :cowboy_req.reply(200, %{
      "content-type" => "application/json",
      "access-control-allow-origin" => "*"
    }, Jason.encode!(alerts), req)
    
    {:ok, req, state}
  end
end

defmodule Aiex.Telemetry.ClusterDashboard.HistoryHandler do
  @moduledoc false
  
  def init(req, state) do
    history = Aiex.Telemetry.ClusterDashboard.get_metrics_history()
    
    req = :cowboy_req.reply(200, %{
      "content-type" => "application/json",
      "access-control-allow-origin" => "*"
    }, Jason.encode!(history), req)
    
    {:ok, req, state}
  end
end