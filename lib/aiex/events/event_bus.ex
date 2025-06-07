defmodule Aiex.Events.EventBus do
  @moduledoc """
  Distributed event bus using Erlang's pg module for pure OTP pub/sub.
  
  Provides distributed event publishing and subscription without external
  dependencies, using pg process groups for efficient message distribution.
  """

  use GenServer
  require Logger

  @event_scope :aiex_events

  ## Client API

  @doc """
  Starts the event bus.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Subscribes the calling process to a specific topic.
  """
  def subscribe(topic) do
    GenServer.call(__MODULE__, {:subscribe, topic, self()})
  end

  @doc """
  Unsubscribes the calling process from a topic.
  """
  def unsubscribe(topic) do
    GenServer.call(__MODULE__, {:unsubscribe, topic, self()})
  end

  @doc """
  Publishes an event to all subscribers of a topic.
  """
  def publish(topic, event, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:publish, topic, event, metadata})
  end

  @doc """
  Gets the list of subscribers for a topic.
  """
  def subscribers(topic) do
    GenServer.call(__MODULE__, {:subscribers, topic})
  end

  @doc """
  Gets statistics about the event bus.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Start pg scope for this event bus
    case :pg.start(@event_scope) do
      {:ok, _pid} -> 
        Logger.info("Started event bus with pg scope: #{@event_scope}")
      
      {:error, {:already_started, _pid}} -> 
        Logger.debug("Event bus pg scope already started")
        :ok
      
      {:error, reason} ->
        Logger.error("Failed to start pg scope: #{inspect(reason)}")
        {:stop, reason}
    end

    state = %{
      scope: @event_scope,
      node: node(),
      event_count: 0,
      subscription_count: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, topic, pid}, _from, state) do
    # Join the process group for this topic
    :ok = :pg.join(@event_scope, topic, pid)
    
    # Monitor the subscriber process
    Process.monitor(pid)
    
    new_state = %{state | subscription_count: state.subscription_count + 1}
    
    Logger.debug("Process #{inspect(pid)} subscribed to topic: #{topic}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unsubscribe, topic, pid}, _from, state) do
    # Leave the process group
    :ok = :pg.leave(@event_scope, topic, pid)
    
    Logger.debug("Process #{inspect(pid)} unsubscribed from topic: #{topic}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:publish, topic, event, metadata}, _from, state) do
    # Create enriched event
    enriched_event = %{
      event: event,
      topic: topic,
      metadata: metadata,
      timestamp: DateTime.utc_now(),
      node: node(),
      id: generate_event_id()
    }

    # Get all members of the topic group
    members = :pg.get_members(@event_scope, topic)
    
    # Dispatch to all subscribers concurrently
    Task.async_stream(
      members,
      fn pid ->
        safe_dispatch(pid, enriched_event)
      end,
      max_concurrency: System.schedulers_online() * 2,
      ordered: false,
      timeout: 5_000
    )
    |> Stream.run()

    new_state = %{state | event_count: state.event_count + 1}
    
    Logger.debug("Published event to #{length(members)} subscribers on topic: #{topic}")
    {:reply, {:ok, length(members)}, new_state}
  end

  @impl true
  def handle_call({:subscribers, topic}, _from, state) do
    members = :pg.get_members(@event_scope, topic)
    subscriber_info = Enum.map(members, fn pid ->
      %{
        pid: pid,
        node: node(pid),
        alive: Process.alive?(pid)
      }
    end)
    
    {:reply, {:ok, subscriber_info}, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    # Get all groups and their member counts
    all_groups = :pg.which_groups(@event_scope)
    
    group_stats = Enum.map(all_groups, fn group ->
      members = :pg.get_members(@event_scope, group)
      %{
        topic: group,
        subscriber_count: length(members),
        nodes: members |> Enum.map(&node/1) |> Enum.uniq()
      }
    end)

    stats = %{
      node: state.node,
      scope: state.scope,
      total_events_published: state.event_count,
      total_subscriptions: state.subscription_count,
      active_topics: length(all_groups),
      topic_details: group_stats,
      cluster_nodes: [node() | Node.list()]
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    Logger.debug("Subscriber process #{inspect(pid)} went down: #{inspect(reason)}")
    # pg automatically handles cleanup when processes die
    {:noreply, state}
  end

  ## Private Functions

  defp safe_dispatch(pid, event) do
    try do
      send(pid, {:event_bus, event})
      :ok
    catch
      kind, reason ->
        Logger.warning("Failed to dispatch event to #{inspect(pid)}: #{Exception.format(kind, reason)}")
        :error
    end
  end

  defp generate_event_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
  end
end