defmodule Aiex.K8s.ClusterCoordinator do
  @moduledoc """
  Kubernetes cluster coordination for distributed Aiex deployment.
  
  Handles automatic cluster formation using libcluster with Kubernetes.DNS strategy,
  pod lifecycle management, and production supervision trees optimized for 
  cloud-native operation.
  """

  use GenServer
  require Logger

  alias Aiex.Events.EventBus

  defmodule State do
    @moduledoc false
    defstruct [
      :cluster_name,
      :namespace,
      :service_name,
      :pod_name,
      :node_ready,
      :cluster_nodes,
      :health_check_interval,
      :health_timer,
      :readiness_probe_port,
      :liveness_probe_port
    ]
  end

  # Client API

  @doc """
  Starts the Kubernetes cluster coordinator.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets current cluster status.
  """
  def cluster_status do
    GenServer.call(__MODULE__, :cluster_status)
  end

  @doc """
  Forces cluster discovery refresh.
  """
  def refresh_cluster do
    GenServer.call(__MODULE__, :refresh_cluster)
  end

  @doc """
  Gets pod information.
  """
  def pod_info do
    GenServer.call(__MODULE__, :pod_info)
  end

  @doc """
  Performs graceful shutdown preparation.
  """
  def prepare_shutdown do
    GenServer.call(__MODULE__, :prepare_shutdown, 30_000)
  end

  @doc """
  Checks if node is ready to serve traffic.
  """
  def ready? do
    GenServer.call(__MODULE__, :ready?)
  end

  @doc """
  Performs liveness check.
  """
  def alive? do
    GenServer.call(__MODULE__, :alive?)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    # Get Kubernetes environment variables
    cluster_name = get_env_var("CLUSTER_NAME", "aiex-cluster")
    namespace = get_env_var("NAMESPACE", "default")
    service_name = get_env_var("SERVICE_NAME", "aiex-headless")
    pod_name = get_env_var("HOSTNAME", "unknown-pod")
    
    health_check_interval = Keyword.get(opts, :health_check_interval, 30_000)
    readiness_probe_port = Keyword.get(opts, :readiness_probe_port, 8080)
    liveness_probe_port = Keyword.get(opts, :liveness_probe_port, 8081)
    
    state = %State{
      cluster_name: cluster_name,
      namespace: namespace,
      service_name: service_name,
      pod_name: pod_name,
      node_ready: false,
      cluster_nodes: [],
      health_check_interval: health_check_interval,
      readiness_probe_port: readiness_probe_port,
      liveness_probe_port: liveness_probe_port
    }
    
    # Start health check probes
    start_health_probes(state)
    
    # Schedule cluster status check
    timer = Process.send_after(self(), :health_check, health_check_interval)
    
    Logger.info("Kubernetes cluster coordinator started for pod #{pod_name} in namespace #{namespace}")
    
    {:ok, %{state | health_timer: timer}}
  end

  @impl true
  def handle_call(:cluster_status, _from, state) do
    cluster_info = %{
      cluster_name: state.cluster_name,
      namespace: state.namespace,
      service_name: state.service_name,
      pod_name: state.pod_name,
      node_ready: state.node_ready,
      current_node: node(),
      cluster_nodes: Node.list(),
      connected_nodes: length(Node.list()),
      cluster_size: length(state.cluster_nodes)
    }
    
    {:reply, {:ok, cluster_info}, state}
  end

  @impl true
  def handle_call(:refresh_cluster, _from, state) do
    # Force libcluster to refresh
    case Application.get_env(:libcluster, :topologies) do
      nil -> 
        {:reply, {:error, :no_topologies}, state}
      topologies ->
        # Trigger reconnection by sending connect messages
        for {_name, config} <- topologies do
          case Keyword.get(config, :strategy) do
            Cluster.Strategy.Kubernetes.DNS ->
              send(self(), :force_discovery)
            _ -> :ok
          end
        end
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:pod_info, _from, state) do
    pod_info = %{
      pod_name: state.pod_name,
      namespace: state.namespace,
      node_name: node(),
      started_at: get_pod_start_time(),
      readiness_probe_port: state.readiness_probe_port,
      liveness_probe_port: state.liveness_probe_port,
      cluster_ip: get_cluster_ip(),
      pod_ip: get_pod_ip()
    }
    
    {:reply, {:ok, pod_info}, state}
  end

  @impl true
  def handle_call(:prepare_shutdown, _from, state) do
    Logger.info("Preparing for graceful shutdown...")
    
    # Mark node as not ready
    new_state = %{state | node_ready: false}
    
    # Notify cluster of shutdown
    publish_event(:node_shutting_down, %{
      node: node(),
      pod_name: state.pod_name,
      timestamp: DateTime.utc_now()
    })
    
    # Give time for connections to drain
    Process.sleep(5000)
    
    Logger.info("Graceful shutdown preparation complete")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:ready?, _from, state) do
    ready = state.node_ready and check_application_health()
    {:reply, ready, state}
  end

  @impl true
  def handle_call(:alive?, _from, state) do
    alive = Process.alive?(self()) and check_critical_processes()
    {:reply, alive, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Check cluster health
    current_nodes = Node.list()
    
    # Update node readiness
    node_ready = check_node_readiness()
    
    # Detect node changes
    if length(current_nodes) != length(state.cluster_nodes) do
      Logger.info("Cluster size changed: #{length(state.cluster_nodes)} -> #{length(current_nodes)}")
      
      publish_event(:cluster_size_changed, %{
        previous_size: length(state.cluster_nodes),
        current_size: length(current_nodes),
        nodes: current_nodes,
        timestamp: DateTime.utc_now()
      })
    end
    
    # Check for failed nodes
    failed_nodes = state.cluster_nodes -- current_nodes
    new_nodes = current_nodes -- state.cluster_nodes
    
    Enum.each(failed_nodes, fn node ->
      Logger.warning("Node disconnected: #{node}")
      publish_event(:node_disconnected, %{node: node, timestamp: DateTime.utc_now()})
    end)
    
    Enum.each(new_nodes, fn node ->
      Logger.info("Node connected: #{node}")
      publish_event(:node_connected, %{node: node, timestamp: DateTime.utc_now()})
    end)
    
    # Schedule next health check
    timer = Process.send_after(self(), :health_check, state.health_check_interval)
    
    new_state = %{state | 
      cluster_nodes: current_nodes,
      node_ready: node_ready,
      health_timer: timer
    }
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:force_discovery, state) do
    # Force DNS resolution for cluster discovery
    case :inet_res.lookup(String.to_charlist(state.service_name), :in, :srv) do
      [] ->
        Logger.debug("No SRV records found for #{state.service_name}")
      records ->
        Logger.debug("Found #{length(records)} SRV records for #{state.service_name}")
    end
    
    {:noreply, state}
  end

  # Private Functions

  defp get_env_var(name, default) do
    System.get_env(name) || default
  end

  defp start_health_probes(state) do
    # Start readiness probe server
    start_probe_server(state.readiness_probe_port, :readiness)
    
    # Start liveness probe server
    start_probe_server(state.liveness_probe_port, :liveness)
  end

  defp start_probe_server(port, type) do
    case :ranch.start_listener(
      :"#{type}_probe", 
      :ranch_tcp, 
      %{port: port, num_acceptors: 1},
      __MODULE__.ProbeHandler,
      [type: type]
    ) do
      {:ok, _} ->
        Logger.info("Started #{type} probe server on port #{port}")
      {:error, :eaddrinuse} ->
        Logger.warning("Port #{port} already in use for #{type} probe")
      {:error, reason} ->
        Logger.error("Failed to start #{type} probe server: #{inspect(reason)}")
    end
  end

  defp check_node_readiness do
    # Check if all critical applications are running
    check_application_health() and 
    check_database_connectivity() and
    check_cluster_connectivity()
  end

  defp check_application_health do
    # Check critical GenServers
    critical_processes = [
      Aiex.Events.EventBus,
      Aiex.Context.Manager,
      Aiex.LLM.ModelCoordinator
    ]
    
    Enum.all?(critical_processes, fn process ->
      case Process.whereis(process) do
        nil -> false
        pid -> Process.alive?(pid)
      end
    end)
  end

  defp check_database_connectivity do
    # Check if Mnesia is running and tables are accessible
    try do
      :mnesia.system_info(:running_db_nodes) != []
    rescue
      _ -> false
    end
  end

  defp check_cluster_connectivity do
    # Check if we can communicate with other nodes
    case Node.list() do
      [] -> true  # Single node is okay
      nodes ->
        # Ping a random node to verify connectivity
        random_node = Enum.random(nodes)
        :net_adm.ping(random_node) == :pong
    end
  end

  defp check_critical_processes do
    # Check if critical system processes are running
    critical_apps = [:kernel, :stdlib, :sasl, :crypto]
    
    Enum.all?(critical_apps, fn app ->
      case Application.ensure_started(app) do
        :ok -> true
        {:error, {:already_started, ^app}} -> true
        _ -> false
      end
    end)
  end

  defp get_pod_start_time do
    # Get process start time as approximation
    {:ok, start_time} = :erlang.system_info(:start_time)
    start_time
  end

  defp get_cluster_ip do
    # Try to get cluster IP from environment
    case System.get_env("CLUSTER_IP") do
      nil ->
        # Fallback to resolving service name
        case :inet.gethostbyname(String.to_charlist("aiex-service")) do
          {:ok, hostent} ->
            :inet.ntoa(elem(hostent, 5) |> hd()) |> to_string()
          _ -> "unknown"
        end
      ip -> ip
    end
  end

  defp get_pod_ip do
    # Get pod IP from environment or network interface
    case System.get_env("POD_IP") do
      nil ->
        # Fallback to getting IP from network interface
        case :inet.getif() do
          {:ok, interfaces} ->
            # Find first non-loopback interface
            interfaces
            |> Enum.find(fn {ip, _broadcast, _netmask} ->
              ip != {127, 0, 0, 1}
            end)
            |> case do
              {ip, _, _} -> :inet.ntoa(ip) |> to_string()
              nil -> "unknown"
            end
          _ -> "unknown"
        end
      ip -> ip
    end
  end

  defp publish_event(event_type, data) do
    case Process.whereis(Aiex.Events.EventBus) do
      nil -> :ok  # EventBus not started
      _pid ->
        EventBus.publish(event_type, data)
    end
  end
end

defmodule Aiex.K8s.ClusterCoordinator.ProbeHandler do
  @moduledoc """
  HTTP handler for Kubernetes health probes.
  """
  
  require Logger
  
  def start_link(ref, transport, opts) do
    pid = spawn_link(__MODULE__, :init, [ref, transport, opts])
    {:ok, pid}
  end
  
  def init(ref, transport, opts) do
    {:ok, socket} = :ranch.handshake(ref)
    loop(socket, transport, opts)
  end
  
  defp loop(socket, transport, opts) do
    case transport.recv(socket, 0, 5000) do
      {:ok, data} ->
        probe_type = Keyword.get(opts, :type, :unknown)
        response = handle_probe(probe_type, data)
        transport.send(socket, response)
        :ok = transport.close(socket)
        
      {:error, :closed} ->
        :ok
        
      {:error, reason} ->
        Logger.warning("Probe connection error: #{inspect(reason)}")
        :ok = transport.close(socket)
    end
  end
  
  defp handle_probe(:readiness, _data) do
    case Aiex.K8s.ClusterCoordinator.ready?() do
      true ->
        "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nReady"
      false ->
        "HTTP/1.1 503 Service Unavailable\r\nContent-Length: 9\r\n\r\nNot Ready"
    end
  end
  
  defp handle_probe(:liveness, _data) do
    case Aiex.K8s.ClusterCoordinator.alive?() do
      true ->
        "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nAlive"
      false ->
        "HTTP/1.1 503 Service Unavailable\r\nContent-Length: 4\r\n\r\nDead"
    end
  end
  
  defp handle_probe(_type, _data) do
    "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nNot Found"
  end
end