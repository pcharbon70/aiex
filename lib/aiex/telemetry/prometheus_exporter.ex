defmodule Aiex.Telemetry.PrometheusExporter do
  @moduledoc """
  Prometheus metrics exporter for cluster-wide monitoring.
  
  Exports telemetry data in Prometheus format for external monitoring systems.
  Provides HTTP endpoint for scraping and automatic metric registration.
  """
  
  use GenServer
  require Logger
  
  alias Aiex.Telemetry.DistributedAggregator
  
  @default_port 9090
  @metrics_path "/metrics"
  @health_path "/health"
  
  defstruct [
    :port,
    :server_ref,
    :registry,
    metrics: %{},
    collectors: []
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc "Register a custom metric collector"
  def register_collector(collector_module) do
    GenServer.call(__MODULE__, {:register_collector, collector_module})
  end
  
  @doc "Get the metrics endpoint URL"
  def metrics_url do
    GenServer.call(__MODULE__, :get_metrics_url)
  end
  
  @doc "Get current Prometheus metrics as text"
  def get_metrics_text do
    GenServer.call(__MODULE__, :get_metrics_text)
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, @default_port)
    
    # Start HTTP server for metrics endpoint
    server_ref = case start_http_server(port) do
      {:ok, ref} -> ref
      {:error, :eaddrinuse} ->
        Logger.warning("Port #{port} already in use for Prometheus exporter, trying alternative port")
        {:ok, ref} = start_http_server(port + 100)
        ref
    end
    
    # Create metrics registry
    registry = :ets.new(:prometheus_metrics, [:set, :private])
    
    # Register default collectors
    collectors = [
      __MODULE__.SystemCollector,
      __MODULE__.AiexCollector
    ]
    
    state = %__MODULE__{
      port: port,
      server_ref: server_ref,
      registry: registry,
      collectors: collectors
    }
    
    Logger.info("Prometheus exporter started on port #{port}")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:register_collector, collector_module}, _from, state) do
    collectors = [collector_module | state.collectors]
    {:reply, :ok, %{state | collectors: collectors}}
  end
  
  def handle_call(:get_metrics_url, _from, state) do
    url = "http://localhost:#{state.port}#{@metrics_path}"
    {:reply, url, state}
  end
  
  def handle_call(:get_metrics_text, _from, state) do
    metrics_text = collect_all_metrics(state)
    {:reply, metrics_text, state}
  end
  
  @impl true
  def terminate(_reason, state) do
    # Stop HTTP server
    if state.server_ref do
      :ranch.stop_listener(state.server_ref)
    end
    
    # Clean up ETS table
    :ets.delete(state.registry)
    
    :ok
  end
  
  # HTTP Server functions
  
  defp start_http_server(port) do
    dispatch = :cowboy_router.compile([
      {:_, [
        {@metrics_path, __MODULE__.MetricsHandler, []},
        {@health_path, __MODULE__.HealthHandler, []},
        {:_, __MODULE__.NotFoundHandler, []}
      ]}
    ])
    
    :cowboy.start_clear(:prometheus_http, [{:port, port}], %{
      env: %{dispatch: dispatch}
    })
  end
  
  # Metrics collection
  
  defp collect_all_metrics(state) do
    # Collect from all registered collectors
    metrics = Enum.flat_map(state.collectors, fn collector ->
      try do
        if function_exported?(collector, :collect, 0) do
          collector.collect()
        else
          []
        end
      rescue
        error ->
          Logger.warning("Failed to collect metrics from #{collector}: #{inspect(error)}")
          []
      end
    end)
    
    # Convert to Prometheus format
    format_prometheus_metrics(metrics)
  end
  
  defp format_prometheus_metrics(metrics) do
    metrics
    |> Enum.group_by(& &1.name)
    |> Enum.map(&format_metric_family/1)
    |> Enum.join("\n")
  end
  
  defp format_metric_family({name, metrics}) do
    # Get metric info from first metric
    first_metric = List.first(metrics)
    help = Map.get(first_metric, :help, "")
    type = Map.get(first_metric, :type, :gauge)
    
    # Format header
    header = [
      "# HELP #{name} #{help}",
      "# TYPE #{name} #{type}"
    ]
    
    # Format metric lines
    metric_lines = Enum.map(metrics, &format_metric_line/1)
    
    (header ++ metric_lines)
    |> Enum.join("\n")
  end
  
  defp format_metric_line(metric) do
    labels = format_labels(Map.get(metric, :labels, %{}))
    value = Map.get(metric, :value, 0)
    timestamp = Map.get(metric, :timestamp)
    
    line = "#{metric.name}#{labels} #{value}"
    
    if timestamp do
      "#{line} #{timestamp}"
    else
      line
    end
  end
  
  defp format_labels(labels) when map_size(labels) == 0, do: ""
  defp format_labels(labels) do
    formatted = labels
    |> Enum.map(fn {key, value} -> "#{key}=\"#{escape_label_value(value)}\"" end)
    |> Enum.join(",")
    
    "{#{formatted}}"
  end
  
  defp escape_label_value(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end
end

# HTTP Handlers

defmodule Aiex.Telemetry.PrometheusExporter.MetricsHandler do
  @moduledoc false
  
  def init(req, state) do
    metrics_text = Aiex.Telemetry.PrometheusExporter.get_metrics_text()
    
    req = :cowboy_req.reply(200, %{
      "content-type" => "text/plain; version=0.0.4; charset=utf-8"
    }, metrics_text, req)
    
    {:ok, req, state}
  end
end

defmodule Aiex.Telemetry.PrometheusExporter.HealthHandler do
  @moduledoc false
  
  def init(req, state) do
    req = :cowboy_req.reply(200, %{
      "content-type" => "application/json"
    }, Jason.encode!(%{status: "healthy"}), req)
    
    {:ok, req, state}
  end
end

defmodule Aiex.Telemetry.PrometheusExporter.NotFoundHandler do
  @moduledoc false
  
  def init(req, state) do
    req = :cowboy_req.reply(404, %{
      "content-type" => "text/plain"
    }, "Not Found", req)
    
    {:ok, req, state}
  end
end

# Default Collectors

defmodule Aiex.Telemetry.PrometheusExporter.SystemCollector do
  @moduledoc "Collects system-level metrics"
  
  def collect do
    [
      %{
        name: "aiex_node_info",
        help: "Information about the Aiex node",
        type: :gauge,
        value: 1,
        labels: %{
          node: Node.self(),
          version: Application.spec(:aiex, :vsn) || "unknown"
        }
      },
      %{
        name: "aiex_connected_nodes_total",
        help: "Number of connected nodes in the cluster",
        type: :gauge,
        value: length(Node.list()) + 1
      },
      %{
        name: "aiex_memory_usage_bytes",
        help: "Memory usage by category",
        type: :gauge,
        value: :erlang.memory(:total),
        labels: %{type: "total"}
      },
      %{
        name: "aiex_process_count",
        help: "Number of processes running",
        type: :gauge,
        value: length(Process.list())
      },
      %{
        name: "aiex_uptime_seconds",
        help: "Node uptime in seconds",
        type: :counter,
        value: :erlang.statistics(:wall_clock) |> elem(0) |> div(1000)
      }
    ]
  end
end

defmodule Aiex.Telemetry.PrometheusExporter.AiexCollector do
  @moduledoc "Collects Aiex-specific metrics"
  
  def collect do
    # Get cluster metrics from distributed aggregator
    {:ok, cluster_metrics} = Aiex.Telemetry.DistributedAggregator.get_cluster_metrics()
    
    # Convert aggregated metrics to Prometheus format
    Enum.flat_map(cluster_metrics, fn {key, aggregated} ->
      [
        %{
          name: "aiex_#{String.replace(to_string(key), ".", "_")}_total",
          help: "Total count for #{key}",
          type: :counter,
          value: aggregated.count
        },
        %{
          name: "aiex_#{String.replace(to_string(key), ".", "_")}_sum",
          help: "Sum of values for #{key}",
          type: :counter,
          value: aggregated.sum
        },
        %{
          name: "aiex_#{String.replace(to_string(key), ".", "_")}_avg",
          help: "Average value for #{key}",
          type: :gauge,
          value: aggregated.avg
        },
        %{
          name: "aiex_#{String.replace(to_string(key), ".", "_")}_nodes",
          help: "Number of nodes reporting #{key}",
          type: :gauge,
          value: aggregated.nodes
        }
      ]
    end)
  rescue
    _ ->
      # Return empty list if aggregator is not available
      []
  end
end