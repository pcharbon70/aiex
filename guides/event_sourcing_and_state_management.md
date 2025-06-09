# Event Sourcing and State Management Guide

## Overview

Aiex implements a sophisticated distributed event sourcing and state management system built entirely on OTP primitives. This architecture provides horizontal scalability, fault tolerance, and complete auditability without external dependencies. The system leverages Elixir's strengths in concurrency and distribution to create a production-ready foundation for AI coding assistance.

## Table of Contents

1. [Core Architecture](#core-architecture)
2. [Event Sourcing System](#event-sourcing-system)
3. [State Management Components](#state-management-components)
4. [Distributed Coordination](#distributed-coordination)
5. [Context Management](#context-management)
6. [Security and Audit](#security-and-audit)
7. [Development Patterns](#development-patterns)
8. [Testing Strategies](#testing-strategies)
9. [Performance Considerations](#performance-considerations)
10. [Troubleshooting](#troubleshooting)

## Core Architecture

### Design Principles

Aiex's event sourcing and state management follows these key principles:

- **Pure OTP**: No external message brokers or databases required
- **Event-First**: All state changes flow through the event sourcing system
- **Distributed by Default**: Designed for multi-node clustering from day one
- **Fault Tolerant**: Circuit breakers, health monitoring, and graceful degradation
- **Auditable**: Complete audit trail of all system operations

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                    Event Sourcing Layer                     │
├─────────────────┬─────────────────┬─────────────────────────┤
│   OTPEventBus   │   EventStore    │    EventProjection      │
│   (Coordinator) │   (Persistence) │    (Read Models)        │
├─────────────────┼─────────────────┼─────────────────────────┤
│            EventAggregate (State Reconstruction)            │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│                  State Management Layer                     │
├─────────────────┬─────────────────┬─────────────────────────┤
│ CheckpointSys   │ SessionManager  │    Context.Manager      │
│ (Snapshots)     │ (User Sessions) │    (Context Storage)    │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│                  Distributed Foundation                     │
├─────────────────┬─────────────────┬─────────────────────────┤
│      Mnesia     │      pg         │         Horde           │
│   (Persistence) │ (Distribution)  │    (Process Groups)     │
└─────────────────────────────────────────────────────────────┘
```

## Event Sourcing System

### OTPEventBus - Central Coordinator

The `Aiex.Events.OTPEventBus` serves as the central nervous system of the event sourcing architecture:

```elixir
# Publishing events across the cluster
OTPEventBus.publish(%{
  type: :code_analysis_completed,
  aggregate_id: "session_123",
  data: %{file_path: "lib/example.ex", results: analysis_results},
  correlation_id: UUID.uuid4()
})

# Subscribing to specific event types
OTPEventBus.subscribe(:code_analysis_completed)
```

**Key Features:**
- **Distributed Publishing**: Events are automatically distributed across all nodes using `pg`
- **Event Validation**: Comprehensive validation with required fields and type checking
- **Automatic Enrichment**: Adds correlation IDs, timestamps, and cluster metadata
- **Health Monitoring**: Circuit breaker patterns for cluster connectivity

### EventStore - Persistent Storage

The `Aiex.Events.EventStore` provides Mnesia-based event persistence with advanced querying:

```elixir
# Store events with automatic versioning
EventStore.append_events("aggregate_123", [
  %{type: :session_started, data: %{user_id: "user_456"}},
  %{type: :context_loaded, data: %{project_path: "/path/to/project"}}
])

# Query events with sophisticated filtering
events = EventStore.get_events(
  aggregate_id: "aggregate_123",
  from_version: 5,
  to_version: 10,
  event_types: [:code_analysis_completed, :context_updated]
)

# Time-based queries for debugging
recent_events = EventStore.get_events_by_time_range(
  DateTime.add(DateTime.utc_now(), -3600, :second),
  DateTime.utc_now()
)
```

**Key Features:**
- **Event Streams**: Organized by aggregate with version ordering
- **Advanced Filtering**: Time ranges, event types, version ranges
- **Efficient Queries**: Mnesia match specifications for complex queries
- **Event Replay**: Support for debugging and projection rebuilding

### EventAggregate - State Reconstruction

The `Aiex.Events.EventAggregate` reconstructs aggregate state from event streams:

```elixir
defmodule Aiex.Sessions.SessionAggregate do
  use Aiex.Events.EventAggregate

  # Define the aggregate structure
  defstruct [:id, :user_id, :project_path, :context, :status, :created_at]

  # Handle individual events to rebuild state
  def apply_event(%__MODULE__{} = state, %{type: :session_started, data: data}) do
    %{state | 
      user_id: data.user_id,
      status: :active,
      created_at: data.timestamp
    }
  end

  def apply_event(%__MODULE__{} = state, %{type: :context_loaded, data: data}) do
    %{state | 
      project_path: data.project_path,
      context: data.context
    }
  end

  # Business rule validation
  def validate_command(%__MODULE__{status: :closed}, :load_context), do: {:error, :session_closed}
  def validate_command(_state, _command), do: :ok
end

# Reconstruct current state from events
{:ok, session_state} = EventAggregate.rebuild_state("session_123", SessionAggregate)
```

**Key Features:**
- **State Reconstruction**: Rebuilds aggregate state from event streams
- **Business Rules Validation**: Prevents invalid state transitions
- **Snapshotting**: Performance optimization for large aggregates
- **Distributed Coordination**: Cross-node aggregate consistency

### EventProjection - Read Models

The `Aiex.Events.EventProjection` generates real-time read models from event streams:

```elixir
defmodule Aiex.Projections.SessionSummaryProjection do
  use Aiex.Events.EventProjection

  # Define the projection structure
  defstruct [:session_count, :active_sessions, :completed_analyses]

  # Handle events to update read model
  def handle_event(%{type: :session_started}, state) do
    %{state | 
      session_count: state.session_count + 1,
      active_sessions: state.active_sessions + 1
    }
  end

  def handle_event(%{type: :code_analysis_completed}, state) do
    %{state | completed_analyses: state.completed_analyses + 1}
  end

  def handle_event(%{type: :session_ended}, state) do
    %{state | active_sessions: state.active_sessions - 1}
  end
end

# Register and start the projection
EventProjection.register_projection(SessionSummaryProjection, %{
  session_count: 0,
  active_sessions: 0,
  completed_analyses: 0
})
```

**Key Features:**
- **Real-Time Updates**: Subscribes to events via pg for immediate updates
- **Projection Management**: Registration, lifecycle management, and rebuilding
- **State Persistence**: Projection state is persisted and recoverable
- **Error Isolation**: Projection failures don't affect the core system

## State Management Components

### DistributedCheckpointSystem - Cluster Snapshots

The `Aiex.State.DistributedCheckpointSystem` provides cluster-wide state checkpointing:

```elixir
# Create a full cluster checkpoint
{:ok, checkpoint_id} = DistributedCheckpointSystem.create_checkpoint(%{
  name: "pre_upgrade_checkpoint",
  description: "Full system state before version upgrade",
  include_events: true,
  include_context: true,
  include_sessions: true
})

# Create incremental checkpoint
{:ok, incremental_id} = DistributedCheckpointSystem.create_incremental_checkpoint(
  base_checkpoint_id,
  %{name: "incremental_update"}
)

# Restore from checkpoint (dry run first)
{:ok, comparison} = DistributedCheckpointSystem.restore_checkpoint(
  checkpoint_id,
  %{dry_run: true}
)

# Actual restore
{:ok, :restored} = DistributedCheckpointSystem.restore_checkpoint(checkpoint_id)
```

**Key Features:**
- **Distributed Coordination**: Coordinates across all cluster nodes
- **Data Collection**: Gathers state from context, sessions, and events
- **Compression**: Sophisticated data compression with retention policies
- **Restore Operations**: Full cluster state restoration with dry-run capabilities

### DistributedSessionManager - Session Lifecycle

The `Aiex.Sessions.DistributedSessionManager` handles distributed session management:

```elixir
# Create a new distributed session
{:ok, session_id} = DistributedSessionManager.create_session(%{
  user_id: "user_456",
  project_path: "/path/to/project",
  node_preference: node()
})

# Migrate session to another node
{:ok, :migrated} = DistributedSessionManager.migrate_session(
  session_id,
  target_node,
  %{preserve_context: true}
)

# Handle network partition recovery
{:ok, :recovered} = DistributedSessionManager.recover_from_partition(
  affected_sessions
)
```

**Key Features:**
- **Event Sourcing Integration**: All session operations generate events
- **Automatic Migration**: Session handoff between nodes on failures
- **Network Partition Recovery**: Queue-based recovery with automatic healing
- **Crash Detection**: Process monitoring with automatic restart

## Distributed Coordination

### Process Groups with pg

Aiex uses Erlang's `pg` module for distributed coordination without external dependencies:

```elixir
# Subscribe to distributed events
:pg.join(:aiex_events, :code_analysis_events, self())

# Publish to all subscribers across the cluster
:pg.get_members(:aiex_events, :code_analysis_events)
|> Enum.each(fn pid -> 
  send(pid, {:event, event_data})
end)

# Handle process cleanup automatically
# pg automatically removes dead processes from groups
```

### Mnesia for Distributed Storage

Mnesia provides ACID transactions and automatic replication:

```elixir
# Define distributed tables
def create_tables do
  :mnesia.create_table(:aiex_events, [
    attributes: [:id, :aggregate_id, :type, :data, :version, :timestamp],
    disc_copies: [node() | Node.list()],
    index: [:aggregate_id, :type, :timestamp]
  ])
end

# Perform distributed transactions
:mnesia.transaction(fn ->
  events = :mnesia.read(:aiex_events, aggregate_id)
  :mnesia.write(:aiex_events, new_event)
  :mnesia.write(:aiex_aggregate_state, updated_state)
end)
```

## Context Management

### Tiered Memory Architecture

The context system uses a three-tier memory architecture for optimal performance:

```elixir
# Hot tier - in memory ETS for frequently accessed data
:ets.insert(:hot_context, {key, value, access_count, last_accessed})

# Warm tier - less frequently accessed but still in memory
:ets.insert(:warm_context, {key, value, last_accessed})

# Cold tier - persistent DETS storage
:dets.insert(:cold_context, {key, compressed_value, archived_at})
```

### Context Compression and Analysis

The `Aiex.Context.DistributedEngine` provides intelligent context management:

```elixir
# Store context with automatic compression
DistributedEngine.store_context(
  session_id,
  %{
    files: file_analysis_results,
    dependencies: dependency_graph,
    metrics: code_metrics
  },
  %{compress: true, tier: :hot}
)

# Retrieve with automatic decompression
{:ok, context} = DistributedEngine.get_context(session_id)

# Cross-node context synchronization
DistributedEngine.sync_context_across_nodes(session_id)
```

**Key Features:**
- **Multi-Table Storage**: AI contexts, code analysis cache, and LLM interactions
- **Context Compression**: Intelligent compression while preserving critical data
- **Distributed Analysis**: Cross-node code analysis and context correlation
- **Automatic Promotion**: Moves frequently accessed data to faster tiers

## Security and Audit

### Tamper-Resistant Audit Logging

The `Aiex.Security.DistributedAuditLogger` provides comprehensive audit capabilities:

```elixir
# Log security-sensitive operations
DistributedAuditLogger.log_event(:file_access, %{
  user_id: "user_456",
  file_path: "/sensitive/file.ex",
  operation: :read,
  result: :success
})

# Generate compliance reports
{:ok, report} = DistributedAuditLogger.generate_compliance_report(
  :gdpr,
  DateTime.add(DateTime.utc_now(), -30*24*3600, :second),
  DateTime.utc_now()
)

# Verify audit log integrity
{:ok, :verified} = DistributedAuditLogger.verify_integrity(
  start_date,
  end_date
)
```

**Key Features:**
- **Tamper-Resistant Logging**: Cryptographic integrity verification
- **Distributed Collection**: Cross-node audit event aggregation
- **Compliance Reporting**: Automated compliance report generation
- **Hash Chains**: Prevents unauthorized audit log modification

## Development Patterns

### Event-Driven Development

When adding new features, follow these event sourcing patterns:

```elixir
# 1. Define your events
defmodule MyApp.Events.FeatureEvents do
  def feature_started(data), do: %{type: :feature_started, data: data}
  def feature_completed(data), do: %{type: :feature_completed, data: data}
  def feature_failed(data), do: %{type: :feature_failed, data: data}
end

# 2. Create aggregate to handle state
defmodule MyApp.Aggregates.FeatureAggregate do
  use Aiex.Events.EventAggregate
  
  defstruct [:id, :status, :result, :started_at, :completed_at]
  
  def apply_event(state, %{type: :feature_started, data: data}) do
    %{state | status: :in_progress, started_at: data.timestamp}
  end
end

# 3. Create projection for read models
defmodule MyApp.Projections.FeatureStatsProjection do
  use Aiex.Events.EventProjection
  
  def handle_event(%{type: :feature_completed}, state) do
    %{state | completed_count: state.completed_count + 1}
  end
end

# 4. Use in your business logic
defmodule MyApp.FeatureService do
  def start_feature(feature_id, params) do
    with :ok <- validate_params(params),
         {:ok, _} <- OTPEventBus.publish(FeatureEvents.feature_started(%{
           feature_id: feature_id,
           params: params,
           timestamp: DateTime.utc_now()
         })) do
      {:ok, feature_id}
    end
  end
end
```

### State Management Best Practices

```elixir
# Use context tiers appropriately
defmodule MyApp.ContextManager do
  # Hot tier for frequently accessed data
  def store_active_session_data(session_id, data) do
    Context.Engine.store(session_id, data, tier: :hot)
  end
  
  # Warm tier for recent but less active data
  def store_recent_analysis(file_path, analysis) do
    Context.Engine.store(file_path, analysis, tier: :warm)
  end
  
  # Cold tier for archival data
  def archive_old_session(session_id, data) do
    Context.Engine.store(session_id, data, tier: :cold, compress: true)
  end
end
```

### Error Handling and Recovery

```elixir
defmodule MyApp.ResiliencePatterns do
  # Circuit breaker for external services
  def call_with_circuit_breaker(service, operation, args) do
    case CircuitBreaker.call({service, operation}, fn ->
      apply(service, operation, args)
    end) do
      {:ok, result} -> {:ok, result}
      {:error, :circuit_open} -> {:error, :service_unavailable}
      error -> error
    end
  end
  
  # Graceful degradation
  def get_analysis_with_fallback(file_path) do
    case DistributedEngine.get_analysis(file_path) do
      {:ok, analysis} -> {:ok, analysis}
      {:error, _} -> 
        Logger.warn("Analysis unavailable, using cached version")
        CacheService.get_cached_analysis(file_path)
    end
  end
end
```

## Testing Strategies

### Event Sourcing Tests

```elixir
defmodule MyApp.EventSourcingTest do
  use ExUnit.Case
  
  test "event aggregate rebuilds state correctly" do
    events = [
      %{type: :session_started, data: %{user_id: "123"}},
      %{type: :context_loaded, data: %{project_path: "/path"}},
      %{type: :analysis_completed, data: %{results: %{}}}
    ]
    
    {:ok, state} = EventAggregate.apply_events(
      %SessionAggregate{},
      events
    )
    
    assert state.user_id == "123"
    assert state.project_path == "/path"
    assert state.status == :analysis_complete
  end
  
  test "projection handles events correctly" do
    projection = %SessionStatsProjection{session_count: 0}
    
    updated = EventProjection.handle_event(
      %{type: :session_started},
      projection
    )
    
    assert updated.session_count == 1
  end
end
```

### Distributed System Tests

```elixir
defmodule MyApp.DistributedTest do
  use ExUnit.Case
  
  @tag :distributed
  test "events are distributed across nodes" do
    # Start additional node for testing
    {:ok, node2} = start_distributed_node()
    
    # Subscribe on both nodes
    OTPEventBus.subscribe(:test_events)
    :rpc.call(node2, OTPEventBus, :subscribe, [:test_events])
    
    # Publish event
    OTPEventBus.publish(%{type: :test_event, data: %{test: true}})
    
    # Verify both nodes receive the event
    assert_receive {:event, %{type: :test_event}}
    assert :rpc.call(node2, :erlang, :receive, [
      {:event, %{type: :test_event}} -> :received
    ]) == :received
  end
end
```

## Performance Considerations

### Memory Management

- **Use tiered storage**: Keep frequently accessed data in hot tier (ETS)
- **Implement compression**: Use context compression for large datasets
- **Monitor memory usage**: Track ETS table sizes and process memory
- **Cleanup strategies**: Implement TTL for cached data

### Query Optimization

```elixir
# Efficient event queries with proper indexing
defmodule MyApp.QueryOptimization do
  # Use indexed fields for faster queries
  def get_recent_events_optimized(aggregate_id, limit \\ 100) do
    # This uses the aggregate_id index
    EventStore.get_events(
      aggregate_id: aggregate_id,
      limit: limit,
      order: :desc
    )
  end
  
  # Batch operations for better performance
  def process_events_in_batches(events, batch_size \\ 1000) do
    events
    |> Enum.chunk_every(batch_size)
    |> Task.async_stream(&process_event_batch/1, max_concurrency: 4)
    |> Enum.to_list()
  end
end
```

### Cluster Performance

- **Partition tolerance**: Design for network partitions
- **Backpressure**: Implement backpressure for event publishing
- **Health monitoring**: Monitor node health and connectivity
- **Load balancing**: Distribute sessions across available nodes

## Troubleshooting

### Common Issues and Solutions

#### Event Store Corruption
```elixir
# Check event store integrity
EventStore.verify_integrity()

# Rebuild from backup if needed
EventStore.restore_from_backup(backup_file)
```

#### Memory Leaks in Context Storage
```elixir
# Monitor context storage usage
Context.Engine.get_statistics()

# Force cleanup of old data
Context.Engine.cleanup_expired_data()

# Check for processes holding references
:recon.proc_count(:memory, 10)
```

#### Distributed Coordination Issues
```elixir
# Check cluster connectivity
:pg.which_groups()
:net_adm.ping(other_node)

# Force cluster synchronization
DistributedEngine.force_sync()

# Check event distribution
OTPEventBus.get_cluster_health()
```

### Monitoring and Observability

```elixir
# Set up comprehensive monitoring
defmodule MyApp.Monitoring do
  def setup_telemetry do
    :telemetry.attach_many(
      "aiex-monitoring",
      [
        [:aiex, :events, :published],
        [:aiex, :context, :stored],
        [:aiex, :session, :created]
      ],
      &handle_event/4,
      nil
    )
  end
  
  def handle_event([:aiex, :events, :published], measurements, metadata, _config) do
    Logger.info("Event published", 
      type: metadata.event_type,
      duration: measurements.duration
    )
  end
end
```

## Best Practices Summary

1. **Always use events**: All state changes should flow through the event sourcing system
2. **Design for distribution**: Assume multi-node deployment from the beginning
3. **Implement proper error handling**: Use circuit breakers and graceful degradation
4. **Monitor everything**: Set up comprehensive observability and alerting
5. **Test distributed scenarios**: Include distributed testing in your test suite
6. **Use tiered storage**: Optimize memory usage with appropriate data tiers
7. **Maintain audit trails**: Ensure all operations are properly logged and auditable
8. **Plan for recovery**: Implement checkpointing and restore capabilities

The Aiex event sourcing and state management system provides a solid foundation for building distributed, fault-tolerant AI applications. By following these patterns and best practices, you can build robust features that scale horizontally and maintain data consistency across your cluster.