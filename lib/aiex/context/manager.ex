defmodule Aiex.Context.Manager do
  @moduledoc """
  Context manager that coordinates distributed context operations using Horde
  for distributed process management and pg for event distribution.
  
  Manages context sessions across cluster nodes with automatic failover and
  distributed state synchronization.
  """

  use GenServer
  require Logger

  ## Client API

  @doc """
  Starts the context manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets or creates a context session, potentially on any cluster node.
  """
  def get_or_create_session(session_id, user_id \\ nil) do
    GenServer.call(__MODULE__, {:get_or_create_session, session_id, user_id})
  end

  @doc """
  Updates context for a session with distributed synchronization.
  """
  def update_context(session_id, updates) do
    GenServer.call(__MODULE__, {:update_context, session_id, updates})
  end

  @doc """
  Gets the current context for a session.
  """
  def get_context(session_id) do
    GenServer.call(__MODULE__, {:get_context, session_id})
  end

  @doc """
  Lists all active sessions across the cluster.
  """
  def list_sessions do
    GenServer.call(__MODULE__, :list_sessions)
  end

  @doc """
  Archives a session and removes it from active memory.
  """
  def archive_session(session_id) do
    GenServer.call(__MODULE__, {:archive_session, session_id})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Only join pg groups if not in test environment
    unless Application.get_env(:aiex, :test_mode, false) do
      Process.send_after(self(), :join_pg_groups, 100)
    end

    state = %{
      local_sessions: %{},
      node: node()
    }

    Logger.info("Context manager started on node #{node()}")
    {:ok, state}
  end

  @impl true
  def handle_call({:get_or_create_session, session_id, user_id}, _from, state) do
    case find_session_process(session_id) do
      {:ok, pid} -> 
        {:reply, {:ok, pid}, state}
      
      {:error, :not_found} -> 
        case create_session_process(session_id, user_id) do
          {:ok, pid} -> 
            new_state = track_local_session(state, session_id, pid)
            {:reply, {:ok, pid}, new_state}
          
          {:error, reason} -> 
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:update_context, session_id, updates}, _from, state) do
    case Aiex.Context.DistributedEngine.get_context(session_id) do
      {:ok, current_context} ->
        merged_context = Map.merge(current_context, updates)
        result = Aiex.Context.DistributedEngine.put_context(session_id, merged_context)
        {:reply, result, state}
      
      {:error, :not_found} ->
        # Create new context with updates
        new_context = Map.merge(%{
          session_id: session_id,
          created_at: DateTime.utc_now()
        }, updates)
        
        result = Aiex.Context.DistributedEngine.put_context(session_id, new_context)
        {:reply, result, state}
      
      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_context, session_id}, _from, state) do
    result = Aiex.Context.DistributedEngine.get_context(session_id)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_sessions, _from, state) do
    # Get sessions from all nodes in the cluster
    local_sessions = Map.keys(state.local_sessions)
    
    cluster_sessions = 
      [node() | Node.list()]
      |> Enum.flat_map(fn node ->
        try do
          case :rpc.call(node, __MODULE__, :get_local_sessions, [], 5000) do
            {:badrpc, _reason} -> []
            sessions when is_list(sessions) -> sessions
            _ -> []
          end
        catch
          _, _ -> []
        end
      end)
      |> Enum.uniq()

    all_sessions = Enum.uniq(local_sessions ++ cluster_sessions)
    {:reply, {:ok, all_sessions}, state}
  end

  @impl true
  def handle_call({:archive_session, session_id}, _from, state) do
    # Remove from local tracking
    new_state = %{state | local_sessions: Map.delete(state.local_sessions, session_id)}
    
    # Notify cluster of session archival
    broadcast_session_event(session_id, :archived)
    
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_local_sessions_only, _from, state) do
    {:reply, Map.keys(state.local_sessions), state}
  end

  @impl true
  def handle_info(:join_pg_groups, state) do
    try do
      # Ensure pg scopes exist - each scope is a separate pg instance
      with :ok <- ensure_pg_scope(:aiex_events) do
        # Join the process groups within the aiex_events scope
        :pg.join(:aiex_events, :context_managers, self())
        :pg.join(:aiex_events, :context_updates, self())
        
        Logger.info("Joined pg groups for context management")
      end
    catch
      :error, reason ->
        Logger.warning("Failed to join pg groups: #{inspect(reason)}")
        # Retry after a delay
        Process.send_after(self(), :join_pg_groups, 1000)
    end
    
    {:noreply, state}
  end

  @impl true
  def handle_info({:context_update, event}, state) do
    Logger.debug("Received context update: #{inspect(event)}")
    # Handle context synchronization events from other nodes
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Handle session process termination
    case find_session_by_pid(state, pid) do
      {:ok, session_id} ->
        Logger.warning("Session #{session_id} process terminated: #{inspect(reason)}")
        new_state = %{state | local_sessions: Map.delete(state.local_sessions, session_id)}
        
        # Broadcast session termination
        broadcast_session_event(session_id, :terminated)
        
        {:noreply, new_state}
      
      :not_found ->
        {:noreply, state}
    end
  end

  ## Public functions for RPC calls

  @doc """
  Gets local sessions for this node (used by RPC calls).
  """
  def get_local_sessions do
    case GenServer.whereis(__MODULE__) do
      nil -> []
      pid -> 
        try do
          GenServer.call(pid, :get_local_sessions_only)
        catch
          _, _ -> []
        end
    end
  end

  ## Private Functions
  
  defp ensure_pg_scope(scope) do
    # The scope should already be started by the TUI.EventBridge
    # Just check if it exists, don't try to start it
    case :pg.which_groups(scope) do
      groups when is_list(groups) -> :ok
      {:error, {:no_such_group, _}} -> 
        # Scope doesn't exist, but that's okay - it will be created when first used
        :ok
      error -> 
        Logger.debug("pg scope #{scope} check returned: #{inspect(error)}")
        :ok  # Don't fail - let the join operation handle it
    end
  end

  defp find_session_process(session_id) do
    lookup_result = Horde.Registry.lookup(Aiex.Context.SessionRegistry, {:session, session_id})
    Logger.debug("Looking up session #{session_id}, found: #{inspect(lookup_result)}")
    
    case lookup_result do
      [{pid, _}] when is_pid(pid) -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  defp create_session_process(session_id, user_id) do
    Logger.info("Creating new context for session #{session_id}")
    
    session_spec = %{
      id: {:session, session_id},
      start: {Aiex.Context.Session, :start_link, [session_id, user_id]},
      restart: :transient
    }

    case Horde.DynamicSupervisor.start_child(
      Aiex.Context.SessionSupervisor,
      session_spec
    ) do
      {:ok, pid} ->
        # Session process will register itself
        {:ok, pid}
      
      {:error, {:already_started, pid}} ->
        {:ok, pid}
      
      error ->
        error
    end
  end

  defp track_local_session(state, session_id, pid) do
    # Monitor the session process
    Process.monitor(pid)
    
    %{state | local_sessions: Map.put(state.local_sessions, session_id, pid)}
  end

  defp find_session_by_pid(state, pid) do
    case Enum.find(state.local_sessions, fn {_id, p} -> p == pid end) do
      {session_id, ^pid} -> {:ok, session_id}
      nil -> :not_found
    end
  end

  defp broadcast_session_event(session_id, action) do
    # Skip broadcasting in test environment
    unless Application.get_env(:aiex, :test_mode, false) do
      event = %{
        session_id: session_id,
        action: action,
        node: node(),
        timestamp: DateTime.utc_now()
      }

      try do
        # Broadcast to all context managers in the aiex_events scope
        members = :pg.get_members(:aiex_events, :context_managers)
        Enum.each(members, fn pid ->
          send(pid, {:session_event, event})
        end)
      catch
        :error, reason ->
          Logger.warning("Failed to broadcast session event: #{inspect(reason)}")
      end
    end
  end
end