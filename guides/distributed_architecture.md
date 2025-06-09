# Distributed Architecture Guide

## Overview

Aiex implements a sophisticated distributed architecture built entirely on OTP (Open Telecom Platform) primitives. This design achieves horizontal scalability, fault tolerance, and high availability without external dependencies, while providing optional enhancement through libcluster for production deployments. The system leverages Elixir's actor model and Erlang's battle-tested distributed computing capabilities to create a production-ready foundation for AI coding assistance.

## Table of Contents

1. [Architectural Principles](#architectural-principles)
2. [System Overview](#system-overview)
3. [Supervision Trees](#supervision-trees)
4. [Distributed Coordination](#distributed-coordination)
5. [Storage and Persistence](#storage-and-persistence)
6. [Process Management](#process-management)
7. [Interface Coordination](#interface-coordination)
8. [Configuration Management](#configuration-management)
9. [Clustering and Discovery](#clustering-and-discovery)
10. [Fault Tolerance](#fault-tolerance)
11. [Deployment Patterns](#deployment-patterns)
12. [Monitoring and Observability](#monitoring-and-observability)
13. [Performance Optimization](#performance-optimization)
14. [Troubleshooting](#troubleshooting)

## Architectural Principles

### Pure OTP Design

Aiex's distributed architecture follows these core principles:

- **No External Dependencies**: Core distribution uses only Erlang/OTP primitives
- **Actor Model**: Everything is a process with isolated state and message passing
- **Fault Tolerance**: "Let it crash" philosophy with comprehensive supervision
- **Location Transparency**: Processes can run anywhere in the cluster
- **Hot Code Swapping**: Support for zero-downtime deployments

### Design Goals

```
┌─────────────────────────────────────────────────────────────┐
│                    Design Objectives                        │
├─────────────────┬─────────────────┬─────────────────────────┤
│ Horizontal      │ Fault           │ Zero External           │
│ Scalability     │ Tolerance       │ Dependencies            │
├─────────────────┼─────────────────┼─────────────────────────┤
│ • Add nodes     │ • Process       │ • Pure OTP              │
│   dynamically   │   isolation     │ • pg coordination       │
│ • Load balance  │ • Supervision   │ • Mnesia storage        │
│ • Auto failover │ • Circuit       │ • Optional libcluster   │
│               │   breakers      │   enhancement           │
└─────────────────┴─────────────────┴─────────────────────────┘
```

## System Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Interface Layer                          │
├─────────────────┬─────────────────┬─────────────────────────┤
│      CLI        │       TUI       │    LSP / LiveView       │
│   (Terminal)    │   (Rust App)    │   (Future Interfaces)   │
└─────────────────┴─────────────────┴─────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────┐
│                 Interface Gateway                           │
│         (Unified Business Logic Routing)                   │
└─────────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────┐
│                  Distributed Services                       │
├─────────────────┬─────────────────┬─────────────────────────┤
│  AI Coordination│ Context Engine  │   Event Sourcing        │
│ (Multi-LLM)     │(Analysis Cache) │  (Audit & Recovery)     │
└─────────────────┴─────────────────┴─────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────┐
│              Distributed Foundation                         │
├─────────────────┬─────────────────┬─────────────────────────┤
│      pg         │     Mnesia      │        Horde            │
│ (Coordination)  │ (Persistence)   │  (Process Registry)     │
└─────────────────┴─────────────────┴─────────────────────────┘
```

### Node Types and Roles

Aiex supports heterogeneous cluster deployments with specialized node roles:

**Coordinator Nodes** (`aiex@coordinator-1`)
- Event sourcing and audit logging
- Distributed configuration management
- Cluster health monitoring
- Session lifecycle management

**Worker Nodes** (`aiex@worker-1`, `aiex@worker-2`)
- AI processing and LLM coordination
- Context analysis and caching
- Code generation and explanation
- Load balancing across providers

**Interface Nodes** (`aiex@interface-1`)
- CLI and TUI server endpoints
- WebSocket connections for LiveView
- LSP protocol handling
- Rate limiting and authentication

## Supervision Trees

### Root Application Supervisor

The main application supervisor in `lib/aiex.ex` orchestrates the entire distributed system:

```elixir
defmodule Aiex.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Core Infrastructure
      core_infrastructure(),
      
      # Distributed Coordination
      distributed_coordination(),
      
      # Business Logic Services
      business_services(),
      
      # Optional External Interfaces
      external_interfaces()
    ] |> List.flatten() |> Enum.reject(&is_nil/1)

    opts = [strategy: :one_for_one, name: Aiex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp core_infrastructure do
    [
      # Local process registry
      {Registry, keys: :unique, name: Aiex.Registry},
      
      # Distributed process registry and supervision
      {Horde.Registry, name: Aiex.HordeRegistry, keys: :unique},
      {Horde.DynamicSupervisor, name: Aiex.HordeSupervisor, 
       strategy: :one_for_one}
    ]
  end

  defp distributed_coordination do
    [
      # Event bus for distributed communication
      Aiex.Events.EventBus,
      
      # Distributed configuration management
      Aiex.Config.DistributedConfig,
      
      # Optional clustering
      cluster_supervisor()
    ]
  end

  defp business_services do
    [
      # Context management and analysis
      Aiex.Context.DistributedEngine,
      Aiex.Context.Manager,
      
      # Multi-LLM coordination
      {Aiex.LLM.ModelCoordinator, []},
      
      # Interface gateway
      {Aiex.InterfaceGateway, []}
    ]
  end

  defp external_interfaces do
    [
      # TUI server and event bridge
      tui_supervisor(),
      
      # NATS bridge for external integration
      nats_supervisor()
    ]
  end
end
```

### Specialized Supervisors

**Context Supervisor** - Manages distributed context processing:
```elixir
defmodule Aiex.Context.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    children = [
      # Distributed storage engine
      {Aiex.Context.DistributedEngine, []},
      
      # Context session manager
      {Aiex.Context.Manager, []},
      
      # Session supervisor for dynamic processes
      {Aiex.Context.SessionSupervisor, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

**LLM Coordinator Supervisor** - Manages AI processing distribution:
```elixir
defmodule Aiex.LLM.Supervisor do
  use Supervisor

  def init(_init_arg) do
    children = [
      # Rate limiting and circuit breakers
      {Aiex.LLM.RateLimiter, []},
      
      # Provider coordination
      {Aiex.LLM.ModelCoordinator, []},
      
      # Response processing
      {Aiex.LLM.ResponseParser, []},
      
      # Template management
      {Aiex.LLM.Templates.Supervisor, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

### Restart Strategies

Different components use appropriate restart strategies:

- **`:one_for_one`**: Core services that should restart independently
- **`:rest_for_one`**: Dependent services where failure cascades
- **`:one_for_all`**: Tightly coupled services that must restart together

```elixir
# Example of strategic restart configuration
defp critical_services do
  [
    {EventStore, restart: :permanent, shutdown: :brutal_kill},
    {DistributedEngine, restart: :permanent, shutdown: 5000},
    {ModelCoordinator, restart: :transient, shutdown: 10000}
  ]
end
```

## Distributed Coordination

### Process Groups with pg

Aiex uses Erlang's `pg` module for distributed process coordination without external dependencies:

```elixir
defmodule Aiex.Events.EventBus do
  @event_scope :aiex_events

  def subscribe(topic) when is_atom(topic) do
    :pg.join(@event_scope, topic, self())
  end

  def publish(topic, event) when is_atom(topic) do
    # Get all subscribers across the cluster
    members = :pg.get_members(@event_scope, topic)
    
    # Enrich event with cluster metadata
    enriched_event = enrich_event(event)
    
    # Dispatch concurrently with backpressure
    Task.async_stream(
      members,
      fn pid -> safe_dispatch(pid, enriched_event) end,
      max_concurrency: 100,
      timeout: 5000
    )
    |> Stream.run()
  end

  defp enrich_event(event) do
    event
    |> Map.put(:node, node())
    |> Map.put(:timestamp, DateTime.utc_now())
    |> Map.put(:correlation_id, UUID.uuid4())
  end

  defp safe_dispatch(pid, event) do
    try do
      send(pid, {:event, event})
      :ok
    catch
      _, _ -> {:error, :dispatch_failed}
    end
  end
end
```

### Event-Driven Communication

All inter-service communication uses events for loose coupling:

```elixir
# Publishing domain events
EventBus.publish(:ai_request, %{
  type: :code_analysis_requested,
  session_id: session_id,
  file_path: file_path,
  requested_by: :cli_interface
})

# Subscribing to relevant events
EventBus.subscribe(:ai_request)
EventBus.subscribe(:context_updated)
EventBus.subscribe(:llm_response)

# Handling events in GenServer
def handle_info({:event, %{type: :code_analysis_requested} = event}, state) do
  # Process the analysis request
  result = analyze_code(event.file_path, event.session_id)
  
  # Publish completion event
  EventBus.publish(:ai_response, %{
    type: :code_analysis_completed,
    session_id: event.session_id,
    result: result,
    correlation_id: event.correlation_id
  })
  
  {:noreply, state}
end
```

### Cross-Node Coordination

The system handles cross-node coordination patterns:

```elixir
defmodule Aiex.Coordination.ClusterManager do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Monitor node changes
    :net_kernel.monitor_nodes(true, [nodedown_reason])
    
    # Join cluster coordination group
    :pg.join(:aiex_cluster, :coordinators, self())
    
    {:ok, %{nodes: [node() | Node.list()], last_sync: DateTime.utc_now()}}
  end

  def handle_info({:nodeup, node}, state) do
    Logger.info("Node joined cluster: #{node}")
    
    # Sync configuration with new node
    sync_configuration_with_node(node)
    
    # Redistribute processes if needed
    maybe_rebalance_processes()
    
    {:noreply, %{state | nodes: [node | state.nodes]}}
  end

  def handle_info({:nodedown, node, reason}, state) do
    Logger.warn("Node left cluster: #{node}, reason: #{inspect(reason)}")
    
    # Handle process migration
    migrate_processes_from_node(node)
    
    {:noreply, %{state | nodes: List.delete(state.nodes, node)}}
  end

  defp migrate_processes_from_node(failed_node) do
    # Find processes that were running on the failed node
    failed_processes = Horde.Registry.select(Aiex.HordeRegistry, [
      {{:"$1", :"$2", :"$3"}, [{:==, {:node, :"$2"}, failed_node}], [:"$1"]}
    ])
    
    # Restart them on available nodes
    Enum.each(failed_processes, fn {name, _pid, _value} ->
      Horde.DynamicSupervisor.start_child(
        Aiex.HordeSupervisor,
        {ProcessWorker, name: name}
      )
    end)
  end
end
```

## Storage and Persistence

### Mnesia Distributed Database

Aiex uses Mnesia for distributed, ACID-compliant storage:

```elixir
defmodule Aiex.Storage.MnesiaSetup do
  @tables [
    :ai_context,
    :code_analysis_cache,
    :llm_interaction,
    :event_store,
    :audit_log
  ]

  def setup_cluster(nodes) do
    # Create schema on all nodes
    case :mnesia.create_schema(nodes) do
      :ok -> :ok
      {:error, {_, {:already_exists, _}}} -> :ok
      error -> error
    end

    # Start Mnesia on all nodes
    Enum.each(nodes, fn node ->
      :rpc.call(node, :mnesia, :start, [])
    end)

    # Create tables with appropriate replication
    Enum.each(@tables, &create_table(&1, nodes))
    
    # Wait for tables to be available
    :mnesia.wait_for_tables(@tables, 30_000)
  end

  defp create_table(table, nodes) do
    # Determine replication strategy based on cluster size
    replication_type = if length(nodes) > 1, do: :disc_copies, else: :ram_copies
    
    table_def = case table do
      :ai_context ->
        [
          {replication_type, nodes},
          {:attributes, [:session_id, :context, :updated_at]},
          {:index, [:updated_at]},
          {:type, :set}
        ]
      
      :event_store ->
        [
          {replication_type, nodes},
          {:attributes, [:id, :aggregate_id, :type, :data, :version, :timestamp]},
          {:index, [:aggregate_id, :type, :timestamp]},
          {:type, :ordered_set}
        ]
      
      _ ->
        default_table_config(replication_type, nodes)
    end

    :mnesia.create_table(table, table_def)
  end

  def transaction(fun) do
    case :mnesia.transaction(fun) do
      {:atomic, result} -> {:ok, result}
      {:aborted, reason} -> {:error, reason}
    end
  end
end
```

### Tiered Storage Strategy

The context engine implements a three-tier storage strategy:

```elixir
defmodule Aiex.Context.StorageTiers do
  # Hot tier - frequently accessed data in ETS
  @hot_tier :hot_context
  
  # Warm tier - recent but less active data in ETS
  @warm_tier :warm_context
  
  # Cold tier - archived data in DETS/Mnesia
  @cold_tier :cold_context

  def store(key, value, opts \\ []) do
    tier = Keyword.get(opts, :tier, determine_tier(key, value))
    
    case tier do
      :hot -> 
        :ets.insert(@hot_tier, {key, value, System.monotonic_time(), 1})
      :warm -> 
        :ets.insert(@warm_tier, {key, value, System.monotonic_time()})
      :cold -> 
        compressed_value = compress_if_large(value)
        :mnesia.dirty_write(@cold_tier, {key, compressed_value, DateTime.utc_now()})
    end
  end

  def get(key) do
    # Try hot tier first
    case :ets.lookup(@hot_tier, key) do
      [{^key, value, timestamp, access_count}] ->
        # Increment access count and update timestamp
        :ets.update_element(@hot_tier, key, [{4, access_count + 1}, {3, System.monotonic_time()}])
        {:ok, value}
      
      [] ->
        # Try warm tier
        case :ets.lookup(@warm_tier, key) do
          [{^key, value, _timestamp}] ->
            # Promote to hot tier if accessed frequently
            maybe_promote_to_hot(key, value)
            {:ok, value}
          
          [] ->
            # Try cold tier
            case :mnesia.dirty_read(@cold_tier, key) do
              [{^key, compressed_value, _timestamp}] ->
                value = decompress_if_needed(compressed_value)
                # Consider promoting to warm tier
                maybe_promote_to_warm(key, value)
                {:ok, value}
              
              [] ->
                {:error, :not_found}
            end
        end
    end
  end

  defp determine_tier(key, value) do
    cond do
      is_frequently_accessed?(key) -> :hot
      is_recent_data?(value) -> :warm
      true -> :cold
    end
  end
end
```

## Process Management

### Horde Distributed Registry

Horde provides distributed process registry and dynamic supervision:

```elixir
defmodule Aiex.Context.Session do
  use GenServer

  def start_link(session_id) do
    # Register in distributed registry
    GenServer.start_link(__MODULE__, session_id, 
      name: {:via, Horde.Registry, {Aiex.HordeRegistry, {:session, session_id}}}
    )
  end

  def find_session(session_id) do
    case Horde.Registry.lookup(Aiex.HordeRegistry, {:session, session_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  def create_session(session_id, opts \\ []) do
    child_spec = %{
      id: {:session, session_id},
      start: {__MODULE__, :start_link, [session_id]},
      restart: :transient
    }

    case Horde.DynamicSupervisor.start_child(Aiex.HordeSupervisor, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  # GenServer callbacks
  def init(session_id) do
    # Set up process state
    state = %{
      session_id: session_id,
      context: %{},
      last_activity: DateTime.utc_now(),
      node: node()
    }

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup_check, 60_000)

    {:ok, state}
  end

  def handle_info(:cleanup_check, state) do
    # Check if session should be cleaned up
    if session_expired?(state) do
      {:stop, :normal, state}
    else
      Process.send_after(self(), :cleanup_check, 60_000)
      {:noreply, state}
    end
  end
end
```

### Dynamic Supervision

Dynamic supervisors handle varying workloads:

```elixir
defmodule Aiex.LLM.RequestSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one, max_children: 100)
  end

  def process_request(request) do
    child_spec = %{
      id: {:request_worker, make_ref()},
      start: {Aiex.LLM.RequestWorker, :start_link, [request]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
end

defmodule Aiex.LLM.RequestWorker do
  use GenServer, restart: :temporary

  def start_link(request) do
    GenServer.start_link(__MODULE__, request)
  end

  def init(request) do
    # Process the request asynchronously
    send(self(), :process_request)
    {:ok, %{request: request, start_time: DateTime.utc_now()}}
  end

  def handle_info(:process_request, state) do
    # Process the LLM request
    result = process_llm_request(state.request)
    
    # Publish result event
    EventBus.publish(:llm_response, %{
      request_id: state.request.id,
      result: result,
      processing_time: DateTime.diff(DateTime.utc_now(), state.start_time, :millisecond)
    })

    # Worker shuts down after completing the task
    {:stop, :normal, state}
  end
end
```

## Interface Coordination

### Unified Interface Gateway

The `InterfaceGateway` provides a unified entry point for all interfaces:

```elixir
defmodule Aiex.InterfaceGateway do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def request(interface_type, request, opts \\ []) do
    GenServer.call(__MODULE__, {:request, interface_type, request, opts})
  end

  def handle_call({:request, interface_type, request, opts}, from, state) do
    # Create request context
    request_info = %{
      interface: interface_type,
      from: from,
      timestamp: DateTime.utc_now(),
      correlation_id: UUID.uuid4()
    }

    # Route to appropriate service
    case route_request(request, request_info) do
      {:async, correlation_id} ->
        # Store async request for later response
        state = store_async_request(state, correlation_id, from)
        {:reply, {:ok, :async, correlation_id}, state}
      
      {:sync, result} ->
        {:reply, {:ok, result}, state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp route_request(%{type: :completion} = request, request_info) do
    # Route to LLM coordinator
    Aiex.LLM.ModelCoordinator.request_completion(
      request.prompt,
      request.options,
      request_info
    )
  end

  defp route_request(%{type: :analysis} = request, request_info) do
    # Route to context engine
    Aiex.Context.DistributedEngine.analyze_code(
      request.file_path,
      request.options,
      request_info
    )
  end

  defp route_request(%{type: :session_create} = request, request_info) do
    # Route to session manager
    Aiex.Sessions.DistributedSessionManager.create_session(
      request.user_id,
      request.options,
      request_info
    )
  end

  # Handle async responses
  def handle_info({:async_response, correlation_id, result}, state) do
    case get_async_request(state, correlation_id) do
      {:ok, from} ->
        GenServer.reply(from, {:ok, result})
        state = remove_async_request(state, correlation_id)
        {:noreply, state}
      
      {:error, :not_found} ->
        Logger.warn("Received response for unknown correlation_id: #{correlation_id}")
        {:noreply, state}
    end
  end
end
```

### Multi-Interface Support

The system supports multiple interface types with consistent behavior:

```elixir
# CLI Interface
defmodule Aiex.Interfaces.CLIInterface do
  def handle_command(["analyze", file_path], opts) do
    request = %{type: :analysis, file_path: file_path, options: opts}
    
    case InterfaceGateway.request(:cli, request) do
      {:ok, result} -> format_cli_result(result)
      {:error, reason} -> format_cli_error(reason)
    end
  end
end

# TUI Interface
defmodule Aiex.Interfaces.TUIInterface do
  def handle_message(%{action: "analyze_file", file_path: file_path}, socket) do
    request = %{type: :analysis, file_path: file_path, options: %{}}
    
    case InterfaceGateway.request(:tui, request) do
      {:ok, :async, correlation_id} ->
        # Store correlation_id for async response
        {:noreply, assign(socket, :pending_analysis, correlation_id)}
      
      {:ok, result} ->
        # Send immediate response
        {:reply, {:ok, format_tui_result(result)}, socket}
    end
  end
end

# Future LiveView Interface
defmodule Aiex.Interfaces.LiveViewInterface do
  use Phoenix.LiveView

  def handle_event("analyze_file", %{"file_path" => file_path}, socket) do
    request = %{type: :analysis, file_path: file_path, options: %{}}
    
    case InterfaceGateway.request(:liveview, request) do
      {:ok, :async, correlation_id} ->
        {:noreply, assign(socket, :loading, true)}
      
      {:ok, result} ->
        {:noreply, assign(socket, :analysis_result, result)}
    end
  end
end
```

## Configuration Management

### Distributed Configuration

The `DistributedConfig` module synchronizes configuration across the cluster:

```elixir
defmodule Aiex.Config.DistributedConfig do
  use GenServer

  @config_table :aiex_distributed_config
  @sync_interval 30_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def set(app, key, value) do
    GenServer.call(__MODULE__, {:set, app, key, value})
  end

  def get(app, key, default \\ nil) do
    case :ets.lookup(@config_table, {app, key}) do
      [{_, value, _node, _timestamp}] -> value
      [] -> default
    end
  end

  def init(_opts) do
    # Create ETS table for fast local access
    :ets.new(@config_table, [
      :set, :public, :named_table, 
      {:read_concurrency, true}
    ])

    # Subscribe to cluster events
    :pg.join(:aiex_cluster, :config_managers, self())
    
    # Schedule periodic synchronization
    Process.send_after(self(), :sync_config, @sync_interval)

    {:ok, %{}}
  end

  def handle_call({:set, app, key, value}, _from, state) do
    timestamp = DateTime.utc_now()
    node = node()
    
    # Store locally
    :ets.insert(@config_table, {{app, key}, value, node, timestamp})
    
    # Broadcast to cluster
    broadcast_config_change(app, key, value, node, timestamp)
    
    # Update application config
    Application.put_env(app, key, value)
    
    {:reply, :ok, state}
  end

  def handle_info({:config_change, app, key, value, remote_node, timestamp}, state) do
    # Check if this update is newer than local version
    case :ets.lookup(@config_table, {app, key}) do
      [{_, _current_value, _current_node, current_timestamp}] ->
        if DateTime.compare(timestamp, current_timestamp) == :gt do
          accept_config_update(app, key, value, remote_node, timestamp)
        end
      
      [] ->
        accept_config_update(app, key, value, remote_node, timestamp)
    end

    {:noreply, state}
  end

  def handle_info(:sync_config, state) do
    # Sync with all nodes in cluster
    sync_with_cluster_nodes()
    
    # Schedule next sync
    Process.send_after(self(), :sync_config, @sync_interval)
    
    {:noreply, state}
  end

  defp broadcast_config_change(app, key, value, node, timestamp) do
    members = :pg.get_members(:aiex_cluster, :config_managers)
    
    Enum.each(members, fn pid ->
      if node(pid) != node() do
        send(pid, {:config_change, app, key, value, node, timestamp})
      end
    end)
  end

  defp accept_config_update(app, key, value, remote_node, timestamp) do
    # Update local cache
    :ets.insert(@config_table, {{app, key}, value, remote_node, timestamp})
    
    # Update application configuration
    Application.put_env(app, key, value)
    
    Logger.info("Accepted config update from #{remote_node}: #{app}.#{key}")
  end
end
```

## Clustering and Discovery

### Optional Clustering with libcluster

Aiex supports optional clustering for production deployments:

```elixir
defmodule Aiex.Clustering do
  def cluster_supervisor do
    with true <- Application.get_env(:aiex, :cluster_enabled, false),
         {:ok, _} <- Application.ensure_loaded(:libcluster),
         topologies when not is_nil(topologies) <- 
           Application.get_env(:libcluster, :topologies) do
      
      {Cluster.Supervisor, [topologies, [name: Aiex.ClusterSupervisor]]}
    else
      _ -> 
        Logger.info("Clustering disabled, running in single-node mode")
        nil
    end
  end

  def setup_production_clustering do
    # Kubernetes DNS-based discovery
    config = [
      aiex_cluster: [
        strategy: Cluster.Strategy.Kubernetes.DNS,
        config: [
          service: "aiex-headless",
          application_name: "aiex",
          polling_interval: 10_000
        ]
      ]
    ]

    Application.put_env(:libcluster, :topologies, config)
    Application.put_env(:aiex, :cluster_enabled, true)
  end

  def setup_development_clustering(nodes) do
    # Static node list for development
    config = [
      aiex_cluster: [
        strategy: Cluster.Strategy.Epmd,
        config: [hosts: nodes]
      ]
    ]

    Application.put_env(:libcluster, :topologies, config)
    Application.put_env(:aiex, :cluster_enabled, true)
  end
end
```

### Node Discovery Strategies

**Kubernetes DNS Strategy** (Production):
```yaml
# kubernetes/aiex-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: aiex-headless
spec:
  clusterIP: None
  selector:
    app: aiex
  ports:
  - port: 4369
    name: epmd
  - port: 25000
    name: distributed
```

**EPMD Strategy** (Development):
```elixir
# Start nodes manually for development
iex --sname aiex1@localhost --cookie aiex_cluster -S mix
iex --sname aiex2@localhost --cookie aiex_cluster -S mix
iex --sname aiex3@localhost --cookie aiex_cluster -S mix
```

**Gossip Strategy** (Multi-datacenter):
```elixir
config :libcluster,
  topologies: [
    aiex_cluster: [
      strategy: Cluster.Strategy.Gossip,
      config: [
        port: 45892,
        if_addr: "0.0.0.0",
        multicast_addr: "230.1.1.251",
        multicast_ttl: 1,
        secret: "aiex_cluster_secret"
      ]
    ]
  ]
```

## Fault Tolerance

### Circuit Breaker Pattern

Circuit breakers protect against cascading failures:

```elixir
defmodule Aiex.LLM.CircuitBreaker do
  use GenServer

  defstruct [
    :name,
    :failure_threshold,
    :recovery_time,
    :timeout,
    state: :closed,
    failure_count: 0,
    last_failure_time: nil,
    total_requests: 0,
    successful_requests: 0
  ]

  def call(circuit_breaker, fun, args \\ []) do
    GenServer.call(circuit_breaker, {:call, fun, args})
  end

  def handle_call({:call, fun, args}, _from, %{state: :open} = circuit) do
    if should_attempt_reset?(circuit) do
      # Try to reset circuit
      attempt_call(fun, args, %{circuit | state: :half_open})
    else
      {:reply, {:error, :circuit_open}, circuit}
    end
  end

  def handle_call({:call, fun, args}, _from, circuit) do
    attempt_call(fun, args, circuit)
  end

  defp attempt_call(fun, args, circuit) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      result = apply(fun, args)
      processing_time = System.monotonic_time(:millisecond) - start_time
      
      if processing_time > circuit.timeout do
        # Timeout is considered a failure
        new_circuit = record_failure(circuit)
        {:reply, {:error, :timeout}, new_circuit}
      else
        # Success
        new_circuit = record_success(circuit)
        {:reply, {:ok, result}, new_circuit}
      end
    rescue
      error ->
        new_circuit = record_failure(circuit)
        {:reply, {:error, error}, new_circuit}
    end
  end

  defp record_success(circuit) do
    %{circuit |
      state: :closed,
      failure_count: 0,
      successful_requests: circuit.successful_requests + 1,
      total_requests: circuit.total_requests + 1
    }
  end

  defp record_failure(circuit) do
    new_failure_count = circuit.failure_count + 1
    new_state = if new_failure_count >= circuit.failure_threshold do
      :open
    else
      circuit.state
    end

    %{circuit |
      state: new_state,
      failure_count: new_failure_count,
      last_failure_time: DateTime.utc_now(),
      total_requests: circuit.total_requests + 1
    }
  end

  defp should_attempt_reset?(circuit) do
    case circuit.last_failure_time do
      nil -> true
      last_failure ->
        DateTime.diff(DateTime.utc_now(), last_failure, :millisecond) > circuit.recovery_time
    end
  end
end
```

### Health Monitoring

Comprehensive health monitoring across the cluster:

```elixir
defmodule Aiex.Health.Monitor do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_cluster_health do
    GenServer.call(__MODULE__, :get_cluster_health)
  end

  def init(_opts) do
    # Monitor node changes
    :net_kernel.monitor_nodes(true)
    
    # Schedule periodic health checks
    Process.send_after(self(), :health_check, 5_000)

    {:ok, %{
      nodes: %{},
      last_check: DateTime.utc_now(),
      alerts: []
    }}
  end

  def handle_info(:health_check, state) do
    # Check all nodes in cluster
    node_health = check_all_nodes()
    
    # Check critical services
    service_health = check_critical_services()
    
    # Check resource usage
    resource_health = check_resource_usage()
    
    # Detect issues and generate alerts
    alerts = detect_issues(node_health, service_health, resource_health)
    
    new_state = %{state |
      nodes: node_health,
      last_check: DateTime.utc_now(),
      alerts: alerts
    }

    # Schedule next check
    Process.send_after(self(), :health_check, 30_000)
    
    {:noreply, new_state}
  end

  defp check_all_nodes do
    [node() | Node.list()]
    |> Enum.map(fn node ->
      health = check_node_health(node)
      {node, health}
    end)
    |> Map.new()
  end

  defp check_node_health(node) do
    checks = [
      {:connectivity, check_connectivity(node)},
      {:memory, check_memory_usage(node)},
      {:process_count, check_process_count(node)},
      {:mnesia, check_mnesia_status(node)},
      {:load, check_system_load(node)}
    ]

    %{
      status: overall_status(checks),
      checks: Map.new(checks),
      timestamp: DateTime.utc_now()
    }
  end

  defp check_connectivity(node) do
    case :net_adm.ping(node) do
      :pong -> :healthy
      :pang -> :unhealthy
    end
  end

  defp check_critical_services do
    services = [
      Aiex.Events.EventBus,
      Aiex.Context.DistributedEngine,
      Aiex.LLM.ModelCoordinator,
      Aiex.InterfaceGateway
    ]

    Enum.map(services, fn service ->
      status = if Process.whereis(service), do: :running, else: :stopped
      {service, status}
    end)
    |> Map.new()
  end
end
```

### Graceful Degradation

Services degrade gracefully when dependencies fail:

```elixir
defmodule Aiex.LLM.ModelCoordinator do
  use GenServer

  def request_completion(prompt, opts, request_info) do
    GenServer.call(__MODULE__, {:completion, prompt, opts, request_info})
  end

  def handle_call({:completion, prompt, opts, request_info}, from, state) do
    case select_provider(state.providers, opts) do
      {:ok, provider} ->
        # Attempt with primary provider
        attempt_completion(provider, prompt, opts, from, state)
      
      {:error, :no_providers_available} ->
        # Graceful degradation
        fallback_response(prompt, opts, from, state)
    end
  end

  defp attempt_completion(provider, prompt, opts, from, state) do
    case provider.completion(prompt, opts) do
      {:ok, result} ->
        {:reply, {:ok, result}, state}
      
      {:error, reason} ->
        # Try fallback provider
        case select_fallback_provider(state.providers, provider) do
          {:ok, fallback_provider} ->
            attempt_completion(fallback_provider, prompt, opts, from, state)
          
          {:error, :no_fallback} ->
            fallback_response(prompt, opts, from, state)
        end
    end
  end

  defp fallback_response(prompt, opts, from, state) do
    # Use cached responses or simple templates
    case get_cached_response(prompt) do
      {:ok, cached_result} ->
        Logger.info("Using cached response due to provider failure")
        {:reply, {:ok, cached_result}, state}
      
      {:error, :not_found} ->
        # Generate basic template response
        template_result = generate_template_response(prompt, opts)
        Logger.warn("Using template response due to all provider failures")
        {:reply, {:ok, template_result}, state}
    end
  end
end
```

## Deployment Patterns

### Single Node Development

For development, Aiex runs efficiently on a single node:

```elixir
# config/dev.exs
config :aiex,
  cluster_enabled: false,
  interfaces: [:cli, :tui],
  storage_mode: :local

# Start development environment
make dev
# or
iex -S mix
```

### Multi-Node Development

For testing distributed features:

```bash
# Terminal 1
AIEX_NODE_NAME=aiex1@localhost iex --name aiex1@localhost -S mix

# Terminal 2  
AIEX_NODE_NAME=aiex2@localhost iex --name aiex2@localhost -S mix

# Terminal 3
AIEX_NODE_NAME=aiex3@localhost iex --name aiex3@localhost -S mix

# Connect nodes
Node.connect(:"aiex2@localhost")
Node.connect(:"aiex3@localhost")
```

### Kubernetes Production Deployment

Production deployment using Kubernetes:

```yaml
# kubernetes/aiex-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aiex
spec:
  replicas: 3
  selector:
    matchLabels:
      app: aiex
  template:
    metadata:
      labels:
        app: aiex
    spec:
      containers:
      - name: aiex
        image: aiex:latest
        env:
        - name: CLUSTER_ENABLED
          value: "true"
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: KUBERNETES_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        ports:
        - containerPort: 4000
        - containerPort: 4369
        - containerPort: 25000
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
```

### Docker Compose Development

Multi-node development with Docker Compose:

```yaml
# docker-compose.yml
version: '3.8'
services:
  aiex1:
    build: .
    environment:
      - NODE_NAME=aiex1@aiex1
      - CLUSTER_ENABLED=true
      - DISCOVERY_STRATEGY=epmd
    ports:
      - "4000:4000"
    networks:
      - aiex_cluster

  aiex2:
    build: .
    environment:
      - NODE_NAME=aiex2@aiex2
      - CLUSTER_ENABLED=true
      - DISCOVERY_STRATEGY=epmd
    ports:
      - "4001:4000"
    networks:
      - aiex_cluster

  aiex3:
    build: .
    environment:
      - NODE_NAME=aiex3@aiex3
      - CLUSTER_ENABLED=true
      - DISCOVERY_STRATEGY=epmd
    ports:
      - "4002:4000"
    networks:
      - aiex_cluster

networks:
  aiex_cluster:
    driver: bridge
```

## Monitoring and Observability

### Telemetry Integration

Comprehensive telemetry for monitoring:

```elixir
defmodule Aiex.Telemetry do
  def setup do
    events = [
      # Event sourcing metrics
      [:aiex, :events, :published],
      [:aiex, :events, :processed],
      
      # LLM coordination metrics
      [:aiex, :llm, :request, :start],
      [:aiex, :llm, :request, :stop],
      
      # Context engine metrics
      [:aiex, :context, :cache, :hit],
      [:aiex, :context, :cache, :miss],
      
      # Cluster health metrics
      [:aiex, :cluster, :node, :joined],
      [:aiex, :cluster, :node, :left]
    ]

    :telemetry.attach_many(
      "aiex-metrics",
      events,
      &handle_event/4,
      nil
    )
  end

  def handle_event([:aiex, :events, :published], measurements, metadata, _config) do
    # Track event publishing metrics
    :telemetry.execute([:aiex, :events, :published, :count], %{count: 1}, metadata)
    
    # Track processing time
    if processing_time = measurements[:processing_time] do
      :telemetry.execute(
        [:aiex, :events, :published, :duration], 
        %{duration: processing_time}, 
        metadata
      )
    end
  end

  def handle_event([:aiex, :llm, :request, :stop], measurements, metadata, _config) do
    # Track LLM request metrics
    :telemetry.execute(
      [:aiex, :llm, :request, :duration],
      %{duration: measurements.duration},
      metadata
    )

    # Track success/failure rates
    status = if measurements.error, do: :error, else: :success
    :telemetry.execute(
      [:aiex, :llm, :request, :result],
      %{count: 1},
      Map.put(metadata, :status, status)
    )
  end
end
```

### Prometheus Metrics

Export metrics for Prometheus monitoring:

```elixir
defmodule Aiex.Metrics.Prometheus do
  use Prometheus.Metric

  def setup do
    # Counter metrics
    Counter.declare([
      name: :aiex_events_published_total,
      help: "Total number of events published",
      labels: [:node, :event_type]
    ])

    Counter.declare([
      name: :aiex_llm_requests_total,
      help: "Total number of LLM requests",
      labels: [:provider, :status, :node]
    ])

    # Histogram metrics
    Histogram.declare([
      name: :aiex_llm_request_duration_seconds,
      help: "LLM request duration in seconds",
      labels: [:provider, :node],
      buckets: [0.1, 0.5, 1, 2, 5, 10, 30]
    ])

    # Gauge metrics
    Gauge.declare([
      name: :aiex_cluster_nodes,
      help: "Number of nodes in the cluster"
    ])

    Gauge.declare([
      name: :aiex_active_sessions,
      help: "Number of active sessions",
      labels: [:node]
    ])
  end

  def increment_events_published(event_type) do
    Counter.inc([
      name: :aiex_events_published_total,
      labels: [node(), event_type]
    ])
  end

  def observe_llm_request_duration(provider, duration) do
    Histogram.observe([
      name: :aiex_llm_request_duration_seconds,
      labels: [provider, node()]
    ], duration)
  end

  def set_cluster_size(size) do
    Gauge.set([name: :aiex_cluster_nodes], size)
  end
end
```

### Distributed Logging

Centralized logging across the cluster:

```elixir
defmodule Aiex.Logging.DistributedLogger do
  require Logger

  def log_cluster_event(level, message, metadata \\ []) do
    enriched_metadata = Keyword.merge(metadata, [
      node: node(),
      cluster_size: length([node() | Node.list()]),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    ])

    Logger.log(level, message, enriched_metadata)
    
    # Also send to centralized logging if configured
    maybe_send_to_central_logging(level, message, enriched_metadata)
  end

  defp maybe_send_to_central_logging(level, message, metadata) do
    case Application.get_env(:aiex, :central_logging) do
      nil -> :ok
      config -> send_to_central_logging(level, message, metadata, config)
    end
  end

  defp send_to_central_logging(level, message, metadata, config) do
    log_entry = %{
      level: level,
      message: message,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }

    # Send to configured central logging system
    case config.type do
      :elasticsearch -> send_to_elasticsearch(log_entry, config)
      :kafka -> send_to_kafka(log_entry, config)
      :file -> append_to_file(log_entry, config)
    end
  end
end
```

## Performance Optimization

### Load Balancing Strategies

Intelligent load balancing across cluster nodes:

```elixir
defmodule Aiex.LoadBalancer do
  def select_node_for_task(task_type, metadata \\ %{}) do
    available_nodes = get_available_nodes()
    
    case task_type do
      :llm_request ->
        select_by_llm_capacity(available_nodes, metadata)
      
      :context_analysis ->
        select_by_cpu_usage(available_nodes)
      
      :session_creation ->
        select_by_memory_usage(available_nodes)
      
      _ ->
        select_round_robin(available_nodes)
    end
  end

  defp select_by_llm_capacity(nodes, metadata) do
    provider = metadata[:provider]
    
    nodes
    |> Enum.map(fn node ->
      capacity = get_llm_capacity(node, provider)
      current_load = get_current_llm_load(node, provider)
      available_capacity = capacity - current_load
      
      {node, available_capacity}
    end)
    |> Enum.filter(fn {_node, capacity} -> capacity > 0 end)
    |> case do
      [] -> {:error, :no_capacity}
      node_capacities ->
        {node, _capacity} = Enum.max_by(node_capacities, fn {_node, capacity} -> 
          capacity 
        end)
        {:ok, node}
    end
  end

  defp select_by_cpu_usage(nodes) do
    nodes
    |> Enum.map(fn node ->
      cpu_usage = get_cpu_usage(node)
      {node, 100 - cpu_usage}  # Available CPU
    end)
    |> Enum.max_by(fn {_node, available_cpu} -> available_cpu end)
    |> elem(0)
    |> then(&{:ok, &1})
  end

  defp get_cpu_usage(node) do
    case :rpc.call(node, :cpu_sup, :avg1, []) do
      {:badrpc, _} -> 100  # Assume high load if can't measure
      load -> min(load * 100, 100)
    end
  end
end
```

### Memory Management

Efficient memory usage across the distributed system:

```elixir
defmodule Aiex.Memory.Manager do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Schedule periodic memory monitoring
    Process.send_after(self(), :memory_check, 30_000)

    {:ok, %{
      memory_threshold: 0.8,  # 80% memory usage threshold
      cleanup_strategies: [:context_cache, :event_history, :session_cleanup]
    }}
  end

  def handle_info(:memory_check, state) do
    memory_usage = get_memory_usage()
    
    if memory_usage > state.memory_threshold do
      Logger.warn("High memory usage detected: #{trunc(memory_usage * 100)}%")
      trigger_cleanup(state.cleanup_strategies)
    end

    # Schedule next check
    Process.send_after(self(), :memory_check, 30_000)
    
    {:noreply, state}
  end

  defp get_memory_usage do
    memory_info = :erlang.memory()
    total = memory_info[:total]
    system = memory_info[:system]
    
    # Calculate usage as percentage of system memory
    usage_ratio = total / (system * 4)  # Assume 4x system memory available
    min(usage_ratio, 1.0)
  end

  defp trigger_cleanup(strategies) do
    Enum.each(strategies, fn strategy ->
      case strategy do
        :context_cache ->
          Aiex.Context.Engine.cleanup_expired_data()
        
        :event_history ->
          Aiex.Events.EventStore.cleanup_old_events()
        
        :session_cleanup ->
          Aiex.Sessions.DistributedSessionManager.cleanup_expired_sessions()
      end
    end)
  end
end
```

### Caching Strategies

Multi-level caching for optimal performance:

```elixir
defmodule Aiex.Cache.DistributedCache do
  @cache_levels [:l1_local, :l2_cluster, :l3_persistent]

  def get(key, opts \\ []) do
    levels = Keyword.get(opts, :levels, @cache_levels)
    
    case try_cache_levels(key, levels) do
      {:hit, value, level} ->
        # Promote to higher cache levels
        promote_to_higher_levels(key, value, level)
        {:ok, value}
      
      :miss ->
        {:error, :not_found}
    end
  end

  def put(key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, 3600)
    levels = Keyword.get(opts, :levels, @cache_levels)
    
    Enum.each(levels, fn level ->
      store_in_cache_level(key, value, ttl, level)
    end)
    
    :ok
  end

  defp try_cache_levels(_key, []), do: :miss
  defp try_cache_levels(key, [level | remaining_levels]) do
    case get_from_cache_level(key, level) do
      {:ok, value} -> {:hit, value, level}
      {:error, :not_found} -> try_cache_levels(key, remaining_levels)
    end
  end

  defp get_from_cache_level(key, :l1_local) do
    # Local ETS cache
    case :ets.lookup(:l1_cache, key) do
      [{^key, value, expiry}] ->
        if System.system_time(:second) < expiry do
          {:ok, value}
        else
          :ets.delete(:l1_cache, key)
          {:error, :not_found}
        end
      [] ->
        {:error, :not_found}
    end
  end

  defp get_from_cache_level(key, :l2_cluster) do
    # Distributed ETS via pg
    cluster_nodes = [node() | Node.list()]
    
    cluster_nodes
    |> Task.async_stream(fn node ->
      :rpc.call(node, :ets, :lookup, [:l1_cache, key])
    end, timeout: 1000)
    |> Enum.find_value(fn
      {:ok, [{^key, value, expiry}]} ->
        if System.system_time(:second) < expiry, do: {:ok, value}
      _ -> 
        nil
    end)
    |> case do
      nil -> {:error, :not_found}
      result -> result
    end
  end

  defp get_from_cache_level(key, :l3_persistent) do
    # Mnesia persistent cache
    case :mnesia.dirty_read(:persistent_cache, key) do
      [{:persistent_cache, ^key, value, expiry}] ->
        if System.system_time(:second) < expiry do
          {:ok, value}
        else
          :mnesia.dirty_delete(:persistent_cache, key)
          {:error, :not_found}
        end
      [] ->
        {:error, :not_found}
    end
  end
end
```

## Troubleshooting

### Common Issues and Solutions

#### Split Brain Scenarios

When cluster nodes lose connectivity:

```elixir
defmodule Aiex.Troubleshooting.SplitBrain do
  def detect_split_brain do
    current_nodes = [node() | Node.list()]
    
    # Check if we can reach all expected nodes
    expected_nodes = get_expected_cluster_nodes()
    unreachable_nodes = expected_nodes -- current_nodes
    
    if length(unreachable_nodes) > 0 do
      Logger.error("Potential split brain detected. Unreachable nodes: #{inspect(unreachable_nodes)}")
      
      # Implement split brain resolution strategy
      resolve_split_brain(current_nodes, unreachable_nodes)
    end
  end

  defp resolve_split_brain(reachable_nodes, unreachable_nodes) do
    # Strategy 1: Majority wins
    total_expected = length(reachable_nodes) + length(unreachable_nodes)
    
    if length(reachable_nodes) > total_expected / 2 do
      Logger.info("This partition has majority, continuing operations")
      :continue_operations
    else
      Logger.warn("This partition lacks majority, entering read-only mode")
      enter_read_only_mode()
    end
  end

  defp enter_read_only_mode do
    # Disable write operations
    :ets.insert(:aiex_cluster_state, {:mode, :read_only})
    
    # Notify all services
    EventBus.publish(:cluster_management, %{
      type: :entering_read_only_mode,
      reason: :split_brain_minority
    })
  end
end
```

#### Memory Leaks

Detecting and resolving memory leaks:

```elixir
defmodule Aiex.Troubleshooting.MemoryLeaks do
  def diagnose_memory_usage do
    # Get process memory usage
    processes = :recon.proc_count(:memory, 20)
    
    # Identify potential leaks
    suspicious_processes = Enum.filter(processes, fn {pid, memory, _info} ->
      memory > 50_000_000  # 50MB threshold
    end)

    if length(suspicious_processes) > 0 do
      Logger.warn("Suspicious high-memory processes detected")
      
      Enum.each(suspicious_processes, fn {pid, memory, info} ->
        Logger.warn("High memory process: #{inspect(pid)}, Memory: #{memory}, Info: #{inspect(info)}")
        
        # Get detailed process information
        process_info = Process.info(pid, [:message_queue_len, :heap_size, :stack_size])
        Logger.warn("Process details: #{inspect(process_info)}")
      end)
    end

    # Check ETS table sizes
    check_ets_tables()
    
    # Check Mnesia table sizes
    check_mnesia_tables()
  end

  defp check_ets_tables do
    :ets.all()
    |> Enum.map(fn table ->
      size = :ets.info(table, :size)
      memory = :ets.info(table, :memory)
      {table, size, memory}
    end)
    |> Enum.filter(fn {_table, _size, memory} -> memory > 10_000_000 end)  # 10MB
    |> case do
      [] -> :ok
      large_tables ->
        Logger.warn("Large ETS tables detected: #{inspect(large_tables)}")
    end
  end
end
```

#### Network Partitions

Handling network partition recovery:

```elixir
defmodule Aiex.Troubleshooting.NetworkPartitions do
  def handle_partition_recovery do
    # Detect when nodes reconnect after partition
    previously_known_nodes = get_previously_known_nodes()
    current_nodes = [node() | Node.list()]
    
    reconnected_nodes = current_nodes -- [node()]
    
    if length(reconnected_nodes) > 0 do
      Logger.info("Nodes reconnected after partition: #{inspect(reconnected_nodes)}")
      
      # Synchronize state after partition
      synchronize_after_partition(reconnected_nodes)
    end
  end

  defp synchronize_after_partition(reconnected_nodes) do
    # Synchronize distributed configuration
    Aiex.Config.DistributedConfig.force_sync_with_nodes(reconnected_nodes)
    
    # Synchronize event stores
    Aiex.Events.EventStore.sync_with_nodes(reconnected_nodes)
    
    # Resolve session conflicts
    Aiex.Sessions.DistributedSessionManager.resolve_partition_conflicts(reconnected_nodes)
    
    # Redistribute processes
    redistribute_processes_after_partition(reconnected_nodes)
  end

  defp redistribute_processes_after_partition(reconnected_nodes) do
    # Get processes that might need redistribution
    all_processes = Horde.Registry.select(Aiex.HordeRegistry, [
      {{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}
    ])

    # Check for processes that should be redistributed
    Enum.each(all_processes, fn {name, pid, value} ->
      if should_redistribute_process?(name, pid, reconnected_nodes) do
        maybe_redistribute_process(name, pid, value)
      end
    end)
  end
end
```

### Debugging Tools

Comprehensive debugging utilities:

```elixir
defmodule Aiex.Debug do
  def cluster_status do
    %{
      local_node: node(),
      connected_nodes: Node.list(),
      cluster_size: length([node() | Node.list()]),
      pg_groups: :pg.which_groups(:aiex_events),
      horde_registry_count: Horde.Registry.count(Aiex.HordeRegistry),
      mnesia_running: :mnesia.system_info(:is_running),
      uptime: :erlang.statistics(:wall_clock) |> elem(0)
    }
  end

  def event_bus_status do
    groups = :pg.which_groups(:aiex_events)
    
    Enum.map(groups, fn group ->
      members = :pg.get_members(:aiex_events, group)
      {group, length(members), members}
    end)
  end

  def memory_report do
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

  def process_report do
    %{
      process_count: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      port_count: :erlang.system_info(:port_count),
      port_limit: :erlang.system_info(:port_limit)
    }
  end

  def trace_events(duration_ms \\ 10_000) do
    # Start tracing all events
    :dbg.tracer()
    :dbg.p(:all, :c)
    :dbg.tpl(Aiex.Events.EventBus, :publish, [])
    
    # Stop tracing after duration
    Process.send_after(self(), :stop_trace, duration_ms)
    
    receive do
      :stop_trace -> :dbg.stop_clear()
    end
  end
end
```

## Best Practices Summary

### Architectural Guidelines

1. **Design for Distribution**: Always assume multi-node deployment
2. **Embrace the Actor Model**: Use processes for isolation and concurrency
3. **Implement Circuit Breakers**: Protect against cascading failures
4. **Monitor Everything**: Comprehensive observability is essential
5. **Plan for Failures**: Design failure scenarios and recovery procedures

### Performance Guidelines

1. **Use Appropriate Storage Tiers**: Hot/warm/cold data placement
2. **Implement Caching Strategies**: Multi-level caching for optimal performance
3. **Load Balance Intelligently**: Consider task characteristics for node selection
4. **Monitor Resource Usage**: Proactive memory and CPU management
5. **Optimize Network Usage**: Batch operations and compress large payloads

### Operational Guidelines

1. **Automate Deployment**: Use container orchestration for production
2. **Implement Health Checks**: Comprehensive monitoring and alerting
3. **Plan Capacity**: Understand scaling characteristics and bottlenecks
4. **Document Procedures**: Operational runbooks for common scenarios
5. **Test Disaster Recovery**: Regular testing of backup and recovery procedures

The Aiex distributed architecture provides a robust foundation for building scalable, fault-tolerant AI applications. By following these patterns and practices, you can build systems that gracefully handle failures, scale horizontally, and maintain high availability across distributed deployments.