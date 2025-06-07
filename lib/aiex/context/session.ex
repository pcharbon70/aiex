defmodule Aiex.Context.Session do
  @moduledoc """
  Individual context session process that manages state for a specific user session.
  
  Each session is a GenServer that maintains conversation context, handles
  AI interactions, and synchronizes state with the distributed context engine.
  """

  use GenServer
  require Logger

  defstruct [
    :session_id,
    :user_id,
    :conversation_history,
    :active_model,
    :embeddings,
    :created_at,
    :last_activity,
    :metadata
  ]

  ## Client API

  @doc """
  Starts a context session process.
  """
  def start_link(session_id, user_id \\ nil) do
    GenServer.start_link(__MODULE__, {session_id, user_id})
  end

  @doc """
  Adds a message to the conversation history.
  """
  def add_message(pid, message) do
    GenServer.call(pid, {:add_message, message})
  end

  @doc """
  Sets the active AI model for this session.
  """
  def set_active_model(pid, model) do
    GenServer.call(pid, {:set_active_model, model})
  end

  @doc """
  Updates session metadata.
  """
  def update_metadata(pid, metadata) do
    GenServer.call(pid, {:update_metadata, metadata})
  end

  @doc """
  Gets the current session state.
  """
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Adds or updates embeddings for context.
  """
  def put_embedding(pid, key, embedding) do
    GenServer.call(pid, {:put_embedding, key, embedding})
  end

  @doc """
  Gets embeddings for similarity search.
  """
  def get_embeddings(pid) do
    GenServer.call(pid, :get_embeddings)
  end

  ## Server Callbacks

  @impl true
  def init({session_id, user_id}) do
    # Try to load existing context from distributed storage
    initial_state = case Aiex.Context.DistributedEngine.get_context(session_id) do
      {:ok, stored_context} ->
        Logger.info("Loaded existing context for session #{session_id}")
        struct(__MODULE__, stored_context)
      
      {:error, :not_found} ->
        Logger.info("Creating new context for session #{session_id}")
        %__MODULE__{
          session_id: session_id,
          user_id: user_id,
          conversation_history: [],
          active_model: nil,
          embeddings: %{},
          created_at: DateTime.utc_now(),
          last_activity: DateTime.utc_now(),
          metadata: %{}
        }
    end

    # Schedule periodic persistence
    schedule_persistence()

    {:ok, initial_state}
  end

  @impl true
  def handle_call({:add_message, message}, _from, state) do
    new_message = Map.merge(message, %{
      timestamp: DateTime.utc_now(),
      id: generate_message_id()
    })

    new_history = [new_message | state.conversation_history]
    new_state = %{state | 
      conversation_history: new_history,
      last_activity: DateTime.utc_now()
    }

    # Persist to distributed storage
    persist_state(new_state)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:set_active_model, model}, _from, state) do
    new_state = %{state | 
      active_model: model,
      last_activity: DateTime.utc_now()
    }

    persist_state(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:update_metadata, metadata}, _from, state) do
    new_metadata = Map.merge(state.metadata || %{}, metadata)
    new_state = %{state | 
      metadata: new_metadata,
      last_activity: DateTime.utc_now()
    }

    persist_state(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:put_embedding, key, embedding}, _from, state) do
    new_embeddings = Map.put(state.embeddings, key, embedding)
    new_state = %{state | 
      embeddings: new_embeddings,
      last_activity: DateTime.utc_now()
    }

    persist_state(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_embeddings, _from, state) do
    {:reply, state.embeddings, state}
  end

  @impl true
  def handle_info(:persist_state, state) do
    persist_state(state)
    schedule_persistence()
    {:noreply, state}
  end

  @impl true
  def handle_info({:context_update, event}, state) do
    # Handle distributed context updates
    if event.session_id == state.session_id and event.node != node() do
      Logger.debug("Received external context update for session #{state.session_id}")
      # Could reload state from distributed storage if needed
    end
    
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Session #{state.session_id} terminating: #{inspect(reason)}")
    # Final persistence before shutdown
    persist_state(state)
    :ok
  end

  ## Private Functions

  defp persist_state(state) do
    context_map = %{
      session_id: state.session_id,
      user_id: state.user_id,
      conversation_history: state.conversation_history,
      active_model: state.active_model,
      embeddings: state.embeddings,
      created_at: state.created_at,
      last_updated: DateTime.utc_now(),
      metadata: state.metadata
    }

    case Aiex.Context.DistributedEngine.put_context(state.session_id, context_map) do
      {:atomic, :ok} ->
        Logger.debug("Persisted context for session #{state.session_id}")
      
      {:aborted, reason} ->
        Logger.error("Failed to persist context for session #{state.session_id}: #{inspect(reason)}")
    end
  end

  defp schedule_persistence do
    # Persist every 30 seconds
    Process.send_after(self(), :persist_state, 30_000)
  end

  defp generate_message_id do
    :crypto.strong_rand_bytes(8) |> Base.encode64(padding: false)
  end
end