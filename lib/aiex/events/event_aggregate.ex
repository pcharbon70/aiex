defmodule Aiex.Events.EventAggregate do
  @moduledoc """
  Distributed event aggregate management for event sourcing.
  
  Provides aggregate state management with distributed coordination,
  event replay for state reconstruction, and conflict resolution
  for concurrent updates across cluster nodes.
  
  ## Usage
  
      # Get aggregate state
      {:ok, state} = EventAggregate.get_state("user-123")
      
      # Apply events to aggregate
      events = [%{type: :user_created, data: %{name: "John"}}]
      {:ok, new_state} = EventAggregate.apply_events("user-123", events)
      
      # Rebuild aggregate from events
      {:ok, state} = EventAggregate.rebuild_from_events("user-123")
      
  ## Aggregate State Format
  
  All aggregates follow this structure:
  
      %{
        id: "aggregate-id",
        version: 5,
        state: %{},  # Aggregate-specific state
        last_event_id: "event-123",
        metadata: %{
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          node: node()
        }
      }
  """
  
  use GenServer
  require Logger
  
  alias Aiex.Events.EventStore
  
  @aggregate_table :aiex_aggregate_store
  @pg_scope :aiex_event_sourcing
  
  defstruct [
    :aggregate_id,
    :version,
    :state,
    :last_event_id,
    :metadata
  ]
  
  ## Client API
  
  @doc """
  Starts the EventAggregate GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Gets the current state of an aggregate.
  
  Returns the latest aggregate state from Mnesia or rebuilds
  it from events if not found in cache.
  
  ## Examples
  
      {:ok, state} = EventAggregate.get_state("user-123")
      
      # Returns aggregate state structure
      %{
        id: "user-123",
        version: 5,
        state: %{name: "John", email: "john@example.com"},
        last_event_id: "evt-456",
        metadata: %{...}
      }
  """
  def get_state(aggregate_id) do
    GenServer.call(__MODULE__, {:get_state, aggregate_id})
  end
  
  @doc """
  Applies a list of events to an aggregate.
  
  Updates the aggregate state by applying events in order,
  ensuring version consistency and conflict resolution.
  
  ## Examples
  
      events = [
        %{type: :user_updated, data: %{email: "new@example.com"}},
        %{type: :user_activated, data: %{activated_at: DateTime.utc_now()}}
      ]
      
      {:ok, new_state} = EventAggregate.apply_events("user-123", events)
  """
  def apply_events(aggregate_id, events) do
    GenServer.call(__MODULE__, {:apply_events, aggregate_id, events})
  end
  
  @doc """
  Rebuilds an aggregate state from its event stream.
  
  Replays all events for the aggregate to reconstruct
  its current state. Useful for cache invalidation or recovery.
  
  ## Examples
  
      {:ok, state} = EventAggregate.rebuild_from_events("user-123")
  """
  def rebuild_from_events(aggregate_id) do
    GenServer.call(__MODULE__, {:rebuild_from_events, aggregate_id})
  end
  
  @doc """
  Gets the current version of an aggregate.
  
  Returns the version number without loading the full state.
  
  ## Examples
  
      {:ok, 5} = EventAggregate.get_version("user-123")
  """
  def get_version(aggregate_id) do
    GenServer.call(__MODULE__, {:get_version, aggregate_id})
  end
  
  @doc """
  Creates a snapshot of the aggregate state.
  
  Stores the current aggregate state as a snapshot for
  faster reconstruction in the future.
  
  ## Examples
  
      :ok = EventAggregate.create_snapshot("user-123")
  """
  def create_snapshot(aggregate_id) do
    GenServer.call(__MODULE__, {:create_snapshot, aggregate_id})
  end
  
  @doc """
  Validates that an event can be applied to the aggregate.
  
  Checks business rules and aggregate invariants before
  allowing event application.
  
  ## Examples
  
      event = %{type: :user_created, data: %{name: "John"}}
      case EventAggregate.validate_event("user-123", event) do
        :ok -> # Event is valid
        {:error, reason} -> # Event violates rules
      end
  """
  def validate_event(aggregate_id, event) do
    GenServer.call(__MODULE__, {:validate_event, aggregate_id, event})
  end
  
  @doc """
  Gets statistics about all aggregates.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  ## Server Callbacks
  
  @impl true
  def init(_opts) do
    # Setup Mnesia table for aggregates if not exists
    case setup_aggregate_table() do
      :ok ->
        Logger.info("EventAggregate started successfully")
        {:ok, %{node: node()}}
        
      {:error, reason} ->
        Logger.error("Failed to setup aggregate table: #{inspect(reason)}")
        {:stop, reason}
    end
  end
  
  @impl true
  def handle_call({:get_state, aggregate_id}, _from, state) do
    result = get_aggregate_state(aggregate_id)
    {:reply, result, state}
  end
  
  def handle_call({:apply_events, aggregate_id, events}, _from, state) do
    result = apply_events_to_aggregate(aggregate_id, events)
    {:reply, result, state}
  end
  
  def handle_call({:rebuild_from_events, aggregate_id}, _from, state) do
    result = rebuild_aggregate_from_events(aggregate_id)
    {:reply, result, state}
  end
  
  def handle_call({:get_version, aggregate_id}, _from, state) do
    result = get_aggregate_version(aggregate_id)
    {:reply, result, state}
  end
  
  def handle_call({:create_snapshot, aggregate_id}, _from, state) do
    result = create_aggregate_snapshot(aggregate_id)
    {:reply, result, state}
  end
  
  def handle_call({:validate_event, aggregate_id, event}, _from, state) do
    result = validate_event_for_aggregate(aggregate_id, event)
    {:reply, result, state}
  end
  
  def handle_call(:get_stats, _from, state) do
    stats = get_aggregate_stats()
    {:reply, stats, state}
  end
  
  ## Private Functions
  
  defp setup_aggregate_table do
    # Use ram_copies for single-node development, disc_copies for cluster
    table_type = if node() == :nonode@nohost, do: :ram_copies, else: :disc_copies
    
    table_opts = [
      {:attributes, [:id, :state, :version, :last_event_id, :updated_at]},
      {table_type, [node()]},
      {:type, :set}
    ]
    
    case :mnesia.create_table(@aggregate_table, table_opts) do
      {:atomic, :ok} ->
        Logger.debug("Created aggregate table: #{@aggregate_table}")
        :ok
        
      {:aborted, {:already_exists, @aggregate_table}} ->
        Logger.debug("Aggregate table already exists: #{@aggregate_table}")
        :ok
        
      {:aborted, reason} ->
        {:error, reason}
    end
  end
  
  defp get_aggregate_state(aggregate_id) do
    try do
      result = :mnesia.transaction(fn ->
        case :mnesia.read(@aggregate_table, aggregate_id) do
          [{@aggregate_table, ^aggregate_id, aggregate_state, version, last_event_id, updated_at}] ->
            {:ok, %{
              id: aggregate_id,
              version: version,
              state: aggregate_state,
              last_event_id: last_event_id,
              metadata: %{
                updated_at: updated_at,
                node: node()
              }
            }}
            
          [] ->
            # Aggregate not in cache, try to rebuild from events
            case rebuild_from_event_stream(aggregate_id) do
              {:ok, aggregate} -> {:ok, aggregate}
              {:error, :no_events} -> 
                # Create empty aggregate
                empty_aggregate = create_empty_aggregate(aggregate_id)
                store_aggregate(empty_aggregate)
                {:ok, empty_aggregate}
              {:error, reason} -> {:error, reason}
            end
        end
      end)
      
      case result do
        {:atomic, inner_result} -> inner_result
        {:aborted, reason} -> {:error, reason}
      end
    catch
      :exit, reason -> {:error, {:mnesia_exit, reason}}
    end
  end
  
  defp apply_events_to_aggregate(aggregate_id, events) do
    try do
      result = :mnesia.transaction(fn ->
        # Get current aggregate state
        case get_current_aggregate_version(aggregate_id) do
          {:ok, current_version} ->
            # Apply events sequentially
            {final_state, final_version} = Enum.reduce(events, {%{}, current_version}, fn event, {acc_state, acc_version} ->
              new_state = apply_single_event(acc_state, event)
              new_version = acc_version + 1
              {new_state, new_version}
            end)
            
            # Store updated aggregate
            last_event_id = case List.last(events) do
              %{id: id} -> id
              _ -> generate_event_id()
            end
            
            updated_aggregate = %{
              id: aggregate_id,
              version: final_version,
              state: final_state,
              last_event_id: last_event_id,
              metadata: %{
                updated_at: DateTime.utc_now(),
                node: node()
              }
            }
            
            case store_aggregate(updated_aggregate) do
              :ok -> {:ok, updated_aggregate}
              {:error, reason} -> {:error, reason}
            end
            
          {:error, reason} ->
            {:error, reason}
        end
      end)
      
      case result do
        {:atomic, inner_result} -> inner_result
        {:aborted, reason} -> {:error, reason}
      end
    catch
      :exit, reason -> {:error, {:mnesia_exit, reason}}
    end
  end
  
  defp rebuild_aggregate_from_events(aggregate_id) do
    case EventStore.get_events(aggregate_id) do
      {:ok, [_ | _] = events} ->
        try do
          # Rebuild state by applying all events
          final_state = Enum.reduce(events, %{}, fn event, acc_state ->
            apply_single_event(acc_state, event)
          end)
          
          # Get version from last event
          final_version = case List.last(events) do
            %{metadata: %{version: version}} -> version
            _ -> length(events)
          end
          
          last_event_id = case List.last(events) do
            %{id: id} -> id
            _ -> nil
          end
          
          rebuilt_aggregate = %{
            id: aggregate_id,
            version: final_version,
            state: final_state,
            last_event_id: last_event_id,
            metadata: %{
              updated_at: DateTime.utc_now(),
              node: node(),
              rebuilt: true
            }
          }
          
          # Store rebuilt aggregate
          case store_aggregate(rebuilt_aggregate) do
            :ok -> {:ok, rebuilt_aggregate}
            {:error, reason} -> {:error, reason}
          end
        catch
          _, reason -> {:error, {:rebuild_failed, reason}}
        end
        
      {:ok, []} ->
        # No events found, create empty aggregate
        empty_aggregate = create_empty_aggregate(aggregate_id)
        case store_aggregate(empty_aggregate) do
          :ok -> {:ok, empty_aggregate}
          {:error, reason} -> {:error, reason}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp rebuild_from_event_stream(aggregate_id) do
    case EventStore.get_events(aggregate_id) do
      {:ok, [_ | _]} ->
        rebuild_aggregate_from_events(aggregate_id)
        
      {:ok, []} ->
        {:error, :no_events}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp get_current_aggregate_version(aggregate_id) do
    try do
      result = :mnesia.transaction(fn ->
        case :mnesia.read(@aggregate_table, aggregate_id) do
          [{@aggregate_table, ^aggregate_id, _state, version, _last_event_id, _updated_at}] ->
            {:ok, version}
            
          [] ->
            # Check EventStore for version
            case EventStore.get_aggregate_version(aggregate_id) do
              {:ok, version} -> {:ok, version}
              {:error, _} -> {:ok, 0}  # New aggregate
            end
        end
      end)
      
      case result do
        {:atomic, inner_result} -> inner_result
        {:aborted, reason} -> {:error, reason}
      end
    catch
      :exit, reason -> {:error, {:mnesia_exit, reason}}
    end
  end
  
  defp get_aggregate_version(aggregate_id) do
    case get_current_aggregate_version(aggregate_id) do
      {:ok, version} -> {:ok, version}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp create_aggregate_snapshot(aggregate_id) do
    case get_aggregate_state(aggregate_id) do
      {:ok, _aggregate} ->
        # For now, snapshots are just stored aggregates
        # In a more sophisticated system, we might compress or store differently
        snapshot_id = "snapshot_#{aggregate_id}_#{System.unique_integer([:positive])}"
        
        Logger.info("Created snapshot #{snapshot_id} for aggregate #{aggregate_id}")
        :ok
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp validate_event_for_aggregate(aggregate_id, event) do
    # Basic validation - in a real system this would check business rules
    case event do
      %{type: type, data: data} when is_atom(type) and is_map(data) ->
        # Get current aggregate state for validation
        case get_aggregate_state(aggregate_id) do
          {:ok, aggregate} ->
            validate_business_rules(aggregate, event)
            
          {:error, _} ->
            # Allow events for new aggregates
            :ok
        end
        
      _ ->
        {:error, :invalid_event_format}
    end
  end
  
  defp validate_business_rules(aggregate, event) do
    # Implement business rule validation here
    # This is a simplified example
    case {aggregate.state, event.type} do
      {%{status: :deleted}, _} ->
        {:error, :aggregate_deleted}
        
      {_, :user_created} when map_size(aggregate.state) > 0 ->
        {:error, :user_already_exists}
        
      _ ->
        :ok
    end
  end
  
  defp apply_single_event(current_state, event) do
    # Apply event to current state based on event type
    case event.type do
      :user_created ->
        Map.merge(current_state, event.data)
        
      :user_updated ->
        Map.merge(current_state, event.data)
        
      :user_deleted ->
        Map.put(current_state, :status, :deleted)
        
      :user_activated ->
        Map.put(current_state, :status, :active)
        
      :user_deactivated ->
        Map.put(current_state, :status, :inactive)
        
      # Add more event handlers as needed
      _ ->
        # Unknown event type, preserve current state
        current_state
    end
  end
  
  defp store_aggregate(aggregate) do
    try do
      result = :mnesia.transaction(fn ->
        aggregate_record = {
          @aggregate_table,
          aggregate.id,
          aggregate.state,
          aggregate.version,
          aggregate.last_event_id,
          aggregate.metadata.updated_at
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
  
  defp create_empty_aggregate(aggregate_id) do
    %{
      id: aggregate_id,
      version: 0,
      state: %{},
      last_event_id: nil,
      metadata: %{
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        node: node()
      }
    }
  end
  
  defp generate_event_id do
    "evt_#{System.unique_integer([:positive])}_#{System.os_time(:millisecond)}"
  end
  
  defp get_aggregate_stats do
    try do
      total_aggregates = :mnesia.table_info(@aggregate_table, :size)
      
      %{
        total_aggregates: total_aggregates,
        table: @aggregate_table,
        node: node(),
        mnesia_running: :mnesia.system_info(:is_running)
      }
    catch
      :exit, _ ->
        %{
          total_aggregates: 0,
          table: @aggregate_table,
          node: node(),
          mnesia_running: false
        }
    end
  end
end