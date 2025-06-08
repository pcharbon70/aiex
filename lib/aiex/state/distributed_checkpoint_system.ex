defmodule Aiex.State.DistributedCheckpointSystem do
  @moduledoc """
  Distributed checkpoint system for cluster-wide state management.

  Provides comprehensive checkpoint functionality with:
  - Distributed checkpoint creation with Mnesia storage
  - Cross-node synchronization for cluster-wide state consistency
  - Checkpoint diff storage and incremental updates
  - Cluster-wide naming, tagging, and categorization
  - Distributed retention policies and cleanup
  - Cross-node comparison tools and analysis
  - Distributed restore mechanisms with rollback support
  - Checkpoint replication and backup strategies
  - Integration with event sourcing for complete state tracking

  ## Architecture

  Uses pg module for distributed coordination, Mnesia for persistent storage,
  and integrates with the existing event sourcing system for complete
  checkpoint auditability across the cluster.

  ## Usage

      # Create a checkpoint across the cluster
      {:ok, checkpoint_id} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "before_major_update",
        description: "State before implementing new feature",
        include_data: [:context, :sessions, :events],
        tag: "release-v1.2.0"
      })

      # Restore from a checkpoint
      {:ok, restore_info} = DistributedCheckpointSystem.restore_checkpoint(
        checkpoint_id,
        %{dry_run: false, confirm: true}
      )

      # Compare two checkpoints
      {:ok, diff} = DistributedCheckpointSystem.compare_checkpoints(
        checkpoint_id_1,
        checkpoint_id_2
      )
  """

  use GenServer
  require Logger

  alias Aiex.Events.OTPEventBus
  alias Aiex.Context.DistributedEngine
  alias Aiex.State.DistributedSessionManager

  @pg_scope :checkpoint_system
  @checkpoint_table :distributed_checkpoints
  @checkpoint_data_table :checkpoint_data
  @checkpoint_diffs_table :checkpoint_diffs
  @checkpoint_metadata_table :checkpoint_metadata
  @checkpoint_tags_table :checkpoint_tags

  defstruct [
    :node,
    :active_operations,
    :checkpoint_cache,
    :retention_policies,
    :replication_status,
    :metrics
  ]

  ## Client API

  @doc """
  Starts the distributed checkpoint system.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates a distributed checkpoint across all nodes.

  ## Options
  - `:name` - Human-readable name for the checkpoint
  - `:description` - Detailed description of the checkpoint
  - `:include_data` - List of data types to include (`:context`, `:sessions`, `:events`, `:all`)
  - `:tag` - Tag for categorizing checkpoints
  - `:retention_days` - Number of days to retain this checkpoint
  - `:compression` - Compression level (`:none`, `:low`, `:medium`, `:high`)
  - `:replicate_to` - Specific nodes to replicate to (default: all)

  ## Examples

      {:ok, checkpoint_id} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "pre_deployment_state",
        description: "State before deploying version 2.0",
        include_data: [:context, :sessions],
        tag: "deployment",
        retention_days: 90
      })
  """
  def create_checkpoint(options \\ %{}) do
    GenServer.call(__MODULE__, {:create_checkpoint, options}, 120_000)
  end

  @doc """
  Lists all available checkpoints with filtering options.

  ## Options
  - `:tags` - Filter by specific tags
  - `:created_after` - Show checkpoints created after this datetime
  - `:created_before` - Show checkpoints created before this datetime
  - `:include_data_types` - Filter by included data types
  - `:order` - `:asc` or `:desc` (default: `:desc`)
  - `:limit` - Maximum number of checkpoints to return

  ## Examples

      {:ok, checkpoints} = DistributedCheckpointSystem.list_checkpoints(%{
        tags: ["deployment", "backup"],
        created_after: ~U[2024-01-01 00:00:00Z],
        limit: 10
      })
  """
  def list_checkpoints(options \\ %{}) do
    GenServer.call(__MODULE__, {:list_checkpoints, options}, 30_000)
  end

  @doc """
  Gets detailed information about a specific checkpoint.
  """
  def get_checkpoint_info(checkpoint_id) do
    GenServer.call(__MODULE__, {:get_checkpoint_info, checkpoint_id})
  end

  @doc """
  Restores the cluster state from a checkpoint.

  ## Options
  - `:dry_run` - Preview the restore without applying changes (default: true)
  - `:confirm` - Explicit confirmation required for actual restore (default: false)
  - `:restore_data` - List of data types to restore (default: all included in checkpoint)
  - `:target_nodes` - Specific nodes to restore to (default: all)
  - `:backup_current` - Create backup of current state before restore (default: true)

  ## Examples

      # Dry run to preview changes
      {:ok, preview} = DistributedCheckpointSystem.restore_checkpoint(checkpoint_id, %{
        dry_run: true
      })

      # Actual restore with confirmation
      {:ok, result} = DistributedCheckpointSystem.restore_checkpoint(checkpoint_id, %{
        dry_run: false,
        confirm: true,
        backup_current: true
      })
  """
  def restore_checkpoint(checkpoint_id, options \\ %{}) do
    GenServer.call(__MODULE__, {:restore_checkpoint, checkpoint_id, options}, 300_000)
  end

  @doc """
  Compares two checkpoints and returns their differences.
  """
  def compare_checkpoints(checkpoint_id_1, checkpoint_id_2, options \\ %{}) do
    GenServer.call(__MODULE__, {:compare_checkpoints, checkpoint_id_1, checkpoint_id_2, options}, 60_000)
  end

  @doc """
  Deletes a checkpoint from all nodes.
  """
  def delete_checkpoint(checkpoint_id, options \\ %{}) do
    GenServer.call(__MODULE__, {:delete_checkpoint, checkpoint_id, options})
  end

  @doc """
  Tags a checkpoint for organization and filtering.
  """
  def tag_checkpoint(checkpoint_id, tags) when is_list(tags) do
    GenServer.call(__MODULE__, {:tag_checkpoint, checkpoint_id, tags})
  end

  @doc """
  Gets cluster-wide checkpoint system status and metrics.
  """
  def get_cluster_status do
    GenServer.call(__MODULE__, :get_cluster_status)
  end

  @doc """
  Sets retention policies for automatic checkpoint cleanup.
  """
  def set_retention_policy(policy) do
    GenServer.call(__MODULE__, {:set_retention_policy, policy})
  end

  @doc """
  Manually triggers cleanup of expired checkpoints.
  """
  def cleanup_expired_checkpoints(options \\ %{}) do
    GenServer.call(__MODULE__, {:cleanup_expired, options}, 60_000)
  end

  @doc """
  Replicates a checkpoint to specific nodes.
  """
  def replicate_checkpoint(checkpoint_id, target_nodes) do
    GenServer.call(__MODULE__, {:replicate_checkpoint, checkpoint_id, target_nodes}, 120_000)
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
      active_operations: %{},
      checkpoint_cache: %{},
      retention_policies: default_retention_policies(),
      replication_status: %{},
      metrics: init_metrics()
    }

    # Join pg groups for coordination
    :pg.join(@pg_scope, :checkpoint_managers, self())

    # Schedule periodic tasks
    schedule_retention_cleanup()
    schedule_metrics_update()

    Logger.info("Distributed checkpoint system started on #{node()}")
    {:ok, state}
  end

  @impl true
  def handle_call({:create_checkpoint, options}, from, state) do
    operation_id = generate_operation_id()

    # Start distributed checkpoint creation
    start_checkpoint_creation(operation_id, options, from)

    # Track operation
    new_state = track_operation(state, operation_id, %{
      type: :create_checkpoint,
      options: options,
      caller: from,
      started_at: DateTime.utc_now()
    })

    {:noreply, new_state}
  end

  def handle_call({:list_checkpoints, options}, _from, state) do
    case list_distributed_checkpoints(options) do
      {:ok, checkpoints} ->
        {:reply, {:ok, checkpoints}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_checkpoint_info, checkpoint_id}, _from, state) do
    case get_distributed_checkpoint_info(checkpoint_id) do
      {:ok, info} ->
        {:reply, {:ok, info}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:restore_checkpoint, checkpoint_id, options}, from, state) do
    operation_id = generate_operation_id()

    # Start distributed restore operation
    start_checkpoint_restore(operation_id, checkpoint_id, options, from)

    # Track operation
    new_state = track_operation(state, operation_id, %{
      type: :restore_checkpoint,
      checkpoint_id: checkpoint_id,
      options: options,
      caller: from,
      started_at: DateTime.utc_now()
    })

    {:noreply, new_state}
  end

  def handle_call({:compare_checkpoints, checkpoint_id_1, checkpoint_id_2, options}, _from, state) do
    case perform_checkpoint_comparison(checkpoint_id_1, checkpoint_id_2, options) do
      {:ok, diff} ->
        {:reply, {:ok, diff}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:delete_checkpoint, checkpoint_id, options}, _from, state) do
    case delete_distributed_checkpoint(checkpoint_id, options) do
      {:ok, result} ->
        # Update cache
        new_state = %{state |
          checkpoint_cache: Map.delete(state.checkpoint_cache, checkpoint_id)
        }
        {:reply, {:ok, result}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:tag_checkpoint, checkpoint_id, tags}, _from, state) do
    case add_checkpoint_tags(checkpoint_id, tags) do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_cluster_status, _from, state) do
    status = compile_cluster_status(state)
    {:reply, status, state}
  end

  def handle_call({:set_retention_policy, policy}, _from, state) do
    case validate_retention_policy(policy) do
      :ok ->
        new_state = %{state | retention_policies: Map.merge(state.retention_policies, policy)}
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:cleanup_expired, options}, _from, state) do
    case perform_cleanup(state.retention_policies, options) do
      {:ok, cleanup_result} ->
        {:reply, {:ok, cleanup_result}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:replicate_checkpoint, checkpoint_id, target_nodes}, _from, state) do
    case perform_checkpoint_replication(checkpoint_id, target_nodes) do
      {:ok, replication_result} ->
        # Update replication status
        new_replication_status = Map.put(state.replication_status, checkpoint_id, replication_result)
        new_state = %{state | replication_status: new_replication_status}
        {:reply, {:ok, replication_result}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:operation_complete, operation_id, result}, state) do
    case Map.get(state.active_operations, operation_id) do
      %{caller: from} = _operation ->
        # Reply to original caller
        GenServer.reply(from, result)

        # Clean up operation tracking
        new_state = %{state |
          active_operations: Map.delete(state.active_operations, operation_id)
        }

        # Update metrics
        updated_state = update_operation_metrics(new_state, result)

        {:noreply, updated_state}

      nil ->
        {:noreply, state}
    end
  end

  def handle_cast({:update_checkpoint_cache, checkpoint_id, checkpoint_info}, state) do
    new_cache = Map.put(state.checkpoint_cache, checkpoint_id, checkpoint_info)
    new_state = %{state | checkpoint_cache: new_cache}
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:event_notification, event}, state) do
    # Handle checkpoint-related events
    new_state = handle_checkpoint_event(event, state)
    {:noreply, new_state}
  end

  def handle_info(:retention_cleanup, state) do
    # Perform periodic cleanup
    spawn(fn ->
      perform_cleanup(state.retention_policies, %{})
    end)

    schedule_retention_cleanup()
    {:noreply, state}
  end

  def handle_info(:metrics_update, state) do
    # Update metrics
    new_state = refresh_checkpoint_metrics(state)
    schedule_metrics_update()
    {:noreply, new_state}
  end

  def handle_info({:operation_progress, operation_id, progress}, state) do
    # Update operation progress
    case Map.get(state.active_operations, operation_id) do
      operation when not is_nil(operation) ->
        updated_operation = Map.put(operation, :progress, progress)
        new_state = %{state |
          active_operations: Map.put(state.active_operations, operation_id, updated_operation)
        }
        {:noreply, new_state}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private Functions

  defp setup_infrastructure do
    # Setup pg scope
    :pg.start_link(@pg_scope)

    # Setup Mnesia tables
    setup_mnesia_tables()
  end

  defp setup_mnesia_tables do
    table_type = if node() == :nonode@nohost, do: :ram_copies, else: :disc_copies

    # Main checkpoints table
    :mnesia.create_table(@checkpoint_table, [
      {table_type, [node()]},
      {:attributes, [:checkpoint_id, :name, :description, :created_at, :created_by, :node, :status, :data_types, :metadata]},
      {:type, :ordered_set},
      {:index, [:created_at, :node, :status]}
    ])

    # Checkpoint data storage
    :mnesia.create_table(@checkpoint_data_table, [
      {table_type, [node()]},
      {:attributes, [:key, :checkpoint_id, :data_type, :data, :compression, :checksum]},
      {:type, :bag},
      {:index, [:checkpoint_id, :data_type]}
    ])

    # Checkpoint diffs for incremental updates
    :mnesia.create_table(@checkpoint_diffs_table, [
      {table_type, [node()]},
      {:attributes, [:diff_id, :from_checkpoint, :to_checkpoint, :diff_data, :created_at]},
      {:type, :ordered_set},
      {:index, [:from_checkpoint, :to_checkpoint]}
    ])

    # Checkpoint metadata and properties
    :mnesia.create_table(@checkpoint_metadata_table, [
      {table_type, [node()]},
      {:attributes, [:checkpoint_id, :property, :value, :updated_at]},
      {:type, :bag},
      {:index, [:property]}
    ])

    # Checkpoint tags for organization
    :mnesia.create_table(@checkpoint_tags_table, [
      {table_type, [node()]},
      {:attributes, [:checkpoint_id, :tag, :added_at]},
      {:type, :bag},
      {:index, [:tag]}
    ])
  end

  defp subscribe_to_events do
    # Subscribe to checkpoint-related events
    OTPEventBus.subscribe({:event_type, :checkpoint_created})
    OTPEventBus.subscribe({:event_type, :checkpoint_restored})
    OTPEventBus.subscribe({:event_type, :checkpoint_deleted})
    OTPEventBus.subscribe({:event_type, :state_changed})
  end

  defp start_checkpoint_creation(operation_id, options, _caller) do
    # Start distributed checkpoint creation
    Task.start(fn ->
      result = perform_distributed_checkpoint_creation(options)
      GenServer.cast(self(), {:operation_complete, operation_id, result})
    end)
  end

  defp perform_distributed_checkpoint_creation(options) do
    checkpoint_id = generate_checkpoint_id()

    try do
      # Get cluster nodes for checkpoint creation
      checkpoint_nodes = get_checkpoint_nodes(options)

      # Collect data from all nodes
      collected_data = collect_checkpoint_data(checkpoint_nodes, options)

      # Create checkpoint record
      checkpoint_record = %{
        checkpoint_id: checkpoint_id,
        name: options[:name] || "checkpoint_#{System.os_time(:second)}",
        description: options[:description] || "Automated checkpoint",
        created_at: DateTime.utc_now(),
        created_by: node(),
        node: node(),
        status: :creating,
        data_types: options[:include_data] || [:all],
        metadata: %{
          total_size: calculate_data_size(collected_data),
          node_count: length(checkpoint_nodes),
          compression: options[:compression] || :medium
        }
      }

      # Store checkpoint record
      store_checkpoint_record(checkpoint_record)

      # Store collected data
      store_checkpoint_data(checkpoint_id, collected_data, options)

      # Add tags if specified
      if options[:tag] do
        add_checkpoint_tags(checkpoint_id, [options[:tag]])
      end

      # Mark as completed
      update_checkpoint_status(checkpoint_id, :completed)

      # Publish event
      publish_checkpoint_event(:checkpoint_created, checkpoint_id, checkpoint_record)

      # Replicate to other nodes if requested
      if options[:replicate_to] do
        perform_checkpoint_replication(checkpoint_id, options[:replicate_to])
      end

      {:ok, %{
        checkpoint_id: checkpoint_id,
        name: checkpoint_record.name,
        created_at: checkpoint_record.created_at,
        data_size: checkpoint_record.metadata.total_size,
        nodes_included: length(checkpoint_nodes)
      }}

    catch
      kind, reason ->
        # Mark as failed if we created a record
        update_checkpoint_status(checkpoint_id, :failed)
        {:error, {kind, reason}}
    end
  end

  defp get_checkpoint_nodes(options) do
    case options[:target_nodes] do
      nil ->
        # Get all checkpoint managers in the cluster
        :pg.get_members(@pg_scope, :checkpoint_managers)
        |> Enum.map(&node/1)
        |> Enum.uniq()

      nodes when is_list(nodes) ->
        nodes
    end
  end

  defp collect_checkpoint_data(nodes, options) do
    data_types = options[:include_data] || [:context, :sessions, :events]

    # Collect data from each node
    node_data = Enum.map(nodes, fn target_node ->
      if target_node == node() do
        # Collect local data
        collect_local_checkpoint_data(data_types)
      else
        # Collect remote data
        :rpc.call(target_node, __MODULE__, :collect_local_checkpoint_data, [data_types], 60_000)
      end
    end)

    # Combine data from all nodes
    combine_node_data(node_data, nodes)
  end

  def collect_local_checkpoint_data(data_types) do
    # Collect data based on requested types
    Enum.reduce(data_types, %{}, fn data_type, acc ->
      case data_type do
        :context ->
          case collect_context_data() do
            {:ok, context_data} -> Map.put(acc, :context, context_data)
            {:error, _} -> acc
          end

        :sessions ->
          case collect_session_data() do
            {:ok, session_data} -> Map.put(acc, :sessions, session_data)
            {:error, _} -> acc
          end

        :events ->
          case collect_event_data() do
            {:ok, event_data} -> Map.put(acc, :events, event_data)
            {:error, _} -> acc
          end

        :all ->
          # Recursively collect all data types
          all_data = collect_local_checkpoint_data([:context, :sessions, :events])
          Map.merge(acc, all_data)

        _ ->
          acc
      end
    end)
    |> Map.put(:node, node())
    |> Map.put(:collected_at, DateTime.utc_now())
  end

  defp collect_context_data do
    # Collect distributed context data
    case DistributedEngine.get_all_contexts() do
      {:ok, contexts} ->
        context_data = %{
          contexts: contexts,
          count: length(contexts),
          total_size: calculate_contexts_size(contexts)
        }
        {:ok, context_data}

      error ->
        error
    end
  end

  defp collect_session_data do
    # Collect distributed session data
    case DistributedSessionManager.list_all_sessions() do
      {:ok, sessions} ->
        session_data = %{
          sessions: sessions,
          count: length(sessions),
          active_count: count_active_sessions(sessions)
        }
        {:ok, session_data}

      error ->
        error
    end
  end

  defp collect_event_data do
    # Collect recent event data (last 1000 events)
    case OTPEventBus.get_events(%{limit: 1000, order: :desc}) do
      {:ok, events} ->
        event_data = %{
          events: events,
          count: length(events),
          latest_timestamp: get_latest_event_timestamp(events)
        }
        {:ok, event_data}

      error ->
        error
    end
  end

  defp combine_node_data(node_data, nodes) do
    # Combine data from all nodes into a unified structure
    valid_data = Enum.zip(nodes, node_data)
    |> Enum.filter(fn {_node, data} ->
      case data do
        {:ok, _} -> true
        _ -> false
      end
    end)
    |> Enum.map(fn {node, {:ok, data}} -> {node, data} end)

    combined = %{
      nodes: Enum.into(valid_data, %{}),
      summary: %{
        total_nodes: length(valid_data),
        collection_timestamp: DateTime.utc_now()
      }
    }

    # Add aggregate statistics
    add_aggregate_statistics(combined)
  end

  defp add_aggregate_statistics(combined_data) do
    node_data = Map.values(combined_data.nodes)

    # Calculate aggregates
    total_contexts = Enum.sum(Enum.map(node_data, fn data ->
      get_in(data, [:context, :count]) || 0
    end))

    total_sessions = Enum.sum(Enum.map(node_data, fn data ->
      get_in(data, [:sessions, :count]) || 0
    end))

    total_events = Enum.sum(Enum.map(node_data, fn data ->
      get_in(data, [:events, :count]) || 0
    end))

    summary = Map.merge(combined_data.summary, %{
      total_contexts: total_contexts,
      total_sessions: total_sessions,
      total_events: total_events
    })

    %{combined_data | summary: summary}
  end

  defp store_checkpoint_record(checkpoint_record) do
    :mnesia.transaction(fn ->
      :mnesia.write({@checkpoint_table,
        checkpoint_record.checkpoint_id,
        checkpoint_record.name,
        checkpoint_record.description,
        checkpoint_record.created_at,
        checkpoint_record.created_by,
        checkpoint_record.node,
        checkpoint_record.status,
        checkpoint_record.data_types,
        checkpoint_record.metadata
      })
    end)
  end

  defp store_checkpoint_data(checkpoint_id, collected_data, options) do
    compression = options[:compression] || :medium

    # Store each data type separately
    Enum.each(collected_data.nodes, fn {node_name, node_data} ->
      Enum.each(node_data, fn {data_type, data} ->
        if data_type not in [:node, :collected_at] do
          # Compress and store data
          compressed_data = compress_data(data, compression)
          checksum = calculate_checksum(compressed_data)

          key = {checkpoint_id, node_name, data_type}

          :mnesia.transaction(fn ->
            :mnesia.write({@checkpoint_data_table,
              key,
              checkpoint_id,
              data_type,
              compressed_data,
              compression,
              checksum
            })
          end)
        end
      end)
    end)

    # Store summary data
    summary_key = {checkpoint_id, :cluster, :summary}
    compressed_summary = compress_data(collected_data.summary, compression)
    summary_checksum = calculate_checksum(compressed_summary)

    :mnesia.transaction(fn ->
      :mnesia.write({@checkpoint_data_table,
        summary_key,
        checkpoint_id,
        :summary,
        compressed_summary,
        compression,
        summary_checksum
      })
    end)
  end

  defp start_checkpoint_restore(operation_id, checkpoint_id, options, _caller) do
    # Start distributed checkpoint restore
    Task.start(fn ->
      result = perform_distributed_checkpoint_restore(checkpoint_id, options)
      GenServer.cast(self(), {:operation_complete, operation_id, result})
    end)
  end

  defp perform_distributed_checkpoint_restore(checkpoint_id, options) do
    try do
      # Validate checkpoint exists
      case get_checkpoint_record(checkpoint_id) do
        {:ok, checkpoint_record} ->
          if options[:dry_run] == true do
            # Perform dry run
            perform_restore_dry_run(checkpoint_id, checkpoint_record, options)
          else
            # Perform actual restore
            perform_actual_restore(checkpoint_id, checkpoint_record, options)
          end

        {:error, reason} ->
          {:error, {:checkpoint_not_found, reason}}
      end

    catch
      kind, reason ->
        {:error, {kind, reason}}
    end
  end

  defp perform_restore_dry_run(checkpoint_id, checkpoint_record, options) do
    # Load checkpoint data for analysis
    case load_checkpoint_data(checkpoint_id) do
      {:ok, checkpoint_data} ->
        # Analyze what would be restored
        restore_plan = create_restore_plan(checkpoint_data, options)

        {:ok, %{
          dry_run: true,
          checkpoint_id: checkpoint_id,
          checkpoint_name: checkpoint_record.name,
          restore_plan: restore_plan,
          estimated_duration: estimate_restore_duration(restore_plan),
          affected_nodes: get_affected_nodes(restore_plan)
        }}

      {:error, reason} ->
        {:error, {:data_load_failed, reason}}
    end
  end

  defp perform_actual_restore(checkpoint_id, checkpoint_record, options) do
    unless options[:confirm] == true do
      {:error, :confirmation_required}
    else
      # Create backup of current state if requested
      backup_id = if options[:backup_current] != false do
        case create_pre_restore_backup() do
          {:ok, %{checkpoint_id: backup_id}} -> backup_id
          _ -> nil
        end
      end

      # Load checkpoint data
      case load_checkpoint_data(checkpoint_id) do
        {:ok, checkpoint_data} ->
          # Perform restore across cluster
          restore_result = execute_cluster_restore(checkpoint_data, options)

          # Publish event
          publish_checkpoint_event(:checkpoint_restored, checkpoint_id, %{
            backup_id: backup_id,
            restore_result: restore_result
          })

          {:ok, %{
            checkpoint_id: checkpoint_id,
            checkpoint_name: checkpoint_record.name,
            backup_id: backup_id,
            restore_result: restore_result,
            restored_at: DateTime.utc_now()
          }}

        {:error, reason} ->
          {:error, {:data_load_failed, reason}}
      end
    end
  end

  defp create_pre_restore_backup do
    # Create automatic backup before restore
    backup_options = %{
      name: "pre_restore_backup_#{System.os_time(:second)}",
      description: "Automatic backup created before checkpoint restore",
      include_data: [:all],
      tag: "auto_backup"
    }

    perform_distributed_checkpoint_creation(backup_options)
  end

  defp load_checkpoint_data(checkpoint_id) do
    case :mnesia.transaction(fn ->
      :mnesia.match_object(@checkpoint_data_table, {:_, checkpoint_id, :_, :_, :_, :_}, :read)
    end) do
      {:atomic, records} ->
        # Decompress and organize data
        data = Enum.reduce(records, %{}, fn {key, _checkpoint_id, data_type, compressed_data, compression, _checksum}, acc ->
          decompressed_data = decompress_data(compressed_data, compression)

          case key do
            {^checkpoint_id, node_name, ^data_type} ->
              node_data = Map.get(acc, node_name, %{})
              updated_node_data = Map.put(node_data, data_type, decompressed_data)
              Map.put(acc, node_name, updated_node_data)

            _ ->
              acc
          end
        end)

        {:ok, data}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  defp create_restore_plan(checkpoint_data, options) do
    restore_data_types = options[:restore_data] || Map.keys(checkpoint_data[:cluster][:summary])
    target_nodes = options[:target_nodes] || Map.keys(checkpoint_data) -- [:cluster]

    %{
      data_types: restore_data_types,
      target_nodes: target_nodes,
      operations: estimate_restore_operations(checkpoint_data, restore_data_types, target_nodes)
    }
  end

  defp estimate_restore_operations(checkpoint_data, data_types, target_nodes) do
    Enum.flat_map(target_nodes, fn node ->
      node_data = Map.get(checkpoint_data, node, %{})

      Enum.map(data_types, fn data_type ->
        case Map.get(node_data, data_type) do
          nil ->
            {:skip, node, data_type, "No data available"}

          data ->
            operation_complexity = estimate_operation_complexity(data_type, data)
            {:restore, node, data_type, operation_complexity}
        end
      end)
    end)
  end

  defp estimate_operation_complexity(data_type, data) do
    base_complexity = case data_type do
      :context -> 2
      :sessions -> 3
      :events -> 4
      _ -> 1
    end

    # Adjust based on data size
    data_size = calculate_data_size(data)
    size_multiplier = cond do
      data_size > 10_000_000 -> 3  # > 10MB
      data_size > 1_000_000 -> 2   # > 1MB
      true -> 1
    end

    base_complexity * size_multiplier
  end

  defp estimate_restore_duration(restore_plan) do
    # Estimate based on operations complexity
    total_complexity = Enum.sum(Enum.map(restore_plan.operations, fn
      {:restore, _node, _type, complexity} -> complexity
      _ -> 0
    end))

    # Base time per complexity unit (in seconds)
    base_time_per_unit = 5
    estimated_seconds = total_complexity * base_time_per_unit

    %{
      estimated_seconds: estimated_seconds,
      estimated_minutes: div(estimated_seconds, 60),
      complexity_score: total_complexity
    }
  end

  defp get_affected_nodes(restore_plan) do
    Enum.map(restore_plan.operations, fn
      {:restore, node, _type, _complexity} -> node
      {:skip, node, _type, _reason} -> node
    end)
    |> Enum.uniq()
  end

  defp execute_cluster_restore(checkpoint_data, options) do
    # Execute restore operations across the cluster
    target_nodes = options[:target_nodes] || Map.keys(checkpoint_data) -- [:cluster]
    restore_data_types = options[:restore_data] || [:context, :sessions, :events]

    # Execute on each node
    node_results = Enum.map(target_nodes, fn target_node ->
      node_data = Map.get(checkpoint_data, target_node, %{})

      if target_node == node() do
        # Restore locally
        restore_local_data(node_data, restore_data_types)
      else
        # Restore on remote node
        :rpc.call(target_node, __MODULE__, :restore_local_data, [node_data, restore_data_types], 120_000)
      end
    end)

    # Analyze results
    {successful, failed} = Enum.split_with(node_results, fn
      {:ok, _} -> true
      _ -> false
    end)

    %{
      total_nodes: length(target_nodes),
      successful_nodes: length(successful),
      failed_nodes: length(failed),
      node_results: Enum.zip(target_nodes, node_results)
    }
  end

  def restore_local_data(node_data, restore_data_types) do
    # Restore data on local node
    results = Enum.map(restore_data_types, fn data_type ->
      case Map.get(node_data, data_type) do
        nil ->
          {:skipped, data_type, :no_data}

        data ->
          case restore_data_type(data_type, data) do
            :ok -> {:restored, data_type, :success}
            {:error, reason} -> {:failed, data_type, reason}
          end
      end
    end)

    {:ok, %{
      node: node(),
      restore_results: results,
      restored_at: DateTime.utc_now()
    }}
  end

  defp restore_data_type(:context, context_data) do
    # Restore context data
    case DistributedEngine.restore_contexts(context_data.contexts) do
      :ok -> :ok
      error -> error
    end
  end

  defp restore_data_type(:sessions, session_data) do
    # Restore session data
    case DistributedSessionManager.restore_sessions(session_data.sessions) do
      :ok -> :ok
      error -> error
    end
  end

  defp restore_data_type(:events, event_data) do
    # Restore event data (replay events)
    case OTPEventBus.replay_events(event_data.events) do
      :ok -> :ok
      error -> error
    end
  end

  defp restore_data_type(_data_type, _data) do
    # Unknown data type
    {:error, :unsupported_data_type}
  end

  defp perform_checkpoint_comparison(checkpoint_id_1, checkpoint_id_2, options) do
    # Load both checkpoints
    with {:ok, data_1} <- load_checkpoint_data(checkpoint_id_1),
         {:ok, data_2} <- load_checkpoint_data(checkpoint_id_2) do

      # Compare checkpoints
      comparison = compare_checkpoint_data(data_1, data_2, options)

      {:ok, %{
        checkpoint_1: checkpoint_id_1,
        checkpoint_2: checkpoint_id_2,
        comparison: comparison,
        compared_at: DateTime.utc_now()
      }}
    else
      error -> error
    end
  end

  defp compare_checkpoint_data(data_1, data_2, _options) do
    # Get common nodes
    nodes_1 = Map.keys(data_1) -- [:cluster]
    nodes_2 = Map.keys(data_2) -- [:cluster]
    common_nodes = nodes_1 -- (nodes_1 -- nodes_2)
    only_in_1 = nodes_1 -- nodes_2
    only_in_2 = nodes_2 -- nodes_1

    # Compare each common node
    node_comparisons = Enum.map(common_nodes, fn node ->
      node_data_1 = Map.get(data_1, node, %{})
      node_data_2 = Map.get(data_2, node, %{})

      {node, compare_node_data(node_data_1, node_data_2)}
    end)
    |> Enum.into(%{})

    %{
      nodes: %{
        common: common_nodes,
        only_in_checkpoint_1: only_in_1,
        only_in_checkpoint_2: only_in_2,
        comparisons: node_comparisons
      },
      summary: create_comparison_summary(node_comparisons)
    }
  end

  defp compare_node_data(data_1, data_2) do
    # Get common data types
    types_1 = Map.keys(data_1)
    types_2 = Map.keys(data_2)
    common_types = types_1 -- (types_1 -- types_2)

    type_comparisons = Enum.map(common_types, fn data_type ->
      {data_type, compare_data_by_type(data_type, Map.get(data_1, data_type), Map.get(data_2, data_type))}
    end)
    |> Enum.into(%{})

    %{
      data_types: common_types,
      only_in_1: types_1 -- types_2,
      only_in_2: types_2 -- types_1,
      comparisons: type_comparisons
    }
  end

  defp compare_data_by_type(:context, context_1, context_2) do
    %{
      count_diff: context_1.count - context_2.count,
      size_diff: context_1.total_size - context_2.total_size,
      details: "Context count changed by #{context_1.count - context_2.count}"
    }
  end

  defp compare_data_by_type(:sessions, sessions_1, sessions_2) do
    %{
      count_diff: sessions_1.count - sessions_2.count,
      active_diff: sessions_1.active_count - sessions_2.active_count,
      details: "Session count changed by #{sessions_1.count - sessions_2.count}"
    }
  end

  defp compare_data_by_type(:events, events_1, events_2) do
    %{
      count_diff: events_1.count - events_2.count,
      latest_timestamp_1: events_1.latest_timestamp,
      latest_timestamp_2: events_2.latest_timestamp,
      details: "Event count changed by #{events_1.count - events_2.count}"
    }
  end

  defp compare_data_by_type(_data_type, data_1, data_2) do
    %{
      size_1: calculate_data_size(data_1),
      size_2: calculate_data_size(data_2),
      details: "Generic data comparison"
    }
  end

  defp create_comparison_summary(node_comparisons) do
    # Create high-level summary of differences
    total_changes = Enum.reduce(node_comparisons, 0, fn {_node, comparison}, acc ->
      data_changes = Enum.count(comparison.comparisons, fn {_type, comp} ->
        Map.get(comp, :count_diff, 0) != 0
      end)
      acc + data_changes
    end)

    %{
      total_nodes_compared: map_size(node_comparisons),
      total_data_changes: total_changes,
      has_differences: total_changes > 0
    }
  end

  defp list_distributed_checkpoints(options) do
    case :mnesia.transaction(fn ->
      # Build match pattern based on options
      pattern = build_checkpoint_match_pattern(options)
      :mnesia.select(@checkpoint_table, pattern)
    end) do
      {:atomic, records} ->
        # Convert records to maps and apply additional filtering
        checkpoints = Enum.map(records, &checkpoint_record_to_map/1)
        |> apply_checkpoint_filters(options)
        |> apply_checkpoint_ordering(options)
        |> apply_checkpoint_limit(options)

        {:ok, checkpoints}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  defp build_checkpoint_match_pattern(options) do
    # Build Mnesia match specification
    base_pattern = {:_, :_, :_, :_, :_, :_, :_, :_, :_}

    conditions = []

    # Add time range filters
    conditions = case options[:created_after] do
      nil -> conditions
      datetime ->
        [{:>=, {:element, 5, :"$_"}, datetime} | conditions]
    end

    conditions = case options[:created_before] do
      nil -> conditions
      datetime ->
        [{:<=, {:element, 5, :"$_"}, datetime} | conditions]
    end

    final_condition = case conditions do
      [] -> []
      [single] -> [single]
      multiple -> [List.to_tuple([:andalso | multiple])]
    end

    [{base_pattern, final_condition, [:"$_"]}]
  end

  defp checkpoint_record_to_map({_table, checkpoint_id, name, description, created_at, created_by, node, status, data_types, metadata}) do
    %{
      checkpoint_id: checkpoint_id,
      name: name,
      description: description,
      created_at: created_at,
      created_by: created_by,
      node: node,
      status: status,
      data_types: data_types,
      metadata: metadata
    }
  end

  defp apply_checkpoint_filters(checkpoints, options) do
    checkpoints
    |> filter_by_tags(options[:tags])
    |> filter_by_data_types(options[:include_data_types])
  end

  defp filter_by_tags(checkpoints, nil), do: checkpoints
  defp filter_by_tags(checkpoints, tags) when is_list(tags) do
    Enum.filter(checkpoints, fn checkpoint ->
      checkpoint_tags = get_checkpoint_tags(checkpoint.checkpoint_id)
      Enum.any?(tags, fn tag -> tag in checkpoint_tags end)
    end)
  end

  defp filter_by_data_types(checkpoints, nil), do: checkpoints
  defp filter_by_data_types(checkpoints, data_types) when is_list(data_types) do
    Enum.filter(checkpoints, fn checkpoint ->
      Enum.any?(data_types, fn data_type -> data_type in checkpoint.data_types end)
    end)
  end

  defp apply_checkpoint_ordering(checkpoints, options) do
    case options[:order] do
      :asc -> Enum.sort_by(checkpoints, & &1.created_at, {:asc, DateTime})
      _ -> Enum.sort_by(checkpoints, & &1.created_at, {:desc, DateTime})
    end
  end

  defp apply_checkpoint_limit(checkpoints, options) do
    case options[:limit] do
      nil -> checkpoints
      limit when is_integer(limit) -> Enum.take(checkpoints, limit)
    end
  end

  defp get_distributed_checkpoint_info(checkpoint_id) do
    case get_checkpoint_record(checkpoint_id) do
      {:ok, checkpoint_record} ->
        # Get additional info
        tags = get_checkpoint_tags(checkpoint_id)
        data_summary = get_checkpoint_data_summary(checkpoint_id)

        info = Map.merge(checkpoint_record, %{
          tags: tags,
          data_summary: data_summary
        })

        {:ok, info}

      error ->
        error
    end
  end

  defp get_checkpoint_record(checkpoint_id) do
    case :mnesia.transaction(fn ->
      :mnesia.read(@checkpoint_table, checkpoint_id)
    end) do
      {:atomic, [record]} ->
        {:ok, checkpoint_record_to_map(record)}

      {:atomic, []} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  defp get_checkpoint_tags(checkpoint_id) do
    case :mnesia.transaction(fn ->
      :mnesia.match_object(@checkpoint_tags_table, {checkpoint_id, :_, :_}, :read)
    end) do
      {:atomic, records} ->
        Enum.map(records, fn {_, tag, _} -> tag end)

      _ ->
        []
    end
  end

  defp get_checkpoint_data_summary(checkpoint_id) do
    case :mnesia.transaction(fn ->
      :mnesia.match_object(@checkpoint_data_table, {:_, checkpoint_id, :_, :_, :_, :_}, :read)
    end) do
      {:atomic, records} ->
        # Summarize data by type
        data_types = Enum.group_by(records, fn {_, _, data_type, _, _, _} -> data_type end)

        summary = Enum.map(data_types, fn {data_type, type_records} ->
          total_size = Enum.sum(Enum.map(type_records, fn {_, _, _, data, _, _} ->
            calculate_data_size(data)
          end))

          {data_type, %{
            count: length(type_records),
            total_size: total_size
          }}
        end)
        |> Enum.into(%{})

        summary

      _ ->
        %{}
    end
  end

  defp delete_distributed_checkpoint(checkpoint_id, options) do
    force = options[:force] == true

    # Check if checkpoint exists
    case get_checkpoint_record(checkpoint_id) do
      {:ok, _checkpoint_record} ->
        # Delete from all tables
        delete_result = :mnesia.transaction(fn ->
          # Delete main record
          :mnesia.delete({@checkpoint_table, checkpoint_id})

          # Delete data records
          data_records = :mnesia.match_object(@checkpoint_data_table, {:_, checkpoint_id, :_, :_, :_, :_}, :write)
          Enum.each(data_records, fn record ->
            :mnesia.delete_object(record)
          end)

          # Delete metadata
          metadata_records = :mnesia.match_object(@checkpoint_metadata_table, {checkpoint_id, :_, :_, :_}, :write)
          Enum.each(metadata_records, fn record ->
            :mnesia.delete_object(record)
          end)

          # Delete tags
          tag_records = :mnesia.match_object(@checkpoint_tags_table, {checkpoint_id, :_, :_}, :write)
          Enum.each(tag_records, fn record ->
            :mnesia.delete_object(record)
          end)

          :ok
        end)

        case delete_result do
          {:atomic, :ok} ->
            # Publish event
            publish_checkpoint_event(:checkpoint_deleted, checkpoint_id, %{force: force})

            {:ok, %{
              checkpoint_id: checkpoint_id,
              deleted_at: DateTime.utc_now()
            }}

          {:aborted, reason} ->
            {:error, reason}
        end

      {:error, :not_found} ->
        if force do
          {:ok, %{checkpoint_id: checkpoint_id, was_missing: true}}
        else
          {:error, :not_found}
        end

      error ->
        error
    end
  end

  defp add_checkpoint_tags(checkpoint_id, tags) when is_list(tags) do
    # Add tags to checkpoint
    :mnesia.transaction(fn ->
      Enum.each(tags, fn tag ->
        :mnesia.write({@checkpoint_tags_table, checkpoint_id, tag, DateTime.utc_now()})
      end)
    end)

    :ok
  end

  defp perform_checkpoint_replication(checkpoint_id, target_nodes) do
    # Replicate checkpoint to specific nodes
    case load_checkpoint_data(checkpoint_id) do
      {:ok, checkpoint_data} ->
        # Get checkpoint record
        {:ok, checkpoint_record} = get_checkpoint_record(checkpoint_id)

        # Replicate to each target node
        replication_results = Enum.map(target_nodes, fn target_node ->
          if target_node == node() do
            {:ok, :already_local}
          else
            :rpc.call(target_node, __MODULE__, :receive_replicated_checkpoint,
                     [checkpoint_id, checkpoint_record, checkpoint_data], 60_000)
          end
        end)

        # Analyze results
        {successful, failed} = Enum.split_with(replication_results, fn
          {:ok, _} -> true
          _ -> false
        end)

        {:ok, %{
          checkpoint_id: checkpoint_id,
          target_nodes: target_nodes,
          successful_replications: length(successful),
          failed_replications: length(failed),
          results: Enum.zip(target_nodes, replication_results)
        }}

      error ->
        error
    end
  end

  def receive_replicated_checkpoint(checkpoint_id, checkpoint_record, checkpoint_data) do
    # Receive and store replicated checkpoint
    try do
      # Store checkpoint record
      store_checkpoint_record(checkpoint_record)

      # Store checkpoint data
      store_replicated_data(checkpoint_id, checkpoint_data)

      {:ok, :replicated}
    catch
      kind, reason ->
        {:error, {kind, reason}}
    end
  end

  defp store_replicated_data(checkpoint_id, checkpoint_data) do
    # Store replicated checkpoint data
    Enum.each(checkpoint_data, fn {node_name, node_data} ->
      Enum.each(node_data, fn {data_type, data} ->
        if data_type not in [:node, :collected_at] do
          # Store without additional compression since it's already processed
          key = {checkpoint_id, node_name, data_type}
          checksum = calculate_checksum(data)

          :mnesia.transaction(fn ->
            :mnesia.write({@checkpoint_data_table,
              key,
              checkpoint_id,
              data_type,
              data,
              :none,  # No additional compression
              checksum
            })
          end)
        end
      end)
    end)
  end

  defp perform_cleanup(retention_policies, options) do
    # Clean up expired checkpoints based on retention policies
    force = options[:force] == true
    dry_run = options[:dry_run] == true

    # Get all checkpoints
    case list_distributed_checkpoints(%{}) do
      {:ok, checkpoints} ->
        # Apply retention policies
        expired_checkpoints = identify_expired_checkpoints(checkpoints, retention_policies)

        if dry_run do
          {:ok, %{
            dry_run: true,
            expired_checkpoints: expired_checkpoints,
            total_expired: length(expired_checkpoints)
          }}
        else
          # Delete expired checkpoints
          deletion_results = Enum.map(expired_checkpoints, fn checkpoint ->
            delete_distributed_checkpoint(checkpoint.checkpoint_id, %{force: force})
          end)

          {successful, failed} = Enum.split_with(deletion_results, fn
            {:ok, _} -> true
            _ -> false
          end)

          {:ok, %{
            expired_checkpoints: expired_checkpoints,
            total_expired: length(expired_checkpoints),
            successful_deletions: length(successful),
            failed_deletions: length(failed)
          }}
        end

      error ->
        error
    end
  end

  defp identify_expired_checkpoints(checkpoints, retention_policies) do
    now = DateTime.utc_now()

    Enum.filter(checkpoints, fn checkpoint ->
      is_expired?(checkpoint, retention_policies, now)
    end)
  end

  defp is_expired?(checkpoint, retention_policies, now) do
    # Check various retention policies

    # Default retention
    default_days = retention_policies[:default_retention_days] || 365
    default_cutoff = DateTime.add(now, -default_days * 24 * 60 * 60, :second)

    if DateTime.compare(checkpoint.created_at, default_cutoff) == :lt do
      true
    else
      # Check tag-specific retention
      checkpoint_tags = get_checkpoint_tags(checkpoint.checkpoint_id)

      Enum.any?(checkpoint_tags, fn tag ->
        case Map.get(retention_policies, :"#{tag}_retention_days") do
          nil -> false
          tag_days ->
            tag_cutoff = DateTime.add(now, -tag_days * 24 * 60 * 60, :second)
            DateTime.compare(checkpoint.created_at, tag_cutoff) == :lt
        end
      end)
    end
  end

  defp compile_cluster_status(state) do
    # Get cluster-wide checkpoint status
    checkpoint_managers = :pg.get_members(@pg_scope, :checkpoint_managers)
    cluster_nodes = Enum.map(checkpoint_managers, &node/1) |> Enum.uniq()

    # Get local statistics
    local_stats = get_local_checkpoint_stats()

    %{
      node: state.node,
      cluster_nodes: cluster_nodes,
      total_nodes: length(cluster_nodes),
      active_operations: map_size(state.active_operations),
      local_stats: local_stats,
      retention_policies: state.retention_policies,
      metrics: state.metrics,
      system_status: :healthy
    }
  end

  defp get_local_checkpoint_stats do
    checkpoint_count = case :mnesia.table_info(@checkpoint_table, :size) do
      size when is_integer(size) -> size
      _ -> 0
    end

    data_size = case :mnesia.table_info(@checkpoint_data_table, :size) do
      size when is_integer(size) -> size
      _ -> 0
    end

    %{
      total_checkpoints: checkpoint_count,
      total_data_records: data_size,
      oldest_checkpoint: get_oldest_checkpoint(),
      newest_checkpoint: get_newest_checkpoint()
    }
  end

  defp get_oldest_checkpoint do
    case :mnesia.transaction(fn ->
      :mnesia.select(@checkpoint_table, [{{:_, :_, :_, :_, :"$1", :_, :_, :_, :_, :_}, [], [:"$1"]}], 1, :read)
    end) do
      {:atomic, {[timestamp], _}} -> timestamp
      _ -> nil
    end
  end

  defp get_newest_checkpoint do
    case :mnesia.transaction(fn ->
      :mnesia.last(@checkpoint_table)
    end) do
      {:atomic, :"$end_of_table"} -> nil
      {:atomic, checkpoint_id} ->
        case get_checkpoint_record(checkpoint_id) do
          {:ok, record} -> record.created_at
          _ -> nil
        end
      _ -> nil
    end
  end

  defp validate_retention_policy(policy) do
    # Validate retention policy structure
    required_keys = [:default_retention_days]

    if Enum.all?(required_keys, &Map.has_key?(policy, &1)) do
      :ok
    else
      {:error, :invalid_retention_policy}
    end
  end

  # Utility functions

  defp default_retention_policies do
    %{
      default_retention_days: 365,     # 1 year default
      backup_retention_days: 90,       # 3 months for backups
      deployment_retention_days: 180,  # 6 months for deployments
      auto_backup_retention_days: 30   # 1 month for auto backups
    }
  end

  defp compress_data(data, compression_level) do
    binary_data = :erlang.term_to_binary(data)

    case compression_level do
      :none -> binary_data
      :low -> :zlib.compress(binary_data)
      :medium -> :zlib.compress(binary_data)
      :high -> :zlib.compress(binary_data)
      _ -> binary_data
    end
  end

  defp decompress_data(compressed_data, compression_level) do
    case compression_level do
      :none -> :erlang.binary_to_term(compressed_data)
      _ -> :erlang.binary_to_term(:zlib.uncompress(compressed_data))
    end
  end

  defp calculate_checksum(data) do
    :crypto.hash(:sha256, data) |> Base.encode16()
  end

  defp calculate_data_size(data) do
    :erlang.byte_size(:erlang.term_to_binary(data))
  end

  defp calculate_contexts_size(contexts) when is_list(contexts) do
    Enum.sum(Enum.map(contexts, &calculate_data_size/1))
  end
  defp calculate_contexts_size(_), do: 0

  defp count_active_sessions(sessions) when is_list(sessions) do
    Enum.count(sessions, fn session ->
      Map.get(session, :status) == :active
    end)
  end
  defp count_active_sessions(_), do: 0

  defp get_latest_event_timestamp(events) when is_list(events) and length(events) > 0 do
    latest_event = Enum.max_by(events, fn event ->
      Map.get(event, :timestamp, ~U[1970-01-01 00:00:00Z])
    end, DateTime)

    Map.get(latest_event, :timestamp)
  end
  defp get_latest_event_timestamp(_), do: nil

  defp update_checkpoint_status(checkpoint_id, new_status) do
    :mnesia.transaction(fn ->
      case :mnesia.read(@checkpoint_table, checkpoint_id) do
        [{table, checkpoint_id, name, description, created_at, created_by, node, _old_status, data_types, metadata}] ->
          :mnesia.write({table, checkpoint_id, name, description, created_at, created_by, node, new_status, data_types, metadata})

        [] ->
          {:error, :not_found}
      end
    end)
  end

  defp publish_checkpoint_event(event_type, checkpoint_id, event_data) do
    # Publish checkpoint event to event bus
    event = %{
      id: generate_operation_id(),
      aggregate_id: "checkpoint_system",
      type: event_type,
      data: Map.merge(event_data, %{
        checkpoint_id: checkpoint_id,
        node: node()
      }),
      metadata: %{
        node: node(),
        checkpoint_manager: self()
      }
    }

    OTPEventBus.publish_event(event)
  end

  defp track_operation(state, operation_id, operation_info) do
    %{state |
      active_operations: Map.put(state.active_operations, operation_id, operation_info)
    }
  end

  defp update_operation_metrics(state, result) do
    metrics = state.metrics

    updated_metrics = case result do
      {:ok, _} ->
        %{metrics |
          successful_operations: metrics.successful_operations + 1,
          total_operations: metrics.total_operations + 1
        }

      {:error, _} ->
        %{metrics |
          failed_operations: metrics.failed_operations + 1,
          total_operations: metrics.total_operations + 1
        }
    end

    %{state | metrics: updated_metrics}
  end

  defp refresh_checkpoint_metrics(state) do
    # Refresh metrics with current data
    state
  end

  defp handle_checkpoint_event(%{type: :state_changed} = event, state) do
    # Handle state change events that might affect checkpoints
    Logger.debug("State change event received: #{inspect(event)}")
    state
  end

  defp handle_checkpoint_event(_event, state), do: state

  defp init_metrics do
    %{
      total_operations: 0,
      successful_operations: 0,
      failed_operations: 0,
      checkpoints_created: 0,
      checkpoints_restored: 0,
      checkpoints_deleted: 0,
      data_compressed: 0,
      data_replicated: 0
    }
  end

  defp generate_operation_id do
    "op_#{:erlang.unique_integer([:positive])}_#{System.os_time(:millisecond)}"
  end

  defp generate_checkpoint_id do
    "checkpoint_#{:erlang.unique_integer([:positive])}_#{System.os_time(:millisecond)}"
  end

  defp schedule_retention_cleanup do
    # Schedule cleanup every 24 hours
    Process.send_after(self(), :retention_cleanup, 24 * 60 * 60 * 1000)
  end

  defp schedule_metrics_update do
    # Schedule metrics update every 5 minutes
    Process.send_after(self(), :metrics_update, 5 * 60 * 1000)
  end
end
