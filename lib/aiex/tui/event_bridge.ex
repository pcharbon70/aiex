defmodule Aiex.TUI.EventBridge do
  @moduledoc """
  Bridges Erlang process group (pg) events to TUI Server messages.

  This GenServer monitors pg events and forwards them to connected TUI clients,
  replacing the previous NATS-based bridge.
  """

  use GenServer
  require Logger

  @pg_scope :aiex_events

  defstruct [
    :monitor_ref,
    subscribed_groups: MapSet.new()
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Subscribe to specific pg group events for TUI bridging.
  """
  def subscribe_to_group(group) do
    GenServer.cast(__MODULE__, {:subscribe_group, group})
  end

  @doc """
  Unsubscribe from pg group events.
  """
  def unsubscribe_from_group(group) do
    GenServer.cast(__MODULE__, {:unsubscribe_group, group})
  end

  @doc """
  Publish a custom event to TUI clients.
  """
  def publish_event(topic, event_data) do
    GenServer.cast(__MODULE__, {:publish_event, topic, event_data})
  end

  @impl true
  def init(_opts) do
    # Ensure pg scope exists
    ensure_pg_scope(@pg_scope)

    # Monitor pg scope for membership changes
    {_groups, monitor_ref} = :pg.monitor_scope(@pg_scope)

    # Subscribe to common events by default
    default_groups = [:context_updates, :model_responses, :interface_events]
    subscribed = MapSet.new(default_groups)

    state = %__MODULE__{
      monitor_ref: monitor_ref,
      subscribed_groups: subscribed
    }

    Logger.info("TUI Event Bridge started, monitoring scope: #{@pg_scope}")

    {:ok, state}
  end

  @impl true
  def handle_cast({:subscribe_group, group}, state) do
    new_subscribed = MapSet.put(state.subscribed_groups, group)
    {:noreply, %{state | subscribed_groups: new_subscribed}}
  end

  def handle_cast({:unsubscribe_group, group}, state) do
    new_subscribed = MapSet.delete(state.subscribed_groups, group)
    {:noreply, %{state | subscribed_groups: new_subscribed}}
  end

  def handle_cast({:publish_event, topic, event_data}, state) do
    publish_to_tui(topic, event_data)
    {:noreply, state}
  end

  @impl true
  def handle_info({:pg_notify, event_type, group, pid}, state) do
    # Only bridge events for subscribed groups
    if MapSet.member?(state.subscribed_groups, group) do
      topic = "otp.event.pg.#{group}.#{event_type}"

      event = %{
        group: group,
        pid: inspect(pid),
        node: node(pid),
        event_type: event_type,
        timestamp: System.system_time(:microsecond)
      }

      publish_to_tui(topic, event)
    end

    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("TUI Bridge received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp publish_to_tui(topic, event_data) do
    # Check if TUI server is running
    case Process.whereis(Aiex.TUI.Server) do
      nil ->
        Logger.debug("TUI Server not available for publishing to #{topic}")

      _pid ->
        Aiex.TUI.Server.publish(topic, event_data)
        Logger.debug("Published event to TUI topic: #{topic}")
    end
  end

  defp ensure_pg_scope(scope) do
    # pg is part of kernel, just start the scope
    case :pg.start(scope) do
      :ok -> :ok
      {:error, {:already_started, _}} -> :ok
      error -> error
    end
  end
end
