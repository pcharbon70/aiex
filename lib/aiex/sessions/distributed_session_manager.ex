defmodule Aiex.Sessions.DistributedSessionManager do
  @moduledoc """
  Enhanced distributed session management with event sourcing integration,
  automatic migration, partition handling, and cluster-aware recovery.
  
  Provides:
  - Session lifecycle management with event sourcing
  - Automatic session migration on node failures
  - Network partition recovery with queuing
  - Cross-node session handoff
  - Distributed crash detection and recovery
  - Session archival and replay capabilities
  
  ## Architecture
  
  Uses Horde.DynamicSupervisor for distributed process supervision,
  pg for cross-node coordination, and integrates with the event
  sourcing system for complete auditability.
  
  ## Usage
  
      # Start a new session
      {:ok, session_id} = DistributedSessionManager.create_session(%{
        user_id: "user123",
        interface: :cli,
        metadata: %{source: "terminal"}
      })
      
      # Migrate session to another node
      :ok = DistributedSessionManager.migrate_session(session_id, :target_node)
      
      # Handle partition recovery
      :ok = DistributedSessionManager.recover_from_partition()
  """
  
  use GenServer
  require Logger
  
  alias Aiex.Context.SessionSupervisor
  alias Aiex.Events.OTPEventBus
  
  @session_registry :session_registry
  @pg_scope :session_coordination
  @recovery_queue_table :session_recovery_queue
  @archive_table :session_archive
  
  defstruct [
    :node,
    :sessions,
    :migrations,
    :recovery_queue,
    :metrics
  ]
  
  ## Client API
  
  @doc """
  Starts the distributed session manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Creates a new distributed session with event sourcing.
  
  ## Options
  - `:user_id` - User identifier
  - `:interface` - Interface type (:cli, :web, :lsp)
  - `:metadata` - Additional session metadata
  - `:node` - Target node (optional, auto-selected if not provided)
  
  ## Examples
  
      {:ok, session_id} = DistributedSessionManager.create_session(%{
        user_id: "user123",
        interface: :cli
      })
  """
  def create_session(opts) do
    GenServer.call(__MODULE__, {:create_session, opts})
  end
  
  @doc """
  Gets session information including current node and state.
  """
  def get_session(session_id) do
    GenServer.call(__MODULE__, {:get_session, session_id})
  end
  
  @doc """
  Lists all active sessions across the cluster.
  """
  def list_sessions(opts \\ []) do
    GenServer.call(__MODULE__, {:list_sessions, opts})
  end
  
  @doc """
  Migrates a session to another node with handoff.
  
  ## Examples
  
      :ok = DistributedSessionManager.migrate_session("session123", :node2@host)
  """
  def migrate_session(session_id, target_node) do
    GenServer.call(__MODULE__, {:migrate_session, session_id, target_node})
  end
  
  @doc """
  Implements distributed rollback for a session.
  
  Rolls back session state to a previous checkpoint or event.
  
  ## Examples
  
      :ok = DistributedSessionManager.rollback_session("session123", 
        to: ~U[2024-01-01 12:00:00Z])
  """
  def rollback_session(session_id, opts) do
    GenServer.call(__MODULE__, {:rollback_session, session_id, opts})
  end
  
  @doc """
  Archives a session for later analysis or recovery.
  """
  def archive_session(session_id) do
    GenServer.call(__MODULE__, {:archive_session, session_id})
  end
  
  @doc """
  Recovers sessions after network partition.
  
  Processes the recovery queue and restores sessions that
  were affected by network partitions.
  """
  def recover_from_partition do
    GenServer.call(__MODULE__, :recover_from_partition)
  end
  
  @doc """
  Gets cluster-wide session statistics.
  """
  def get_cluster_stats do
    GenServer.call(__MODULE__, :get_cluster_stats)
  end
  
  @doc """
  Registers crash detection for a session.
  """
  def monitor_session(session_id) do
    GenServer.call(__MODULE__, {:monitor_session, session_id})
  end
  
  ## Server Callbacks
  
  @impl true
  def init(_opts) do
    # Setup distributed infrastructure
    setup_infrastructure()
    
    # Subscribe to relevant events
    subscribe_to_events()
    
    state = %__MODULE__{
      node: node(),
      sessions: %{},
      migrations: %{},
      recovery_queue: [],
      metrics: init_metrics()
    }
    
    # Start periodic health checks
    schedule_health_check()
    
    Logger.info("Distributed session manager started on #{node()}")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:create_session, opts}, _from, state) do
    session_id = generate_session_id()
    
    # Select optimal node for session
    target_node = select_optimal_node(opts)
    
    # Create session event
    event = %{
      id: generate_event_id(),
      aggregate_id: session_id,
      type: :session_created,
      data: Map.merge(opts, %{
        session_id: session_id,
        created_at: DateTime.utc_now(),
        node: target_node
      }),
      metadata: %{
        user_id: opts[:user_id],
        interface: opts[:interface]
      }
    }
    
    # Publish event
    :ok = OTPEventBus.publish_event(event)
    
    # Start session on target node
    case start_session_on_node(session_id, opts, target_node) do
      {:ok, pid} ->
        # Track session with metadata
        new_state = track_session_with_metadata(state, session_id, pid, target_node, opts)
        
        # Register in pg for coordination
        :pg.join(@pg_scope, {:session, session_id}, pid)
        
        {:reply, {:ok, session_id}, new_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:get_session, session_id}, _from, state) do
    case find_session(session_id) do
      {:ok, session_info} ->
        # Enrich with current state if local
        enriched_info = enrich_session_info(session_info, state)
        {:reply, {:ok, enriched_info}, state}
        
      {:error, :not_found} ->
        # Check archive
        case get_archived_session(session_id) do
          {:ok, archived} -> {:reply, {:ok, archived}, state}
          {:error, _} -> {:reply, {:error, :not_found}, state}
        end
    end
  end
  
  def handle_call({:list_sessions, opts}, _from, state) do
    # Get all sessions from cluster
    all_sessions = get_cluster_sessions()
    
    # Apply filters
    filtered = apply_session_filters(all_sessions, opts)
    
    {:reply, {:ok, filtered}, state}
  end
  
  def handle_call({:migrate_session, session_id, target_node}, from, state) do
    case find_session(session_id) do
      {:ok, %{pid: pid, node: current_node}} when current_node != target_node ->
        # Start migration process
        migration_id = start_migration(session_id, current_node, target_node, from)
        
        # Track migration
        new_state = %{state | 
          migrations: Map.put(state.migrations, migration_id, %{
            session_id: session_id,
            from_node: current_node,
            to_node: target_node,
            started_at: DateTime.utc_now(),
            caller: from
          })
        }
        
        # Initiate async migration
        Task.start(fn ->
          perform_migration(migration_id, session_id, pid, current_node, target_node)
        end)
        
        {:noreply, new_state}
        
      {:ok, %{node: ^target_node}} ->
        # Already on target node
        {:reply, {:ok, :already_on_target}, state}
        
      {:error, :not_found} ->
        {:reply, {:error, :session_not_found}, state}
    end
  end
  
  def handle_call({:rollback_session, session_id, opts}, _from, state) do
    case perform_session_rollback(session_id, opts) do
      :ok ->
        # Publish rollback event
        event = %{
          id: generate_event_id(),
          aggregate_id: session_id,
          type: :session_rolled_back,
          data: %{
            session_id: session_id,
            rollback_opts: opts,
            timestamp: DateTime.utc_now()
          },
          metadata: %{node: node()}
        }
        
        :ok = OTPEventBus.publish_event(event)
        
        {:reply, :ok, state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:archive_session, session_id}, _from, state) do
    case archive_session_data(session_id) do
      :ok ->
        # Remove from active sessions
        new_state = remove_session_tracking(state, session_id)
        
        # Publish archive event
        event = %{
          id: generate_event_id(),
          aggregate_id: session_id,
          type: :session_archived,
          data: %{
            session_id: session_id,
            archived_at: DateTime.utc_now()
          },
          metadata: %{node: node()}
        }
        
        :ok = OTPEventBus.publish_event(event)
        
        {:reply, :ok, new_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call(:recover_from_partition, _from, state) do
    # Process recovery queue
    recovered = process_recovery_queue(state.recovery_queue)
    
    # Clear processed items
    new_state = %{state | recovery_queue: []}
    
    {:reply, {:ok, recovered}, new_state}
  end
  
  def handle_call(:get_cluster_stats, _from, state) do
    stats = compile_cluster_stats(state)
    {:reply, stats, state}
  end
  
  def handle_call({:monitor_session, session_id}, _from, state) do
    case find_session(session_id) do
      {:ok, %{pid: pid}} ->
        # Monitor the session process
        ref = Process.monitor(pid)
        
        # Track monitoring
        new_state = add_session_monitor(state, session_id, ref)
        
        {:reply, :ok, new_state}
        
      {:error, :not_found} ->
        {:reply, {:error, :session_not_found}, state}
    end
  end
  
  @impl true
  def handle_info({:event_notification, event}, state) do
    # Handle session-related events
    new_state = handle_session_event(event, state)
    {:noreply, new_state}
  end
  
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    # Handle crashed session
    new_state = handle_session_crash(ref, pid, reason, state)
    {:noreply, new_state}
  end
  
  def handle_info({:migration_complete, migration_id, result}, state) do
    # Handle migration completion
    case Map.get(state.migrations, migration_id) do
      %{caller: from} = _migration ->
        # Reply to original caller
        GenServer.reply(from, result)
        
        # Clean up migration tracking
        new_state = %{state | 
          migrations: Map.delete(state.migrations, migration_id)
        }
        
        {:noreply, new_state}
        
      nil ->
        {:noreply, state}
    end
  end
  
  def handle_info(:health_check, state) do
    # Perform cluster health check
    perform_health_check(state)
    
    # Schedule next check
    schedule_health_check()
    
    {:noreply, state}
  end
  
  def handle_info({:nodeup, node}, state) do
    # Handle node joining cluster
    Logger.info("Node #{node} joined cluster")
    
    # Attempt partition recovery
    new_state = handle_node_up(node, state)
    
    {:noreply, new_state}
  end
  
  def handle_info({:nodedown, node}, state) do
    # Handle node leaving cluster
    Logger.warning("Node #{node} left cluster")
    
    # Queue sessions for recovery
    new_state = handle_node_down(node, state)
    
    {:noreply, new_state}
  end
  
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  ## Private Functions
  
  defp setup_infrastructure do
    # Setup pg scope
    :pg.start_link(@pg_scope)
    
    # Setup ETS tables for fast lookups
    :ets.new(@session_registry, [:set, :named_table, :public])
    
    # Setup Mnesia tables
    setup_mnesia_tables()
    
    # Monitor nodes
    :net_kernel.monitor_nodes(true)
  end
  
  defp setup_mnesia_tables do
    # Recovery queue table
    table_type = if node() == :nonode@nohost, do: :ram_copies, else: :disc_copies
    
    :mnesia.create_table(@recovery_queue_table, [
      {table_type, [node()]},
      {:attributes, [:id, :session_id, :data, :queued_at]},
      {:type, :set}
    ])
    
    # Session archive table
    :mnesia.create_table(@archive_table, [
      {table_type, [node()]},
      {:attributes, [:session_id, :data, :archived_at]},
      {:type, :set},
      {:index, [:archived_at]}
    ])
  end
  
  defp subscribe_to_events do
    # Subscribe to session events
    OTPEventBus.subscribe({:event_type, :session_created})
    OTPEventBus.subscribe({:event_type, :session_updated})
    OTPEventBus.subscribe({:event_type, :session_closed})
    OTPEventBus.subscribe({:event_type, :session_migrated})
  end
  
  defp generate_session_id do
    "session_#{:erlang.unique_integer([:positive])}_#{System.os_time(:millisecond)}"
  end
  
  defp generate_event_id do
    "evt_session_#{:erlang.unique_integer([:positive])}_#{System.os_time(:millisecond)}"
  end
  
  defp select_optimal_node(opts) do
    preferred_node = opts[:node]
    
    if preferred_node && node_available?(preferred_node) do
      preferred_node
    else
      # Select based on load
      select_least_loaded_node()
    end
  end
  
  defp node_available?(node) do
    node == node() || node in Node.list()
  end
  
  defp select_least_loaded_node do
    nodes = [node() | Node.list()]
    
    # Get session counts for each node
    node_loads = Enum.map(nodes, fn n ->
      count = get_node_session_count(n)
      {n, count}
    end)
    
    # Select node with least sessions
    {selected_node, _count} = Enum.min_by(node_loads, fn {_n, count} -> count end)
    
    selected_node
  end
  
  defp get_node_session_count(node) do
    try do
      :rpc.call(node, SessionSupervisor, :stats, [], 5000)
      |> Map.get(:local_sessions, 0)
    catch
      _, _ -> 999  # High number to avoid selecting unreachable nodes
    end
  end
  
  defp start_session_on_node(session_id, opts, target_node) do
    user_id = opts[:user_id]
    
    result = if target_node == node() do
      # Start locally
      SessionSupervisor.start_session(session_id, user_id)
    else
      # Start on remote node
      :rpc.call(target_node, SessionSupervisor, :start_session, [session_id, user_id], 10000)
    end
    
    result
  end
  
  defp track_session(state, session_id, pid, node) do
    track_session_with_metadata(state, session_id, pid, node, %{})
  end

  defp track_session_with_metadata(state, session_id, pid, node, opts) do
    # Create session info with metadata
    session_info = %{
      session_id: session_id,
      pid: pid,
      node: node,
      user_id: opts[:user_id],
      interface: opts[:interface],
      status: :active,
      started_at: DateTime.utc_now(),
      metadata: opts[:metadata] || %{}
    }
    
    # Update ETS registry
    :ets.insert(@session_registry, {session_id, session_info})
    
    # Update state
    %{state |
      sessions: Map.put(state.sessions, session_id, %{
        pid: pid,
        node: node,
        monitors: []
      })
    }
  end
  
  defp find_session(session_id) do
    case :ets.lookup(@session_registry, session_id) do
      [{^session_id, info}] -> {:ok, info}
      [] -> find_session_in_cluster(session_id)
    end
  end
  
  defp find_session_in_cluster(session_id) do
    # Query all nodes
    nodes = [node() | Node.list()]
    
    Enum.find_value(nodes, {:error, :not_found}, fn n ->
      try do
        case :rpc.call(n, :ets, :lookup, [@session_registry, session_id], 5000) do
          [{^session_id, info}] -> {:ok, info}
          _ -> nil
        end
      catch
        _, _ -> nil
      end
    end)
  end
  
  defp enrich_session_info(info, state) do
    session_id = Map.get(info, :session_id)
    
    # Add current state if available
    case Map.get(state.sessions, session_id) do
      nil -> info
      session_state -> Map.merge(info, session_state)
    end
  end
  
  defp get_archived_session(session_id) do
    case :mnesia.transaction(fn ->
      :mnesia.read(@archive_table, session_id)
    end) do
      {:atomic, [{@archive_table, ^session_id, data, archived_at}]} ->
        {:ok, Map.merge(data, %{archived_at: archived_at})}
        
      _ ->
        {:error, :not_found}
    end
  end
  
  defp get_cluster_sessions do
    # Get sessions from all nodes via ETS registry
    try do
      :ets.tab2list(@session_registry)
      |> Enum.map(fn {session_id, info} -> 
        # Merge session info with any additional metadata
        Map.put(info, :session_id, session_id)
      end)
    catch
      _, _ -> []
    end
  end
  
  defp apply_session_filters(sessions, opts) do
    sessions
    |> filter_by_user(opts[:user_id])
    |> filter_by_interface(opts[:interface])
    |> filter_by_node(opts[:node])
    |> filter_by_status(opts[:status])
  end
  
  defp filter_by_user(sessions, nil), do: sessions
  defp filter_by_user(sessions, user_id) do
    Enum.filter(sessions, fn s -> s[:user_id] == user_id end)
  end
  
  defp filter_by_interface(sessions, nil), do: sessions
  defp filter_by_interface(sessions, interface) do
    Enum.filter(sessions, fn s -> s[:interface] == interface end)
  end
  
  defp filter_by_node(sessions, nil), do: sessions
  defp filter_by_node(sessions, node) do
    Enum.filter(sessions, fn s -> s[:node] == node end)
  end
  
  defp filter_by_status(sessions, nil), do: sessions
  defp filter_by_status(sessions, status) do
    Enum.filter(sessions, fn s -> s[:status] == status end)
  end
  
  defp start_migration(session_id, from_node, to_node, _caller) do
    migration_id = "mig_#{:erlang.unique_integer([:positive])}"
    
    # Publish migration started event
    event = %{
      id: generate_event_id(),
      aggregate_id: session_id,
      type: :session_migration_started,
      data: %{
        session_id: session_id,
        migration_id: migration_id,
        from_node: from_node,
        to_node: to_node,
        started_at: DateTime.utc_now()
      },
      metadata: %{node: node()}
    }
    
    :ok = OTPEventBus.publish_event(event)
    
    migration_id
  end
  
  defp perform_migration(migration_id, session_id, pid, from_node, to_node) do
    try do
      # Get session state
      session_state = get_session_state(pid)
      
      # Start session on target node
      case start_session_on_node(session_id, session_state, to_node) do
        {:ok, new_pid} ->
          # Perform handoff
          perform_handoff(pid, new_pid, session_state)
          
          # Stop old session
          stop_session_on_node(session_id, from_node)
          
          # Update registry
          :ets.insert(@session_registry, {session_id, %{
            pid: new_pid,
            node: to_node,
            started_at: DateTime.utc_now()
          }})
          
          # Publish completion event
          publish_migration_complete(session_id, migration_id, :success)
          
          # Notify manager
          send(self(), {:migration_complete, migration_id, :ok})
          
        {:error, reason} ->
          # Publish failure event
          publish_migration_complete(session_id, migration_id, {:error, reason})
          
          # Notify manager
          send(self(), {:migration_complete, migration_id, {:error, reason}})
      end
    catch
      kind, reason ->
        Logger.error("Migration failed: #{kind} #{inspect(reason)}")
        send(self(), {:migration_complete, migration_id, {:error, {kind, reason}}})
    end
  end
  
  defp get_session_state(pid) do
    Aiex.Context.Session.get_state(pid)
  end
  
  defp perform_handoff(old_pid, new_pid, state) do
    # Transfer state to new session
    Aiex.Context.Session.restore_state(new_pid, state)
    
    # Notify old session about handoff
    GenServer.cast(old_pid, {:handoff_complete, new_pid})
  end
  
  defp stop_session_on_node(session_id, node) do
    if node == node() do
      SessionSupervisor.stop_session(session_id)
    else
      :rpc.call(node, SessionSupervisor, :stop_session, [session_id], 5000)
    end
  end
  
  defp publish_migration_complete(session_id, migration_id, result) do
    event = %{
      id: generate_event_id(),
      aggregate_id: session_id,
      type: :session_migration_completed,
      data: %{
        session_id: session_id,
        migration_id: migration_id,
        result: result,
        completed_at: DateTime.utc_now()
      },
      metadata: %{node: node()}
    }
    
    OTPEventBus.publish_event(event)
  end
  
  defp perform_session_rollback(session_id, opts) do
    # Get rollback target
    target = opts[:to] || opts[:version] || opts[:event_id]
    
    case find_session(session_id) do
      {:ok, %{pid: pid}} when not is_nil(pid) ->
        # Perform rollback on session
        Aiex.Context.Session.rollback(pid, target)
        
      {:error, :not_found} ->
        # Try to restore from archive and rollback
        restore_and_rollback(session_id, target)
    end
  end
  
  defp restore_and_rollback(session_id, target) do
    case get_archived_session(session_id) do
      {:ok, archived_data} ->
        # Restore session
        {:ok, pid} = start_session_on_node(session_id, archived_data, node())
        
        # Perform rollback
        Aiex.Context.Session.rollback(pid, target)
        
      {:error, _} ->
        {:error, :session_not_found}
    end
  end
  
  defp archive_session_data(session_id) do
    case find_session(session_id) do
      {:ok, %{pid: pid} = info} ->
        # Get full session state
        state = get_session_state(pid)
        
        # Store in archive
        :mnesia.transaction(fn ->
          :mnesia.write({@archive_table, session_id, Map.merge(info, state), DateTime.utc_now()})
        end)
        
        # Stop session
        SessionSupervisor.stop_session(session_id)
        
        :ok
        
      {:error, :not_found} ->
        {:error, :session_not_found}
    end
  end
  
  defp remove_session_tracking(state, session_id) do
    # Remove from ETS
    :ets.delete(@session_registry, session_id)
    
    # Remove from state
    %{state |
      sessions: Map.delete(state.sessions, session_id)
    }
  end
  
  defp process_recovery_queue(queue) do
    Enum.map(queue, fn item ->
      case recover_session(item) do
        {:ok, session_id} -> {:recovered, session_id}
        {:error, reason} -> {:failed, item.session_id, reason}
      end
    end)
  end
  
  defp recover_session(%{session_id: session_id, data: data}) do
    # Attempt to restart session
    case start_session_on_node(session_id, data, select_optimal_node(data)) do
      {:ok, _pid} ->
        Logger.info("Recovered session #{session_id}")
        {:ok, session_id}
        
      {:error, reason} ->
        Logger.error("Failed to recover session #{session_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp compile_cluster_stats(state) do
    # Get basic stats
    session_stats = SessionSupervisor.stats()
    
    # Add manager stats
    %{
      cluster_stats: session_stats,
      migrations: %{
        active: map_size(state.migrations),
        history: get_migration_history()
      },
      recovery_queue: %{
        size: length(state.recovery_queue),
        oldest: get_oldest_queued_item(state.recovery_queue)
      },
      archives: %{
        count: count_archived_sessions(),
        oldest: get_oldest_archive()
      },
      node_health: check_node_health(),
      metrics: state.metrics
    }
  end
  
  defp get_migration_history do
    # Query event store for recent migrations
    case OTPEventBus.get_event_stream("migrations", event_types: [:session_migration_completed], limit: 100) do
      {:ok, events} -> length(events)
      _ -> 0
    end
  end
  
  defp get_oldest_queued_item([]), do: nil
  defp get_oldest_queued_item(queue) do
    Enum.min_by(queue, fn item -> item[:queued_at] end, DateTime)
  end
  
  defp count_archived_sessions do
    case :mnesia.table_info(@archive_table, :size) do
      size when is_integer(size) -> size
      _ -> 0
    end
  end
  
  defp get_oldest_archive do
    case :mnesia.transaction(fn ->
      :mnesia.first(@archive_table)
    end) do
      {:atomic, :"$end_of_table"} -> nil
      {:atomic, session_id} -> session_id
      _ -> nil
    end
  end
  
  defp check_node_health do
    nodes = [node() | Node.list()]
    
    Enum.map(nodes, fn n ->
      health = if n == node() do
        :healthy
      else
        case :net_adm.ping(n) do
          :pong -> :healthy
          :pang -> :unreachable
        end
      end
      
      {n, health}
    end)
    |> Enum.into(%{})
  end
  
  defp add_session_monitor(state, session_id, ref) do
    case Map.get(state.sessions, session_id) do
      nil ->
        state
        
      session ->
        updated_session = Map.update(session, :monitors, [ref], &[ref | &1])
        %{state |
          sessions: Map.put(state.sessions, session_id, updated_session)
        }
    end
  end
  
  defp handle_session_event(%{type: :session_created} = event, state) do
    # Only track if this session is not already tracked and is from another node
    session_id = event.data.session_id
    
    if event.data.node != node() do
      # This is from another node, track it
      track_session(state, session_id, nil, event.data.node)
    else
      # This is from our own node, it should already be tracked
      state
    end
  end
  
  defp handle_session_event(%{type: :session_closed, data: %{session_id: session_id}}, state) do
    remove_session_tracking(state, session_id)
  end
  
  defp handle_session_event(_event, state), do: state
  
  defp handle_session_crash(ref, _pid, reason, state) do
    # Find session by monitor ref
    case find_session_by_monitor(ref, state.sessions) do
      {:ok, session_id} ->
        Logger.error("Session #{session_id} crashed: #{inspect(reason)}")
        
        # Queue for recovery
        recovery_item = %{
          session_id: session_id,
          data: get_session_recovery_data(session_id),
          queued_at: DateTime.utc_now(),
          reason: reason
        }
        
        # Add to recovery queue
        new_state = %{state |
          recovery_queue: [recovery_item | state.recovery_queue],
          sessions: Map.delete(state.sessions, session_id)
        }
        
        # Attempt immediate recovery
        case recover_session(recovery_item) do
          {:ok, _} ->
            # Remove from queue if recovered
            %{new_state |
              recovery_queue: List.delete(new_state.recovery_queue, recovery_item)
            }
            
          _ ->
            new_state
        end
        
      _ ->
        state
    end
  end
  
  defp find_session_by_monitor(ref, sessions) do
    Enum.find_value(sessions, fn {session_id, %{monitors: monitors}} ->
      if ref in monitors do
        {:ok, session_id}
      else
        nil
      end
    end)
  end
  
  defp get_session_recovery_data(session_id) do
    # Try to get from event store
    case OTPEventBus.get_event_stream(session_id, limit: 1) do
      {:ok, [event | _]} -> event.data
      _ -> %{}
    end
  end
  
  defp handle_node_up(node, state) do
    Logger.info("Attempting partition recovery for node #{node}")
    
    # Process any queued sessions
    {recovered, remaining} = Enum.split_with(state.recovery_queue, fn item ->
      case recover_session(item) do
        {:ok, _} -> true
        _ -> false
      end
    end)
    
    Logger.info("Recovered #{length(recovered)} sessions after partition heal")
    
    %{state | recovery_queue: remaining}
  end
  
  defp handle_node_down(down_node, state) do
    # Find sessions on the down node
    affected_sessions = get_sessions_on_node(down_node)
    
    # Queue them for recovery
    recovery_items = Enum.map(affected_sessions, fn %{session_id: session_id} = info ->
      %{
        session_id: session_id,
        data: info,
        queued_at: DateTime.utc_now(),
        reason: {:nodedown, down_node}
      }
    end)
    
    Logger.warning("Queued #{length(recovery_items)} sessions for recovery from node #{down_node}")
    
    %{state |
      recovery_queue: state.recovery_queue ++ recovery_items
    }
  end
  
  defp get_sessions_on_node(node) do
    get_cluster_sessions()
    |> Enum.filter(fn s -> s[:node] == node end)
  end
  
  defp init_metrics do
    %{
      sessions_created: 0,
      sessions_migrated: 0,
      sessions_recovered: 0,
      sessions_archived: 0,
      crashes_handled: 0,
      partitions_healed: 0
    }
  end
  
  defp schedule_health_check do
    Process.send_after(self(), :health_check, 30_000)  # 30 seconds
  end
  
  defp perform_health_check(state) do
    # Check for stuck migrations
    stuck_migrations = Enum.filter(state.migrations, fn {_id, migration} ->
      DateTime.diff(DateTime.utc_now(), migration.started_at) > 300  # 5 minutes
    end)
    
    if length(stuck_migrations) > 0 do
      Logger.warning("Found #{length(stuck_migrations)} stuck migrations")
    end
    
    # Check recovery queue health
    if length(state.recovery_queue) > 100 do
      Logger.warning("Recovery queue is large: #{length(state.recovery_queue)} items")
    end
  end
end