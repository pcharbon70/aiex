defmodule Aiex.TUI.Communication.OTPBridge do
  @moduledoc """
  OTP Bridge for Ratatouille TUI integration.
  
  Provides direct communication between the TUI application and the OTP
  business logic using native Elixir messaging and pg process groups.
  """
  
  use GenServer
  require Logger
  
  alias Aiex.TUI.RatatouilleApp
  alias Aiex.InterfaceGateway
  alias Aiex.Context.Manager, as: ContextManager
  
  @pg_scope :aiex_events
  
  defstruct [
    :tui_pid,
    :interface_id,
    :subscriptions,
    :context_cache,
    :message_queue
  ]
  
  ## Public API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Sends a message to the TUI application.
  """
  def send_to_tui(message) do
    GenServer.cast(__MODULE__, {:send_to_tui, message})
  end
  
  @doc """
  Updates TUI with new context information.
  """
  def update_tui_context(context_type, context_data) do
    GenServer.cast(__MODULE__, {:update_context, context_type, context_data})
  end
  
  @doc """
  Notifies TUI of AI response.
  """
  def ai_response_received(response) do
    GenServer.cast(__MODULE__, {:ai_response, response})
  end
  
  ## GenServer implementation
  
  @impl true
  def init(opts) do
    # Subscribe to pg events
    :pg.join(@pg_scope, :tui_bridge, self())
    :pg.join(@pg_scope, :context_updates, self())
    :pg.join(@pg_scope, :ai_responses, self())
    
    state = %__MODULE__{
      tui_pid: nil,
      interface_id: nil,
      subscriptions: [:tui_bridge, :context_updates, :ai_responses],
      context_cache: %{},
      message_queue: []
    }
    
    Logger.info("TUI OTP Bridge started")
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:send_to_tui, message}, state) do
    if state.tui_pid do
      send(state.tui_pid, {:tui_message, message})
      {:noreply, state}
    else
      # Queue message for when TUI connects
      queued_messages = state.message_queue ++ [message]
      {:noreply, %{state | message_queue: queued_messages}}
    end
  end
  
  def handle_cast({:update_context, context_type, context_data}, state) do
    context_update = %{
      type: context_type,
      data: context_data,
      timestamp: DateTime.utc_now()
    }
    
    # Cache the context
    new_cache = Map.put(state.context_cache, context_type, context_update)
    
    # Send to TUI if connected
    if state.tui_pid do
      send(state.tui_pid, {:context_update, context_update})
    end
    
    {:noreply, %{state | context_cache: new_cache}}
  end
  
  def handle_cast({:ai_response, response}, state) do
    if state.tui_pid do
      send(state.tui_pid, {:ai_response, response})
    end
    
    {:noreply, state}
  end
  
  def handle_cast({:register_tui, tui_pid}, state) do
    Logger.info("TUI application registered with OTP Bridge")
    
    # Send queued messages
    for message <- state.message_queue do
      send(tui_pid, {:tui_message, message})
    end
    
    # Send cached context
    for {_type, context} <- state.context_cache do
      send(tui_pid, {:context_update, context})
    end
    
    {:noreply, %{state | tui_pid: tui_pid, message_queue: []}}
  end
  
  def handle_cast({:unregister_tui, _tui_pid}, state) do
    Logger.info("TUI application unregistered from OTP Bridge")
    {:noreply, %{state | tui_pid: nil, interface_id: nil}}
  end
  
  @impl true
  def handle_call({:get_cached_context, context_type}, _from, state) do
    context = Map.get(state.context_cache, context_type)
    {:reply, context, state}
  end
  
  def handle_call(:get_tui_status, _from, state) do
    status = %{
      connected: state.tui_pid != nil,
      interface_id: state.interface_id,
      cached_contexts: Map.keys(state.context_cache),
      queued_messages: length(state.message_queue)
    }
    
    {:reply, status, state}
  end
  
  @impl true
  def handle_info({:pg_message, topic, message}, state) do
    handle_pg_message(state, topic, message)
  end
  
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    if pid == state.tui_pid do
      Logger.info("TUI process went down: #{reason}")
      {:noreply, %{state | tui_pid: nil, interface_id: nil}}
    else
      {:noreply, state}
    end
  end
  
  def handle_info(msg, state) do
    Logger.debug("TUI Bridge received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
  
  ## Private functions
  
  defp handle_pg_message(state, topic, message) do
    case topic do
      :context_updates ->
        handle_context_update(state, message)
        
      :ai_responses ->
        handle_ai_response_event(state, message)
        
      :tui_bridge ->
        handle_tui_bridge_event(state, message)
        
      _ ->
        Logger.debug("TUI Bridge unknown pg message on #{topic}: #{inspect(message)}")
        {:noreply, state}
    end
  end
  
  defp handle_context_update(state, message) do
    case message do
      {:context_updated, context_type, context_data} ->
        GenServer.cast(self(), {:update_context, context_type, context_data})
        
      _ ->
        Logger.debug("Unknown context update: #{inspect(message)}")
    end
    
    {:noreply, state}
  end
  
  defp handle_ai_response_event(state, message) do
    case message do
      {:ai_response_ready, response} ->
        GenServer.cast(self(), {:ai_response, response})
        
      {:ai_thinking, metadata} ->
        if state.tui_pid do
          send(state.tui_pid, {:tui_message, {:ai_thinking, metadata}})
        end
        
      {:ai_error, error} ->
        if state.tui_pid do
          send(state.tui_pid, {:tui_message, {:ai_error, error}})
        end
        
      _ ->
        Logger.debug("Unknown AI response event: #{inspect(message)}")
    end
    
    {:noreply, state}
  end
  
  defp handle_tui_bridge_event(state, message) do
    case message do
      {:tui_notification, type, content} ->
        if state.tui_pid do
          send(state.tui_pid, {:tui_message, {:notification, type, content}})
        end
        
      {:tui_status, status} ->
        if state.tui_pid do
          send(state.tui_pid, {:tui_message, {:status, status}})
        end
        
      _ ->
        Logger.debug("Unknown TUI bridge event: #{inspect(message)}")
    end
    
    {:noreply, state}
  end
  
  ## Public functions for integration
  
  @doc """
  Registers TUI process with the bridge.
  """
  def register_tui(tui_pid) when is_pid(tui_pid) do
    GenServer.cast(__MODULE__, {:register_tui, tui_pid})
    Process.monitor(tui_pid)
  end
  
  @doc """
  Unregisters TUI process from the bridge.
  """
  def unregister_tui(tui_pid) when is_pid(tui_pid) do
    GenServer.cast(__MODULE__, {:unregister_tui, tui_pid})
  end
  
  @doc """
  Gets cached context by type.
  """
  def get_cached_context(context_type) do
    GenServer.call(__MODULE__, {:get_cached_context, context_type})
  end
  
  @doc """
  Gets TUI connection status.
  """
  def get_tui_status do
    GenServer.call(__MODULE__, :get_tui_status)
  end
  
  @doc """
  Publishes TUI notification via pg.
  """
  def publish_tui_notification(type, content) do
    :pg.send_to_all(@pg_scope, :tui_bridge, {:tui_notification, type, content})
  end
  
  @doc """
  Publishes TUI status update via pg.
  """
  def publish_tui_status(status) do
    :pg.send_to_all(@pg_scope, :tui_bridge, {:tui_status, status})
  end
end