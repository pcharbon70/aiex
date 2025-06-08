defmodule Aiex.Events.EventProjection do
  @moduledoc """
  Event projection behaviour and implementation for building read models
  from event streams in a distributed environment.
  
  Projections transform events into denormalized read models optimized
  for queries. They run in real-time and can be rebuilt from event history.
  
  ## Behaviour Definition
  
  Implement this behaviour to create custom projections:
  
      defmodule MyProjection do
        @behaviour Aiex.Events.EventProjection
        
        def project(%{type: :user_created, data: data}) do
          {:ok, %{action: :insert, table: :users, data: data}}
        end
        
        def project(%{type: :user_updated, data: data}) do
          {:ok, %{action: :update, table: :users, data: data}}
        end
        
        def project(_event), do: {:ok, :ignore}
      end
  
  ## Usage
  
      # Register a projection
      :ok = EventProjection.register(MyProjection)
      
      # Project events manually  
      {:ok, result} = EventProjection.project_event(event)
      
      # Rebuild projection from events
      :ok = EventProjection.rebuild_projection("user-projection")
      
  ## Projection Result Format
  
  Projections should return results in this format:
  
      {:ok, %{
        action: :insert | :update | :delete,
        table: atom(),
        data: map(),
        metadata: map()
      }}
      
      # Or for ignored events
      {:ok, :ignore}
  """
  
  use GenServer
  require Logger
  
  alias Aiex.Events.{EventStore, OTPEventBus}
  
  @projection_table :aiex_projection_store
  @pg_scope :aiex_event_sourcing
  
  @doc """
  Projects an event into a read model update.
  
  This callback is called for each event that flows through the system.
  Return `:ignore` for events that don't affect this projection.
  
  ## Examples
  
      def project(%{type: :user_created, data: %{id: id, name: name}}) do
        {:ok, %{
          action: :insert,
          table: :user_profiles,
          data: %{user_id: id, display_name: name, created_at: DateTime.utc_now()}
        }}
      end
  """
  @callback project(event :: map()) :: 
    {:ok, map()} | 
    {:ok, :ignore} | 
    {:error, term()}
  
  @doc """
  Optional callback for projection initialization.
  
  Called when the projection is first registered or rebuilt.
  """
  @callback init() :: {:ok, term()} | {:error, term()}
  
  @doc """
  Optional callback for projection cleanup.
  
  Called when the projection is unregistered or the system shuts down.
  """
  @callback terminate(term()) :: :ok
  
  # Provide default implementations
  @optional_callbacks [init: 0, terminate: 1]
  
  defstruct [
    :projection_id,
    :module,
    :state,
    :last_event_id,
    :metadata
  ]
  
  ## Client API
  
  @doc """
  Starts the EventProjection GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Registers a projection module.
  
  The projection will start receiving events and build its read model.
  
  ## Examples
  
      :ok = EventProjection.register(UserProfileProjection)
  """
  def register(projection_module) do
    GenServer.call(__MODULE__, {:register, projection_module})
  end
  
  @doc """
  Unregisters a projection module.
  
  The projection will stop receiving events.
  
  ## Examples
  
      :ok = EventProjection.unregister(UserProfileProjection)
  """
  def unregister(projection_module) do
    GenServer.call(__MODULE__, {:unregister, projection_module})
  end
  
  @doc """
  Projects a single event using a specific projection.
  
  ## Examples
  
      event = %{type: :user_created, data: %{name: "John"}}
      {:ok, result} = EventProjection.project_event(UserProjection, event)
  """
  def project_event(projection_module, event) do
    GenServer.call(__MODULE__, {:project_event, projection_module, event})
  end
  
  @doc """
  Rebuilds a projection from its event stream.
  
  This replays all events to reconstruct the projection's read model.
  Useful for fixing data corruption or updating projection logic.
  
  ## Examples
  
      :ok = EventProjection.rebuild_projection("user-projection")
  """
  def rebuild_projection(projection_id) do
    GenServer.call(__MODULE__, {:rebuild_projection, projection_id})
  end
  
  @doc """
  Gets the state of a projection.
  
  ## Examples
  
      {:ok, state} = EventProjection.get_projection_state("user-projection")
  """
  def get_projection_state(projection_id) do
    GenServer.call(__MODULE__, {:get_projection_state, projection_id})
  end
  
  @doc """
  Lists all registered projections.
  
  ## Examples
  
      projections = EventProjection.list_projections()
  """
  def list_projections do
    GenServer.call(__MODULE__, :list_projections)
  end
  
  @doc """
  Gets projection statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  ## Server Callbacks
  
  @impl true
  def init(_opts) do
    # Setup Mnesia table for projections
    case setup_projection_table() do
      :ok ->
        # Subscribe to all events for projection processing
        case subscribe_to_events() do
          :ok ->
            Logger.info("EventProjection started successfully")
            {:ok, %{
              projections: %{},
              node: node()
            }}
            
          {:error, reason} ->
            Logger.error("Failed to subscribe to events: #{inspect(reason)}")
            {:stop, reason}
        end
        
      {:error, reason} ->
        Logger.error("Failed to setup projection table: #{inspect(reason)}")
        {:stop, reason}
    end
  end
  
  @impl true
  def handle_call({:register, projection_module}, _from, state) do
    case register_projection(projection_module, state) do
      {:ok, new_state} ->
        Logger.info("Registered projection: #{projection_module}")
        {:reply, :ok, new_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:unregister, projection_module}, _from, state) do
    case unregister_projection(projection_module, state) do
      {:ok, new_state} ->
        Logger.info("Unregistered projection: #{projection_module}")
        {:reply, :ok, new_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:project_event, projection_module, event}, _from, state) do
    result = apply_projection(projection_module, event)
    {:reply, result, state}
  end
  
  def handle_call({:rebuild_projection, projection_id}, _from, state) do
    result = rebuild_projection_from_events(projection_id)
    {:reply, result, state}
  end
  
  def handle_call({:get_projection_state, projection_id}, _from, state) do
    result = get_stored_projection_state(projection_id)
    {:reply, result, state}
  end
  
  def handle_call(:list_projections, _from, state) do
    projections = Map.keys(state.projections)
    {:reply, projections, state}
  end
  
  def handle_call(:get_stats, _from, state) do
    stats = get_projection_stats(state)
    {:reply, stats, state}
  end
  
  @impl true
  def handle_info({:event_notification, event}, state) do
    # Process event with all registered projections
    process_event_with_projections(event, state)
    {:noreply, state}
  end
  
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  ## Private Functions
  
  defp setup_projection_table do
    # Use ram_copies for single-node development, disc_copies for cluster
    table_type = if node() == :nonode@nohost, do: :ram_copies, else: :disc_copies
    
    table_opts = [
      {:attributes, [:id, :name, :state, :last_event_id, :updated_at]},
      {table_type, [node()]},
      {:type, :set}
    ]
    
    case :mnesia.create_table(@projection_table, table_opts) do
      {:atomic, :ok} ->
        Logger.debug("Created projection table: #{@projection_table}")
        :ok
        
      {:aborted, {:already_exists, @projection_table}} ->
        Logger.debug("Projection table already exists: #{@projection_table}")
        :ok
        
      {:aborted, reason} ->
        {:error, reason}
    end
  end
  
  defp subscribe_to_events do
    try do
      # Subscribe to all events via pg
      :pg.join(@pg_scope, :all_events, self())
      :ok
    catch
      :exit, reason -> {:error, {:pg_join_failed, reason}}
    end
  end
  
  defp register_projection(projection_module, state) do
    projection_id = generate_projection_id(projection_module)
    
    # Initialize projection if it supports init/0
    init_result = if function_exported?(projection_module, :init, 0) do
      projection_module.init()
    else
      {:ok, %{}}
    end
    
    case init_result do
      {:ok, initial_state} ->
        projection_record = %__MODULE__{
          projection_id: projection_id,
          module: projection_module,
          state: initial_state,
          last_event_id: nil,
          metadata: %{
            registered_at: DateTime.utc_now(),
            node: node()
          }
        }
        
        case store_projection(projection_record) do
          :ok ->
            new_projections = Map.put(state.projections, projection_id, projection_record)
            new_state = %{state | projections: new_projections}
            {:ok, new_state}
            
          {:error, reason} ->
            {:error, reason}
        end
        
      {:error, reason} ->
        {:error, {:init_failed, reason}}
    end
  end
  
  defp unregister_projection(projection_module, state) do
    # Find projection by module
    projection_entry = Enum.find(state.projections, fn {_id, projection} ->
      projection.module == projection_module
    end)
    
    case projection_entry do
      {projection_id, projection} ->
        # Call terminate if supported
        if function_exported?(projection_module, :terminate, 1) do
          try do
            projection_module.terminate(projection.state)
          catch
            _, reason ->
              Logger.warning("Projection terminate failed: #{inspect(reason)}")
          end
        end
        
        # Remove from state and storage
        new_projections = Map.delete(state.projections, projection_id)
        new_state = %{state | projections: new_projections}
        
        remove_projection(projection_id)
        {:ok, new_state}
        
      nil ->
        {:error, :projection_not_found}
    end
  end
  
  defp apply_projection(projection_module, event) do
    try do
      projection_module.project(event)
    catch
      kind, reason ->
        Logger.error("Projection #{projection_module} failed: #{kind} #{inspect(reason)}")
        {:error, {:projection_failed, kind, reason}}
    end
  end
  
  defp process_event_with_projections(event, state) do
    # Apply event to all registered projections
    Enum.each(state.projections, fn {projection_id, projection} ->
      case apply_projection(projection.module, event) do
        {:ok, :ignore} ->
          # Event ignored by this projection
          :ok
          
        {:ok, projection_result} ->
          # Update projection state
          update_projection_after_event(projection_id, projection, event, projection_result)
          
        {:error, reason} ->
          Logger.error("Projection #{projection.module} failed for event #{event.id}: #{inspect(reason)}")
      end
    end)
  end
  
  defp update_projection_after_event(projection_id, projection, event, _projection_result) do
    # Update projection's last event ID and timestamp
    updated_projection = %{projection |
      last_event_id: Map.get(event, :id),
      metadata: Map.put(projection.metadata, :last_updated, DateTime.utc_now())
    }
    
    store_projection(updated_projection)
  end
  
  defp rebuild_projection_from_events(projection_id) do
    case get_stored_projection_state(projection_id) do
      {:ok, projection} ->
        # Get all events and replay them
        case EventStore.replay_events(to: self()) do
          {:ok, _count} ->
            Logger.info("Rebuilt projection #{projection_id}")
            :ok
            
          {:error, reason} ->
            {:error, reason}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp get_stored_projection_state(projection_id) do
    try do
      result = :mnesia.transaction(fn ->
        case :mnesia.read(@projection_table, projection_id) do
          [{@projection_table, ^projection_id, name, state, last_event_id, updated_at}] ->
            {:ok, %{
              id: projection_id,
              name: name,
              state: state,
              last_event_id: last_event_id,
              updated_at: updated_at
            }}
            
          [] ->
            {:error, :not_found}
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
  
  defp store_projection(projection) do
    try do
      result = :mnesia.transaction(fn ->
        projection_record = {
          @projection_table,
          projection.projection_id,
          projection.module,
          projection.state,
          projection.last_event_id,
          DateTime.utc_now()
        }
        
        :mnesia.write(projection_record)
      end)
      
      case result do
        {:atomic, _} -> :ok
        {:aborted, reason} -> {:error, reason}
      end
    catch
      :exit, reason -> {:error, {:mnesia_exit, reason}}
    end
  end
  
  defp remove_projection(projection_id) do
    try do
      :mnesia.transaction(fn ->
        :mnesia.delete({@projection_table, projection_id})
      end)
      :ok
    catch
      :exit, reason ->
        Logger.error("Failed to remove projection #{projection_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp generate_projection_id(projection_module) do
    module_name = projection_module |> Module.split() |> List.last()
    "#{module_name}_#{System.unique_integer([:positive])}"
  end
  
  defp get_projection_stats(state) do
    total_projections = map_size(state.projections)
    
    projection_info = Enum.map(state.projections, fn {id, projection} ->
      %{
        id: id,
        module: projection.module,
        last_event_id: projection.last_event_id,
        registered_at: projection.metadata[:registered_at]
      }
    end)
    
    %{
      total_projections: total_projections,
      projections: projection_info,
      table: @projection_table,
      node: node()
    }
  end
end