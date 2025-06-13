defmodule Aiex.Release.HealthEndpoint do
  @moduledoc """
  HTTP health check endpoints for load balancers and monitoring systems.
  
  Provides readiness and liveness probes for Kubernetes and other orchestration systems.
  Integrates with the distributed release manager for comprehensive health assessment.
  """
  
  use GenServer
  require Logger
  
  alias Aiex.Release.DistributedRelease
  
  @default_port 8090
  @health_cache_ttl 5_000  # 5 seconds
  
  defstruct [
    :port,
    :server_ref,
    :health_cache,
    :cache_timestamp,
    ready: false,
    alive: true
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc "Check if the node is ready to serve traffic"
  def ready? do
    GenServer.call(__MODULE__, :ready?)
  end
  
  @doc "Check if the node is alive"
  def alive? do
    GenServer.call(__MODULE__, :alive?)
  end
  
  @doc "Set readiness status"
  def set_ready(ready) do
    GenServer.cast(__MODULE__, {:set_ready, ready})
  end
  
  @doc "Set liveness status"
  def set_alive(alive) do
    GenServer.cast(__MODULE__, {:set_alive, alive})
  end
  
  @doc "Get detailed health information"
  def get_health_info do
    GenServer.call(__MODULE__, :get_health_info)
  end
  
  @doc "Get the health endpoint URL"
  def get_health_url do
    GenServer.call(__MODULE__, :get_health_url)
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, @default_port)
    
    # Start HTTP server
    {:ok, server_ref} = start_health_server(port)
    
    # Initialize as ready after startup delay
    Process.send_after(self(), :initialize_ready, 2000)
    
    state = %__MODULE__{
      port: port,
      server_ref: server_ref,
      health_cache: nil,
      cache_timestamp: 0,
      ready: false,
      alive: true
    }
    
    Logger.info("Health endpoint started on port #{port}")
    {:ok, state}
  end
  
  @impl true
  def handle_call(:ready?, _from, state) do
    {:reply, state.ready, state}
  end
  
  def handle_call(:alive?, _from, state) do
    {:reply, state.alive, state}
  end
  
  def handle_call(:get_health_info, _from, state) do
    health_info = get_cached_health_info(state)
    {:reply, health_info, state}
  end
  
  def handle_call(:get_health_url, _from, state) do
    url = "http://localhost:#{state.port}"
    {:reply, url, state}
  end
  
  @impl true
  def handle_cast({:set_ready, ready}, state) do
    Logger.info("Health endpoint readiness changed: #{ready}")
    {:noreply, %{state | ready: ready}}
  end
  
  def handle_cast({:set_alive, alive}, state) do
    Logger.info("Health endpoint liveness changed: #{alive}")
    {:noreply, %{state | alive: alive}}
  end
  
  @impl true
  def handle_info(:initialize_ready, state) do
    # Check if application is fully started
    ready = application_ready?()
    Logger.info("Initial readiness check: #{ready}")
    {:noreply, %{state | ready: ready}}
  end
  
  @impl true
  def terminate(_reason, state) do
    if state.server_ref do
      :cowboy.stop_listener(:health_http)
    end
    :ok
  end
  
  # HTTP Server
  
  defp start_health_server(port) do
    dispatch = :cowboy_router.compile([
      {:_, [
        {"/health", __MODULE__.HealthHandler, []},
        {"/health/ready", __MODULE__.ReadinessHandler, []},
        {"/health/live", __MODULE__.LivenessHandler, []},
        {"/health/detailed", __MODULE__.DetailedHealthHandler, []},
        {"/metrics/health", __MODULE__.HealthMetricsHandler, []},
        {:_, __MODULE__.NotFoundHandler, []}
      ]}
    ])
    
    :cowboy.start_clear(:health_http, [{:port, port}], %{
      env: %{dispatch: dispatch}
    })
  end
  
  # Health assessment
  
  defp get_cached_health_info(state) do
    now = System.system_time(:millisecond)
    
    if state.health_cache && (now - state.cache_timestamp) < @health_cache_ttl do
      state.health_cache
    else
      # Refresh health info
      health_info = collect_health_info(state)
      
      # Update state with new cache (this is just for the return value,
      # the actual state update would need to be done via handle_call)
      health_info
    end
  end
  
  defp collect_health_info(state) do
    base_info = %{
      timestamp: System.system_time(:millisecond),
      node: Node.self(),
      ready: state.ready,
      alive: state.alive,
      uptime_ms: get_uptime_ms(),
      version: Application.spec(:aiex, :vsn) || "unknown"
    }
    
    # Get distributed release health if available
    release_health = case Process.whereis(DistributedRelease) do
      nil ->
        %{release_manager: :not_available}
      _pid ->
        try do
          DistributedRelease.health_check()
        rescue
          _ -> %{release_manager: :error}
        end
    end
    
    # System health indicators
    system_health = %{
      memory: get_memory_info(),
      processes: length(Process.list()),
      ports: length(Port.list()),
      schedulers: :erlang.system_info(:schedulers),
      run_queue: :erlang.statistics(:run_queue)
    }
    
    # Cluster health
    cluster_health = %{
      cluster_enabled: Application.get_env(:aiex, :cluster_enabled, false),
      connected_nodes: Node.list(),
      node_count: length(Node.list()) + 1
    }
    
    Map.merge(base_info, %{
      release: release_health,
      system: system_health,
      cluster: cluster_health
    })
  end
  
  defp application_ready? do
    # Check if critical processes are running
    critical_processes = [
      Aiex.Supervisor,
      Aiex.Events.EventBus,
      Aiex.Context.Manager
    ]
    
    Enum.all?(critical_processes, fn process ->
      case Process.whereis(process) do
        nil -> false
        _pid -> true
      end
    end)
  end
  
  defp get_uptime_ms do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_ms
  end
  
  defp get_memory_info do
    memory = :erlang.memory()
    
    %{
      total: memory[:total],
      processes: memory[:processes],
      system: memory[:system],
      atom: memory[:atom],
      binary: memory[:binary],
      ets: memory[:ets]
    }
  end
end

# HTTP Handlers

defmodule Aiex.Release.HealthEndpoint.HealthHandler do
  @moduledoc false
  
  def init(req, state) do
    ready = Aiex.Release.HealthEndpoint.ready?()
    alive = Aiex.Release.HealthEndpoint.alive?()
    
    {status_code, response} = if ready and alive do
      {200, %{status: "healthy", ready: true, alive: true}}
    else
      {503, %{status: "unhealthy", ready: ready, alive: alive}}
    end
    
    req = :cowboy_req.reply(status_code, %{
      "content-type" => "application/json",
      "cache-control" => "no-cache"
    }, Jason.encode!(response), req)
    
    {:ok, req, state}
  end
end

defmodule Aiex.Release.HealthEndpoint.ReadinessHandler do
  @moduledoc false
  
  def init(req, state) do
    ready = Aiex.Release.HealthEndpoint.ready?()
    
    {status_code, response} = if ready do
      {200, %{status: "ready"}}
    else
      {503, %{status: "not ready"}}
    end
    
    req = :cowboy_req.reply(status_code, %{
      "content-type" => "application/json",
      "cache-control" => "no-cache"
    }, Jason.encode!(response), req)
    
    {:ok, req, state}
  end
end

defmodule Aiex.Release.HealthEndpoint.LivenessHandler do
  @moduledoc false
  
  def init(req, state) do
    alive = Aiex.Release.HealthEndpoint.alive?()
    
    {status_code, response} = if alive do
      {200, %{status: "alive"}}
    else
      {503, %{status: "not alive"}}
    end
    
    req = :cowboy_req.reply(status_code, %{
      "content-type" => "application/json",
      "cache-control" => "no-cache"
    }, Jason.encode!(response), req)
    
    {:ok, req, state}
  end
end

defmodule Aiex.Release.HealthEndpoint.DetailedHealthHandler do
  @moduledoc false
  
  def init(req, state) do
    health_info = Aiex.Release.HealthEndpoint.get_health_info()
    
    status_code = if health_info.ready and health_info.alive do
      200
    else
      503
    end
    
    req = :cowboy_req.reply(status_code, %{
      "content-type" => "application/json",
      "cache-control" => "no-cache"
    }, Jason.encode!(health_info), req)
    
    {:ok, req, state}
  end
end

defmodule Aiex.Release.HealthEndpoint.HealthMetricsHandler do
  @moduledoc false
  
  def init(req, state) do
    health_info = Aiex.Release.HealthEndpoint.get_health_info()
    
    # Convert health info to Prometheus metrics format
    metrics = [
      "# HELP aiex_health_ready Node readiness status",
      "# TYPE aiex_health_ready gauge",
      "aiex_health_ready{node=\"#{health_info.node}\"} #{if health_info.ready, do: 1, else: 0}",
      "",
      "# HELP aiex_health_alive Node liveness status", 
      "# TYPE aiex_health_alive gauge",
      "aiex_health_alive{node=\"#{health_info.node}\"} #{if health_info.alive, do: 1, else: 0}",
      "",
      "# HELP aiex_uptime_seconds Node uptime in seconds",
      "# TYPE aiex_uptime_seconds counter",
      "aiex_uptime_seconds{node=\"#{health_info.node}\"} #{div(health_info.uptime_ms, 1000)}",
      "",
      "# HELP aiex_memory_bytes Memory usage by type",
      "# TYPE aiex_memory_bytes gauge"
    ]
    
    memory_metrics = Enum.map(health_info.system.memory, fn {type, bytes} ->
      "aiex_memory_bytes{node=\"#{health_info.node}\",type=\"#{type}\"} #{bytes}"
    end)
    
    all_metrics = (metrics ++ memory_metrics) |> Enum.join("\n")
    
    req = :cowboy_req.reply(200, %{
      "content-type" => "text/plain; version=0.0.4; charset=utf-8",
      "cache-control" => "no-cache"
    }, all_metrics, req)
    
    {:ok, req, state}
  end
end

defmodule Aiex.Release.HealthEndpoint.NotFoundHandler do
  @moduledoc false
  
  def init(req, state) do
    req = :cowboy_req.reply(404, %{
      "content-type" => "application/json"
    }, Jason.encode!(%{error: "Not Found"}), req)
    
    {:ok, req, state}
  end
end