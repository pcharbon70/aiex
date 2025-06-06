defmodule Aiex.Context.Engine do
  @moduledoc """
  Core context management engine using ETS tables with tiered memory architecture.

  Manages code context with hot/warm/cold tiers, DETS persistence, and efficient
  storage/retrieval operations.
  """

  use GenServer
  require Logger

  @dets_file_name "aiex_context.dets"
  # 100MB
  @max_hot_tier_size 100_000_000
  # 500MB
  @max_warm_tier_size 500_000_000

  # Client API

  @doc """
  Starts the context engine with the given options.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Stores a context entry with the given key and value.
  """
  def put(key, value, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:put, key, value, metadata})
  end

  @doc """
  Retrieves a context entry by key.
  """
  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  @doc """
  Deletes a context entry by key.
  """
  def delete(key) do
    GenServer.call(__MODULE__, {:delete, key})
  end

  @doc """
  Lists all keys in the context engine.
  """
  def list_keys do
    GenServer.call(__MODULE__, :list_keys)
  end

  @doc """
  Gets the current memory usage statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Clears all context entries.
  """
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    # Create ETS table with read/write concurrency
    table =
      :ets.new(:aiex_context_table, [
        :set,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])

    # Open or create DETS file for persistence
    dets_path = get_dets_path(opts)
    dets_ref = make_ref()

    {:ok, dets_table} =
      :dets.open_file(dets_ref,
        file: String.to_charlist(dets_path),
        type: :set
      )

    # Load persisted data from DETS to ETS
    load_from_dets(table, dets_table)

    # Initialize state
    state = %{
      ets_table: table,
      dets_table: dets_table,
      dets_path: dets_path,
      hot_tier: %{},
      warm_tier: %{},
      cold_tier: %{},
      total_size: 0,
      access_counts: %{},
      last_accessed: %{}
    }

    # Schedule periodic persistence
    schedule_persistence()

    # Schedule tier management
    schedule_tier_management()

    {:ok, state}
  end

  @impl true
  def handle_call({:put, key, value, metadata}, _from, state) do
    timestamp = System.system_time(:second)

    # Create entry with metadata
    entry = %{
      key: key,
      value: value,
      metadata:
        Map.merge(metadata, %{
          created_at: timestamp,
          updated_at: timestamp,
          size: :erlang.byte_size(:erlang.term_to_binary(value))
        }),
      tier: :hot
    }

    # Store in ETS
    :ets.insert(state.ets_table, {key, entry})

    # Update state tracking
    new_state =
      state
      |> update_tier_tracking(key, entry)
      |> update_access_tracking(key, timestamp)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    case :ets.lookup(state.ets_table, key) do
      [{^key, entry}] ->
        # Update access tracking
        new_state = update_access_tracking(state, key, System.system_time(:second))

        # Consider tier promotion if in warm/cold tier
        promoted_state = maybe_promote_tier(new_state, key, entry)

        {:reply, {:ok, entry.value}, promoted_state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:delete, key}, _from, state) do
    case :ets.lookup(state.ets_table, key) do
      [{^key, entry}] ->
        :ets.delete(state.ets_table, key)
        new_state = remove_from_tier_tracking(state, key, entry)
        {:reply, :ok, new_state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:list_keys, _from, state) do
    keys = :ets.select(state.ets_table, [{{:"$1", :_}, [], [:"$1"]}])
    {:reply, keys, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      total_entries: :ets.info(state.ets_table, :size),
      total_size: state.total_size,
      hot_tier: %{
        entries: map_size(state.hot_tier),
        size: calculate_tier_size(state.hot_tier)
      },
      warm_tier: %{
        entries: map_size(state.warm_tier),
        size: calculate_tier_size(state.warm_tier)
      },
      cold_tier: %{
        entries: map_size(state.cold_tier),
        size: calculate_tier_size(state.cold_tier)
      }
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(state.ets_table)

    new_state = %{
      state
      | hot_tier: %{},
        warm_tier: %{},
        cold_tier: %{},
        total_size: 0,
        access_counts: %{},
        last_accessed: %{}
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:persist_to_dets, state) do
    persist_to_dets(state)
    schedule_persistence()
    {:noreply, state}
  end

  @impl true
  def handle_info(:manage_tiers, state) do
    new_state = manage_memory_tiers(state)
    schedule_tier_management()
    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, state) do
    # Final persistence before shutdown
    persist_to_dets(state)
    :dets.close(state.dets_table)
    :ok
  end

  # Private functions

  defp get_dets_path(opts) do
    data_dir = Keyword.get(opts, :data_dir, "priv/data")
    File.mkdir_p!(data_dir)

    # Use a unique filename if provided, otherwise use default
    filename = Keyword.get(opts, :dets_filename, @dets_file_name)
    Path.join(data_dir, filename)
  end

  defp load_from_dets(ets_table, dets_table) do
    :dets.traverse(dets_table, fn {key, value} ->
      :ets.insert(ets_table, {key, value})
      :continue
    end)
  end

  defp persist_to_dets(state) do
    # Persist all ETS entries to DETS
    :ets.foldl(
      fn {key, entry}, _acc ->
        :dets.insert(state.dets_table, {key, entry})
        :ok
      end,
      :ok,
      state.ets_table
    )

    # Sync DETS to disk
    :dets.sync(state.dets_table)

    Logger.debug("Context persisted to DETS")
  end

  defp schedule_persistence do
    # Persist every 5 minutes
    Process.send_after(self(), :persist_to_dets, 5 * 60 * 1000)
  end

  defp schedule_tier_management do
    # Check tiers every minute
    Process.send_after(self(), :manage_tiers, 60 * 1000)
  end

  defp update_tier_tracking(state, key, entry) do
    # Remove from old tier if exists
    state =
      Enum.reduce([:hot_tier, :warm_tier, :cold_tier], state, fn tier, acc ->
        Map.update!(acc, tier, &Map.delete(&1, key))
      end)

    # Add to new tier
    tier_key = String.to_atom("#{entry.tier}_tier")
    Map.update!(state, tier_key, &Map.put(&1, key, entry))
  end

  defp update_access_tracking(state, key, timestamp) do
    state
    |> Map.update!(:access_counts, &Map.update(&1, key, 1, fn count -> count + 1 end))
    |> Map.update!(:last_accessed, &Map.put(&1, key, timestamp))
  end

  defp remove_from_tier_tracking(state, key, entry) do
    tier_key = String.to_atom("#{entry.tier}_tier")

    state
    |> Map.update!(tier_key, &Map.delete(&1, key))
    |> Map.update!(:total_size, &(&1 - entry.metadata.size))
    |> Map.update!(:access_counts, &Map.delete(&1, key))
    |> Map.update!(:last_accessed, &Map.delete(&1, key))
  end

  defp maybe_promote_tier(state, key, entry) do
    access_count = Map.get(state.access_counts, key, 0)

    cond do
      entry.tier == :hot -> state
      entry.tier == :warm and access_count > 5 -> promote_to_hot(state, key, entry)
      entry.tier == :cold and access_count > 2 -> promote_to_warm(state, key, entry)
      true -> state
    end
  end

  defp promote_to_hot(state, key, entry) do
    new_entry = %{entry | tier: :hot}
    :ets.insert(state.ets_table, {key, new_entry})
    update_tier_tracking(state, key, new_entry)
  end

  defp promote_to_warm(state, key, entry) do
    new_entry = %{entry | tier: :warm}
    :ets.insert(state.ets_table, {key, new_entry})
    update_tier_tracking(state, key, new_entry)
  end

  defp calculate_tier_size(tier_map) do
    Enum.reduce(tier_map, 0, fn {_key, entry}, acc ->
      acc + entry.metadata.size
    end)
  end

  defp manage_memory_tiers(state) do
    # Check if hot tier is too large
    hot_size = calculate_tier_size(state.hot_tier)

    state =
      if hot_size > @max_hot_tier_size do
        demote_from_hot_tier(state)
      else
        state
      end

    # Check if warm tier is too large
    warm_size = calculate_tier_size(state.warm_tier)

    if warm_size > @max_warm_tier_size do
      demote_from_warm_tier(state)
    else
      state
    end
  end

  defp demote_from_hot_tier(state) do
    # Find least recently accessed entries in hot tier
    hot_entries =
      state.hot_tier
      |> Enum.map(fn {key, entry} ->
        {key, entry, Map.get(state.last_accessed, key, 0)}
      end)
      |> Enum.sort_by(fn {_, _, last_accessed} -> last_accessed end)
      # Demote 25%
      |> Enum.take(div(map_size(state.hot_tier), 4))

    Enum.reduce(hot_entries, state, fn {key, entry, _}, acc ->
      new_entry = %{entry | tier: :warm}
      :ets.insert(acc.ets_table, {key, new_entry})
      update_tier_tracking(acc, key, new_entry)
    end)
  end

  defp demote_from_warm_tier(state) do
    # Find least recently accessed entries in warm tier
    warm_entries =
      state.warm_tier
      |> Enum.map(fn {key, entry} ->
        {key, entry, Map.get(state.last_accessed, key, 0)}
      end)
      |> Enum.sort_by(fn {_, _, last_accessed} -> last_accessed end)
      # Demote 25%
      |> Enum.take(div(map_size(state.warm_tier), 4))

    Enum.reduce(warm_entries, state, fn {key, entry, _}, acc ->
      new_entry = %{entry | tier: :cold}
      :ets.insert(acc.ets_table, {key, new_entry})
      update_tier_tracking(acc, key, new_entry)
    end)
  end
end
