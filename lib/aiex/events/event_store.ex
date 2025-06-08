defmodule Aiex.Events.EventStore do
  @moduledoc """
  Mnesia-based event store for distributed event sourcing.

  Provides persistent storage and retrieval of events with support for:
  - Event streams by aggregate
  - Event filtering and querying
  - Event replay functionality
  - Cross-node replication via Mnesia
  """

  require Logger

  @event_store_table :aiex_event_store

  @doc """
  Gets events for a specific aggregate.
  """
  def get_events(aggregate_id, opts \\ []) do
    from_version = Keyword.get(opts, :from_version, 1)
    to_version = Keyword.get(opts, :to_version, :infinity)
    event_types = Keyword.get(opts, :event_types, :all)
    limit = Keyword.get(opts, :limit, :infinity)

    try do
      result = :mnesia.transaction(fn ->
        # Build match pattern
        match_pattern = {@event_store_table, :_, aggregate_id, :_, :_, :_, :_, :_}
        
        events = :mnesia.match_object(match_pattern)
        |> Enum.filter(&filter_by_version(&1, from_version, to_version))
        |> Enum.filter(&filter_by_type(&1, event_types))
        |> Enum.sort_by(&event_version/1)
        |> limit_results(limit)
        |> Enum.map(&mnesia_record_to_event/1)

        events
      end)

      case result do
        {:atomic, events} -> {:ok, events}
        {:aborted, reason} -> {:error, reason}
      end
    catch
      :exit, reason -> {:error, {:mnesia_exit, reason}}
    end
  end

  @doc """
  Replays events based on criteria.
  """
  def replay_events(opts \\ []) do
    from_timestamp = Keyword.get(opts, :from)
    aggregate_id = Keyword.get(opts, :aggregate_id)
    to_handler = Keyword.get(opts, :to)
    event_types = Keyword.get(opts, :event_types, :all)

    try do
      result = :mnesia.transaction(fn ->
        # Get all events matching criteria
        match_pattern = case aggregate_id do
          nil -> {@event_store_table, :_, :_, :_, :_, :_, :_, :_}
          id -> {@event_store_table, :_, id, :_, :_, :_, :_, :_}
        end

        events = :mnesia.match_object(match_pattern)
        |> Enum.filter(&filter_by_timestamp(&1, from_timestamp))
        |> Enum.filter(&filter_by_type(&1, event_types))
        |> Enum.sort_by(&event_timestamp/1, DateTime)

        # Replay events
        Enum.each(events, fn event_record ->
          event = mnesia_record_to_event(event_record)
          
          if to_handler do
            try do
              to_handler.handle_event(event)
            catch
              kind, reason ->
                Logger.warning("Replay handler failed: #{kind} #{inspect(reason)}")
            end
          else
            # Broadcast to event bus
            send(Aiex.Events.OTPEventBus, {:event_notification, event})
          end
        end)

        length(events)
      end)

      case result do
        {:atomic, count} -> {:ok, count}
        {:aborted, reason} -> {:error, reason}
      end
    catch
      :exit, reason -> {:error, {:mnesia_exit, reason}}
    end
  end

  @doc """
  Counts total events in the store.
  """
  def count_events do
    try do
      :mnesia.table_info(@event_store_table, :size)
    catch
      :exit, _ -> 0
    end
  end

  @doc """
  Gets events by type across all aggregates.
  """
  def get_events_by_type(event_type, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    from_timestamp = Keyword.get(opts, :from)

    try do
      result = :mnesia.transaction(fn ->
        match_pattern = {@event_store_table, :_, :_, event_type, :_, :_, :_, :_}
        
        events = :mnesia.match_object(match_pattern)
        |> Enum.filter(&filter_by_timestamp(&1, from_timestamp))
        |> Enum.sort_by(&event_timestamp/1, DateTime)
        |> limit_results(limit)
        |> Enum.map(&mnesia_record_to_event/1)

        events
      end)

      case result do
        {:atomic, events} -> {:ok, events}
        {:aborted, reason} -> {:error, reason}
      end
    catch
      :exit, reason -> {:error, {:mnesia_exit, reason}}
    end
  end

  @doc """
  Gets the latest event for an aggregate.
  """
  def get_latest_event(aggregate_id) do
    case get_events(aggregate_id, limit: 1) do
      {:ok, [event | _]} -> {:ok, event}
      {:ok, []} -> {:error, :no_events}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets aggregate version from latest event.
  """
  def get_aggregate_version(aggregate_id) do
    try do
      result = :mnesia.transaction(fn ->
        match_pattern = {@event_store_table, :_, aggregate_id, :_, :_, :_, :_, :_}
        
        case :mnesia.match_object(match_pattern) do
          [] -> 0
          events -> 
            events
            |> Enum.map(&event_version/1)
            |> Enum.max()
        end
      end)

      case result do
        {:atomic, version} -> {:ok, version}
        {:aborted, reason} -> {:error, reason}
      end
    catch
      :exit, reason -> {:error, {:mnesia_exit, reason}}
    end
  end

  ## Private Functions

  defp filter_by_version(event_record, from_version, to_version) do
    version = event_version(event_record)
    
    case {from_version, to_version} do
      {from, :infinity} -> version >= from
      {from, to} -> version >= from and version <= to
      {:infinity, to} -> version <= to
      _ -> true
    end
  end

  defp filter_by_type(_event_record, :all), do: true
  defp filter_by_type(event_record, event_types) when is_list(event_types) do
    type = event_type(event_record)
    type in event_types
  end
  defp filter_by_type(event_record, event_type) do
    event_type(event_record) == event_type
  end

  defp filter_by_timestamp(_event_record, nil), do: true
  defp filter_by_timestamp(event_record, from_timestamp) do
    timestamp = event_timestamp(event_record)
    DateTime.compare(timestamp, from_timestamp) != :lt
  end

  defp limit_results(events, :infinity), do: events
  defp limit_results(events, limit) when is_integer(limit) do
    Enum.take(events, limit)
  end

  defp mnesia_record_to_event({@event_store_table, id, aggregate_id, type, data, metadata, version, timestamp}) do
    %{
      id: id,
      aggregate_id: aggregate_id,
      type: type,
      data: data,
      metadata: Map.merge(metadata, %{version: version, timestamp: timestamp})
    }
  end

  defp event_version({@event_store_table, _, _, _, _, _, version, _}), do: version
  defp event_type({@event_store_table, _, _, type, _, _, _, _}), do: type
  defp event_timestamp({@event_store_table, _, _, _, _, _, _, timestamp}), do: timestamp
end