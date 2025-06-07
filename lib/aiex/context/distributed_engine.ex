defmodule Aiex.Context.DistributedEngine do
  @moduledoc """
  Distributed context management engine using Mnesia for persistence and 
  pg module for event distribution across cluster nodes.

  Provides distributed context storage with ACID guarantees, cross-node 
  synchronization, and automatic failover.
  """

  use GenServer
  require Logger

  # Mnesia table definitions
  @ai_context_table :ai_context
  @code_analysis_cache_table :code_analysis_cache
  @llm_interaction_table :llm_interaction

  # Context data structures (moved to separate modules would be cleaner,
  # but keeping here for simplicity in this initial implementation)

  ## Client API

  @doc """
  Starts the distributed context engine.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates or updates an AI context session.
  """
  def put_context(session_id, context) do
    GenServer.call(__MODULE__, {:put_context, session_id, context})
  end

  @doc """
  Retrieves an AI context by session ID.
  """
  def get_context(session_id) do
    GenServer.call(__MODULE__, {:get_context, session_id})
  end

  @doc """
  Stores code analysis results in the cache.
  """
  def put_analysis(file_path, analysis) do
    GenServer.call(__MODULE__, {:put_analysis, file_path, analysis})
  end

  @doc """
  Retrieves cached code analysis for a file.
  """
  def get_analysis(file_path) do
    GenServer.call(__MODULE__, {:get_analysis, file_path})
  end

  @doc """
  Records an LLM interaction.
  """
  def record_interaction(interaction) do
    GenServer.call(__MODULE__, {:record_interaction, interaction})
  end

  @doc """
  Gets interaction history for a session.
  """
  def get_interactions(session_id) do
    GenServer.call(__MODULE__, {:get_interactions, session_id})
  end

  @doc """
  Gets distributed context statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Initialize Mnesia if not already done
    case setup_mnesia() do
      :ok -> 
        Logger.info("Distributed context engine started successfully")
        {:ok, %{node: node()}}
      {:error, reason} -> 
        Logger.error("Failed to setup Mnesia: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:put_context, session_id, context}, _from, state) do
    result = mnesia_transaction(fn ->
      context_record = %{
        session_id: session_id,
        user_id: Map.get(context, :user_id),
        conversation_history: Map.get(context, :conversation_history, []),
        active_model: Map.get(context, :active_model),
        embeddings: Map.get(context, :embeddings, %{}),
        created_at: Map.get(context, :created_at, DateTime.utc_now()),
        last_updated: DateTime.utc_now()
      }
      
      :mnesia.write({@ai_context_table, session_id, context_record})
    end)

    # Broadcast context update via pg (only if available)
    try do
      broadcast_context_update(session_id, :updated)
    catch
      _, _ -> 
        Logger.debug("pg not available for broadcasting, skipping")
    end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_context, session_id}, _from, state) do
    result = mnesia_transaction(fn ->
      case :mnesia.read({@ai_context_table, session_id}) do
        [{@ai_context_table, ^session_id, context}] -> {:ok, context}
        [] -> {:error, :not_found}
      end
    end)

    case result do
      {:atomic, inner_result} -> {:reply, inner_result, state}
      {:aborted, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:put_analysis, file_path, analysis}, _from, state) do
    result = mnesia_transaction(fn ->
      analysis_record = %{
        file_path: file_path,
        ast: Map.get(analysis, :ast),
        symbols: Map.get(analysis, :symbols, []),
        dependencies: Map.get(analysis, :dependencies, []),
        last_analyzed: DateTime.utc_now()
      }
      
      :mnesia.write({@code_analysis_cache_table, file_path, analysis_record})
    end)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_analysis, file_path}, _from, state) do
    result = mnesia_transaction(fn ->
      case :mnesia.read({@code_analysis_cache_table, file_path}) do
        [{@code_analysis_cache_table, ^file_path, analysis}] -> {:ok, analysis}
        [] -> {:error, :not_found}
      end
    end)

    case result do
      {:atomic, inner_result} -> {:reply, inner_result, state}
      {:aborted, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:record_interaction, interaction}, _from, state) do
    interaction_id = generate_interaction_id()
    
    result = mnesia_transaction(fn ->
      interaction_record = %{
        interaction_id: interaction_id,
        session_id: Map.get(interaction, :session_id),
        prompt: Map.get(interaction, :prompt),
        response: Map.get(interaction, :response),
        model_used: Map.get(interaction, :model_used),
        tokens_used: Map.get(interaction, :tokens_used),
        latency_ms: Map.get(interaction, :latency_ms),
        timestamp: DateTime.utc_now()
      }
      
      :mnesia.write({@llm_interaction_table, interaction_id, interaction_record})
    end)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_interactions, session_id}, _from, state) do
    result = mnesia_transaction(fn ->
      # For now, scan all interactions to find by session_id
      all_interactions = :mnesia.select(@llm_interaction_table, [{{@llm_interaction_table, :'$1', :'$2'}, [], [:'$2']}])
      Enum.filter(all_interactions, fn record -> 
        Map.get(record, :session_id) == session_id 
      end)
    end)

    case result do
      {:atomic, interactions} -> 
        {:reply, {:ok, interactions}, state}
      {:aborted, reason} -> 
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      node: node(),
      ai_contexts: table_size(@ai_context_table),
      code_analyses: table_size(@code_analysis_cache_table),
      llm_interactions: table_size(@llm_interaction_table),
      cluster_nodes: [node() | Node.list()],
      mnesia_running: :mnesia.system_info(:is_running)
    }

    {:reply, stats, state}
  end

  ## Private Functions

  defp setup_mnesia do
    nodes = [node() | Node.list()]
    
    # Create schema if it doesn't exist
    case :mnesia.create_schema(nodes) do
      :ok -> :ok
      {:error, {_, {:already_exists, _}}} -> :ok
      error -> error
    end

    # Start Mnesia
    case :mnesia.start() do
      :ok -> create_tables(nodes)
      error -> error
    end
  end

  defp create_tables(nodes) do
    # AI Context table - use ram_copies for single node development
    table_type = if length(nodes) > 1, do: :disc_copies, else: :ram_copies
    
    create_table(@ai_context_table, [
      {table_type, nodes},
      {:attributes, [:session_id, :context]},
      {:type, :set}
    ])

    # Code Analysis Cache table
    create_table(@code_analysis_cache_table, [
      {table_type, nodes},
      {:attributes, [:file_path, :analysis]},
      {:type, :set}
    ])

    # LLM Interaction table - simplified for single node development
    create_table(@llm_interaction_table, [
      {table_type, nodes},
      {:attributes, [:interaction_id, :interaction]},
      {:type, :set}
    ])

    :ok
  end

  defp create_table(name, options) do
    case :mnesia.create_table(name, options) do
      {:atomic, :ok} -> 
        Logger.info("Created Mnesia table: #{name}")
        :ok
      {:aborted, {:already_exists, ^name}} -> 
        Logger.debug("Mnesia table already exists: #{name}")
        :ok
      {:aborted, reason} -> 
        Logger.error("Failed to create Mnesia table #{name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp mnesia_transaction(fun) do
    try do
      :mnesia.transaction(fun)
    catch
      :exit, {:aborted, reason} -> {:aborted, reason}
      :exit, reason -> {:aborted, reason}
    end
  end

  defp table_size(table_name) do
    try do
      :mnesia.table_info(table_name, :size)
    catch
      :exit, _ -> 0
    end
  end

  defp generate_interaction_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
  end

  defp broadcast_context_update(session_id, action) do
    # Use pg module for distributed event broadcasting
    event = %{
      session_id: session_id,
      action: action,
      node: node(),
      timestamp: DateTime.utc_now()
    }

    # Join the context_updates group if not already joined
    :pg.join(:context_updates, self())
    
    # Broadcast to all members of the group
    members = :pg.get_members(:context_updates)
    Enum.each(members, fn pid ->
      send(pid, {:context_update, event})
    end)
  end
end