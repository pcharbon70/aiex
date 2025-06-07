defmodule Aiex.Config.DistributedConfig do
  @moduledoc """
  Distributed configuration management for the Aiex cluster.

  This module manages configuration synchronization across cluster nodes,
  provides runtime configuration updates, and ensures consistency of
  settings across the distributed system.
  """

  use GenServer
  require Logger

  alias Aiex.Events.EventBus

  @config_table :aiex_distributed_config
  @config_sync_interval 30_000

  defstruct [
    :node,
    :config_cache,
    :sync_timer,
    :pending_updates
  ]

  ## Client API

  @doc """
  Starts the distributed configuration manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get a configuration value with distributed fallback.
  """
  @spec get(atom(), atom(), term()) :: term()
  def get(app, key, default \\ nil) do
    case get_distributed_config(app, key) do
      {:ok, value} -> value
      :not_found -> Application.get_env(app, key, default)
    end
  end

  @doc """
  Set a configuration value across the cluster.
  """
  @spec put(atom(), atom(), term()) :: :ok | {:error, term()}
  def put(app, key, value) do
    GenServer.call(__MODULE__, {:put_config, app, key, value})
  end

  @doc """
  Get all configuration for an application.
  """
  @spec get_all(atom()) :: keyword()
  def get_all(app) do
    distributed_config = get_all_distributed_config(app)
    local_config = Application.get_all_env(app)

    # Merge with distributed config taking precedence
    Keyword.merge(local_config, distributed_config)
  end

  @doc """
  Synchronize configuration across the cluster.
  """
  @spec sync_cluster() :: :ok
  def sync_cluster do
    GenServer.cast(__MODULE__, :sync_cluster)
  end

  @doc """
  Get cluster-wide configuration status.
  """
  @spec cluster_status() :: map()
  def cluster_status do
    GenServer.call(__MODULE__, :cluster_status)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    # Create ETS table for configuration cache
    :ets.new(@config_table, [:set, :public, :named_table, {:read_concurrency, true}])

    # Subscribe to configuration events
    EventBus.subscribe(:config_updated)
    EventBus.subscribe(:node_joined)
    EventBus.subscribe(:node_left)

    # Schedule periodic synchronization
    sync_timer = Process.send_after(self(), :sync_cluster, @config_sync_interval)

    state = %__MODULE__{
      node: node(),
      config_cache: %{},
      sync_timer: sync_timer,
      pending_updates: []
    }

    # Initial sync
    perform_cluster_sync(state)

    Logger.info("Distributed configuration manager started on #{node()}")
    {:ok, state}
  end

  @impl true
  def handle_call({:put_config, app, key, value}, _from, state) do
    # Store locally first
    :ets.insert(@config_table, {{app, key}, value, node(), DateTime.utc_now()})

    # Broadcast to cluster
    EventBus.publish(:config_updated, %{
      app: app,
      key: key,
      value: value,
      node: node(),
      timestamp: DateTime.utc_now()
    })

    # Update runtime configuration
    Application.put_env(app, key, value)

    Logger.info("Configuration updated: #{app}.#{key} = #{inspect(value)}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:cluster_status, _from, state) do
    status = %{
      local_node: node(),
      cluster_nodes: [node() | Node.list()],
      config_entries: :ets.info(@config_table, :size),
      last_sync: state.sync_timer,
      pending_updates: length(state.pending_updates)
    }

    {:reply, status, state}
  end

  @impl true
  def handle_cast(:sync_cluster, state) do
    new_state = perform_cluster_sync(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:sync_cluster, state) do
    # Periodic sync
    new_state = perform_cluster_sync(state)

    # Schedule next sync
    sync_timer = Process.send_after(self(), :sync_cluster, @config_sync_interval)

    {:noreply, %{new_state | sync_timer: sync_timer}}
  end

  @impl true
  def handle_info({:event, :config_updated, event_data}, state) do
    # Handle configuration updates from other nodes
    if event_data.node != node() do
      handle_remote_config_update(event_data, state)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:event, :node_joined, event_data}, state) do
    Logger.info("Node joined cluster: #{event_data.node}, triggering config sync")
    spawn(fn -> sync_with_new_node(event_data.node) end)
    {:noreply, state}
  end

  @impl true
  def handle_info({:event, :node_left, event_data}, state) do
    Logger.info("Node left cluster: #{event_data.node}")
    # Clean up any node-specific configurations
    cleanup_node_config(event_data.node)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private Functions

  defp get_distributed_config(app, key) do
    case :ets.lookup(@config_table, {app, key}) do
      [{_key, value, _node, _timestamp}] -> {:ok, value}
      [] -> :not_found
    end
  end

  defp get_all_distributed_config(app) do
    :ets.match(@config_table, {{app, :"$1"}, :"$2", :_, :_})
    |> Enum.into(%{})
  end

  defp perform_cluster_sync(state) do
    cluster_nodes = Node.list()

    if length(cluster_nodes) > 0 do
      sync_with_cluster_nodes(cluster_nodes)
    end

    state
  end

  defp sync_with_cluster_nodes(nodes) do
    # Request configuration from each node
    Enum.each(nodes, fn node ->
      spawn(fn ->
        case :rpc.call(node, __MODULE__, :get_node_config, []) do
          {:ok, node_config} ->
            merge_node_config(node_config, node)

          {:error, reason} ->
            Logger.warn("Failed to sync config with #{node}: #{inspect(reason)}")
        end
      end)
    end)
  end

  defp sync_with_new_node(new_node) do
    # Send our configuration to the new node
    local_config = export_local_config()

    case :rpc.call(new_node, __MODULE__, :import_config, [local_config, node()]) do
      :ok ->
        Logger.info("Successfully synced config to new node: #{new_node}")

      {:error, reason} ->
        Logger.warn("Failed to sync config to new node #{new_node}: #{inspect(reason)}")
    end
  end

  defp handle_remote_config_update(event_data, _state) do
    %{app: app, key: key, value: value, node: remote_node, timestamp: timestamp} = event_data

    # Check if we should accept this update (timestamp-based conflict resolution)
    case :ets.lookup(@config_table, {app, key}) do
      [{_key, _current_value, _current_node, current_timestamp}] ->
        if DateTime.compare(timestamp, current_timestamp) == :gt do
          accept_config_update(app, key, value, remote_node, timestamp)
        end

      [] ->
        accept_config_update(app, key, value, remote_node, timestamp)
    end
  end

  defp accept_config_update(app, key, value, remote_node, timestamp) do
    :ets.insert(@config_table, {{app, key}, value, remote_node, timestamp})
    Application.put_env(app, key, value)

    Logger.debug("Accepted config update from #{remote_node}: #{app}.#{key} = #{inspect(value)}")
  end

  defp cleanup_node_config(departed_node) do
    # Remove configurations that were set by the departed node
    # (if they haven't been overridden by other nodes)
    match_spec = [
      {{{:"$1", :"$2"}, :"$3", departed_node, :"$4"}, [], [{{:"$1", :"$2"}}]}
    ]

    departed_configs = :ets.select(@config_table, match_spec)

    Enum.each(departed_configs, fn {app, key} ->
      :ets.delete(@config_table, {app, key})
      Logger.debug("Cleaned up config from departed node #{departed_node}: #{app}.#{key}")
    end)
  end

  @doc false
  def get_node_config do
    config_list = :ets.match(@config_table, {:"$1", :"$2", :"$3", :"$4"})
    {:ok, config_list}
  end

  @doc false
  def import_config(remote_config, remote_node) do
    Enum.each(remote_config, fn [{app, key}, value, _origin_node, timestamp] ->
      case :ets.lookup(@config_table, {app, key}) do
        [{_key, _current_value, _current_node, current_timestamp}] ->
          if DateTime.compare(timestamp, current_timestamp) == :gt do
            :ets.insert(@config_table, {{app, key}, value, remote_node, timestamp})
            Application.put_env(app, key, value)
          end

        [] ->
          :ets.insert(@config_table, {{app, key}, value, remote_node, timestamp})
          Application.put_env(app, key, value)
      end
    end)

    :ok
  end

  defp export_local_config do
    :ets.match(@config_table, {:"$1", :"$2", :"$3", :"$4"})
  end

  defp merge_node_config(node_config, remote_node) do
    Enum.each(node_config, fn [{app, key}, value, _origin_node, timestamp] ->
      case :ets.lookup(@config_table, {app, key}) do
        [{_key, _current_value, _current_node, current_timestamp}] ->
          if DateTime.compare(timestamp, current_timestamp) == :gt do
            :ets.insert(@config_table, {{app, key}, value, remote_node, timestamp})
            Application.put_env(app, key, value)
          end

        [] ->
          :ets.insert(@config_table, {{app, key}, value, remote_node, timestamp})
          Application.put_env(app, key, value)
      end
    end)
  end
end
