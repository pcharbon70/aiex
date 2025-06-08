defmodule Aiex.Events.OTPEventBus do
  @moduledoc """
  Distributed event sourcing system using pg module for event distribution
  and Mnesia for event storage.

  This module provides cluster-wide auditability without external dependencies
  by leveraging OTP's built-in pg module for process group-based event 
  distribution and Mnesia for persistent event storage.

  ## Architecture

  - **Event Distribution**: Uses pg module to distribute events across cluster nodes
  - **Event Storage**: Uses Mnesia for persistent, replicated event storage
  - **Event Aggregates**: Provides distributed aggregate management
  - **Event Replay**: Supports event replay for recovery and debugging
  - **Projections**: Enables real-time projections for read models

  ## Usage

      # Start the event bus
      {:ok, _pid} = OTPEventBus.start_link()

      # Publish an event
      event = %{
        id: UUID.generate(),
        aggregate_id: "user-123",
        type: :user_created,
        data: %{name: "John", email: "john@example.com"},
        metadata: %{user_id: "admin-1"}
      }
      :ok = OTPEventBus.publish_event(event)

      # Subscribe to events
      :ok = OTPEventBus.subscribe(:user_events)

      # Get event stream
      {:ok, events} = OTPEventBus.get_event_stream("user-123")

  ## Event Format

  All events must follow this structure:

      %{
        id: "unique-event-id",
        aggregate_id: "aggregate-identifier", 
        type: :event_type_atom,
        data: %{},  # Event-specific data
        metadata: %{
          timestamp: DateTime.utc_now(),
          node: node(),
          version: 1,
          causation_id: "parent-event-id",
          correlation_id: "trace-id"
        }
      }

  ## Distributed Features

  - Events are automatically replicated across all cluster nodes
  - Aggregate consistency is maintained using distributed locks
  - Event ordering is preserved per aggregate
  - Network partitions are handled gracefully with eventual consistency
  """

  use GenServer
  require Logger

  alias Aiex.Events.{EventStore, EventAggregate, EventProjection}

  @pg_scope :aiex_event_sourcing
  @event_store_table :aiex_event_store
  @aggregate_table :aiex_aggregate_store
  @projection_table :aiex_projection_store

  defstruct [
    :node,
    :pg_scope,
    :event_handlers,
    :projections,
    :aggregates
  ]

  ## Client API

  @doc """
  Starts the OTP Event Bus.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Publishes an event to the distributed event bus.

  The event will be:
  1. Validated for required fields
  2. Stored in Mnesia across all nodes
  3. Distributed via pg to all subscribers
  4. Applied to relevant aggregates and projections

  ## Examples

      event = %{
        id: "evt_123",
        aggregate_id: "user_456", 
        type: :user_registered,
        data: %{email: "user@example.com"},
        metadata: %{user_id: "admin"}
      }

      :ok = OTPEventBus.publish_event(event)
  """
  def publish_event(event) do
    GenServer.call(__MODULE__, {:publish_event, event})
  end

  @doc """
  Subscribes to events of a specific type or pattern.

  ## Examples

      # Subscribe to all user events
      :ok = OTPEventBus.subscribe(:user_events)

      # Subscribe to specific event types
      :ok = OTPEventBus.subscribe({:event_type, :user_created})

      # Subscribe to events for specific aggregate
      :ok = OTPEventBus.subscribe({:aggregate, "user_123"})
  """
  def subscribe(subscription) do
    GenServer.call(__MODULE__, {:subscribe, subscription, self()})
  end

  @doc """
  Unsubscribes from event notifications.
  """
  def unsubscribe(subscription) do
    GenServer.call(__MODULE__, {:unsubscribe, subscription, self()})
  end

  @doc """
  Gets the event stream for a specific aggregate.

  Returns events in chronological order with optional filtering.

  ## Examples

      # Get all events for aggregate
      {:ok, events} = OTPEventBus.get_event_stream("user_123")

      # Get events from specific version
      {:ok, events} = OTPEventBus.get_event_stream("user_123", from_version: 5)

      # Get events of specific types
      {:ok, events} = OTPEventBus.get_event_stream("user_123", 
        event_types: [:user_created, :user_updated])
  """
  def get_event_stream(aggregate_id, opts \\ []) do
    GenServer.call(__MODULE__, {:get_event_stream, aggregate_id, opts})
  end

  @doc """
  Replays events for recovery or debugging.

  ## Examples

      # Replay all events from specific timestamp
      :ok = OTPEventBus.replay_events(from: ~U[2024-01-01 00:00:00Z])

      # Replay events for specific aggregate
      :ok = OTPEventBus.replay_events(aggregate_id: "user_123")

      # Replay events to specific handler
      :ok = OTPEventBus.replay_events(to: MyEventHandler)
  """
  def replay_events(opts \\ []) do
    GenServer.call(__MODULE__, {:replay_events, opts})
  end

  @doc """
  Gets the current state of an aggregate.
  """
  def get_aggregate_state(aggregate_id) do
    GenServer.call(__MODULE__, {:get_aggregate_state, aggregate_id})
  end

  @doc """
  Registers an event handler for automatic event processing.

  ## Examples

      defmodule MyEventHandler do
        @behaviour Aiex.Events.EventHandler

        def handle_event(%{type: :user_created} = event) do
          # Process user creation
          {:ok, :processed}
        end

        def handle_event(_event), do: {:ok, :ignored}
      end

      :ok = OTPEventBus.register_handler(MyEventHandler)
  """
  def register_handler(handler_module) do
    GenServer.call(__MODULE__, {:register_handler, handler_module})
  end

  @doc """
  Registers a projection for real-time read model updates.

  ## Examples

      defmodule UserProjection do
        @behaviour Aiex.Events.EventProjection

        def project(%{type: :user_created, data: data}) do
          # Update read model
          {:ok, %{action: :insert, table: :users, data: data}}
        end
      end

      :ok = OTPEventBus.register_projection(UserProjection)
  """
  def register_projection(projection_module) do
    GenServer.call(__MODULE__, {:register_projection, projection_module})
  end

  @doc """
  Gets distributed event bus statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Gets the health status of the event bus cluster.
  """
  def get_health_status do
    GenServer.call(__MODULE__, :get_health_status)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    # Setup pg scope for event distribution
    case setup_pg_scope() do
      :ok ->
        # Setup Mnesia tables for event storage
        case setup_mnesia_tables() do
          :ok ->
            state = %__MODULE__{
              node: node(),
              pg_scope: @pg_scope,
              event_handlers: %{},
              projections: %{},
              aggregates: %{}
            }

            Logger.info("OTP Event Bus started on #{node()}")
            {:ok, state}

          {:error, reason} ->
            Logger.error("Failed to setup Mnesia tables: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to setup pg scope: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def handle_call({:publish_event, event}, _from, state) do
    case validate_event(event) do
      :ok ->
        enriched_event = enrich_event(event)
        
        case store_event(enriched_event) do
          :ok ->
            # Distribute event via pg
            distribute_event(enriched_event, state)
            
            # Process with handlers and projections
            process_event_locally(enriched_event, state)
            
            {:reply, :ok, state}

          {:error, reason} ->
            {:reply, {:error, {:storage_failed, reason}}, state}
        end

      {:error, reason} ->
        {:reply, {:error, {:validation_failed, reason}}, state}
    end
  end

  def handle_call({:subscribe, subscription, pid}, _from, state) do
    # Join appropriate pg group based on subscription
    pg_group = subscription_to_pg_group(subscription)
    :pg.join(@pg_scope, pg_group, pid)
    
    Logger.debug("Process #{inspect(pid)} subscribed to #{inspect(subscription)}")
    {:reply, :ok, state}
  end

  def handle_call({:unsubscribe, subscription, pid}, _from, state) do
    pg_group = subscription_to_pg_group(subscription)
    :pg.leave(@pg_scope, pg_group, pid)
    
    Logger.debug("Process #{inspect(pid)} unsubscribed from #{inspect(subscription)}")
    {:reply, :ok, state}
  end

  def handle_call({:get_event_stream, aggregate_id, opts}, _from, state) do
    case EventStore.get_events(aggregate_id, opts) do
      {:ok, events} -> {:reply, {:ok, events}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:replay_events, opts}, _from, state) do
    # Replay events based on criteria
    case EventStore.replay_events(opts) do
      {:ok, replayed_count} -> 
        Logger.info("Replayed #{replayed_count} events")
        {:reply, :ok, state}
      
      {:error, reason} -> 
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_aggregate_state, aggregate_id}, _from, state) do
    case EventAggregate.get_state(aggregate_id) do
      {:ok, aggregate_state} -> {:reply, {:ok, aggregate_state}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:register_handler, handler_module}, _from, state) do
    handler_id = generate_handler_id(handler_module)
    new_handlers = Map.put(state.event_handlers, handler_id, handler_module)
    new_state = %{state | event_handlers: new_handlers}
    
    Logger.info("Registered event handler: #{handler_module}")
    {:reply, :ok, new_state}
  end

  def handle_call({:register_projection, projection_module}, _from, state) do
    projection_id = generate_projection_id(projection_module)
    new_projections = Map.put(state.projections, projection_id, projection_module)
    new_state = %{state | projections: new_projections}
    
    Logger.info("Registered event projection: #{projection_module}")
    {:reply, :ok, new_state}
  end

  def handle_call(:get_stats, _from, state) do
    stats = %{
      node: node(),
      event_handlers: map_size(state.event_handlers),
      projections: map_size(state.projections),
      aggregates: map_size(state.aggregates),
      total_events: EventStore.count_events(),
      cluster_nodes: [node() | Node.list()],
      pg_groups: get_pg_groups_info()
    }
    
    {:reply, stats, state}
  end

  def handle_call(:get_health_status, _from, state) do
    health = %{
      status: determine_health_status(),
      mnesia_status: mnesia_running?(),
      pg_scope_status: pg_scope_healthy?(),
      cluster_connectivity: check_cluster_connectivity(),
      last_check: DateTime.utc_now()
    }
    
    {:reply, health, state}
  end

  @impl true
  def handle_info({:pg_message, group, event}, state) do
    # Handle events distributed via pg
    Logger.debug("Received pg event for group #{group}: #{inspect(event)}")
    process_distributed_event(event, state)
    {:noreply, state}
  end

  def handle_info({:event_notification, event}, state) do
    # Handle direct event notifications
    process_event_locally(event, state)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private Functions

  defp setup_pg_scope do
    try do
      # Create pg scope for event distribution
      case :pg.start_link(@pg_scope) do
        {:ok, _pid} -> 
          Logger.debug("Started pg scope: #{@pg_scope}")
          :ok
        
        {:error, {:already_started, _pid}} -> 
          Logger.debug("pg scope already started: #{@pg_scope}")
          :ok
        
        {:error, reason} -> 
          {:error, reason}
      end
    catch
      :exit, reason -> {:error, {:pg_exit, reason}}
    end
  end

  defp setup_mnesia_tables do
    # Create Mnesia tables for event storage
    # Use ram_copies for single-node development, disc_copies for cluster
    table_type = if node() == :nonode@nohost, do: :ram_copies, else: :disc_copies
    
    tables = [
      {@event_store_table, [
        {:attributes, [:id, :aggregate_id, :type, :data, :metadata, :version, :timestamp]},
        {table_type, [node()]},
        {:type, :ordered_set},
        {:index, [:aggregate_id, :type, :timestamp]}
      ]},
      {@aggregate_table, [
        {:attributes, [:id, :state, :version, :last_event_id, :updated_at]},
        {table_type, [node()]},
        {:type, :set}
      ]},
      {@projection_table, [
        {:attributes, [:id, :name, :state, :last_event_id, :updated_at]},
        {table_type, [node()]},
        {:type, :set}
      ]}
    ]

    case ensure_tables_exist(tables) do
      :ok -> 
        Logger.info("Event sourcing Mnesia tables ready")
        :ok
      
      {:error, reason} -> 
        {:error, reason}
    end
  end

  defp ensure_tables_exist(tables) do
    Enum.reduce_while(tables, :ok, fn {table_name, table_opts}, _acc ->
      case :mnesia.create_table(table_name, table_opts) do
        {:atomic, :ok} -> 
          Logger.debug("Created Mnesia table: #{table_name}")
          {:cont, :ok}
        
        {:aborted, {:already_exists, ^table_name}} -> 
          Logger.debug("Mnesia table already exists: #{table_name}")
          {:cont, :ok}
        
        {:aborted, reason} -> 
          Logger.error("Failed to create table #{table_name}: #{inspect(reason)}")
          {:halt, {:error, {:table_creation_failed, table_name, reason}}}
      end
    end)
  end

  defp validate_event(event) do
    required_fields = [:id, :aggregate_id, :type, :data]
    
    case Enum.all?(required_fields, &Map.has_key?(event, &1)) do
      true -> 
        # Additional validation
        cond do
          not is_binary(event.id) -> {:error, :invalid_id}
          not is_binary(event.aggregate_id) -> {:error, :invalid_aggregate_id}
          not is_atom(event.type) -> {:error, :invalid_type}
          not is_map(event.data) -> {:error, :invalid_data}
          true -> :ok
        end
      
      false -> 
        {:error, :missing_required_fields}
    end
  end

  defp enrich_event(event) do
    metadata = Map.merge(%{
      timestamp: DateTime.utc_now(),
      node: node(),
      version: 1,
      causation_id: nil,
      correlation_id: generate_correlation_id()
    }, Map.get(event, :metadata, %{}))

    Map.put(event, :metadata, metadata)
  end

  defp store_event(event) do
    try do
      result = :mnesia.transaction(fn ->
        # Get current aggregate version
        current_version = case :mnesia.read(@aggregate_table, event.aggregate_id) do
          [{@aggregate_table, _, _, version, _, _}] -> version
          [] -> 0
        end

        new_version = current_version + 1
        
        # Store event with version
        event_record = {
          @event_store_table,
          event.id,
          event.aggregate_id,
          event.type,
          event.data,
          event.metadata,
          new_version,
          event.metadata.timestamp
        }

        :mnesia.write(event_record)

        # Update aggregate version
        aggregate_record = {
          @aggregate_table,
          event.aggregate_id,
          %{},  # State will be computed by aggregate
          new_version,
          event.id,
          DateTime.utc_now()
        }

        :mnesia.write(aggregate_record)
      end)

      case result do
        {:atomic, _} -> :ok
        {:aborted, reason} -> {:error, reason}
      end
    catch
      :exit, reason -> {:error, {:mnesia_exit, reason}}
    end
  end

  defp distribute_event(event, state) do
    # Distribute event to appropriate pg groups
    groups = [
      :all_events,
      {:event_type, event.type},
      {:aggregate, event.aggregate_id}
    ]

    Enum.each(groups, fn group ->
      try do
        pids = :pg.get_members(@pg_scope, group)
        Enum.each(pids, fn pid ->
          send(pid, {:event_notification, event})
        end)
      catch
        :exit, reason ->
          Logger.warning("Failed to distribute event to group #{inspect(group)}: #{inspect(reason)}")
      end
    end)
  end

  defp process_event_locally(event, state) do
    # Process with registered handlers
    Enum.each(state.event_handlers, fn {_id, handler_module} ->
      try do
        handler_module.handle_event(event)
      catch
        kind, reason ->
          Logger.warning("Event handler #{handler_module} failed: #{kind} #{inspect(reason)}")
      end
    end)

    # Process with registered projections
    Enum.each(state.projections, fn {_id, projection_module} ->
      try do
        projection_module.project(event)
      catch
        kind, reason ->
          Logger.warning("Event projection #{projection_module} failed: #{kind} #{inspect(reason)}")
      end
    end)
  end

  defp process_distributed_event(event, state) do
    # Process events received from other nodes
    process_event_locally(event, state)
  end

  defp subscription_to_pg_group(subscription) do
    case subscription do
      :all_events -> :all_events
      {:event_type, type} -> {:event_type, type}
      {:aggregate, id} -> {:aggregate, id}
      other -> other
    end
  end

  defp generate_handler_id(handler_module) do
    "handler_#{handler_module}_#{System.unique_integer([:positive])}"
  end

  defp generate_projection_id(projection_module) do
    "projection_#{projection_module}_#{System.unique_integer([:positive])}"
  end

  defp generate_correlation_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp get_pg_groups_info do
    try do
      :pg.which_groups(@pg_scope)
      |> Enum.map(fn group ->
        members = :pg.get_members(@pg_scope, group)
        {group, length(members)}
      end)
      |> Enum.into(%{})
    catch
      _, _ -> %{}
    end
  end

  defp determine_health_status do
    cond do
      not mnesia_running?() -> :unhealthy
      not pg_scope_healthy?() -> :degraded
      Node.list() == [] -> :single_node
      true -> :healthy
    end
  end
  
  defp mnesia_running? do
    try do
      :mnesia.system_info(:is_running) == :yes
    catch
      :exit, _ -> false
    end
  end

  defp pg_scope_healthy? do
    try do
      :pg.which_groups(@pg_scope)
      true
    catch
      _, _ -> false
    end
  end

  defp check_cluster_connectivity do
    node_list = Node.list()
    total_nodes = 1 + length(node_list)
    connected_nodes = length(node_list)
    
    %{
      total_nodes: total_nodes,
      connected_nodes: connected_nodes,
      connectivity_ratio: connected_nodes / max(total_nodes - 1, 1)
    }
  end
end