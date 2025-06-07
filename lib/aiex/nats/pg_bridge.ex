defmodule Aiex.NATS.PGBridge do
  @moduledoc """
  Bridges Erlang process group (pg) events to NATS messages for TUI integration.
  
  This GenServer automatically converts pg membership changes and custom events
  into NATS messages following the subject naming convention:
  otp.event.pg.{group}.{event_type}
  
  This enables the Rust TUI to receive real-time updates about distributed
  OTP application state changes.
  """
  
  use GenServer
  require Logger
  
  @pg_scope :aiex_events
  
  defstruct [
    :monitor_ref,
    :gnat_conn,
    subscribed_groups: MapSet.new()
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Subscribe to specific pg group events for NATS bridging.
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
  Publish a custom event to NATS (bypassing pg).
  """
  def publish_event(topic, event_data) do
    GenServer.cast(__MODULE__, {:publish_event, topic, event_data})
  end
  
  @impl true
  def init(opts) do
    gnat_conn = Keyword.fetch!(opts, :gnat_conn)
    
    # Monitor pg scope for membership changes
    {_groups, monitor_ref} = :pg.monitor_scope(@pg_scope)
    
    # Register to receive NATS connection updates
    :pg.join(@pg_scope, :nats_listeners, self())
    
    # Subscribe to common events by default
    default_groups = [:context_updates, :model_responses, :interface_events]
    subscribed = MapSet.new(default_groups)
    
    state = %__MODULE__{
      monitor_ref: monitor_ref,
      gnat_conn: gnat_conn,
      subscribed_groups: subscribed
    }
    
    Logger.info("PG-NATS Bridge started, monitoring scope: #{@pg_scope}")
    
    # Schedule initial NATS status check
    Process.send_after(self(), :check_nats_status, 1000)
    
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
    publish_to_nats(state.gnat_conn, topic, event_data)
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
      
      publish_to_nats(state.gnat_conn, topic, event)
    end
    
    {:noreply, state}
  end
  
  def handle_info({:nats_connected, _pid}, state) do
    Logger.info("PG-NATS Bridge: NATS connection established")
    {:noreply, state}
  end
  
  def handle_info(:check_nats_status, state) do
    case :global.whereis_name(state.gnat_conn) do
      :undefined ->
        Logger.debug("NATS not connected yet, PG-NATS Bridge waiting...")
      pid when is_pid(pid) ->
        Logger.info("NATS connection active, PG-NATS Bridge ready")
    end
    {:noreply, state}
  end
  
  def handle_info(msg, state) do
    Logger.debug("PG Bridge received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
  
  defp publish_to_nats(gnat_conn_name, topic, event_data) do
    case :global.whereis_name(gnat_conn_name) do
      :undefined ->
        # Don't warn on every attempt - NATS might not be running yet
        Logger.debug("NATS connection not available for publishing to #{topic}")
        
      pid when is_pid(pid) ->
        encoded_event = Msgpax.pack!(event_data)
        
        case Gnat.pub(pid, topic, encoded_event) do
          :ok ->
            Logger.debug("Published event to NATS topic: #{topic}")
            
          {:error, reason} ->
            Logger.warning("Failed to publish to NATS topic #{topic}: #{inspect(reason)}")
        end
    end
  end
end