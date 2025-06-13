defmodule Aiex.Performance.MnesiaOptimizer do
  @moduledoc """
  Mnesia performance optimization utilities.
  
  Provides tools for optimizing Mnesia table configuration, analyzing
  table performance, and implementing best practices for distributed
  Mnesia deployments.
  """

  require Logger

  @doc """
  Analyzes all Mnesia tables and provides optimization recommendations.
  """
  def analyze_tables do
    tables = :mnesia.system_info(:tables) -- [:schema]
    
    analysis = Enum.map(tables, fn table ->
      {table, analyze_table(table)}
    end)
    |> Map.new()
    
    %{
      tables: analysis,
      recommendations: generate_recommendations(analysis),
      cluster_status: analyze_cluster_status()
    }
  end

  @doc """
  Optimizes a specific Mnesia table based on usage patterns.
  """
  def optimize_table(table, opts \\ []) do
    analysis = analyze_table(table)
    
    optimizations = []
    
    # Add indices if needed
    optimizations = if should_add_indices?(analysis, opts) do
      add_optimal_indices(table, analysis) ++ optimizations
    else
      optimizations
    end
    
    # Adjust table type if needed
    optimizations = if should_change_table_type?(analysis, opts) do
      [change_table_type(table, analysis) | optimizations]
    else
      optimizations
    end
    
    # Configure table fragmentation if needed
    optimizations = if should_fragment_table?(analysis, opts) do
      [configure_fragmentation(table, analysis) | optimizations]
    else
      optimizations
    end
    
    {:ok, optimizations}
  end

  @doc """
  Creates optimized Mnesia schema for the cluster.
  """
  def create_optimized_schema(nodes \\ [node() | Node.list()]) do
    # Stop Mnesia on all nodes
    :rpc.multicall(nodes, :mnesia, :stop, [])
    
    # Delete old schema
    :mnesia.delete_schema(nodes)
    
    # Create new schema
    :ok = :mnesia.create_schema(nodes)
    
    # Start Mnesia on all nodes
    :rpc.multicall(nodes, :mnesia, :start, [])
    
    # Wait for tables
    :mnesia.wait_for_tables([:schema], 5000)
    
    :ok
  end

  @doc """
  Configures Mnesia for optimal performance.
  """
  def configure_performance_settings do
    # Set dump log threshold (more frequent dumps for better performance)
    :mnesia.system_info(:dump_log_write_threshold)
    |> case do
      threshold when threshold > 1000 ->
        Application.put_env(:mnesia, :dump_log_write_threshold, 1000)
      _ -> :ok
    end
    
    # Configure DC dump limit
    Application.put_env(:mnesia, :dc_dump_limit, 40)
    
    # Configure maximum wait for decision
    Application.put_env(:mnesia, :max_wait_for_decision, 60_000)
    
    :ok
  end

  @doc """
  Performs maintenance on Mnesia tables.
  """
  def perform_maintenance do
    tables = :mnesia.system_info(:tables) -- [:schema]
    
    Enum.each(tables, fn table ->
      # Force checkpoint
      case :mnesia.checkpoint([{:name, table}, {:ram_overrides_dump, true}]) do
        {:ok, _name} -> :ok
        {:error, reason} -> 
          Logger.warning("Failed to checkpoint #{table}: #{inspect(reason)}")
      end
      
      # Dump tables to ensure persistence
      :mnesia.dump_tables([table])
    end)
    
    # Force garbage collection of transaction log
    :mnesia.system_info(:transaction_log)
    
    :ok
  end

  @doc """
  Monitors Mnesia performance metrics.
  """
  def get_performance_metrics do
    %{
      transactions: get_transaction_metrics(),
      tables: get_table_metrics(),
      replication: get_replication_metrics(),
      checkpoints: get_checkpoint_metrics(),
      memory: get_memory_metrics()
    }
  end

  # Private functions

  defp analyze_table(table) do
    info = get_table_info(table)
    
    %{
      info: info,
      size: :mnesia.table_info(table, :size),
      memory: :mnesia.table_info(table, :memory),
      type: :mnesia.table_info(table, :type),
      disc_copies: :mnesia.table_info(table, :disc_copies),
      ram_copies: :mnesia.table_info(table, :ram_copies),
      disc_only_copies: :mnesia.table_info(table, :disc_only_copies),
      indices: :mnesia.table_info(table, :index),
      attributes: :mnesia.table_info(table, :attributes),
      fragmentation: analyze_fragmentation(table),
      access_patterns: analyze_access_patterns(table)
    }
  end

  defp get_table_info(table) do
    [
      size: :mnesia.table_info(table, :size),
      type: :mnesia.table_info(table, :type),
      access_mode: :mnesia.table_info(table, :access_mode),
      load_order: :mnesia.table_info(table, :load_order),
      majority: :mnesia.table_info(table, :majority),
      master_nodes: :mnesia.table_info(table, :master_nodes)
    ]
  rescue
    _ -> []
  end

  defp analyze_fragmentation(table) do
    case :mnesia.table_info(table, :frag_properties) do
      [] -> 
        %{fragmented: false}
      props ->
        %{
          fragmented: true,
          n_fragments: Keyword.get(props, :n_fragments, 1),
          node_pool: Keyword.get(props, :node_pool, []),
          n_disc_copies: Keyword.get(props, :n_disc_copies, 0),
          n_ram_copies: Keyword.get(props, :n_ram_copies, 0)
        }
    end
  rescue
    _ -> %{fragmented: false}
  end

  defp analyze_access_patterns(table) do
    # This would ideally track actual access patterns
    # For now, we'll use heuristics based on table properties
    %{
      read_heavy: estimate_read_pattern(table),
      write_heavy: estimate_write_pattern(table),
      recommended_type: recommend_table_type(table)
    }
  end

  defp estimate_read_pattern(table) do
    # Tables with indices are usually read-heavy
    indices = :mnesia.table_info(table, :index)
    length(indices) > 0
  end

  defp estimate_write_pattern(table) do
    # Large tables without indices might be write-heavy
    size = :mnesia.table_info(table, :size)
    indices = :mnesia.table_info(table, :index)
    size > 10000 and length(indices) == 0
  end

  defp recommend_table_type(table) do
    size = :mnesia.table_info(table, :size)
    current_type = :mnesia.table_info(table, :type)
    
    cond do
      size < 1000 -> :ram_copies
      size < 100_000 and current_type == :disc_only_copies -> :disc_copies
      size > 1_000_000 and current_type == :ram_copies -> :disc_copies
      true -> current_type
    end
  end

  defp generate_recommendations(analysis) do
    recommendations = []
    
    recommendations = Enum.reduce(analysis, recommendations, fn {table, data}, recs ->
      table_recs = []
      
      # Check memory usage
      table_recs = if data.memory > 100_000_000 do  # 100MB
        ["Table #{table} uses #{div(data.memory, 1_048_576)}MB - consider fragmentation" | table_recs]
      else
        table_recs
      end
      
      # Check indices
      table_recs = if data.size > 10000 and length(data.indices) == 0 do
        ["Table #{table} has #{data.size} records but no indices" | table_recs]
      else
        table_recs
      end
      
      # Check replication
      nodes = [node() | Node.list()]
      replicated_nodes = data.disc_copies ++ data.ram_copies ++ data.disc_only_copies
      table_recs = if length(nodes) > 1 and length(replicated_nodes) < length(nodes) do
        ["Table #{table} is not replicated to all nodes" | table_recs]
      else
        table_recs
      end
      
      recs ++ table_recs
    end)
    
    recommendations
  end

  defp should_add_indices?(analysis, opts) do
    force = Keyword.get(opts, :add_indices, false)
    size = Map.get(analysis, :size, 0)
    indices = Map.get(analysis, :indices, [])
    
    force or (size > 10000 and length(indices) == 0)
  end

  defp add_optimal_indices(table, analysis) do
    attributes = Map.get(analysis, :attributes, [])
    existing_indices = Map.get(analysis, :indices, [])
    
    # Add index on second attribute if not present (first is usually the key)
    case attributes do
      [_key, second | _] ->
        if second not in existing_indices do
          :mnesia.add_table_index(table, second)
          [{:added_index, table, second}]
        else
          []
        end
      _ ->
        []
    end
  end

  defp should_change_table_type?(analysis, opts) do
    force = Keyword.get(opts, :optimize_type, false)
    current = Map.get(analysis, :type, :unknown)
    recommended = get_in(analysis, [:access_patterns, :recommended_type])
    
    force or (current != recommended and recommended != nil)
  end

  defp change_table_type(table, analysis) do
    recommended = get_in(analysis, [:access_patterns, :recommended_type])
    nodes = [node() | Node.list()]
    
    case recommended do
      :ram_copies ->
        :mnesia.change_table_copy_type(table, node(), :ram_copies)
        {:changed_type, table, :ram_copies}
        
      :disc_copies ->
        :mnesia.change_table_copy_type(table, node(), :disc_copies)
        {:changed_type, table, :disc_copies}
        
      :disc_only_copies ->
        :mnesia.change_table_copy_type(table, node(), :disc_only_copies)
        {:changed_type, table, :disc_only_copies}
        
      _ ->
        {:no_change, table}
    end
  end

  defp should_fragment_table?(analysis, opts) do
    force = Keyword.get(opts, :fragment, false)
    size = Map.get(analysis, :size, 0)
    already_fragmented = get_in(analysis, [:fragmentation, :fragmented]) == true
    
    force or (size > 1_000_000 and not already_fragmented)
  end

  defp configure_fragmentation(table, _analysis) do
    nodes = [node() | Node.list()]
    n_fragments = length(nodes) * 2  # 2 fragments per node
    
    frag_properties = [
      {:n_fragments, n_fragments},
      {:node_pool, nodes},
      {:n_disc_copies, 1}
    ]
    
    case :mnesia.change_table_frag(table, {:activate, frag_properties}) do
      {:atomic, :ok} ->
        {:fragmented, table, n_fragments}
      {:aborted, reason} ->
        Logger.error("Failed to fragment table #{table}: #{inspect(reason)}")
        {:fragmentation_failed, table, reason}
    end
  end

  defp analyze_cluster_status do
    nodes = [node() | Node.list()]
    running_nodes = :mnesia.system_info(:running_db_nodes)
    
    %{
      configured_nodes: nodes,
      running_nodes: running_nodes,
      down_nodes: nodes -- running_nodes,
      db_nodes: :mnesia.system_info(:db_nodes),
      master_node: :mnesia.system_info(:master_node_tables)
    }
  end

  defp get_transaction_metrics do
    %{
      committed: :mnesia.system_info(:transaction_commits),
      aborted: :mnesia.system_info(:transaction_failures),
      restarts: :mnesia.system_info(:transaction_restarts),
      log_writes: :mnesia.system_info(:transaction_log_writes)
    }
  end

  defp get_table_metrics do
    tables = :mnesia.system_info(:tables) -- [:schema]
    
    Enum.map(tables, fn table ->
      {table, %{
        size: :mnesia.table_info(table, :size),
        memory: :mnesia.table_info(table, :memory),
        checkpoints: length(:mnesia.table_info(table, :checkpoints))
      }}
    end)
    |> Map.new()
  end

  defp get_replication_metrics do
    %{
      messages_sent: :mnesia.system_info(:replication_messages_sent),
      messages_received: :mnesia.system_info(:replication_messages_received)
    }
  rescue
    _ -> %{error: "Replication metrics not available"}
  end

  defp get_checkpoint_metrics do
    checkpoints = :mnesia.system_info(:checkpoints)
    
    Enum.map(checkpoints, fn {name, _pid} ->
      {name, :mnesia.system_info({:checkpoint, name})}
    end)
    |> Map.new()
  rescue
    _ -> %{}
  end

  defp get_memory_metrics do
    %{
      ets_memory: :mnesia.system_info(:ets_memory),
      dets_memory: :mnesia.system_info(:dets_memory)
    }
  rescue
    _ -> %{error: "Memory metrics not available"}
  end
end